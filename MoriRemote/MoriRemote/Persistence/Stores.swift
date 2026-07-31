import Foundation
import Security

protocol AtomicDataWriting: Sendable {
    func write(_ data: Data, to url: URL) throws
}

struct FoundationAtomicDataWriter: AtomicDataWriting {
    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

enum PersistenceError: Error, Equatable, Sendable {
    case notFound(UUID)
    case corruptStore(String)
    case keychain(OSStatus)
}

/// A small persistence boundary: encode whole collections atomically, never expose filesystem details to callers.
struct AtomicJSONStore<Value: Codable & Sendable>: Sendable {
    let url: URL
    private let writer: any AtomicDataWriting
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL, writer: any AtomicDataWriting = FoundationAtomicDataWriter()) {
        self.url = url
        self.writer = writer
        let encoder = JSONEncoder()
        // Preserve legacy Date's fractional seconds exactly during migration.
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func load(or defaultValue: @autoclosure () -> Value) throws -> Value {
        try loadIfPresent() ?? defaultValue()
    }

    func loadIfPresent() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try decoder.decode(Value.self, from: Data(contentsOf: url))
        } catch {
            throw PersistenceError.corruptStore(url.lastPathComponent)
        }
    }

    func save(_ value: Value) throws {
        try writer.write(try encoder.encode(value), to: url)
    }
}

protocol UUIDRecord: Identifiable, Codable, Sendable where ID == UUID {}
extension SavedServer: UUIDRecord {}
extension SavedWorkspace: UUIDRecord {}
extension SSHIdentity: UUIDRecord {}

struct UUIDJSONRepository<Record: UUIDRecord>: Sendable {
    private let store: AtomicJSONStore<[Record]>

    init(url: URL, writer: any AtomicDataWriting = FoundationAtomicDataWriter()) {
        store = AtomicJSONStore(url: url, writer: writer)
    }

    func all() throws -> [Record] { try store.load(or: []) }

    /// Migration uses this instead of upsert: an interrupted retry must not clobber later user edits.
    func insertIfAbsent(_ record: Record) throws -> Bool {
        var records = try all()
        guard !records.contains(where: { $0.id == record.id }) else { return false }
        records.append(record)
        try store.save(records)
        return true
    }

    func replace(_ record: Record) throws {
        var records = try all()
        guard let index = records.firstIndex(where: { $0.id == record.id }) else {
            throw PersistenceError.notFound(record.id)
        }
        records[index] = record
        try store.save(records)
    }

    func remove(_ id: UUID) throws {
        var records = try all()
        guard records.contains(where: { $0.id == id }) else { throw PersistenceError.notFound(id) }
        records.removeAll { $0.id == id }
        try store.save(records)
    }
}

/// Server updates own the host-trust invalidation rule so callers cannot accidentally carry trust to a new endpoint.
struct SavedServerRepository: Sendable {
    private let records: UUIDJSONRepository<SavedServer>
    private let trustedHosts: TrustedHostStore

    init(url: URL, trustedHosts: TrustedHostStore, writer: any AtomicDataWriting = FoundationAtomicDataWriter()) {
        records = UUIDJSONRepository(url: url, writer: writer)
        self.trustedHosts = trustedHosts
    }

    func all() throws -> [SavedServer] { try records.all() }
    func insertIfAbsent(_ server: SavedServer) throws -> Bool { try records.insertIfAbsent(server) }
    func remove(_ id: UUID) throws { try records.remove(id) }

    func replace(_ server: SavedServer) throws {
        _ = try server.validated()
        let previous = try all().first { $0.id == server.id }
        if let previous, let oldEndpoint = previous.endpoint, let newEndpoint = server.endpoint, oldEndpoint != newEndpoint {
            // Remove trust first: a failed invalidation must leave the old endpoint authoritative.
            try trustedHosts.invalidateTrust(for: server.id, ifEndpointChangedFrom: newEndpoint)
        }
        try records.replace(server)
    }
}

