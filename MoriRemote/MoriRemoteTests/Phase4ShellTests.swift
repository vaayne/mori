import Foundation
import Observation
import Security
import Testing
import MoriRemoteTerminal
@testable import MoriRemote

@Suite("Phase 4 app shell contracts") struct Phase4ShellTests {


    @Test("reconnect policy retries only a transport loss once")
    func reconnectPolicy() {
        let policy = WorkspaceReconnectPolicy()
        #expect(policy.mayReconnect(status: .disconnected("lost"), attempts: 0))
        #expect(!policy.mayReconnect(status: .disconnected("lost"), attempts: 1))
        #expect(!policy.mayReconnect(status: .ready, attempts: 0))
        #expect(!policy.mayReconnect(status: .connecting, attempts: 0))
    }

    @Test("runtime state changes invalidate direct observers")
    @MainActor
    func runtimeObservation() async throws {
        let workspace = try SavedWorkspace(
            serverID: UUID(),
            name: "main",
            tmuxSession: "main"
        ).validated()
        let bytes = AsyncThrowingStream<Data, Error> { $0.finish() }
        let runtime = try ActiveWorkspaceRuntime(
            workspace: workspace,
            settings: .default,
            transport: .init(
                receivedBytes: bytes,
                start: { _ in },
                send: { _ in },
                close: { _ in },
                isActive: { false }
            )
        )
        let observation = ObservationFlag()
        withObservationTracking {
            _ = runtime.status
        } onChange: {
            observation.markChanged()
        }

        await runtime.stop()

        #expect(observation.didChange)
    }

    @Test("new profile draft saves only the server and identity")
    func profileDraftValidation() throws {
        var draft = ServerProfileDraft()
        draft.serverName = "Build"
        draft.host = "build.example"
        draft.port = "22"
        draft.username = "mori"
        let records = try draft.records()
        #expect(records.0.identityID == records.1.id)
        #expect(records.1.serverID == records.0.id)
    }

    @Test("tmux discovery lists source sessions and hides MoriRemote shadows")
    func tmuxSessionDiscoveryProjection() throws {
        let shadowID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let output = "zeta\nmain\nmain--mori-remote-\(shadowID.uuidString.lowercased())\nalpha\nmain\n"
        #expect(TmuxSessionList.parse(output).names == ["alpha", "main", "zeta"])
        #expect(try TmuxCommandBuilder.listSessions(executable: "tmux").contains("'list-sessions' '-F' '#{session_name}'"))
    }

    @Test("discovered sessions reuse saved identities and add only missing sessions")
    func synchronizeDiscoveredSessions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = MoriRemoteStorage(root: root)
        let library = RemoteLibrary(storage: storage, migrator: LegacyServerMigrator(storage: storage, legacyServersURL: root.appendingPathComponent("legacy.json")))
        let serverID = UUID(), workspaceID = UUID()
        let server = SavedServer(id: serverID, name: "Build", host: "build.example", username: "mori", identityID: serverID)
        let identity = SSHIdentity(id: serverID, serverID: serverID, kind: .password)
        let main = SavedWorkspace(id: workspaceID, serverID: serverID, name: "Main", tmuxSession: "main")
        _ = try await library.save(server: server, identity: identity, credential: nil)
        _ = try storage.workspaces.insertIfAbsent(main)

