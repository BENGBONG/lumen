import Foundation
import Security

/// Thin wrapper around macOS Keychain for storing AI provider API keys.
/// Each provider gets its own Keychain item (distinguished by account name).
public struct KeychainStore {

    private static let service = "com.panglin.forkliftclone.ai"

    // MARK: - Public API (provider-scoped)

    public static func save(_ key: String, for provider: AIProvider) throws {
        let data = Data(key.utf8)
        let updateQuery = baseQuery(account: provider.rawValue)
        let attrs: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(updateQuery as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = baseQuery(account: provider.rawValue)
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unhandledError(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unhandledError(status)
        }
    }

    public static func load(for provider: AIProvider) -> String? {
        var query = baseQuery(account: provider.rawValue)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(for provider: AIProvider) throws {
        let status = SecItemDelete(baseQuery(account: provider.rawValue) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status)
        }
    }

    public static func hasKey(for provider: AIProvider) -> Bool {
        load(for: provider) != nil
    }

    // MARK: - Convenience (current provider)

    public static var currentKey: String? { load(for: .current) }
    public static var hasCurrentKey: Bool { hasKey(for: .current) }

    // MARK: - Legacy single-key API (kept for backward compat, maps to .anthropic)

    @available(*, deprecated, renamed: "save(_:for:)")
    public static func save(_ key: String) throws { try save(key, for: .anthropic) }

    @available(*, deprecated, renamed: "load(for:)")
    public static func load() -> String? { load(for: .anthropic) }

    @available(*, deprecated, renamed: "delete(for:)")
    public static func delete() throws { try delete(for: .anthropic) }

    @available(*, deprecated, renamed: "hasKey(for:)")
    public static var hasKey: Bool { hasKey(for: .anthropic) }

    // MARK: - Private

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    // MARK: - Error

    public enum KeychainError: LocalizedError {
        case unhandledError(OSStatus)
        public var errorDescription: String? {
            "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) ?? "unknown" as CFString)"
        }
        var status: OSStatus {
            if case .unhandledError(let s) = self { return s }; return errSecParam
        }
    }
}