protocol CredentialStoring: CredentialReading {
    func password(for identityID: UUID) throws -> String?
    /// Returns false when a new-app credential already exists; it is never replaced.
    func createPasswordIfAbsent(_ password: String, for identityID: UUID) throws -> Bool
    func setPassword(_ password: String, for identityID: UUID) throws
}

struct KeychainCredentialStore: CredentialStoring {
    static let service = "com.vaayne.mori-remote.credentials"
    static let legacyService = "com.vaayne.mori-remote.servers"

    let service: String

    init(service: String = Self.service) { self.service = service }

    func password(for identityID: UUID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identityID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw PersistenceError.keychain(status) }
        return String(data: data, encoding: .utf8)
    }

    func createPasswordIfAbsent(_ password: String, for identityID: UUID) throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identityID.uuidString,
            kSecValueData as String: Data(password.utf8),
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else { throw PersistenceError.keychain(status) }
        return true
    }

    func setPassword(_ password: String, for identityID: UUID) throws {
        let attributes = [kSecValueData as String: Data(password.utf8)]
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identityID.uuidString,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            _ = try createPasswordIfAbsent(password, for: identityID)
        } else if status != errSecSuccess {
            throw PersistenceError.keychain(status)
        }
    }

    func deletePassword(for identityID: UUID) throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identityID.uuidString,
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PersistenceError.keychain(status) }
    }
}

struct TrustedHostStore: Sendable {
    private let store: AtomicJSONStore<[TrustedHost]>

    init(url: URL, writer: any AtomicDataWriting = FoundationAtomicDataWriter()) {
        store = AtomicJSONStore(url: url, writer: writer)
    }

    func trustedHost(for serverID: UUID, endpoint: CanonicalEndpoint) throws -> TrustedHost? {
        try store.load(or: []).first { $0.serverID == serverID && $0.endpoint == endpoint }
    }

    /// A changed host/port cannot inherit trust; all prior endpoint entries for this server are removed.
    func trust(_ host: TrustedHost) throws {
        var hosts = try store.load(or: [])
        hosts.removeAll { $0.serverID == host.serverID }
        hosts.append(host)
        try store.save(hosts)
    }

    func invalidateTrust(for serverID: UUID, ifEndpointChangedFrom endpoint: CanonicalEndpoint) throws {
        var hosts = try store.load(or: [])
        let originalCount = hosts.count
        hosts.removeAll { $0.serverID == serverID && $0.endpoint != endpoint }
        if hosts.count != originalCount { try store.save(hosts) }
    }
}

struct MoriRemoteStorage: Sendable {
    let root: URL
    let servers: SavedServerRepository
    let workspaces: UUIDJSONRepository<SavedWorkspace>
    let identities: UUIDJSONRepository<SSHIdentity>
    let settings: AtomicJSONStore<RemoteSettings>
    let trustedHosts: TrustedHostStore
    let migration: AtomicJSONStore<LegacyMigrationMarker>

    init(root: URL, writer: any AtomicDataWriting = FoundationAtomicDataWriter()) {
        self.root = root
        let trustedHosts = TrustedHostStore(url: root.appendingPathComponent("trusted-hosts.json"), writer: writer)
        self.trustedHosts = trustedHosts
        servers = SavedServerRepository(url: root.appendingPathComponent("servers.json"), trustedHosts: trustedHosts, writer: writer)
        workspaces = UUIDJSONRepository(url: root.appendingPathComponent("workspaces.json"), writer: writer)
        identities = UUIDJSONRepository(url: root.appendingPathComponent("identities.json"), writer: writer)
        settings = AtomicJSONStore(url: root.appendingPathComponent("settings.json"), writer: writer)
        migration = AtomicJSONStore(url: root.appendingPathComponent("migration.json"), writer: writer)
    }

    static func applicationSupport(fileManager: FileManager = .default) throws -> MoriRemoteStorage {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return MoriRemoteStorage(root: base.appendingPathComponent("MoriRemote", isDirectory: true))
    }
}
