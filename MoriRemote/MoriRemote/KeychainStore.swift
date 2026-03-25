import Foundation
import Security

/// Keychain wrapper for storing and retrieving the relay session ID.
/// Uses Security.framework directly — no external dependencies.
///
/// The session ID is stored per-relay URL so multiple relays can be supported.
/// Invalidation clears the stored credential, forcing re-pairing.
enum KeychainStore: Sendable {

    private static let service = "com.vaayne.mori.remote"
    private static let sessionIDAccount = "relay-session-id"

    // MARK: - Session ID

    /// Store a session ID in the Keychain.
    static func saveSessionID(_ sessionID: String) throws {
        guard let data = sessionID.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionIDAccount,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionIDAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    /// Load the stored session ID from the Keychain.
    /// Returns nil if no session ID is stored.
    static func loadSessionID() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionIDAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Delete the stored session ID (invalidation / unpair).
    static func deleteSessionID() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionIDAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum KeychainError: Error, CustomStringConvertible {
    case encodingFailed
    case saveFailed(status: OSStatus)

    var description: String {
        switch self {
        case .encodingFailed:
            "Failed to encode session ID to data"
        case .saveFailed(let status):
            "Keychain save failed with status: \(status)"
        }
    }
}
