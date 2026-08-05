import Foundation
import MoriRemoteTerminal
import Observation
import SwiftUI

struct ServerProfileDraft: Identifiable, Sendable {
    let id: UUID
    let serverLastConnectedAt: Date?
    var serverName: String
    var host: String
    var port: String
    var username: String
    var identityKind: SSHIdentityKind
    var password: String
    var privateKey: String
    var passphrase: String

    init(server: SavedServer? = nil, identity: SSHIdentity? = nil) {
        id = server?.id ?? UUID()
        serverLastConnectedAt = server?.lastConnectedAt
        serverName = server?.name ?? ""
        host = server?.host ?? ""
        port = String(server?.port ?? 22)
        username = server?.username ?? ""
        identityKind = identity?.kind ?? .password
        password = ""
        privateKey = ""
        passphrase = ""
    }

    func records(existingIdentityID: UUID? = nil) throws -> (SavedServer, SSHIdentity, ProfileCredential?) {
        guard let port = Int(port) else { throw SavedModelValidationError.invalidPort }
        let identityID = existingIdentityID ?? id
        let server = SavedServer(id: id, name: serverName, host: host, port: port, username: username, identityID: identityID, lastConnectedAt: serverLastConnectedAt)
        let identity = SSHIdentity(id: identityID, serverID: id, kind: identityKind, label: identityKind == .password ? "password" : "private key")
        let credential: ProfileCredential?
        switch identityKind {
        case .password: credential = password.isEmpty ? nil : .password(password)
        case .privateKey:
            credential = privateKey.isEmpty ? nil : .privateKey(.init(privateKeyPEM: privateKey, passphrase: passphrase.isEmpty ? nil : passphrase))
        }
        return (try server.validated(), try identity.validated(), credential)
    }
}

enum RemoteNavigatorProjection {
    static func sessions(_ values: [SavedWorkspace], matching query: String) -> [SavedWorkspace] {
        values.filter { query.isEmpty || $0.tmuxSession.localizedCaseInsensitiveContains(query) }
    }

