import Foundation
import Testing
@testable import MoriRemote

@Suite("Phase 2 transport evidence") struct Phase2TransportTests {
    @Test("private-key secret CRUD is fail-closed and passwords remain fallback")
    func privateKeySecrets() throws {
        let id = UUID()
        let secrets = MemorySecrets()
        let passwords = Passwords([id: "phase-one-password"])
        let store = KeychainSSHCredentialStore(passwords: passwords, secrets: secrets)
        #expect(try store.credential(for: id) == .password("phase-one-password"))

        let first = SSHPrivateKeyInspector.generateEd25519(comment: "one").privateKeyPEM
        try store.savePrivateKey(.init(privateKeyPEM: first, passphrase: "first passphrase"), for: id)
        #expect(try store.credential(for: id) == .privateKey(.init(privateKeyPEM: first, passphrase: "first passphrase")))

        let second = SSHPrivateKeyInspector.generateEd25519(comment: "two").privateKeyPEM
        try store.savePrivateKey(.init(privateKeyPEM: second, passphrase: "second passphrase"), for: id)
        #expect(try store.credential(for: id) == .privateKey(.init(privateKeyPEM: second, passphrase: "second passphrase")))
        try store.deletePrivateKey(for: id)
        #expect(try store.credential(for: id) == .password("phase-one-password"))

        try secrets.createOrUpdate(Data("not json".utf8), service: KeychainSSHCredentialStore.privateKeyService, account: id.uuidString)
        #expect(throws: SSHCredentialStoreError.self) { try store.credential(for: id) }
    }

    @Test("Phase 2 user-facing errors resolve localized descriptions")
    func localizedErrors() throws {
        #expect(TmuxCommandError.unsupportedVersion.errorDescription == "tmux 3.2 or later is required.")
        #expect(SSHAuthResolverError.missingCredential(UUID()).errorDescription == "SSH credential is required.")
        #expect(SSHPrivateKeyInspectionError.unsupportedKeyType("ssh-dss").errorDescription == "SSH private key type “ssh-dss” is not supported.")

        let endpoint = try CanonicalEndpoint(host: "example.test", port: 22)
        let unknown = SSHHostTrustChallenge(
            kind: .unknown,
            serverID: UUID(),
            endpoint: endpoint,
            algorithm: "ssh-ed25519",
            receivedFingerprint: "SHA256:received",
            trustedFingerprint: nil
        )
        let changed = SSHHostTrustChallenge(
            kind: .changed,
            serverID: unknown.serverID,
            endpoint: endpoint,
            algorithm: "ssh-ed25519",
            receivedFingerprint: "SHA256:received",
            trustedFingerprint: "SHA256:trusted"
        )
        #expect(SSHHostTrustError.trustRequired(unknown).errorDescription == "The SSH host key is unknown. Review and trust it before connecting.")
        #expect(SSHHostTrustError.changedKey(changed).errorDescription == "The SSH host key changed. Connection refused.")
    }

    @Test("authentication completion gate accepts exactly one terminal event")
    func authenticationGateIsOneShot() {
        let state = SSHAuthenticationCompletionState()
        #expect(state.claim(.succeed) == .succeed)
        #expect(state.claim(.fail(.closed)) == nil)

        let failureFirst = SSHAuthenticationCompletionState()
        #expect(failureFirst.claim(.fail(.closed)) == .fail(.closed))
        #expect(failureFirst.claim(.succeed) == nil)
    }

    @Test("host trust gate fails before authentication or child opening")
    func trustPrecedesAuthentication() throws {
        let server = SavedServer(name: "server", host: "example.test", username: "v")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let connector = TrustSequencingConnector(server: server, trust: SSHHostTrustResolver(store: TrustedHostStore(url: root)))
        #expect(throws: SSHHostTrustError.self) { try connector.connectSynchronously() }
        #expect(!connector.authenticated)
        #expect(connector.childrenOpened == 0)
    }

    @Test("transport performs preflight then grouped shadow then isolated attach")
    func lifecycle() async throws {
        let id = UUID()
        let root = FakeRoot(plans: [
            .finished("tmux 3.2a\n"), .finished(""), .open,
            .finished("workspace--mori-remote-\(id.uuidString.lowercased())\tworkspace\n"), .finished(""),
        ])
        let connector = FakeConnector(roots: [root])
        let transport = SSHTmuxControlTransport(
            connector: connector, pool: SSHRootPool(), poolKey: try key(), sourceSession: "workspace", runtimeID: id
        )
        try await transport.start()
        let commands = root.commands()
        #expect(commands.count == 3)
        #expect(commands[0].contains("'-V'"))
        #expect(commands[1].contains("'new-session'"))
        #expect(commands[2].contains("'-C' 'attach-session'"))
        #expect(commands[2].contains("'active-pane,ignore-size'"))
        await transport.close(disposition: .reusable)
        #expect(root.commands().count == 5)
        #expect(root.commands()[3].contains("'display-message'"))
        #expect(root.commands()[4].contains("'kill-session'"))
    }

