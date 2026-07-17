import Foundation
import Security

public enum ProviderCredentialStore {
    private static let service = "com.liuxiaoliang.tokenbar.provider-credentials"

    public static func value(providerId: String, modeId: String, fieldId: String) -> String? {
        let account = account(providerId: providerId, modeId: modeId, fieldId: fieldId)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func setValue(_ value: String, providerId: String, modeId: String, fieldId: String) -> Bool {
        let account = account(providerId: providerId, modeId: modeId, fieldId: fieldId)
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(identity as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }
        var insertion = identity
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess
    }

    public static func hasCredentials(providerId: String, mode: ProviderFetchMode) -> Bool {
        mode.credentialFields.allSatisfy {
            !(value(providerId: providerId, modeId: mode.id, fieldId: $0.id) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func account(providerId: String, modeId: String, fieldId: String) -> String {
        "\(providerId).\(modeId).\(fieldId)"
    }
}
