import Foundation
import MoriRemoteTerminal
import Observation
import SwiftUI

struct WorkspaceDraft: Identifiable, Sendable {
    let id: UUID
    let serverID: UUID
    var name: String
    var tmuxSession: String

    init(serverID: UUID, workspace: SavedWorkspace? = nil) {
        id = workspace?.id ?? UUID()
        self.serverID = serverID
        name = workspace?.name ?? "main"
        tmuxSession = workspace?.tmuxSession ?? "main"
    }

    func record() throws -> SavedWorkspace {
        try SavedWorkspace(id: id, serverID: serverID, name: name, tmuxSession: tmuxSession).validated()
    }
}

struct ServerWorkspaceDraft: Identifiable, Sendable {
    let id: UUID
    /// Nil means an existing server edit: profile edits must not invent or
    /// overwrite an arbitrary workspace belonging to that server.
    let workspaceID: UUID?
    let serverLastConnectedAt: Date?
    let workspaceLastConnectedAt: Date?
    var serverName: String
    var host: String
    var port: String
    var username: String
    var workspaceName: String
    var tmuxSession: String
    var identityKind: SSHIdentityKind
    var password: String
    var privateKey: String
    var passphrase: String

    init(server: SavedServer? = nil, workspace: SavedWorkspace? = nil, identity: SSHIdentity? = nil) {
        id = server?.id ?? UUID()
        workspaceID = workspace?.id ?? (server == nil ? UUID() : nil)
        serverLastConnectedAt = server?.lastConnectedAt
        workspaceLastConnectedAt = workspace?.lastConnectedAt
        serverName = server?.name ?? ""
        host = server?.host ?? ""
        port = String(server?.port ?? 22)
        username = server?.username ?? ""
        workspaceName = workspace?.name ?? "main"
        tmuxSession = workspace?.tmuxSession ?? "main"
        identityKind = identity?.kind ?? .password
        password = ""
        privateKey = ""
        passphrase = ""
    }

    func records(existingIdentityID: UUID? = nil) throws -> (SavedServer, SavedWorkspace?, SSHIdentity, ProfileCredential?) {
        guard let port = Int(port) else { throw SavedModelValidationError.invalidPort }
        let identityID = existingIdentityID ?? id
        let server = SavedServer(id: id, name: serverName, host: host, port: port, username: username, identityID: identityID, lastConnectedAt: serverLastConnectedAt)
        let workspace = try workspaceID.map { try SavedWorkspace(id: $0, serverID: id, name: workspaceName, tmuxSession: tmuxSession, lastConnectedAt: workspaceLastConnectedAt).validated() }
        let identity = SSHIdentity(id: identityID, serverID: id, kind: identityKind, label: identityKind == .password ? "password" : "private key")
        let credential: ProfileCredential?
        switch identityKind {
        case .password: credential = password.isEmpty ? nil : .password(password)
        case .privateKey:
            credential = privateKey.isEmpty ? nil : .privateKey(.init(privateKeyPEM: privateKey, passphrase: passphrase.isEmpty ? nil : passphrase))
        }
        return (try server.validated(), workspace, try identity.validated(), credential)
    }
}

enum WorkspaceRuntimeStatus: Equatable {
    case connecting
    case ready
    case reconnecting
    case disconnected(String)

    var title: String {
        switch self {
        case .connecting: String(localized: "Connecting…")
        case .ready: String(localized: "Connected")
        case .reconnecting: String(localized: "Reconnecting…")
        case .disconnected: String(localized: "Disconnected")
        }
    }
}

/// The small pure policy prevents credential/trust/profile failures from becoming
/// noisy background retries. Only a live transport loss gets one bounded retry.
struct WorkspaceReconnectPolicy: Sendable {
    static let automaticAttempts = 1
    func mayReconnect(status: WorkspaceRuntimeStatus, attempts: Int) -> Bool {
        if case .disconnected = status { return attempts < Self.automaticAttempts }
        return false
    }
}

