import Foundation
import Testing
@testable import MoriRemote

@Suite("Legacy profile migration")
struct LegacyMigrationTests {
    @Test("empty install completes once")
    func emptyInstall() throws {
        let fixture = try Fixture()
        let report = try fixture.migrator().migrateIfNeeded()
        #expect(report.completed)
        #expect(report.records.isEmpty)
        #expect(try fixture.storage.servers.all().isEmpty)
        #expect(try fixture.storage.migration.loadIfPresent() != nil)
    }

    @Test("migrates profiles, identities, workspaces and credentials without mutating legacy JSON")
    func successfulMigration() throws {
        let fixture = try Fixture()
        let first = fixture.legacyServer(name: "First", session: "dev", date: Date(timeIntervalSince1970: 20.123_456))
        let second = fixture.legacyServer(name: "Second", session: "ops", date: Date(timeIntervalSince1970: 10.654_321))
        let legacyBytes = try fixture.writeLegacy([first, second])
        fixture.legacyCredentials.values[first.id] = "first-password"
        fixture.legacyCredentials.values[second.id] = "second-password"

        let report = try fixture.migrator().migrateIfNeeded()
        #expect(report.records.map(\.disposition) == [.migrated, .migrated])
        let servers = try fixture.storage.servers.all()
        let identities = try fixture.storage.identities.all()
        let workspaces = try fixture.storage.workspaces.all()
        #expect(servers.map(\.id) == [first.id, second.id])
        #expect(identities.map(\.id) == [first.id, second.id])
        #expect(workspaces.map(\.serverID) == [first.id, second.id])
        #expect(workspaces.map(\.tmuxSession) == ["dev", "ops"])
        #expect(servers.map(\.lastConnectedAt) == [first.lastConnectedAt, second.lastConnectedAt])
        #expect(workspaces.map(\.lastConnectedAt) == [first.lastConnectedAt, second.lastConnectedAt])
        #expect(try fixture.destinationCredentials.password(for: first.id) == "first-password")
        #expect(try Data(contentsOf: fixture.legacyURL) == legacyBytes)
        #expect(try fixture.legacyCredentials.password(for: first.id) == "first-password")
    }

    @Test("missing password is terminal and second launch is idempotent")
    func missingPasswordAndSecondLaunch() throws {
        let fixture = try Fixture()
        let server = fixture.legacyServer()
        _ = try fixture.writeLegacy([server])
        fixture.legacyCredentials.values[server.id] = ""

        let first = try fixture.migrator().migrateIfNeeded()
        #expect(first.records == [LegacyMigrationRecord(legacyID: server.id.uuidString, disposition: .migratedWithoutCredential)])
        #expect(try fixture.destinationCredentials.password(for: server.id) == nil)
        #expect(try credentialRequirement(identityID: server.id, credentials: fixture.destinationCredentials) == .credentialRequired)
        let second = try fixture.migrator().migrateIfNeeded()
        #expect(second == first)
        #expect(try fixture.storage.servers.all().count == 1)
    }

    @Test("malformed JSON and duplicate UUIDs receive terminal invalid dispositions")
    func malformedAndDuplicates() throws {
        let malformed = try Fixture()
        try Data("not json".utf8).write(to: malformed.legacyURL)
        let malformedReport = try malformed.migrator().migrateIfNeeded()
        #expect(malformedReport.records.map(\.disposition) == [.skippedInvalid])
        #expect(try malformed.storage.migration.loadIfPresent() != nil)

        let fixture = try Fixture()
        let server = fixture.legacyServer()
        _ = try fixture.writeLegacy([server, server])
        let report = try fixture.migrator().migrateIfNeeded()
        #expect(report.records.map(\.disposition) == [.migratedWithoutCredential, .skippedInvalid])
        #expect(try fixture.storage.servers.all().count == 1)
    }

