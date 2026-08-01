import Foundation
import Security
import Testing
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

    @Test("workspace draft owns a distinct record and rejects unsafe sessions")
    func workspaceDraftValidation() throws {
        let serverID = UUID()
        var draft = WorkspaceDraft(serverID: serverID)
        draft.name = "Logs"
        draft.tmuxSession = "logs"
        let workspace = try draft.record()
        #expect(workspace.serverID == serverID)
        #expect(workspace.id != serverID)
        draft.tmuxSession = "bad\nname"
        #expect(throws: SavedModelValidationError.invalidTmuxSession) { try draft.record() }
    }

    @Test("profile draft keeps server identity and rejects unsafe sessions")
    func profileDraftValidation() throws {
        var draft = ServerWorkspaceDraft()
        draft.serverName = "Build"
        draft.host = "build.example"
        draft.port = "22"
        draft.username = "mori"
        draft.workspaceName = "Build"
        draft.tmuxSession = "build"
        let records = try draft.records()
        #expect(records.0.id == records.1?.serverID)
        #expect(records.0.identityID == records.2.id)
        #expect(records.2.serverID == records.0.id)
        draft.tmuxSession = "bad\nname"
        #expect(throws: SavedModelValidationError.invalidTmuxSession) { try draft.records() }
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

    @Test("profile edits preserve the selected workspace identity and recency")
    func profileDraftPreservesWorkspace() throws {
        let serverID = UUID(), workspaceID = UUID(), identityID = UUID()
        let date = Date(timeIntervalSince1970: 123)
        let server = SavedServer(id: serverID, name: "Build", host: "build.example", username: "mori", identityID: identityID, lastConnectedAt: date)
        let workspace = SavedWorkspace(id: workspaceID, serverID: serverID, name: "Build", tmuxSession: "build", lastConnectedAt: date)
        let draft = ServerWorkspaceDraft(server: server, workspace: workspace, identity: SSHIdentity(id: identityID, serverID: serverID, kind: .password))
        let records = try draft.records(existingIdentityID: identityID)
        #expect(records.1?.id == workspaceID)
        #expect(records.0.lastConnectedAt == date)
        #expect(records.1?.lastConnectedAt == date)
        let serverOnly = ServerWorkspaceDraft(server: server, identity: SSHIdentity(id: identityID, serverID: serverID, kind: .password))
        #expect(try serverOnly.records(existingIdentityID: identityID).1 == nil)
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
        _ = try await library.save(server: originalServer, workspace: originalWorkspace, identity: identity, credential: nil)
        let editedServer = SavedServer(id: serverID, name: "Renamed", host: "build.example", username: "mori", identityID: identityID)
        let editedWorkspace = SavedWorkspace(id: workspaceID, serverID: serverID, name: "Renamed", tmuxSession: "build")
        let snapshot = try await library.save(server: editedServer, workspace: editedWorkspace, identity: identity, credential: nil)
        #expect(snapshot.servers.first?.lastConnectedAt == date)
        #expect(snapshot.workspaces == [SavedWorkspace(id: workspaceID, serverID: serverID, name: "Renamed", tmuxSession: "build", lastConnectedAt: date)])
        _ = try await library.save(server: editedServer, workspace: nil, identity: identity, credential: nil)
        let workspaceOnlyEdit = SavedWorkspace(id: workspaceID, serverID: serverID, name: "Workspace only", tmuxSession: "build")
        let workspaceSnapshot = try await library.save(workspace: workspaceOnlyEdit)
        #expect(workspaceSnapshot.workspaces == [SavedWorkspace(id: workspaceID, serverID: serverID, name: "Workspace only", tmuxSession: "build", lastConnectedAt: date)])
        #expect((try await library.reload()).workspaces.count == 1)
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
        _ = try await library.save(server: server, workspace: workspace, identity: identity, credential: .privateKey(.init(privateKeyPEM: privateKey, passphrase: passphrase)))
        let persisted = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .reduce(into: "") { $0 += (try? String(contentsOf: $1, encoding: .utf8)) ?? "" }
        #expect(!persisted.contains("BEGIN OPENSSH PRIVATE KEY"))
        #expect(!persisted.contains(passphrase))
        _ = try await library.delete(serverID: serverID)
    }


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
