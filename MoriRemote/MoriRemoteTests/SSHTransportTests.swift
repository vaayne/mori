import Foundation
import Testing
@testable import MoriRemote

@Suite("SSH and tmux transport") struct SSHTransportTests {
    @Test("private key inspector accepts generated Ed25519 key") func privateKey() throws {
        let key = SSHPrivateKeyInspector.generateEd25519(comment: "test")
        let inspection = try SSHPrivateKeyInspector.inspect(key.privateKeyPEM)
        #expect(inspection.keyType == .ed25519)
        #expect(inspection.publicFingerprint == key.publicFingerprint)
    }
    @Test("auth resolver supports password and imported private key") func auth() throws {
        let id = UUID(), server = SavedServer(id: UUID(), name: "s", host: "host", username: "u", identityID: id)
        let password = SSHIdentity(id: id, serverID: server.id, kind: .password)
        #expect(try SSHAuthResolver(credentials: Credentials([id: .password("pw")])).resolve(server: server, identity: password) == .password(username: "u", password: "pw", identityID: id, label: ""))
        let keyID = UUID(), keyIdentity = SSHIdentity(id: keyID, serverID: server.id, kind: .privateKey)
        let key = SSHPrivateKeyInspector.generateEd25519(comment: "test").privateKeyPEM
        guard case .privateKey = try SSHAuthResolver(credentials: Credentials([keyID: .privateKey(.init(privateKeyPEM: key, passphrase: nil))])).resolve(server: SavedServer(id: server.id, name: "s", host: "host", username: "u", identityID: keyID), identity: keyIdentity) else { Issue.record("key was not resolved"); return }
    }
    @Test("unknown and changed host keys fail closed") func trust() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let store = TrustedHostStore(url: root), server = SavedServer(name: "s", host: "Host", username: "u"), resolver = SSHHostTrustResolver(store: store)
        #expect(throws: SSHHostTrustError.self) { try resolver.verify(server: server, algorithm: "ssh-ed25519", fingerprint: "new") }
        let endpoint = try #require(server.endpoint); let challenge = SSHHostTrustChallenge(kind: .unknown, serverID: server.id, endpoint: endpoint, algorithm: "ssh-ed25519", receivedFingerprint: "old", trustedFingerprint: nil)
        try resolver.explicitlyTrust(challenge); try resolver.verify(server: server, algorithm: "ssh-ed25519", fingerprint: "old")
        #expect(throws: SSHHostTrustError.self) { try resolver.verify(server: server, algorithm: "ssh-ed25519", fingerprint: "new") }
    }
    @Test("tmux version accepts real suffixes and rejects old or malformed output") func version() {
        #expect(TmuxVersion.parse("tmux 3.1")! < TmuxVersion(major: 3, minor: 2))
        #expect(TmuxVersion.parse("tmux 3.2a") == TmuxVersion(major: 3, minor: 2))
        #expect(TmuxVersion.parse("tmux 3.6a") == TmuxVersion(major: 3, minor: 6))
        #expect(TmuxVersion.parse("tmux 3.7b") == TmuxVersion(major: 3, minor: 7))
        #expect(TmuxVersion.parse("tmux nope") == nil)
    }
    @Test("command quoting rejects injection and cleanup owns exact shadow") func commands() throws {
        let id = UUID(), shadow = try TmuxCommandBuilder.shadowName(source: "project/main", runtimeID: id)
        let command = try TmuxCommandBuilder.createShadow(executable: "/opt/tools/tmux", source: "project/main", runtimeID: id)
        #expect(command.contains("'project/main'")); #expect(!command.contains("refresh-client -C")); #expect(throws: TmuxCommandError.self) { _ = try TmuxCommandBuilder.createShadow(executable: "tmux", source: "bad\nkill", runtimeID: id) }; #expect(throws: TmuxCommandError.self) { _ = try TmuxCommandBuilder.cleanupPlan(executable: "tmux", source: "project/main", shadow: shadow + "x", runtimeID: id) }
    }
    @Test("chunked inbound, sequential submissions, and EOF preserve transport lifecycle") func link() async throws {
        let transport = TestTransport()
        let received = Recorder()
        let disconnected = Flag()
        let link = TmuxSessionLink(
            transport: transport,
            receive: { received.add($0) },
            disconnected: { disconnected.set() }
        )

        try await link.start()
        await transport.push(Data("a".utf8))
        await transport.push(Data("b".utf8))
        for value in ["first", "second", "third"] {
            await link.send(Data(value.utf8))
        }
        try await Task.sleep(for: .milliseconds(30))
        #expect(await transport.writes() == [Data("first".utf8), Data("second".utf8), Data("third".utf8)])

        await transport.finish()
        try await Task.sleep(for: .milliseconds(30))
        #expect(received.values() == [Data("a".utf8), Data("b".utf8)])
        #expect(disconnected.value())
        #expect(await transport.dispositions() == [.invalidated])
    }
}
private struct Credentials: SSHCredentialReading { let values: [UUID: SSHCredential]; init(_ values: [UUID: SSHCredential]) { self.values = values }; func credential(for id: UUID) throws -> SSHCredential? { values[id] } }
private actor TestTransport: TmuxControlTransport {
    nonisolated let receivedBytes: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private var submittedWrites: [Data] = []
    private var closes: [TmuxControlTransportCloseDisposition] = []

    init() {
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        receivedBytes = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async throws {}
    func send(_ data: Data) async throws { submittedWrites.append(data) }
    func isActive() async -> Bool { closes.isEmpty }
    func close(disposition: TmuxControlTransportCloseDisposition) async {
        closes.append(disposition)
        continuation.finish()
    }
    func push(_ data: Data) { continuation.yield(data) }
    func finish() { continuation.finish() }
    func writes() -> [Data] { submittedWrites }
    func dispositions() -> [TmuxControlTransportCloseDisposition] { closes }
}
private final class Recorder: @unchecked Sendable { private let lock = NSLock(); private var data: [Data] = []; func add(_ value: Data) { lock.withLock { data.append(value) } }; func values() -> [Data] { lock.withLock { data } } }
private final class Flag: @unchecked Sendable { private let lock = NSLock(); private var flag = false; func set() { lock.withLock { flag = true } }; func value() -> Bool { lock.withLock { flag } } }