    @Test("mixed invalid and dated records have deterministic recent-first order")
    func mixedInvalidAndDatedRecords() throws {
        let fixture = try Fixture()
        let early = fixture.legacyServer(name: "Early", date: Date(timeIntervalSince1970: 1))
        let late = fixture.legacyServer(name: "Late", date: Date(timeIntervalSince1970: 2))
        let earlyObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(early))
        let lateObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(late))
        try JSONSerialization.data(withJSONObject: [earlyObject, "invalid", lateObject]).write(to: fixture.legacyURL)

        let report = try fixture.migrator().migrateIfNeeded()
        #expect(report.records.map(\.legacyID) == [late.id.uuidString, early.id.uuidString, "invalid-1"])
        #expect(try fixture.storage.servers.all().map(\.id) == [late.id, early.id])
    }

    @Test("whitespace default session normalizes to main while newline remains invalid")
    func normalizesEmptyDefaultSession() throws {
        let fixture = try Fixture()
        let whitespace = fixture.legacyServer(name: "Whitespace", session: " \t ")
        let newline = fixture.legacyServer(name: "Newline", session: "bad\nsession")
        _ = try fixture.writeLegacy([whitespace, newline])

        let report = try fixture.migrator().migrateIfNeeded()
        #expect(report.records.map(\.disposition) == [.migratedWithoutCredential, .skippedInvalid])
        #expect(try fixture.storage.workspaces.all().map(\.tmuxSession) == ["main"])
    }

    @Test("a corrupt destination store fails closed without a completion marker")
    func corruptDestinationStore() throws {
        let fixture = try Fixture()
        let server = fixture.legacyServer()
        _ = try fixture.writeLegacy([server])
        let destination = fixture.storage.root.appendingPathComponent("servers.json")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: destination)
        #expect(throws: PersistenceError.corruptStore("servers.json")) {
            try fixture.migrator().migrateIfNeeded()
        }
        #expect(try fixture.storage.migration.loadIfPresent() == nil)
    }

    @Test("write failure leaves marker absent and retry has no duplicate records")
    func partialWriteRetry() throws {
        let fixture = try Fixture()
        let server = fixture.legacyServer()
        _ = try fixture.writeLegacy([server])
        let failingStorage = MoriRemoteStorage(root: fixture.storage.root, writer: FailingWriter(failOnWrite: 4))
        #expect(throws: Error.self) {
            try fixture.migrator(storage: failingStorage).migrateIfNeeded()
        }
        #expect(try fixture.storage.migration.loadIfPresent() == nil)

        _ = try fixture.migrator().migrateIfNeeded()
        #expect(try fixture.storage.servers.all().map(\.id) == [server.id])
        #expect(try fixture.storage.identities.all().map(\.id) == [server.id])
        #expect(try fixture.storage.workspaces.all().map(\.id) == [server.id])
    }

    @Test("retry preserves post-interruption profile and password edits")
    func interruptedMigrationPreservesUserEdits() throws {
        let fixture = try Fixture()
        let first = fixture.legacyServer(name: "Original")
        let second = fixture.legacyServer(name: "Second")
        _ = try fixture.writeLegacy([first, second])
        fixture.legacyCredentials.values[first.id] = "old-first"
        fixture.legacyCredentials.values[second.id] = "old-second"

        let interrupted = MoriRemoteStorage(root: fixture.storage.root, writer: FailingWriter(failOnWrite: 4))
        #expect(throws: Error.self) { try fixture.migrator(storage: interrupted).migrateIfNeeded() }
        var edited = try fixture.storage.servers.all().first!
        edited.name = "Edited by user"
        try fixture.storage.servers.replace(edited)
        let editedCredential = ["new", "first"].joined(separator: "-")
        try fixture.destinationCredentials.setPassword(editedCredential, for: first.id)

        _ = try fixture.migrator().migrateIfNeeded()
        #expect(try fixture.storage.servers.all().first?.name == "Edited by user")
        #expect(try fixture.destinationCredentials.password(for: first.id) == editedCredential)
        #expect(try fixture.destinationCredentials.password(for: second.id) == "old-second")
    }

    @Test("trust invalidation failure leaves the server at its old endpoint")
    func trustInvalidationFailureIsFailClosed() throws {
        let fixture = try Fixture()
        let serverID = UUID()
        let oldEndpoint = try CanonicalEndpoint(host: "old.example", port: 22)
        let newEndpoint = try CanonicalEndpoint(host: "new.example", port: 22)
        let serverURL = fixture.root.appendingPathComponent("servers.json")
        let trustedURL = fixture.root.appendingPathComponent("trusted-hosts.json")
        let trustedHosts = TrustedHostStore(url: trustedURL)
        let initialRepository = SavedServerRepository(url: serverURL, trustedHosts: trustedHosts)
        _ = try initialRepository.insertIfAbsent(SavedServer(id: serverID, name: "Server", host: oldEndpoint.host, port: oldEndpoint.port, username: "v"))
        try trustedHosts.trust(TrustedHost(serverID: serverID, endpoint: oldEndpoint, algorithm: "ssh-ed25519", fingerprint: "abc", trustedAt: .distantPast))

        let failingRepository = SavedServerRepository(url: serverURL, trustedHosts: TrustedHostStore(url: trustedURL, writer: AlwaysFailingWriter()))
        #expect(throws: Error.self) {
            try failingRepository.replace(SavedServer(id: serverID, name: "Server", host: newEndpoint.host, port: newEndpoint.port, username: "v"))
        }
        #expect(try failingRepository.all().first?.endpoint == oldEndpoint)
    }

    @Test("canonical endpoint removes case, brackets and stale trust")
    func canonicalEndpointInvalidatesTrust() throws {
        let fixture = try Fixture()
        let serverID = UUID()
        let original = try CanonicalEndpoint(host: "[2001:DB8::1]", port: 22)
        let changed = try CanonicalEndpoint(host: "example.com", port: 2200)
        let server = SavedServer(id: serverID, name: "Server", host: "[2001:DB8::1]", port: 22, username: "v")
        _ = try fixture.storage.servers.insertIfAbsent(server)
        try fixture.storage.trustedHosts.trust(TrustedHost(serverID: serverID, endpoint: original, algorithm: "ssh-ed25519", fingerprint: "abc", trustedAt: .distantPast))
        #expect(original.host == "2001:db8::1")
        try fixture.storage.servers.replace(SavedServer(id: serverID, name: "Server", host: changed.host, port: changed.port, username: "v"))
        #expect(try fixture.storage.trustedHosts.trustedHost(for: serverID, endpoint: original) == nil)
    }
}

