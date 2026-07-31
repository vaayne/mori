@preconcurrency import Crypto
import Foundation
import Security

struct SSHPrivateKeyCredential: Equatable, Sendable {
    let privateKeyPEM: String
    let passphrase: String?
}

enum SSHCredential: Equatable, Sendable {
    case password(String)
    case privateKey(SSHPrivateKeyCredential)

    var kind: SSHIdentityKind {
        switch self {
        case .password: .password
        case .privateKey: .privateKey
        }
    }
}

enum ResolvedSSHAuth: Equatable, Sendable {
    case password(username: String, password: String, identityID: UUID, label: String)
    case privateKey(username: String, credential: SSHPrivateKeyCredential, identityID: UUID, label: String)

    var identityID: UUID {
        switch self {
        case let .password(_, _, id, _), let .privateKey(_, _, id, _): id
        }
    }
}

enum SSHAuthResolverError: Error, Equatable, Sendable, LocalizedError {
    case missingIdentity(UUID)
    case missingCredential(UUID)
    case credentialKindMismatch(UUID)
    case unsupportedLegacyRSA

    var errorDescription: String? {
        switch self {
        case .missingIdentity:
            String(localized: "SSH identity is missing.")
        case .missingCredential:
            String(localized: "SSH credential is required.")
        case .credentialKindMismatch:
            String(localized: "The saved SSH credential does not match its identity.")
        case .unsupportedLegacyRSA:
            String(localized: "Legacy RSA/SHA-1 authentication is disabled.")
        }
    }
}

struct SSHAuthResolver: Sendable {
    let credentials: any SSHCredentialReading

    func resolve(server: SavedServer, identity: SSHIdentity, settings: RemoteSettings = .default) throws -> ResolvedSSHAuth {
        guard identity.serverID == server.id, identity.id == server.identityID else {
            throw SSHAuthResolverError.missingIdentity(server.identityID)
        }
        guard let credential = try credentials.credential(for: identity.id) else {
            throw SSHAuthResolverError.missingCredential(identity.id)
        }
        guard credential.kind == identity.kind else {
            throw SSHAuthResolverError.credentialKindMismatch(identity.id)
        }
        switch credential {
        case .password(let password):
            return .password(username: server.username, password: password, identityID: identity.id, label: identity.label)
        case .privateKey(let key):
            let inspection = try SSHPrivateKeyInspector.inspect(key.privateKeyPEM)
            guard !(inspection.keyType == .rsa && !settings.allowLegacyRSA) else {
                throw SSHAuthResolverError.unsupportedLegacyRSA
            }
            return .privateKey(username: server.username, credential: key, identityID: identity.id, label: identity.label)
        }
    }
}

protocol SSHCredentialReading: Sendable {
    func credential(for identityID: UUID) throws -> SSHCredential?
}

/// Minimal secret boundary shared by the device Keychain and deterministic tests.
protocol SecretDataStore: Sendable {
    func read(service: String, account: String) throws -> Data?
    func createOrUpdate(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

struct SecuritySecretDataStore: SecretDataStore {
    func read(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw PersistenceError.keychain(status)
        }
        return data
    }

    func createOrUpdate(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else { throw PersistenceError.keychain(insertStatus) }
        } else if status != errSecSuccess {
            throw PersistenceError.keychain(status)
        }
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PersistenceError.keychain(status)
        }
    }
}

enum SSHCredentialStoreError: Error, Equatable, Sendable {
    case corruptPrivateKey(UUID)
}

/// Secrets stay in the Keychain; no key material/passphrase enters profile JSON.
struct KeychainSSHCredentialStore: SSHCredentialReading, Sendable {
    static let privateKeyService = "com.vaayne.mori-remote.private-keys"

    let passwords: any CredentialReading
    let secrets: any SecretDataStore
    let service: String

    init(
        passwords: any CredentialReading = KeychainCredentialStore(),
        secrets: any SecretDataStore = SecuritySecretDataStore(),
        service: String = Self.privateKeyService
    ) {
        self.passwords = passwords
        self.secrets = secrets
        self.service = service
    }

    func credential(for identityID: UUID) throws -> SSHCredential? {
        let account = identityID.uuidString
        if let data = try secrets.read(service: service, account: account) {
            do {
                let key = try JSONDecoder().decode(StoredPrivateKey.self, from: data)
                return .privateKey(.init(privateKeyPEM: key.pem, passphrase: key.passphrase))
            } catch {
                // A present but corrupt private-key secret is not a missing key.
                // Falling through to a password would silently authenticate differently.
                throw SSHCredentialStoreError.corruptPrivateKey(identityID)
            }
        }
        return try passwords.password(for: identityID).map(SSHCredential.password)
    }

    func savePrivateKey(_ credential: SSHPrivateKeyCredential, for identityID: UUID) throws {
        _ = try SSHPrivateKeyInspector.inspect(credential.privateKeyPEM)
        try secrets.createOrUpdate(
            JSONEncoder().encode(StoredPrivateKey(pem: credential.privateKeyPEM, passphrase: credential.passphrase)),
            service: service,
            account: identityID.uuidString
        )
    }

    func deletePrivateKey(for identityID: UUID) throws {
        try secrets.delete(service: service, account: identityID.uuidString)
    }

    private struct StoredPrivateKey: Codable {
        let pem: String
        let passphrase: String?
    }
}
