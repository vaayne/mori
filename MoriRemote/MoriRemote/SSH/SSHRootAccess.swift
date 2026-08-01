import Foundation

/// A lazy, authenticated route into one pooled SSH root. Authentication and
/// endpoint identity are fixed when the route is prepared; TOFU still occurs
/// only when the owning discovery, terminal, or upload operation requests a lease.
struct AuthenticatedSSHRootSource: Sendable {
    private let pool: SSHRootPool
    private let key: SSHRootPool.Key
    private let connector: any SSHRootConnecting

    init(
        pool: SSHRootPool,
        key: SSHRootPool.Key,
        connector: any SSHRootConnecting
    ) {
        self.pool = pool
        self.key = key
        self.connector = connector
    }

    func lease() async throws -> SSHRootLease {
        try await pool.lease(for: key, connector: connector)
    }
}

struct SSHWorkspaceAccess: Sendable {
    let workspace: SavedWorkspace
    let settings: RemoteSettings
    let root: AuthenticatedSSHRootSource
}

/// Resolves durable server material into the single authenticated-root recipe
/// shared by discovery, terminal control, and SFTP uploads.
struct SSHRootAccess: Sendable {
    typealias ConnectorFactory = @Sendable (
        SavedServer,
        ResolvedSSHAuth,
        TrustedHostStore
    ) -> any SSHRootConnecting

    private let library: RemoteLibrary
    private let pool: SSHRootPool
    private let trustedHosts: TrustedHostStore
    private let makeConnector: ConnectorFactory

    init(
        library: RemoteLibrary,
        pool: SSHRootPool,
        trustedHosts: TrustedHostStore,
        makeConnector: @escaping ConnectorFactory = { server, auth, trustedHosts in
            CitadelSSHRootConnector(
                server: server,
                auth: auth,
                trust: SSHHostTrustResolver(store: trustedHosts)
            )
        }
    ) {
        self.library = library
        self.pool = pool
        self.trustedHosts = trustedHosts
        self.makeConnector = makeConnector
    }

    func workspace(_ workspaceID: UUID) async throws -> SSHWorkspaceAccess {
        let material = try await library.connectionMaterial(for: workspaceID)
        let root = try await source(
            server: material.1,
            identity: material.2,
            settings: material.3
        )
        return SSHWorkspaceAccess(
            workspace: material.0,
            settings: material.3,
            root: root
        )
    }

    func server(_ serverID: UUID) async throws -> AuthenticatedSSHRootSource {
        let material = try await library.discoveryMaterial(for: serverID)
        return try await source(
            server: material.0,
            identity: material.1,
            settings: material.2
        )
    }

    private func source(
        server: SavedServer,
        identity: SSHIdentity,
        settings: RemoteSettings
    ) async throws -> AuthenticatedSSHRootSource {
        let auth = try await library.resolveAuth(
            server: server,
            identity: identity,
            settings: settings
        )
        let endpoint = try CanonicalEndpoint(host: server.host, port: server.port)
        let key = SSHRootPool.Key(
            serverID: server.id,
            endpoint: endpoint,
            username: server.username,
            authenticationFingerprint: auth.rootPoolFingerprint
        )
        return AuthenticatedSSHRootSource(
            pool: pool,
            key: key,
            connector: makeConnector(server, auth, trustedHosts)
        )
    }
}
