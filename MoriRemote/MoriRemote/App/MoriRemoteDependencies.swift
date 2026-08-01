import Foundation

/// The app composes durable state once. `RemoteLibrary` is the only writer for
/// profile JSON, trust, and credentials, so foreground/UI tasks cannot race a
/// migration or each other through the whole-file atomic stores.
@MainActor
final class MoriRemoteDependencies {
    let library: RemoteLibrary
    let trustedHosts: TrustedHostStore
    let roots = SSHRootPool()

    init(storage: MoriRemoteStorage, legacyServersURL: URL) {
        trustedHosts = storage.trustedHosts
        let migrator = LegacyServerMigrator(storage: storage, legacyServersURL: legacyServersURL)
        library = RemoteLibrary(storage: storage, migrator: migrator)
    }

    static func live() -> MoriRemoteDependencies {
        do {
            let storage = try MoriRemoteStorage.applicationSupport()
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            return MoriRemoteDependencies(storage: storage, legacyServersURL: documents.appendingPathComponent("servers.json"))
        } catch {
            fatalError("MoriRemote cannot prepare Application Support: \(error)")
        }
    }

}

struct RemoteLibrarySnapshot: Sendable {
    var servers: [SavedServer]
    var workspaces: [SavedWorkspace]
    var identities: [SSHIdentity]
    var settings: RemoteSettings
    var migration: LegacyMigrationReport?
}

enum ProfileCredential: Sendable {
    case password(String)
    case privateKey(SSHPrivateKeyCredential)
}

