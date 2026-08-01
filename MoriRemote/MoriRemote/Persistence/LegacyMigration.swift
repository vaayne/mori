import Foundation

struct LegacyServerRecord: Codable, Sendable {
    let id: UUID
    let name: String
    let host: String
    let port: Int
    let username: String
    let defaultSession: String
    let lastConnectedAt: Date?
}

enum LegacyMigrationDisposition: String, Codable, Equatable, Sendable {
    case migrated
    case migratedWithoutCredential
    case skippedInvalid
}

struct LegacyMigrationRecord: Codable, Equatable, Sendable {
    let legacyID: String
    let disposition: LegacyMigrationDisposition
}

struct LegacyMigrationMarker: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let completedAt: Date
    let records: [LegacyMigrationRecord]
}

struct LegacyMigrationReport: Equatable, Sendable {
    let completed: Bool
    let records: [LegacyMigrationRecord]
}

/// One-way, retry-safe importer. It never writes legacy Documents or the old Keychain service.
struct LegacyServerMigrator: Sendable {
    let storage: MoriRemoteStorage
    let legacyServersURL: URL
    let legacyCredentials: any CredentialReading
    let destinationCredentials: any CredentialStoring
    let now: @Sendable () -> Date

    init(
        storage: MoriRemoteStorage,
        legacyServersURL: URL,
        legacyCredentials: any CredentialReading = KeychainCredentialStore.legacyReader(),
        destinationCredentials: any CredentialStoring = KeychainCredentialStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.storage = storage
        self.legacyServersURL = legacyServersURL
        self.legacyCredentials = legacyCredentials
        self.destinationCredentials = destinationCredentials
        self.now = now
    }

    func migrateIfNeeded() throws -> LegacyMigrationReport {
        if let marker = try storage.migration.loadIfPresent() {
            return LegacyMigrationReport(completed: true, records: marker.records)
        }

        let records = try decodeLegacyRecords()
        var dispositions: [LegacyMigrationRecord] = []
        var seen = Set<UUID>()

        for record in records.enumerated().sorted(by: { migrationOrderKey($0) < migrationOrderKey($1) }).map(\.element) {
            switch record {
            case .invalid(let index):
                dispositions.append(LegacyMigrationRecord(legacyID: "invalid-\(index)", disposition: .skippedInvalid))
            case .server(let legacy):
                guard seen.insert(legacy.id).inserted else {
                    dispositions.append(LegacyMigrationRecord(legacyID: legacy.id.uuidString, disposition: .skippedInvalid))
                    continue
                }
                dispositions.append(try migrate(legacy))
            }
        }

        try validateTerminalSnapshot(dispositions)

        // This is intentionally last: any persistence/keychain failure above leaves migration retryable.
        let marker = LegacyMigrationMarker(schemaVersion: LegacyMigrationMarker.schemaVersion, completedAt: now(), records: dispositions)
        try storage.migration.save(marker)
        return LegacyMigrationReport(completed: true, records: dispositions)
    }

    private func migrate(_ legacy: LegacyServerRecord) throws -> LegacyMigrationRecord {
        let server = SavedServer(
            id: legacy.id,
            name: legacy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? legacy.username + "@" + legacy.host : legacy.name,
            host: legacy.host,
            port: legacy.port,
            username: legacy.username,
            identityID: legacy.id,
            lastConnectedAt: legacy.lastConnectedAt
        )
        let session = legacy.defaultSession
        let normalizedSession = session.contains(where: { $0.isNewline || $0 == "\0" })
            ? session
            : (session.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "main" : session)
        let workspace = SavedWorkspace(
            id: legacy.id,
            serverID: legacy.id,
            name: normalizedSession,
            tmuxSession: normalizedSession,
            lastConnectedAt: legacy.lastConnectedAt
        )
        let identity = SSHIdentity(id: legacy.id, serverID: legacy.id, kind: .password)

        do {
            _ = try server.validated()
            _ = try workspace.validated()
            _ = try identity.validated()
        } catch {
            return LegacyMigrationRecord(legacyID: legacy.id.uuidString, disposition: .skippedInvalid)
        }

        // Insert-only retries preserve any profile edits made after an interrupted first attempt.
        _ = try storage.servers.insertIfAbsent(server)
        _ = try storage.identities.insertIfAbsent(identity)
        _ = try storage.workspaces.insertIfAbsent(workspace)

        guard let password = try legacyCredentials.password(for: legacy.id), !password.isEmpty else {
            return LegacyMigrationRecord(legacyID: legacy.id.uuidString, disposition: .migratedWithoutCredential)
        }
        // Add-only retries may complete a missing destination secret, never replace a user-edited one.
        _ = try destinationCredentials.createPasswordIfAbsent(password, for: legacy.id)
        return LegacyMigrationRecord(legacyID: legacy.id.uuidString, disposition: .migrated)
    }

    private func migrationOrderKey(_ entry: (offset: Int, element: DecodedRecord)) -> MigrationOrderKey {
        switch entry.element {
        case let .server(server) where server.lastConnectedAt != nil:
            return MigrationOrderKey(kind: 0, date: server.lastConnectedAt, sourceIndex: entry.offset)
        case .server:
            return MigrationOrderKey(kind: 1, date: nil, sourceIndex: entry.offset)
        case .invalid:
            return MigrationOrderKey(kind: 2, date: nil, sourceIndex: entry.offset)
        }
    }

    /// Strict total order: dated profiles (newest first), undated profiles, invalid source records; source index breaks ties.
    private struct MigrationOrderKey: Comparable {
        let kind: Int
        let date: Date?
        let sourceIndex: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
            if let left = lhs.date, let right = rhs.date, left != right { return left > right }
            return lhs.sourceIndex < rhs.sourceIndex
        }
    }

    private func validateTerminalSnapshot(_ dispositions: [LegacyMigrationRecord]) throws {
        let servers = try storage.servers.all()
        let identities = try storage.identities.all()
        let workspaces = try storage.workspaces.all()

        for record in dispositions where record.disposition != .skippedInvalid {
            guard let id = UUID(uuidString: record.legacyID),
                  let server = servers.first(where: { $0.id == id }),
                  let identity = identities.first(where: { $0.id == id }), identity.serverID == server.id,
                  let workspace = workspaces.first(where: { $0.id == id }), workspace.serverID == server.id else {
                throw PersistenceError.corruptStore("migration referential integrity")
            }
            if record.disposition == .migrated,
               try destinationCredentials.password(for: id) == nil {
                throw PersistenceError.corruptStore("migration credential disposition")
            }
        }
    }

    private enum DecodedRecord: Sendable {
        case server(LegacyServerRecord)
        case invalid(Int)
    }

    private func decodeLegacyRecords() throws -> [DecodedRecord] {
        guard FileManager.default.fileExists(atPath: legacyServersURL.path) else { return [] }
        let data = try Data(contentsOf: legacyServersURL)
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            // Malformed source is terminal: there is no safe record to retry. Preserve the bytes untouched.
            return [.invalid(0)]
        }
        // Legacy ServerStore used JSONEncoder's default Date representation.
        let decoder = JSONDecoder()
        return raw.enumerated().map { index, object in
            guard JSONSerialization.isValidJSONObject(object),
                  let itemData = try? JSONSerialization.data(withJSONObject: object),
                  let server = try? decoder.decode(LegacyServerRecord.self, from: itemData) else {
                return .invalid(index)
            }
            return .server(server)
        }
    }
}