    @Test("old or malformed tmux never mutates")
    func rejectedPreflight() async throws {
        for output in ["tmux 3.1\n", "not tmux\n"] {
            let root = FakeRoot(plans: [.finished(output)])
            let transport = SSHTmuxControlTransport(
                connector: FakeConnector(roots: [root]), pool: SSHRootPool(), poolKey: try key(), sourceSession: "workspace", runtimeID: UUID()
            )
            await #expect(throws: Error.self) { try await transport.start() }
            #expect(root.commands().count == 1)
        }
        let root = FakeRoot(plans: [.finished("tmux 3.1\n")])
        let transport = SSHTmuxControlTransport(
            connector: FakeConnector(roots: [root]), pool: SSHRootPool(), poolKey: try key(), sourceSession: "workspace", runtimeID: UUID()
        )
        do {
            try await transport.start()
            Issue.record("unsupported tmux unexpectedly started")
        } catch let error as TmuxCommandError {
            #expect(error == .unsupportedVersion)
        } catch {
            Issue.record("startup error was masked: \(error)")
        }
    }

    @Test("attach failure and cleanup mismatch invalidate without kill")
    func failuresInvalidate() async throws {
        let id = UUID()
        let failedAttach = FakeRoot(plans: [
            .finished("tmux 3.2\n"), .finished(""), .failed,
            .finished("workspace--mori-remote-\(id.uuidString.lowercased())\tworkspace\n"), .finished("")
        ])
        let failureTransport = SSHTmuxControlTransport(
            connector: FakeConnector(roots: [failedAttach]), pool: SSHRootPool(), poolKey: try key(), sourceSession: "workspace", runtimeID: id
        )
        await #expect(throws: Error.self) { try await failureTransport.start() }
        #expect(failedAttach.closed)

        let root = FakeRoot(plans: [.finished("tmux 3.2\n"), .finished(""), .open, .finished("wrong\tworkspace\n")])
        let transport = SSHTmuxControlTransport(
            connector: FakeConnector(roots: [root]), pool: SSHRootPool(), poolKey: try key(), sourceSession: "workspace", runtimeID: id
        )
        try await transport.start()
        await transport.close(disposition: .reusable)
        #expect(root.commands().count == 4)
        #expect(!root.commands().contains { $0.contains("'kill-session'") })
        #expect(root.closed)
    }

    @Test("close wins a blocked startup race and releases its child exactly once")
    func closeDuringStartup() async throws {
        let child = StartupBlockingChild()
        let root = StartupRaceRoot(child: child)
        let transport = SSHTmuxControlTransport(
            connector: StartupRaceConnector(root: root), pool: SSHRootPool(), poolKey: try key(), sourceSession: "workspace"
        )
        let start = Task { try await transport.start() }
        await child.waitUntilExecuting()
        await transport.close(disposition: .reusable)
        #expect(await child.closeCount() == 1)
        await #expect(throws: SSHTmuxControlTransportError.closed) { try await start.value }
        #expect(!(await transport.isActive()))
    }

    @Test("a root lease arriving after close returns reusable to the shared pool")
    func closeBeforeLeaseArrivalKeepsHealthyRoot() async throws {
        let root = FakeRoot(plans: [])
        let connector = DelayedRootConnector(root: root)
        let transport = SSHTmuxControlTransport(
            connector: connector, pool: SSHRootPool(), poolKey: try key(), sourceSession: "workspace"
        )
        let start = Task { try await transport.start() }
        await connector.waitUntilRequested()
        await transport.close(disposition: .reusable)
        await connector.resume()
        await #expect(throws: SSHTmuxControlTransportError.closed) { try await start.value }
        #expect(!root.closed)
    }

    @Test("root pool coalesces, bounds shared children, drains invalidation, and idles")
    func pool() async throws {
        let pool = SSHRootPool(idleTimeout: .milliseconds(20))
        let root = FakeRoot(plans: [])
        let connector = FakeConnector(roots: [root, FakeRoot(plans: [])])
        let poolKey = try key()
        async let one = pool.lease(for: poolKey, connector: connector)
        async let two = pool.lease(for: poolKey, connector: connector)
        async let three = pool.lease(for: poolKey, connector: connector)
        async let four = pool.lease(for: poolKey, connector: connector)
        let leases = try await [one, two, three, four]
        #expect(connector.calls == 1)
        let fifth = try await pool.lease(for: poolKey, connector: connector)
        #expect(connector.calls == 2)

        await leases[0].release(.invalidated)
        #expect(!root.closed)
        await leases[1].release(.reusable)
        await leases[1].release(.reusable)
        await leases[2].release(.reusable)
        await leases[3].release(.reusable)
        #expect(root.closed)
        await fifth.release(.reusable)

        let idleRoot = FakeRoot(plans: [])
        let idleConnector = FakeConnector(roots: [idleRoot])
        let idleLease = try await pool.lease(for: try key(), connector: idleConnector)
        await idleLease.release(.reusable)
        try await eventually { idleRoot.closed }
    }
}