    static func windows(_ values: [MoriRemoteTerminalWindow], matching query: String) -> [MoriRemoteTerminalWindow] {
        values.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || String($0.id).contains(query) }
    }

    static func panes(
        _ values: [MoriRemoteTerminalPane],
        windows: [MoriRemoteTerminalWindow],
        matching query: String
    ) -> [MoriRemoteTerminalPane] {
        values.filter { pane in
            let windowTitle = windows.first(where: { $0.id == pane.windowID })?.title ?? ""
            return query.isEmpty || String(pane.id).contains(query) || windowTitle.localizedCaseInsensitiveContains(query)
        }
    }

    static func attention(_ values: [AgentAttentionWorkspaceTarget], matching query: String) -> [AgentAttentionWorkspaceTarget] {
        values.filter { value in
            let target = value.target
            return query.isEmpty
                || value.workspace.tmuxSession.localizedCaseInsensitiveContains(query)
                || target.windowTitle.localizedCaseInsensitiveContains(query)
                || String(target.paneID).contains(query)
                || (target.metadata.name?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
}

enum ServerSessionDiscoveryStatus: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum PendingSSHTrustAction: Equatable, Sendable {
    case connect(UUID)
    case discover(UUID)
}

struct AgentAttentionWorkspaceTarget: Identifiable, Equatable, Sendable {
    let workspace: SavedWorkspace
    let target: AgentAttentionTarget

    var id: UInt64 { target.id }
}

/// A selection from the host-wide snapshot cannot target a runtime until that
/// runtime has published the exact source topology. The instance fence drops a
/// late topology callback from a replaced control client.
struct PendingAgentAttentionSelection: Equatable, Sendable {
    let workspaceID: UUID
    let windowID: UInt64
    let paneID: UInt64
    private(set) var runtimeInstanceID: UUID?

    init(workspaceID: UUID, windowID: UInt64, paneID: UInt64) {
        self.workspaceID = workspaceID
        self.windowID = windowID
        self.paneID = paneID
    }

    mutating func bind(runtimeInstanceID: UUID) { self.runtimeInstanceID = runtimeInstanceID }

    func matches(workspaceID: UUID, runtimeInstanceID: UUID, topology: MoriRemoteTerminalTopology) -> Bool {
        self.workspaceID == workspaceID
            && self.runtimeInstanceID == runtimeInstanceID
            && topology.windows.contains(where: { $0.id == windowID })
            && topology.panes.contains(where: { $0.id == paneID && $0.windowID == windowID })
    }
}

enum WorkspaceRuntimeStatus: Equatable {
    case connecting
    case ready
    case disconnected(String)

    var title: String {
        switch self {
        case .connecting: String(localized: "Connecting…")
        case .ready: String(localized: "Connected")
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

@MainActor @Observable
final class ActiveWorkspaceRuntime {
    let workspace: SavedWorkspace
    let instanceID: UUID
    let session: MoriRemoteTerminalSession
    private let metadataProjector: AgentMetadataProjector
    private var metadataRevision: UInt64 = 0
    private(set) var topology: MoriRemoteTerminalTopology?
    var agentMetadata: [UInt64: AgentMetadata] {
        _ = metadataRevision
        return metadataProjector.metadata
    }
    var agentAttention: [AgentAttentionTarget] {
        _ = metadataRevision
        return metadataProjector.attention
    }
    var focusedPaneID: UInt64? {
        guard let activeWindowID = topology?.activeWindowID else { return nil }
        return topology?.windows.first(where: { $0.id == activeWindowID })?.activePaneID
    }
    private(set) var status: WorkspaceRuntimeStatus = .connecting
    var onTransportLoss: (@MainActor (UUID) -> Void)?
    var onTopologyChange: (@MainActor (MoriRemoteTerminalTopology) -> Void)?

    init(
        workspace: SavedWorkspace,
        settings: RemoteSettings,
        transport: MoriRemoteTerminalTransport,
        instanceID: UUID = UUID(),
        carriedViewport: TmuxControlViewport? = nil
    ) throws {
        self.workspace = workspace
        self.instanceID = instanceID
        session = try MoriRemoteTerminalSession(
            transport: transport,
            initialScrollbackLines: settings.effectiveInitialScrollbackLines,
            instanceID: instanceID,
            carriedViewport: carriedViewport
        )
        metadataProjector = AgentMetadataProjector(instanceID: instanceID) { [session] in
            let result = await session.queryAgentMetadata()
            return .init(succeeded: result.status == .success, body: result.body)
        }
        metadataProjector.onChange = { [weak self] in self?.metadataRevision &+= 1 }
        session.onTopologyChange = { [weak self] topology in
            guard let self else { return }
            self.topology = topology
            self.status = .ready
            self.metadataProjector.topologyDidChange(paneIDs: topology.panes.map(\.id))
            self.onTopologyChange?(topology)
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
    var carriedViewport: TmuxControlViewport? { session.carriedViewport }
    func confirmTransportAfterForeground() async {
        guard await session.isControlChannelActive() else {
            status = .disconnected(String(localized: "Connection lost."))
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
    func selectPane(_ id: UInt64) { session.selectPane(id) }
    func performSharedMutation(_ mutation: MoriRemoteTerminalSharedMutation) { session.performSharedMutation(mutation) }

    private func receive(_ state: MoriRemoteTerminalConnectionState) {
        switch state {
        case .connecting:
            // A late syncing notification may race the topology callback. Once
            // topology exists, the rendered terminal is authoritative and ready.
            if topology == nil { status = .connecting }
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
    private(set) var sessionDiscovery: [UUID: ServerSessionDiscoveryStatus] = [:]
    private var discoveredSessionNames: [UUID: Set<String>] = [:]
    var activeWorkspaceID: UUID?
    var pendingTrust: SSHHostTrustChallenge?
    var errorMessage: String?
    var migrationReport: LegacyMigrationReport?
    private var pendingTrustAction: PendingSSHTrustAction?
    private var pendingAgentAttentionSelection: PendingAgentAttentionSelection?
    private(set) var isLoaded = false
    var libraryLoadError: String? { bootstrapFailure }
    var isBootstrapping: Bool { loadingTask != nil }

    init(dependencies: MoriRemoteDependencies = .live()) { self.dependencies = dependencies }

    var activeRuntime: ActiveWorkspaceRuntime? { activeWorkspaceID.flatMap { runtimes[$0] } }
    var activeWorkspaces: [SavedWorkspace] { workspaces.filter { runtimes[$0.id] != nil } }
    func visibleWorkspaces(for serverID: UUID) -> [SavedWorkspace] {
        let discovered = discoveredSessionNames[serverID]
        let candidates = workspaces.filter {
            $0.serverID == serverID && (discovered == nil || discovered?.contains($0.tmuxSession) == true)
        }
        return Dictionary(grouping: candidates, by: \.tmuxSession)
            .values
            .compactMap { duplicates in
                duplicates.max { lhs, rhs in
                    let lhsActive = runtimes[lhs.id] != nil
                    let rhsActive = runtimes[rhs.id] != nil
                    if lhsActive != rhsActive { return !lhsActive && rhsActive }
                    return (lhs.lastConnectedAt ?? .distantPast, lhs.id.uuidString)
                        < (rhs.lastConnectedAt ?? .distantPast, rhs.id.uuidString)
                }
            }
            .sorted { $0.tmuxSession.localizedStandardCompare($1.tmuxSession) == .orderedAscending }
    }
    func agentSummary(for workspaceID: UUID) -> AgentMetadata { runtimes[workspaceID]?.agentSummary ?? .unknown }
    func metadata(for workspaceID: UUID, paneID: UInt64) -> AgentMetadata { runtimes[workspaceID]?.metadata(for: paneID) ?? .unknown }
    func agentAttention(for serverID: UUID) -> [AgentAttentionWorkspaceTarget] {
        guard activeRuntime?.workspace.serverID == serverID else { return [] }
        return activeRuntime?.agentAttention.compactMap { target in
            workspace(serverID: serverID, tmuxSession: target.sessionName).map {
                .init(workspace: $0, target: target)
            }
        } ?? []
    }
    func agentAttentionSummary(for serverID: UUID) -> AgentAttentionSummary {
        AgentAttentionProjection.summary(agentAttention(for: serverID).map(\.target))
    }

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

    func save(_ draft: ServerProfileDraft, existingServer: SavedServer? = nil) {
        Task {
            do {
                let currentIdentity = existingServer.flatMap { server in identities.first { $0.id == server.identityID } }
                let records = try draft.records(existingIdentityID: currentIdentity?.id)
                let snapshot = try await dependencies.library.save(server: records.0, identity: records.1, credential: records.2)
                apply(snapshot)
                discoverSessions(serverID: records.0.id)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func discoverSessions(serverID: UUID) {
        guard sessionDiscovery[serverID] != .loading else { return }
        sessionDiscovery[serverID] = .loading
        Task { [weak self] in
            guard let self else { return }
            do {
                let root = try await self.dependencies.sshRoots.server(serverID)
                let names = try await SSHTmuxSessionDiscovery(rootSource: root).load()
                let snapshot = try await self.dependencies.library.synchronizeDiscoveredSessions(serverID: serverID, names: names)
                self.apply(snapshot)
                self.discoveredSessionNames[serverID] = Set(names)
                self.sessionDiscovery[serverID] = .loaded
            } catch let error as SSHHostTrustError {
                switch SSHTrustPresentation.resolve(error) {
                case let .challenge(challenge):
                    self.errorMessage = nil
                    self.pendingTrust = challenge
                    self.pendingTrustAction = .discover(serverID)
                    self.sessionDiscovery[serverID] = .idle
                case let .error(message):
                    self.sessionDiscovery[serverID] = .failed(message)
                }
            } catch {
                self.sessionDiscovery[serverID] = .failed(error.localizedDescription)
            }
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

    func connect(
        workspaceID: UUID,
        automatic: Bool = false,
        activating: Bool? = nil,
        carriedViewport: TmuxControlViewport? = nil
    ) {
        if !automatic, pendingAgentAttentionSelection?.workspaceID != workspaceID {
            pendingAgentAttentionSelection = nil
        }
        let shouldActivate = activating ?? (!automatic || activeWorkspaceID == nil || activeWorkspaceID == workspaceID)
        deferredReconnects.remove(workspaceID)
        if let runtime = runtimes[workspaceID] {
            if case .disconnected = runtime.status {
                // A background loss leaves its one-shot runtime intact until
                // foregrounding or an explicit tap. Never "activate" a dead
                // surface and strand the user without a reconnect path.
                let carriedViewport = automatic ? (carriedViewport ?? runtime.carriedViewport) : nil
                Task { [weak self] in
                    await self?.disconnect(workspaceID: workspaceID, clearingPendingAttentionSelection: false)
                    self?.connect(
                        workspaceID: workspaceID,
                        automatic: automatic,
                        carriedViewport: carriedViewport
                    )
                }
            } else if shouldActivate {
                activate(workspaceID: workspaceID)
                bindPendingAttentionSelection(to: runtime, workspaceID: workspaceID)
            }
            return
        }
        guard let attempt = connectionAttempts.begin(workspaceID: workspaceID) else { return }
        Task { [weak self] in
            guard let self else { return }
            var runtime: ActiveWorkspaceRuntime?
            do {
                let access = try await self.dependencies.sshRoots.workspace(workspaceID)
                guard self.attemptIsCurrent(attempt, workspaceID: workspaceID) else { return }
                let instanceID = UUID()
                let transport = SSHTmuxControlTransport(
                    rootSource: access.root,
                    sourceSession: access.workspace.tmuxSession,
                    runtimeID: instanceID
                )
                let created = try ActiveWorkspaceRuntime(
                    workspace: access.workspace,
                    settings: access.settings,
                    transport: transport.asTerminalTransport(),
                    instanceID: instanceID,
                    carriedViewport: carriedViewport
                )
                runtime = created
                guard self.attemptIsCurrent(attempt, workspaceID: workspaceID) else { await created.stop(); return }
                created.onTransportLoss = { [weak self] id in self?.lost(workspaceID: workspaceID, instanceID: id) }
                created.onTopologyChange = { [weak self] topology in
                    self?.receivedTopology(workspaceID: workspaceID, instanceID: instanceID, topology: topology)
                }
                self.runtimes[workspaceID] = created
                self.bindPendingAttentionSelection(to: created, workspaceID: workspaceID)
                // An automatic reconnect must not steal focus from another
                // healthy workspace. If the lost workspace was focused,
                // disconnect() cleared the active ID and it is restored here.
                // A later attention tap may also upgrade an already-admitted
                // background attempt into an explicit activation request.
                if shouldActivate || self.pendingAgentAttentionSelection?.workspaceID == workspaceID {
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
                    self.pendingTrustAction = .connect(workspaceID)
                case let .error(message):
                    self.clearPendingAttentionSelection(for: workspaceID)
                    self.pendingTrust = nil
                    self.pendingTrustAction = nil
                    self.errorMessage = message
                }
            } catch {
                guard self.attemptIsCurrent(attempt, workspaceID: workspaceID) else { if let runtime { await self.stop(runtime, workspaceID: workspaceID) }; return }
                if let runtime { await self.stop(runtime, workspaceID: workspaceID) }
                self.clearPendingAttentionSelection(for: workspaceID)
                self.connectionAttempts.end(attempt, for: workspaceID)
                if !automatic { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func dismissTrust() {
        if case let .connect(workspaceID) = pendingTrustAction {
            clearPendingAttentionSelection(for: workspaceID)
        }
        pendingTrust = nil
        pendingTrustAction = nil
    }

    func confirmTrust(_ challenge: SSHHostTrustChallenge, replaceChanged: Bool) {
        Task {
            do {
                try await dependencies.library.trust(challenge, replaceChanged: replaceChanged)
                let action = pendingTrustAction
                pendingTrust = nil
                pendingTrustAction = nil
                errorMessage = nil
                switch action {
                case let .connect(workspaceID): connect(workspaceID: workspaceID)
                case let .discover(serverID): discoverSessions(serverID: serverID)
                case nil: break
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func disconnect(workspaceID: UUID, clearingPendingAttentionSelection: Bool = true) async {
        connectionAttempts.cancel(workspaceID: workspaceID)
        deferredReconnects.remove(workspaceID)
        if clearingPendingAttentionSelection { clearPendingAttentionSelection(for: workspaceID) }
        guard let runtime = runtimes.removeValue(forKey: workspaceID) else { return }
        if activeWorkspaceID == workspaceID { activeWorkspaceID = nil }
        runtime.setVisible(false)
        await runtime.stop()
    }

    func disconnectActive() { if let activeWorkspaceID { Task { await disconnect(workspaceID: activeWorkspaceID) } } }
    func selectWindow(_ id: UInt64) {
        pendingAgentAttentionSelection = nil
        activeRuntime?.selectWindow(id)
    }
    func selectPane(_ id: UInt64) {
        pendingAgentAttentionSelection = nil
        activeRuntime?.selectPane(id)
    }
    func selectAttentionTarget(_ target: AgentAttentionWorkspaceTarget) {
        pendingAgentAttentionSelection = .init(
            workspaceID: target.workspace.id,
            windowID: target.target.windowID,
            paneID: target.target.paneID
        )
        connect(workspaceID: target.workspace.id, activating: true)
    }
    func performSharedMutation(_ mutation: MoriRemoteTerminalSharedMutation) {
        activeRuntime?.performSharedMutation(mutation)
    }

    func imageUploader(for workspaceID: UUID) -> MoriRemoteTerminalImageUploader {
        SSHImageUploadService(sshRoots: dependencies.sshRoots).uploader(for: workspaceID)
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

    private func workspace(serverID: UUID, tmuxSession: String) -> SavedWorkspace? {
        workspaces
            .filter { $0.serverID == serverID && $0.tmuxSession == tmuxSession }
            .max { lhs, rhs in
                let lhsActive = runtimes[lhs.id] != nil
                let rhsActive = runtimes[rhs.id] != nil
                if lhsActive != rhsActive { return !lhsActive && rhsActive }
                return (lhs.lastConnectedAt ?? .distantPast, lhs.id.uuidString)
                    < (rhs.lastConnectedAt ?? .distantPast, rhs.id.uuidString)
            }
    }

    private func bindPendingAttentionSelection(to runtime: ActiveWorkspaceRuntime, workspaceID: UUID) {
        guard pendingAgentAttentionSelection?.workspaceID == workspaceID else { return }
        pendingAgentAttentionSelection?.bind(runtimeInstanceID: runtime.instanceID)
        bindAndApplyPendingAttentionSelection(using: runtime, workspaceID: workspaceID)
    }

    private func bindAndApplyPendingAttentionSelection(using runtime: ActiveWorkspaceRuntime, workspaceID: UUID) {
        guard let topology = runtime.topology else { return }
        receivedTopology(workspaceID: workspaceID, instanceID: runtime.instanceID, topology: topology)
    }

    private func receivedTopology(workspaceID: UUID, instanceID: UUID, topology: MoriRemoteTerminalTopology) {
        guard let selection = pendingAgentAttentionSelection,
              selection.matches(workspaceID: workspaceID, runtimeInstanceID: instanceID, topology: topology),
              runtimes[workspaceID]?.instanceID == instanceID
        else { return }
        pendingAgentAttentionSelection = nil
        runtimes[workspaceID]?.selectPane(selection.paneID)
    }

    private func clearPendingAttentionSelection(for workspaceID: UUID) {
        guard pendingAgentAttentionSelection?.workspaceID == workspaceID else { return }
        pendingAgentAttentionSelection = nil
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
            let carriedViewport = self.runtimes[workspaceID]?.carriedViewport
            await disconnect(workspaceID: workspaceID, clearingPendingAttentionSelection: false)
            try? await Task.sleep(for: .seconds(1))
            guard self.sceneIsActive else {
                self.deferredReconnects.insert(workspaceID)
                return
            }
            self.connect(
                workspaceID: workspaceID,
                automatic: true,
                activating: activating,
                carriedViewport: carriedViewport
            )
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
