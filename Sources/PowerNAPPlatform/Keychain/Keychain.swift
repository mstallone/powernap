import Foundation
import Security

public enum KeychainError: Swift.Error, LocalizedError {
    case unhandledStatus(OSStatus)
    case itemNotFound
    case dataConversion

    public var errorDescription: String? {
        switch self {
        case .unhandledStatus(let s): return "Keychain error (\(s))"
        case .itemNotFound: return "Keychain item not found"
        case .dataConversion: return "Keychain data conversion failed"
        }
    }
}

public enum Keychain {
    public static let service = "dev.powernap"

    public static func setString(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.dataConversion }
        try set(data: data, account: account)
    }

    public static func set(data: Data, account: String) throws {
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        var status = SecItemDelete(attrs as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unhandledStatus(status)
        }
        var add = attrs
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            throw KeychainError.unhandledStatus(status)
        }
    }

    public static func getString(account: String) throws -> String {
        let data = try get(account: account)
        guard let s = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataConversion
        }
        return s
    }

    public static func get(account: String) throws -> Data {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { throw KeychainError.itemNotFound }
        if status != errSecSuccess { throw KeychainError.unhandledStatus(status) }
        guard let data = item as? Data else { throw KeychainError.dataConversion }
        return data
    }

    public static func delete(account: String) throws {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(q as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unhandledStatus(status)
        }
    }
}
