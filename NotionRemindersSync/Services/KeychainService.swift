import Foundation
import Security

/// Service for securely storing sensitive data in the Keychain
final class KeychainService {
    static let shared = KeychainService()

    private let serviceName = "com.notionremindersync"
    private let notionAPIKeyAccount = "notion-api-key"

    private init() {}

    // MARK: - Notion API Key

    func saveNotionAPIKey(_ key: String) throws {
        try save(key: notionAPIKeyAccount, value: key)
    }

    func getNotionAPIKey() -> String? {
        return get(key: notionAPIKeyAccount)
    }

    func deleteNotionAPIKey() throws {
        try delete(key: notionAPIKeyAccount)
    }

    // MARK: - Generic Keychain Operations

    private func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // First, try to delete any existing item
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    private func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }

    // MARK: - Errors

    enum KeychainError: LocalizedError {
        case encodingFailed
        case saveFailed(status: OSStatus)
        case deleteFailed(status: OSStatus)

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode value for Keychain storage"
            case .saveFailed(let status):
                return "Failed to save to Keychain (status: \(status))"
            case .deleteFailed(let status):
                return "Failed to delete from Keychain (status: \(status))"
            }
        }
    }
}
