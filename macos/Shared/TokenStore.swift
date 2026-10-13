import Foundation
import Security

/// Token and workspace choice, shared between the app and the widget extension
/// through a keychain access group (see `keychain-access-groups` in project.yml).
enum TokenStore {
    enum Key: String {
        case token
        case teamId
    }

    private static let service = "com.wansiedler.clickupwidget"

    /// `$(AppIdentifierPrefix)…` resolved at build time via Info.plist.
    private static var accessGroup: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String,
              !group.isEmpty, !group.contains("$(") else { return nil }
        return group
    }

    static func read(_ key: Key) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Empty or nil deletes the item.
    @discardableResult
    static func write(_ key: Key, _ value: String?) -> OSStatus {
        let query = baseQuery(key)
        _ = SecItemDelete(query as CFDictionary)
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return errSecSuccess
        }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil)
    }

    private static func baseQuery(_ key: Key) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}
