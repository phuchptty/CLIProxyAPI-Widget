import Foundation
import Security

struct KeychainStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "vn.ppx.CPA-Widget.management",
         kSecAttrAccount as String: "active-instance"]
    }

    func load() throws -> String {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { throw KeychainError(status: status) }
        return key
    }

    func save(_ key: String) throws {
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var entry = query
            entry.merge(attributes) { _, new in new }
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(entry as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }
}