private final class TrustSequencingConnector: @unchecked Sendable {
    let server: SavedServer
    let trust: SSHHostTrustResolver
    private(set) var authenticated = false
    private(set) var childrenOpened = 0

    init(server: SavedServer, trust: SSHHostTrustResolver) {
        self.server = server
        self.trust = trust
    }

    func connectSynchronously() throws {
        // Models the real adapter's ordering: validation is a prerequisite for
        // authentication success and a root is the only object that can open children.
        try trust.verify(server: server, algorithm: "ssh-ed25519", fingerprint: "unknown")
        authenticated = true
    }
}

private final class MemorySecrets: SecretDataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? { lock.withLock { values["\(service)|\(account)"] } }
    func createOrUpdate(_ data: Data, service: String, account: String) throws { lock.withLock { values["\(service)|\(account)"] = data } }
    func delete(service: String, account: String) throws { lock.withLock { values["\(service)|\(account)"] = nil } }
}

private struct Passwords: CredentialReading {
    let values: [UUID: String]
    init(_ values: [UUID: String]) { self.values = values }
    func password(for identityID: UUID) throws -> String? { values[identityID] }
}

private enum FakePlan { case finished(String), open, failed }

private final class FakeConnector: SSHRootConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var queuedRoots: [FakeRoot]
    private(set) var calls = 0
    init(roots: [FakeRoot]) { queuedRoots = roots }
    func connect() async throws -> any SSHRootConnection {
        lock.withLock {
            calls += 1
            return queuedRoots.removeFirst()
        }
    }
}

private final class FakeRoot: SSHRootConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var plans: [FakePlan]
    private var recordedCommands: [String] = []
    private(set) var closed = false
    init(plans: [FakePlan]) { self.plans = plans }
    func openSessionChannel() async throws -> any SSHChildChannel {
        let plan = lock.withLock { plans.removeFirst() }
        return FakeChild(plan: plan) { [weak self] command in self?.lock.withLock { self?.recordedCommands.append(command) } }
    }
    func close() async { lock.withLock { closed = true } }
    func commands() -> [String] { lock.withLock { recordedCommands } }
}

private final class FakeChild: SSHChildChannel, @unchecked Sendable {
    nonisolated let receivedBytes: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let plan: FakePlan
    private let record: @Sendable (String) -> Void
    private var active = true
    init(plan: FakePlan, record: @escaping @Sendable (String) -> Void) {
        self.plan = plan
        self.record = record
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        receivedBytes = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }
    func execute(_ command: String) async throws {
        record(command)
        switch plan {
        case .finished(let output): continuation.yield(Data(output.utf8)); continuation.finish()
        case .open: break
        case .failed: throw SSHTmuxControlTransportError.closed
        }
    }
    func write(_ data: Data) async throws {}
    func isActive() async -> Bool { active }
    func close() async throws { active = false; continuation.finish() }
}

private actor DelayedRootConnector: SSHRootConnecting {
    private let root: FakeRoot
    private var requested = false
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var connectionWaiter: CheckedContinuation<any SSHRootConnection, Error>?

    init(root: FakeRoot) { self.root = root }

    func connect() async throws -> any SSHRootConnection {
        requested = true
        requestWaiter?.resume()
        requestWaiter = nil
        return try await withCheckedThrowingContinuation { connectionWaiter = $0 }
    }

    func waitUntilRequested() async {
        guard !requested else { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func resume() { connectionWaiter?.resume(returning: root); connectionWaiter = nil }
}

private actor StartupBlockingChild: SSHChildChannel {
    nonisolated let receivedBytes: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private var executionWaiter: CheckedContinuation<Void, Never>?
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var executing = false
    private var closes = 0

    init() {
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        receivedBytes = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }

    func execute(_ command: String) async throws {
        _ = command
        await withCheckedContinuation { continuation in
            executionWaiter = continuation
            executing = true
            startedWaiter?.resume()
            startedWaiter = nil
        }
    }

    func waitUntilExecuting() async {
        guard !executing else { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }

    func write(_ data: Data) async throws { _ = data }
    func isActive() async -> Bool { closes == 0 }
    func close() async throws {
        closes += 1
        continuation.finish()
        executionWaiter?.resume()
        executionWaiter = nil
    }
    func closeCount() -> Int { closes }
}

private final class StartupRaceRoot: SSHRootConnection, @unchecked Sendable {
    let child: StartupBlockingChild
    private let lock = NSLock()
    private(set) var closed = false
    init(child: StartupBlockingChild) { self.child = child }
    func openSessionChannel() async throws -> any SSHChildChannel { child }
    func close() async { lock.withLock { closed = true } }
}

private struct StartupRaceConnector: SSHRootConnecting {
    let root: StartupRaceRoot
    func connect() async throws -> any SSHRootConnection { root }
}

private func key() throws -> SSHRootPool.Key {
    try .init(serverID: UUID(), endpoint: CanonicalEndpoint(host: "example.test", port: 22), username: "v", authenticationFingerprint: UUID().uuidString)
}

private func eventually(_ condition: @escaping @Sendable () -> Bool) async throws {
    for _ in 0..<40 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("condition did not become true")
}