private final class Fixture: @unchecked Sendable {
    let root: URL
    let legacyURL: URL
    let storage: MoriRemoteStorage
    let legacyCredentials = MemoryCredentials()
    let destinationCredentials = MemoryCredentials()

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        legacyURL = root.appendingPathComponent("Documents/servers.json")
        storage = MoriRemoteStorage(root: root.appendingPathComponent("Application Support/MoriRemote"))
        try FileManager.default.createDirectory(at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func legacyServer(name: String = "Server", session: String = "main", date: Date? = nil) -> LegacyServerRecord {
        LegacyServerRecord(id: UUID(), name: name, host: "Example.COM", port: 22, username: "v", defaultSession: session, lastConnectedAt: date)
    }

    @discardableResult
    func writeLegacy(_ servers: [LegacyServerRecord]) throws -> Data {
        let data = try JSONEncoder().encode(servers) // Legacy ServerStore used JSONEncoder defaults.
        try data.write(to: legacyURL)
        return data
    }

    func migrator(storage: MoriRemoteStorage? = nil) -> LegacyServerMigrator {
        LegacyServerMigrator(storage: storage ?? self.storage, legacyServersURL: legacyURL, legacyCredentials: legacyCredentials, destinationCredentials: destinationCredentials, now: { .distantPast })
    }
}

private final class MemoryCredentials: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    var values: [UUID: String] = [:]

    func password(for identityID: UUID) throws -> String? {
        lock.withLock { values[identityID] }
    }

    func createPasswordIfAbsent(_ password: String, for identityID: UUID) throws -> Bool {
        lock.withLock {
            guard values[identityID] == nil else { return false }
            values[identityID] = password
            return true
        }
    }

    func setPassword(_ password: String, for identityID: UUID) throws {
        lock.withLock { values[identityID] = password }
    }

    func deletePassword(for identityID: UUID) throws {
        lock.withLock { values.removeValue(forKey: identityID) }
    }
}

private struct FailingWriter: AtomicDataWriting {
    let failOnWrite: Int
    private let state = FailureState()

    init(failOnWrite: Int) { self.failOnWrite = failOnWrite }

    func write(_ data: Data, to url: URL) throws {
        let writeNumber = state.nextWriteNumber()
        guard writeNumber != failOnWrite else { throw CocoaError(.fileWriteUnknown) }
        try FoundationAtomicDataWriter().write(data, to: url)
    }
}

private struct AlwaysFailingWriter: AtomicDataWriting {
    func write(_: Data, to _: URL) throws { throw CocoaError(.fileWriteUnknown) }
}

private final class FailureState: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func nextWriteNumber() -> Int {
        lock.withLock { count += 1; return count }
    }
}