/// iOS memory warnings are advisory, not an excuse to tear down the terminal a
/// user is actively using. Evict dormant workspaces first; their one-shot
/// runtime fences release native surfaces before the root lease returns to pool.
struct WorkspaceMemoryPressurePolicy: Sendable {
    func workspaceIDsToDisconnect(active: UUID?, all: some Collection<UUID>) -> [UUID] {
        all.filter { $0 != active }.sorted { $0.uuidString < $1.uuidString }
    }
}

/// Adaptive chrome may change around a workspace, but never the retained
/// terminal-session identity. A new runtime is the only valid replacement.
enum WorkspaceTerminalPresentation: Sendable {
    static func identity(for sessionInstanceID: UUID) -> UUID { sessionInstanceID }
}

/// Main-actor admission fence for asynchronous connection attempts. A token is
/// claimed before the first await, then invalidated by disconnect/delete/replacement.
enum SSHTrustPresentation: Equatable {
    case challenge(SSHHostTrustChallenge)
    case error(String)

    static func resolve(_ error: SSHHostTrustError) -> Self {
        switch error {
        case let .trustRequired(challenge), let .changedKey(challenge): .challenge(challenge)
        case .staleChallenge: .error(error.localizedDescription)
        }
    }
}

struct WorkspaceConnectionAttemptLedger: Sendable {
    private var tokens: [UUID: UUID] = [:]

    mutating func begin(workspaceID: UUID) -> UUID? {
        guard tokens[workspaceID] == nil else { return nil }
        let token = UUID()
        tokens[workspaceID] = token
        return token
    }

    func isCurrent(_ token: UUID, for workspaceID: UUID) -> Bool { tokens[workspaceID] == token }
    mutating func end(_ token: UUID, for workspaceID: UUID) { guard isCurrent(token, for: workspaceID) else { return }; tokens[workspaceID] = nil }
    mutating func cancel(workspaceID: UUID) { tokens[workspaceID] = nil }
}

@MainActor
final class ActiveWorkspaceRuntime {
    let workspace: SavedWorkspace
    let instanceID: UUID
    let session: MoriRemoteTerminalSession
    private let metadataProjector: AgentMetadataProjector
    private(set) var topology: MoriRemoteTerminalTopology?
    var agentMetadata: [UInt64: AgentMetadata] { metadataProjector.metadata }
    var focusedPaneID: UInt64? {
        guard let activeWindowID = topology?.activeWindowID else { return nil }
        return topology?.windows.first(where: { $0.id == activeWindowID })?.activePaneID
    }
    private(set) var status: WorkspaceRuntimeStatus = .connecting
    var onTransportLoss: (@MainActor (UUID) -> Void)?
    var onChange: (@MainActor () -> Void)?

    init(workspace: SavedWorkspace, settings: RemoteSettings, transport: MoriRemoteTerminalTransport, instanceID: UUID = UUID()) throws {
        self.workspace = workspace
        self.instanceID = instanceID
        session = try MoriRemoteTerminalSession(
            transport: transport,
            initialScrollbackLines: settings.effectiveInitialScrollbackLines,
            instanceID: instanceID
        )
        metadataProjector = AgentMetadataProjector(instanceID: instanceID) { [session] in
            let result = await session.queryAgentMetadata()
            return .init(succeeded: result.status == .success, body: result.body)
        }
        metadataProjector.onChange = { [weak self] in self?.onChange?() }
        session.onTopologyChange = { [weak self] topology in
            guard let self else { return }
            self.topology = topology
            self.status = .ready
            self.metadataProjector.topologyDidChange(paneIDs: topology.panes.map(\.id))
            self.onChange?()
        }
        session.onConnectionStateChange = { [weak self] state in self?.receive(state) }
        session.setPresentationActive(false)
    }

