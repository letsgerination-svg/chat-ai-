import Foundation
import Security

public enum APIKeyStoreError: Error, LocalizedError, Sendable {
    case keychainStatus(Int32)

    public var errorDescription: String? {
        switch self {
        case .keychainStatus(let status):
            return "Keychain operation failed (status \(status))."
        }
    }
}

public protocol APIKeyStore: Sendable {
    func read() throws -> String?
    func save(_ key: String) throws
    func delete() throws
}

/// Stores the user's provider credential in the iOS Keychain.
/// The key is never written to UserDefaults, files, or application logs.
public final class KeychainAPIKeyStore: APIKeyStore, @unchecked Sendable {
    private let service: String
    private let account: String

    public init(
        service: String = Bundle.main.bundleIdentifier ?? "HybridChat",
        account: String = "deepseek-api-key"
    ) {
        self.service = service
        self.account = account
    }

    public func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw APIKeyStoreError.keychainStatus(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    public func save(_ key: String) throws {
        guard !key.isEmpty else {
            try delete()
            return
        }

        let data = Data(key.utf8)
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(baseQuery as CFDictionary, update)

        if status == errSecItemNotFound {
            var insert = baseQuery
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw APIKeyStoreError.keychainStatus(addStatus)
            }
        } else if status != errSecSuccess {
            throw APIKeyStoreError.keychainStatus(status)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.keychainStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
