import Foundation
import Security

struct Server: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var defaultSession: String

    /// Transient — not persisted to JSON. Loaded from / saved to Keychain.
    var password: String

    private enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, defaultSession
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        port: Int = 22,
        username: String = "",
        password: String = "",
        defaultSession: String = "main"
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.defaultSession = defaultSession
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decode(Int.self, forKey: .port)
        username = try c.decode(String.self, forKey: .username)
        defaultSession = try c.decode(String.self, forKey: .defaultSession)
        password = KeychainHelper.load(account: id.uuidString) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(host, forKey: .host)
        try c.encode(port, forKey: .port)
        try c.encode(username, forKey: .username)
        try c.encode(defaultSession, forKey: .defaultSession)
    }

    /// Persist the password to Keychain (call after add/update).
    func savePasswordToKeychain() {
        KeychainHelper.save(password, account: id.uuidString)
    }

    /// Remove the password from Keychain (call on delete).
    func deletePasswordFromKeychain() {
        KeychainHelper.delete(account: id.uuidString)
    }

    private var address: String {
        port != 22 ? "\(host):\(port)" : host
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty ? trimmed : "\(username)@\(address)"
    }

    var subtitle: String {
        "\(username)@\(address)"
    }

    var isValid: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        port > 0 && port <= 65535
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {
    private static let service = "dev.mori.remote.servers"

    static func save(_ password: String, account: String) {
        guard let data = password.data(using: .utf8) else { return }
        delete(account: account) // remove old entry first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