        let first = try await library.synchronizeDiscoveredSessions(serverID: serverID, names: ["main", "ops"])
        #expect(first.workspaces.first(where: { $0.tmuxSession == "main" })?.id == workspaceID)
        #expect(Set(first.workspaces.map(\.tmuxSession)) == ["main", "ops"])
        let second = try await library.synchronizeDiscoveredSessions(serverID: serverID, names: ["main", "ops"])
        #expect(second.workspaces.count == 2)
    }

    @Test("navigator filters sessions, windows, and panes within their scopes")
    func navigatorFiltering() {
        let serverID = UUID()
        let sessions = [
            SavedWorkspace(serverID: serverID, name: "Main", tmuxSession: "cs/main"),
            SavedWorkspace(serverID: serverID, name: "Backup", tmuxSession: "cs/backup-v2"),
        ]
        #expect(RemoteNavigatorProjection.sessions(sessions, matching: "BACKUP").map(\.tmuxSession) == ["cs/backup-v2"])

        let windows = [
            MoriRemoteTerminalWindow(id: 1, title: "editor", active: true, activePaneID: 10),
            MoriRemoteTerminalWindow(id: 2, title: "deploy", active: false, activePaneID: 20),
        ]
        let panes = [
            MoriRemoteTerminalPane(id: 10, windowID: 1, columns: 120, rows: 40),
            MoriRemoteTerminalPane(id: 20, windowID: 2, columns: 80, rows: 24),
        ]
        #expect(RemoteNavigatorProjection.windows(windows, matching: "DEPLOY").map(\.id) == [2])
        #expect(RemoteNavigatorProjection.panes(panes, windows: windows, matching: "editor").map(\.id) == [10])
        #expect(RemoteNavigatorProjection.panes(panes, windows: windows, matching: "20").map(\.id) == [20])

        let workspace = SavedWorkspace(serverID: serverID, name: "Main", tmuxSession: "cs/main")
        let attention = AgentAttentionWorkspaceTarget(
            workspace: workspace,
            target: .init(
                sessionName: "cs/main", windowID: 1, windowTitle: "editor", paneID: 10,
                metadata: .init(state: .waiting, name: "claude")
            )
        )
        #expect(RemoteNavigatorProjection.attention([attention], matching: "claude") == [attention])
    }

    @Test("attention selection applies only to its fenced runtime topology")
    func fencedAttentionSelection() {
        let workspaceID = UUID(), runtimeID = UUID()
        var selection = PendingAgentAttentionSelection(workspaceID: workspaceID, windowID: 4, paneID: 8)
        let matching = MoriRemoteTerminalTopology(
            windows: [.init(id: 4, title: "editor", active: true, activePaneID: 8)],
            panes: [.init(id: 8, windowID: 4, columns: 120, rows: 40)],
            activeWindowID: 4
        )
        #expect(!selection.matches(workspaceID: workspaceID, runtimeInstanceID: runtimeID, topology: matching))
        selection.bind(runtimeInstanceID: runtimeID)
        #expect(selection.matches(workspaceID: workspaceID, runtimeInstanceID: runtimeID, topology: matching))
        #expect(!selection.matches(workspaceID: workspaceID, runtimeInstanceID: UUID(), topology: matching))
        #expect(!selection.matches(
            workspaceID: workspaceID,
            runtimeInstanceID: runtimeID,
            topology: .init(windows: [.init(id: 4, title: "editor", active: true, activePaneID: 9)], panes: [.init(id: 9, windowID: 4, columns: 120, rows: 40)], activeWindowID: 4)
        ))
    }

    @Test("connection attempt admission is synchronous and stale tokens cannot finish")
    func connectionAttemptLedger() {
        var attempts = WorkspaceConnectionAttemptLedger()
        let workspace = UUID()
        guard let first = attempts.begin(workspaceID: workspace) else { Issue.record("missing first attempt"); return }
        #expect(attempts.begin(workspaceID: workspace) == nil)
        #expect(attempts.isCurrent(first, for: workspace))
        attempts.cancel(workspaceID: workspace)
        #expect(!attempts.isCurrent(first, for: workspace))
        guard let replacement = attempts.begin(workspaceID: workspace) else { Issue.record("missing replacement attempt"); return }
        attempts.end(first, for: workspace)
        #expect(attempts.isCurrent(replacement, for: workspace))
        attempts.end(replacement, for: workspace)
        #expect(!attempts.isCurrent(replacement, for: workspace))
    }

    @Test("profile drafts preserve server identity and recency")
    func profileDraftPreservesServer() throws {
        let serverID = UUID(), identityID = UUID()
        let date = Date(timeIntervalSince1970: 123)
        let server = SavedServer(id: serverID, name: "Build", host: "build.example", username: "mori", identityID: identityID, lastConnectedAt: date)
        let draft = ServerProfileDraft(
            server: server,
            identity: SSHIdentity(id: identityID, serverID: serverID, kind: .password)
        )
        let records = try draft.records(existingIdentityID: identityID)
        #expect(records.0.id == serverID)
        #expect(records.0.lastConnectedAt == date)
        #expect(records.1.id == identityID)
    }

    @Test("profile persistence preserves recency and never inserts a server-edit workspace")
    func profilePersistencePreservesRecency() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = MoriRemoteStorage(root: root)
        let library = RemoteLibrary(storage: storage, migrator: LegacyServerMigrator(storage: storage, legacyServersURL: root.appendingPathComponent("legacy.json")))
        let serverID = UUID(), workspaceID = UUID(), identityID = UUID()
        let date = Date(timeIntervalSince1970: 456)
        let originalServer = SavedServer(id: serverID, name: "Build", host: "build.example", username: "mori", identityID: identityID, lastConnectedAt: date)
        let originalWorkspace = SavedWorkspace(id: workspaceID, serverID: serverID, name: "Build", tmuxSession: "build", lastConnectedAt: date)
        let identity = SSHIdentity(id: identityID, serverID: serverID, kind: .password)
        _ = try await library.save(server: originalServer, identity: identity, credential: nil)
        _ = try storage.workspaces.insertIfAbsent(originalWorkspace)
        let editedServer = SavedServer(id: serverID, name: "Renamed", host: "build.example", username: "mori", identityID: identityID)
        let snapshot = try await library.save(server: editedServer, identity: identity, credential: nil)
        #expect(snapshot.servers.first?.lastConnectedAt == date)
        #expect(snapshot.workspaces == [originalWorkspace])
        #expect((try await library.reload()).workspaces == [originalWorkspace])
    }

    @Test("stale SSH trust challenges become localized errors rather than disappearing")
    func staleTrustPresentation() {
        #expect(SSHTrustPresentation.resolve(.staleChallenge) == .error("The SSH host-key confirmation is no longer valid. Try again."))
    }

    @Test("scrollback settings clamp old values to the 2k to 10k contract")
    func scrollbackClamp() {
        #expect(RemoteSettings(initialScrollbackLines: 500).effectiveInitialScrollbackLines == 2_000)
        #expect(RemoteSettings(initialScrollbackLines: 8_000).effectiveInitialScrollbackLines == 8_000)
        #expect(RemoteSettings(initialScrollbackLines: 50_000).effectiveInitialScrollbackLines == 10_000)
    }

    @Test("memory pressure evicts only dormant workspace runtimes")
    func memoryPressurePolicy() {
        let active = UUID(), dormantA = UUID(), dormantB = UUID()
        let evicted = WorkspaceMemoryPressurePolicy().workspaceIDsToDisconnect(active: active, all: [active, dormantA, dormantB])
        #expect(Set(evicted) == [dormantA, dormantB])
        #expect(WorkspaceMemoryPressurePolicy().workspaceIDsToDisconnect(active: active, all: [active]).isEmpty)
    }

    @Test("Keychain writes are device-bound and require an unlocked device")
    func keychainProtection() {
        let attributes = MoriRemoteKeychainProtection.writeAttributes()
        let value = attributes[kSecAttrAccessible as String]!
        #expect(CFEqual(value as CFTypeRef, kSecAttrAccessibleWhenUnlockedThisDeviceOnly))
        let item = MoriRemoteKeychainProtection.item(service: "test", account: "account")
        #expect(item[kSecAttrService as String] as? String == "test")
        #expect(item[kSecAttrAccount as String] as? String == "account")
        #expect(KeychainCredentialStore().upgradesProtectionOnRead)
        let legacy = KeychainCredentialStore.legacyReader()
        #expect(legacy.service == KeychainCredentialStore.legacyService)
        #expect(!legacy.upgradesProtectionOnRead)
        #expect(!KeychainCredentialStore(service: KeychainCredentialStore.legacyService).upgradesProtectionOnRead)
    }

    @Test("profile JSON never contains password, private key, or passphrase")
    func profileJSONExcludesSecrets() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = MoriRemoteStorage(root: root)
        let passwords = MemoryProfilePasswords()
        let secrets = MemoryProfileSecrets()
        let library = RemoteLibrary(
            storage: storage,
            migrator: LegacyServerMigrator(storage: storage, legacyServersURL: root.appendingPathComponent("legacy.json")),
            passwords: passwords,
            secretData: secrets
        )
        let serverID = UUID()
        let identity = SSHIdentity(id: serverID, serverID: serverID, kind: .privateKey)
        let server = SavedServer(id: serverID, name: "Build", host: "build.example", username: "mori", identityID: serverID)
        let workspace = SavedWorkspace(id: UUID(), serverID: serverID, name: "Build", tmuxSession: "build")
        let privateKey = SSHPrivateKeyInspector.generateEd25519(comment: "audit").privateKeyPEM
        let passphrase = "phase6-passphrase"
        _ = try await library.save(server: server, identity: identity, credential: .privateKey(.init(privateKeyPEM: privateKey, passphrase: passphrase)))
        _ = try storage.workspaces.insertIfAbsent(workspace)
        let persisted = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .reduce(into: "") { $0 += (try? String(contentsOf: $1, encoding: .utf8)) ?? "" }
        #expect(!persisted.contains("BEGIN OPENSSH PRIVATE KEY"))
        #expect(!persisted.contains(passphrase))
        _ = try await library.delete(serverID: serverID)
    }


}

private final class ObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false

    var didChange: Bool { lock.withLock { changed } }
    func markChanged() { lock.withLock { changed = true } }
}

private final class MemoryProfilePasswords: CredentialStoring, @unchecked Sendable {
    private var values: [UUID: String] = [:]
    func password(for identityID: UUID) throws -> String? { values[identityID] }
    func createPasswordIfAbsent(_ password: String, for identityID: UUID) throws -> Bool {
        guard values[identityID] == nil else { return false }
        values[identityID] = password
        return true
    }
    func setPassword(_ password: String, for identityID: UUID) throws { values[identityID] = password }
    func deletePassword(for identityID: UUID) throws { values.removeValue(forKey: identityID) }
}

private final class MemoryProfileSecrets: SecretDataStore, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private func key(service: String, account: String) -> String { service + "\u{0}" + account }
    func read(service: String, account: String) throws -> Data? { values[key(service: service, account: account)] }
    func createOrUpdate(_ data: Data, service: String, account: String) throws { values[key(service: service, account: account)] = data }
    func delete(service: String, account: String) throws { values.removeValue(forKey: key(service: service, account: account)) }
}
