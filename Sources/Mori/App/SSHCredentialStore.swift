import Foundation
import MoriCore
import Security

enum SSHCredentialStoreError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case accessDenied(OSStatus)
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Unable to encode password for secure storage."
        case .decodingFailed:
            return "Stored SSH password has invalid encoding."
        case .accessDenied(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain access denied: \(message)"
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return message
        }
    }
}

/// Stores password-based SSH credentials in macOS Keychain.
enum SSHCredentialStore {
    private static let service = "com.vaayne.mori.ssh"

    private static func account(for ssh: SSHWorkspaceLocation) -> String {
        "password:\(ssh.endpointKey)"
    }

    static func savePassword(_ password: String, for ssh: SSHWorkspaceLocation) throws {
        guard let data = password.data(using: .utf8) else {
            throw SSHCredentialStoreError.encodingFailed
        }

        let baseQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account(for: ssh),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        var addQuery = baseQuery
        addQuery[kSecValueData] = data

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let attributes: [CFString: Any] = [kSecValueData: data]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw SSHCredentialStoreError.unexpectedStatus(updateStatus)
            }
        default:
            throw SSHCredentialStoreError.unexpectedStatus(addStatus)
        }
    }

    static func password(for ssh: SSHWorkspaceLocation) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account(for: ssh),
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecUserCanceled {
            throw SSHCredentialStoreError.accessDenied(status)
        }
        guard status == errSecSuccess else {
            throw SSHCredentialStoreError.unexpectedStatus(status)
        }
        guard let data = item as? Data,
              let password = String(data: data, encoding: .utf8)
        else {
            throw SSHCredentialStoreError.decodingFailed
        }
        return password
    }

    static func deletePassword(for ssh: SSHWorkspaceLocation) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account(for: ssh),
        ]
        SecItemDelete(query as CFDictionary)
    }
}