    func start() async throws { try await session.start() }
    func stop() async { metadataProjector.stop(); await session.stop() }
    func setVisible(_ visible: Bool) {
        metadataProjector.setVisible(visible)
        session.setPresentationActive(visible)
    }
    func foregrounded() { metadataProjector.foregrounded() }
    func confirmTransportAfterForeground() async {
        guard await session.isControlChannelActive() else {
            status = .disconnected(String(localized: "Connection lost."))
            onChange?()
            onTransportLoss?(instanceID)
            return
        }
        foregrounded()
    }
    func metadata(for paneID: UInt64) -> AgentMetadata { agentMetadata[paneID] ?? .unknown }
    var agentSummary: AgentMetadata {
        agentMetadata.values.max { lhs, rhs in lhs.state.priority < rhs.state.priority } ?? .unknown
    }
    func selectWindow(_ id: UInt64) { session.selectWindow(id) }
    func selectPane(_ id: UInt64) { session.selectPane(id); onChange?() }
    func performSharedMutation(_ mutation: MoriRemoteTerminalSharedMutation) { session.performSharedMutation(mutation) }

    private func receive(_ state: MoriRemoteTerminalConnectionState) {
        switch state {
        case .connecting:
            status = .connecting
        case .ready:
            status = .ready
        case .disconnected:
            let wasDisconnected: Bool
            if case .disconnected = status { wasDisconnected = true } else { wasDisconnected = false }
            status = .disconnected(String(localized: "Connection lost."))
            // A thrown start error is already surfaced by connect(); only a
            // post-start transport transition earns the bounded reconnect.
            if !wasDisconnected, session.lastError == nil { onTransportLoss?(instanceID) }
        }
        onChange?()
    }
}

@MainActor @Observable
final class RemoteRootModel {
    private let dependencies: MoriRemoteDependencies
    private let reconnectPolicy = WorkspaceReconnectPolicy()
    private let memoryPressurePolicy = WorkspaceMemoryPressurePolicy()
    private var reconnectAttempts: [UUID: Int] = [:]
    private var deferredReconnects = Set<UUID>()
    private var connectionAttempts = WorkspaceConnectionAttemptLedger()
    private var loadingTask: Task<Void, Never>?
    private var bootstrapFailure: String?
    private var sceneIsActive = true

    private(set) var servers: [SavedServer] = []
    private(set) var workspaces: [SavedWorkspace] = []
    private(set) var identities: [SSHIdentity] = []
    private(set) var settings = RemoteSettings.default
    private(set) var runtimes: [UUID: ActiveWorkspaceRuntime] = [:]
    var activeWorkspaceID: UUID?
    var pendingTrust: SSHHostTrustChallenge?
    var errorMessage: String?
    var migrationReport: LegacyMigrationReport?
    var runtimeRevision = 0
    private var pendingTrustWorkspaceID: UUID?
    private(set) var isLoaded = false
    var libraryLoadError: String? { bootstrapFailure }
    var isBootstrapping: Bool { loadingTask != nil }

    init(dependencies: MoriRemoteDependencies = .live()) { self.dependencies = dependencies }

    var activeRuntime: ActiveWorkspaceRuntime? { activeWorkspaceID.flatMap { runtimes[$0] } }
    var activeWorkspaces: [SavedWorkspace] { workspaces.filter { runtimes[$0.id] != nil } }
    func agentSummary(for workspaceID: UUID) -> AgentMetadata { runtimes[workspaceID]?.agentSummary ?? .unknown }
    func metadata(for workspaceID: UUID, paneID: UInt64) -> AgentMetadata { runtimes[workspaceID]?.metadata(for: paneID) ?? .unknown }

    func bootstrap() {
        guard !isLoaded, loadingTask == nil else { return }
        bootstrapFailure = nil
        loadingTask = Task { [weak self] in
            guard let self else { return }
            defer { self.loadingTask = nil }
            do {
                let snapshot = try await self.dependencies.library.bootstrap()
                self.apply(snapshot)
            } catch {
                self.bootstrapFailure = error.localizedDescription
            }
        }
    }