/// Actor ownership is intentional: `UUIDJSONRepository` is an atomic-file
/// primitive, not a multi-writer database. All app mutations pass here.
actor RemoteLibrary {
    private let storage: MoriRemoteStorage
    private let migrator: LegacyServerMigrator
    private let passwords: any CredentialStoring
    private let credentials: any SSHCredentialStoring

    init(
        storage: MoriRemoteStorage,
        migrator: LegacyServerMigrator,
        passwords: any CredentialStoring = KeychainCredentialStore(),
        secretData: any SecretDataStore = SecuritySecretDataStore()
    ) {
        self.storage = storage
        self.migrator = migrator
        self.passwords = passwords
        credentials = KeychainSSHCredentialStore(passwords: passwords, secrets: secretData)
    }

    func bootstrap() throws -> RemoteLibrarySnapshot {
        let report = try migrator.migrateIfNeeded()
        return try snapshot(migration: report)
    }

    func reload() throws -> RemoteLibrarySnapshot { try snapshot(migration: nil) }

    func save(server: SavedServer, workspace: SavedWorkspace?, identity: SSHIdentity, credential: ProfileCredential?) throws -> RemoteLibrarySnapshot {
        var server = try server.validated()
        var workspace = try workspace?.validated()
        _ = try identity.validated()
        guard (workspace == nil || workspace?.serverID == server.id), identity.serverID == server.id, identity.id == server.identityID else {
            throw PersistenceError.corruptStore("profile references")
        }
        let existingServers = try storage.servers.all()
        let existingWorkspaces = try storage.workspaces.all()
        // Drafts never own recency. Preserve it through profile edits so an edit
        // cannot reorder a server/workspace or revive a different workspace.
        if let existing = existingServers.first(where: { $0.id == server.id }) { server.lastConnectedAt = existing.lastConnectedAt }
        if let id = workspace?.id, let existing = existingWorkspaces.first(where: { $0.id == id }) {
            // A profile edit may update only its own selected workspace; it may
            // never repurpose another server's workspace record.
            guard existing.serverID == server.id else { throw PersistenceError.corruptStore("workspace ownership") }
            workspace?.lastConnectedAt = existing.lastConnectedAt
        }
        let existingIdentity = try storage.identities.all().first { $0.id == identity.id }
        if let existingIdentity, existingIdentity.kind != identity.kind, credential == nil {
            // A changed identity type must never silently reinterpret a secret.
            throw SSHAuthResolverError.missingCredential(identity.id)
        }
        if let credential {
            switch credential {
            case let .password(password):
                guard !password.isEmpty else { throw SSHAuthResolverError.missingCredential(identity.id) }
            case let .privateKey(key):
                _ = try SSHPrivateKeyInspector.inspect(key.privateKeyPEM)
            }
        }

        if existingServers.contains(where: { $0.id == server.id }) {
            try storage.servers.replace(server)
        } else {
            _ = try storage.servers.insertIfAbsent(server)
        }
        if let workspace {
            if existingWorkspaces.contains(where: { $0.id == workspace.id }) {
                try storage.workspaces.replace(workspace)
            } else {
                _ = try storage.workspaces.insertIfAbsent(workspace)
            }
        }
        if try storage.identities.all().contains(where: { $0.id == identity.id }) {
            try storage.identities.replace(identity)
        } else {
            _ = try storage.identities.insertIfAbsent(identity)
        }

        if let credential {
            switch credential {
            case let .password(password):
                try passwords.setPassword(password, for: identity.id)
                try credentials.deletePrivateKey(for: identity.id)
            case let .privateKey(key):
                try credentials.savePrivateKey(key, for: identity.id)
                try passwords.deletePassword(for: identity.id)
            }
        }
        return try snapshot(migration: nil)
    }

    func markConnected(workspaceID: UUID, now: Date = .now) throws -> RemoteLibrarySnapshot {
        guard var workspace = try storage.workspaces.all().first(where: { $0.id == workspaceID }) else {
            throw PersistenceError.notFound(workspaceID)
        }
        guard var server = try storage.servers.all().first(where: { $0.id == workspace.serverID }) else {
            throw PersistenceError.notFound(workspace.serverID)
        }
        workspace.lastConnectedAt = now
        server.lastConnectedAt = now
        try storage.workspaces.replace(workspace)
        try storage.servers.replace(server)
        return try snapshot(migration: nil)
    }

    func save(workspace: SavedWorkspace) throws -> RemoteLibrarySnapshot {
        var workspace = try workspace.validated()
        guard try storage.servers.all().contains(where: { $0.id == workspace.serverID }) else {
            throw PersistenceError.notFound(workspace.serverID)
        }
        let existingWorkspaces = try storage.workspaces.all()
        if let existing = existingWorkspaces.first(where: { $0.id == workspace.id }) {
            guard existing.serverID == workspace.serverID else { throw PersistenceError.corruptStore("workspace ownership") }
            // User edits name/session, never their recency ordering.
            workspace.lastConnectedAt = existing.lastConnectedAt
            try storage.workspaces.replace(workspace)
        } else {
            _ = try storage.workspaces.insertIfAbsent(workspace)
        }
        return try snapshot(migration: nil)
    }

    func delete(workspaceID: UUID) throws -> RemoteLibrarySnapshot {
        try storage.workspaces.remove(workspaceID)
        return try snapshot(migration: nil)
    }

    func delete(serverID: UUID) throws -> RemoteLibrarySnapshot {
        let workspaces = try storage.workspaces.all().filter { $0.serverID == serverID }
        let identities = try storage.identities.all().filter { $0.serverID == serverID }
        for workspace in workspaces { try storage.workspaces.remove(workspace.id) }
        for identity in identities {
            try storage.identities.remove(identity.id)
            try passwords.deletePassword(for: identity.id)
            try credentials.deletePrivateKey(for: identity.id)
        }
        try storage.servers.remove(serverID)
        return try snapshot(migration: nil)
    }

    func save(settings: RemoteSettings) throws -> RemoteLibrarySnapshot {
        _ = try settings.validated()
        try storage.settings.save(settings)
        return try snapshot(migration: nil)
    }

    func trust(_ challenge: SSHHostTrustChallenge, replaceChanged: Bool) throws {
        try SSHHostTrustResolver(store: storage.trustedHosts).explicitlyTrust(challenge, replaceChanged: replaceChanged)
    }

    func synchronizeDiscoveredSessions(serverID: UUID, names: [String]) throws -> RemoteLibrarySnapshot {
        guard try storage.servers.all().contains(where: { $0.id == serverID }) else {
            throw PersistenceError.notFound(serverID)
        }
        var existingNames = Set(try storage.workspaces.all().filter { $0.serverID == serverID }.map(\.tmuxSession))
        for name in names where !existingNames.contains(name) {
            let workspace = try SavedWorkspace(serverID: serverID, name: name, tmuxSession: name).validated()
            _ = try storage.workspaces.insertIfAbsent(workspace)
            existingNames.insert(name)
        }
        return try snapshot(migration: nil)
    }

    func discoveryMaterial(for serverID: UUID) throws -> (SavedServer, SSHIdentity, RemoteSettings) {
        guard let server = try storage.servers.all().first(where: { $0.id == serverID }) else {
            throw PersistenceError.notFound(serverID)
        }
        guard let identity = try storage.identities.all().first(where: { $0.id == server.identityID }) else {
            throw SSHAuthResolverError.missingIdentity(server.identityID)
        }
        return (server, identity, try storage.settings.load(or: .default))
    }

    func connectionMaterial(for workspaceID: UUID) throws -> (SavedWorkspace, SavedServer, SSHIdentity, RemoteSettings) {
        let workspaces = try storage.workspaces.all()
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { throw PersistenceError.notFound(workspaceID) }
        let servers = try storage.servers.all()
        guard let server = servers.first(where: { $0.id == workspace.serverID }) else { throw PersistenceError.notFound(workspace.serverID) }
        let identities = try storage.identities.all()
        guard let identity = identities.first(where: { $0.id == server.identityID }) else { throw SSHAuthResolverError.missingIdentity(server.identityID) }
        return (workspace, server, identity, try storage.settings.load(or: .default))
    }

    func resolveAuth(server: SavedServer, identity: SSHIdentity, settings: RemoteSettings) throws -> ResolvedSSHAuth {
        try SSHAuthResolver(credentials: credentials).resolve(server: server, identity: identity, settings: settings)
    }

    private func snapshot(migration: LegacyMigrationReport?) throws -> RemoteLibrarySnapshot {
        let servers = try storage.servers.all().sorted { ($0.lastConnectedAt ?? .distantPast, $0.name) > ($1.lastConnectedAt ?? .distantPast, $1.name) }
        let serverIDs = Set(servers.map(\.id))
        let workspaces = try storage.workspaces.all().filter { serverIDs.contains($0.serverID) }.sorted { ($0.lastConnectedAt ?? .distantPast, $0.name) > ($1.lastConnectedAt ?? .distantPast, $1.name) }
        let identities = try storage.identities.all().filter { serverIDs.contains($0.serverID) }
        return .init(servers: servers, workspaces: workspaces, identities: identities, settings: try storage.settings.load(or: .default), migration: migration)
    }
}