    func save(_ draft: ServerWorkspaceDraft, existingServer: SavedServer? = nil) {
        Task {
            do {
                let currentIdentity = existingServer.flatMap { server in identities.first { $0.id == server.identityID } }
                let records = try draft.records(existingIdentityID: currentIdentity?.id)
                let snapshot = try await dependencies.library.save(server: records.0, workspace: records.1, identity: records.2, credential: records.3)
                apply(snapshot)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func save(_ draft: WorkspaceDraft) {
        Task {
            do {
                let snapshot = try await dependencies.library.save(workspace: draft.record())
                apply(snapshot)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func delete(workspace: SavedWorkspace) {
        connectionAttempts.cancel(workspaceID: workspace.id)
        Task {
            do {
                await disconnect(workspaceID: workspace.id)
                let snapshot = try await dependencies.library.delete(workspaceID: workspace.id)
                apply(snapshot)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func delete(_ server: SavedServer) {
        let serverWorkspaces = workspaces.filter { $0.serverID == server.id }
        serverWorkspaces.forEach { connectionAttempts.cancel(workspaceID: $0.id) }
        Task {
            do {
                for workspace in serverWorkspaces { await disconnect(workspaceID: workspace.id) }
                let snapshot = try await dependencies.library.delete(serverID: server.id)
                apply(snapshot)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func save(settings: RemoteSettings) {
        Task {
            do {
                let snapshot = try await dependencies.library.save(settings: settings)
                apply(snapshot)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func connect(workspaceID: UUID, automatic: Bool = false, activating: Bool? = nil) {
        let shouldActivate = activating ?? (!automatic || activeWorkspaceID == nil || activeWorkspaceID == workspaceID)
        deferredReconnects.remove(workspaceID)
        if let runtime = runtimes[workspaceID] {
            if case .disconnected = runtime.status {
                // A background loss leaves its one-shot runtime intact until
                // foregrounding or an explicit tap. Never "activate" a dead
                // surface and strand the user without a reconnect path.
                Task { [weak self] in
                    await self?.disconnect(workspaceID: workspaceID)
                    self?.connect(workspaceID: workspaceID, automatic: automatic)
                }
            } else if shouldActivate {
                activate(workspaceID: workspaceID)
            }
            return
        }
        guard let attempt = connectionAttempts.begin(workspaceID: workspaceID) else { return }
        Task { [weak self] in
            guard let self else { return }
            var runtime: ActiveWorkspaceRuntime?
            do {
                let material = try await self.dependencies.library.connectionMaterial(for: workspaceID)
                guard self.attemptIsCurrent(attempt, workspaceID: workspaceID) else { return }
                let auth = try await self.dependencies.library.resolveAuth(server: material.1, identity: material.2, settings: material.3)
                guard self.attemptIsCurrent(attempt, workspaceID: workspaceID) else { return }
                let endpoint = try CanonicalEndpoint(host: material.1.host, port: material.1.port)
                let key = SSHRootPool.Key(serverID: material.1.id, endpoint: endpoint, username: material.1.username, authenticationFingerprint: auth.rootPoolFingerprint)
                let instanceID = UUID()
                let transport = SSHTmuxControlTransport(
                    connector: CitadelSSHRootConnector(server: material.1, auth: auth, trust: SSHHostTrustResolver(store: self.dependencies.trustedHosts)),
                    pool: self.dependencies.roots,
                    poolKey: key,
                    sourceSession: material.0.tmuxSession,
                    runtimeID: instanceID
                )
                let created = try ActiveWorkspaceRuntime(
                    workspace: material.0,
                    settings: material.3,
                    transport: transport.asTerminalTransport(),
                    instanceID: instanceID
                )
                runtime = created
                guard self.attemptIsCurrent(attempt, workspaceID: workspaceID) else { await created.stop(); return }
                created.onTransportLoss = { [weak self] id in self?.lost(workspaceID: workspaceID, instanceID: id) }
                created.onChange = { [weak self, weak created] in
                    guard let self, self.runtimes[workspaceID] === created else { return }
                    self.runtimeRevision &+= 1
                }
                self.runtimes[workspaceID] = created
                // An automatic reconnect must not steal focus from another
                // healthy workspace. If the lost workspace was focused,
                // disconnect() cleared the active ID and it is restored here.
                if shouldActivate {
                    self.activate(workspaceID: workspaceID)
                }
                try await created.start()
                guard self.attemptIsCurrent(attempt, workspaceID: workspaceID), self.runtimes[workspaceID] === created else { await self.stop(created, workspaceID: workspaceID); return }
                let snapshot = try await self.dependencies.library.markConnected(workspaceID: workspaceID)
                guard self.attemptIsCurrent(attempt, workspaceID: workspaceID), self.runtimes[workspaceID] === created else { await self.stop(created, workspaceID: workspaceID); return }
                self.apply(snapshot)
                self.reconnectAttempts[workspaceID] = 0
                self.connectionAttempts.end(attempt, for: workspaceID)
            } catch let error as SSHHostTrustError {
                guard self.attemptIsCurrent(attempt, workspaceID: workspaceID) else { if let runtime { await self.stop(runtime, workspaceID: workspaceID) }; return }
                if let runtime { await self.stop(runtime, workspaceID: workspaceID) }
                self.connectionAttempts.end(attempt, for: workspaceID)
                switch SSHTrustPresentation.resolve(error) {
                case let .challenge(challenge):
                    self.errorMessage = nil
                    self.pendingTrust = challenge
                    self.pendingTrustWorkspaceID = workspaceID
                case let .error(message):
                    self.pendingTrust = nil
                    self.pendingTrustWorkspaceID = nil
                    self.errorMessage = message
                }
            } catch {
                guard self.attemptIsCurrent(attempt, workspaceID: workspaceID) else { if let runtime { await self.stop(runtime, workspaceID: workspaceID) }; return }
                if let runtime { await self.stop(runtime, workspaceID: workspaceID) }
                self.connectionAttempts.end(attempt, for: workspaceID)
                if !automatic { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func dismissTrust() {
        pendingTrust = nil
        pendingTrustWorkspaceID = nil
    }

    func confirmTrust(_ challenge: SSHHostTrustChallenge, replaceChanged: Bool) {
        Task {
            do {
                try await dependencies.library.trust(challenge, replaceChanged: replaceChanged)
                let workspaceID = pendingTrustWorkspaceID
                pendingTrust = nil
                pendingTrustWorkspaceID = nil
                errorMessage = nil
                if let workspaceID { connect(workspaceID: workspaceID) }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func disconnect(workspaceID: UUID) async {
        connectionAttempts.cancel(workspaceID: workspaceID)
        deferredReconnects.remove(workspaceID)
        guard let runtime = runtimes.removeValue(forKey: workspaceID) else { return }
        if activeWorkspaceID == workspaceID { activeWorkspaceID = nil }
        runtime.setVisible(false)
        await runtime.stop()
    }

    func disconnectActive() { if let activeWorkspaceID { Task { await disconnect(workspaceID: activeWorkspaceID) } } }
    func selectWindow(_ id: UInt64) { activeRuntime?.selectWindow(id) }
    func selectPane(_ id: UInt64) { activeRuntime?.selectPane(id) }
    func performSharedMutation(_ mutation: MoriRemoteTerminalSharedMutation) {
        activeRuntime?.performSharedMutation(mutation)
    }
    /// Scene activation is intentionally metadata-only: reconnect remains
    /// reserved for a real control-transport loss. Backgrounding stops the
    /// visible-runtime poll; foregrounding starts one immediate refresh.
    func scenePhaseChanged(_ phase: ScenePhase) {
        sceneIsActive = phase == .active
        activeRuntime?.setVisible(sceneIsActive)
        guard sceneIsActive else { return }
        // A loss can occur in any live workspace while iOS suspends this scene.
        // Drain all deferred attempts before probing the focused one; otherwise
        // inactive runtimes retain a dead native surface forever.
        let deferred = deferredReconnects.sorted { $0.uuidString < $1.uuidString }
        let activeBeforeReconnect = activeWorkspaceID
        deferredReconnects.removeAll()
        for workspaceID in deferred {
            let shouldActivate = activeBeforeReconnect == nil || activeBeforeReconnect == workspaceID
            if let runtime = runtimes[workspaceID] {
                reconnectAfterTransportLoss(workspaceID: workspaceID, instanceID: runtime.instanceID, activating: shouldActivate)
            } else {
                connect(workspaceID: workspaceID, automatic: true, activating: shouldActivate)
            }
        }
        guard let workspaceID = activeWorkspaceID, let runtime = runtimes[workspaceID] else { return }
        Task { [weak self, weak runtime] in
            guard let self, self.runtimes[workspaceID] === runtime else { return }
            await runtime?.confirmTransportAfterForeground()
        }
    }

    func handleMemoryWarning() {
        let dormant = memoryPressurePolicy.workspaceIDsToDisconnect(active: activeWorkspaceID, all: runtimes.keys)
        guard !dormant.isEmpty else { return }
        Task { [weak self] in
            for workspaceID in dormant { await self?.disconnect(workspaceID: workspaceID) }
        }
    }

    private func activate(workspaceID: UUID) {
        guard activeWorkspaceID != workspaceID else {
            runtimes[workspaceID]?.setVisible(sceneIsActive)
            return
        }
        if let activeWorkspaceID { runtimes[activeWorkspaceID]?.setVisible(false) }
        activeWorkspaceID = workspaceID
        runtimes[workspaceID]?.setVisible(sceneIsActive)
    }

    private func attemptIsCurrent(_ attempt: UUID, workspaceID: UUID) -> Bool {
        connectionAttempts.isCurrent(attempt, for: workspaceID)
    }

    private func stop(_ runtime: ActiveWorkspaceRuntime, workspaceID: UUID) async {
        if runtimes[workspaceID] === runtime {
            runtimes[workspaceID] = nil
            if activeWorkspaceID == workspaceID { activeWorkspaceID = nil }
        }
        runtime.setVisible(false)
        await runtime.stop()
    }

    private func lost(workspaceID: UUID, instanceID: UUID) {
        guard runtimes[workspaceID]?.instanceID == instanceID else { return }
        let attempts = reconnectAttempts[workspaceID, default: 0]
        guard reconnectPolicy.mayReconnect(status: runtimes[workspaceID]?.status ?? .disconnected(""), attempts: attempts) else { return }
        reconnectAttempts[workspaceID] = attempts + 1
        guard sceneIsActive else {
            deferredReconnects.insert(workspaceID)
            return
        }
        reconnectAfterTransportLoss(workspaceID: workspaceID, instanceID: instanceID, activating: activeWorkspaceID == nil || activeWorkspaceID == workspaceID)
    }

    private func reconnectAfterTransportLoss(workspaceID: UUID, instanceID: UUID, activating: Bool) {
        Task { [weak self] in
            guard let self, self.runtimes[workspaceID]?.instanceID == instanceID else { return }
            await disconnect(workspaceID: workspaceID)
            try? await Task.sleep(for: .seconds(1))
            guard self.sceneIsActive else {
                self.deferredReconnects.insert(workspaceID)
                return
            }
            self.connect(workspaceID: workspaceID, automatic: true, activating: activating)
        }
    }

    private func apply(_ snapshot: RemoteLibrarySnapshot) {
        servers = snapshot.servers
        workspaces = snapshot.workspaces
        identities = snapshot.identities
        settings = snapshot.settings
        migrationReport = snapshot.migration
        isLoaded = true
    }
}
