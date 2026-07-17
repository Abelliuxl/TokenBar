import Foundation

/// Simple credential store backed by `UserDefaults`.
/// Avoids Keychain so the ad-hoc signed app never triggers a Keychain
/// authorization prompt.
///
/// These are API keys stored as plaintext in the app's preferences plist.
/// If you need stronger protection, replace this backend with Keychain once
/// the app has a stable code-signing identity.
public enum ProviderCredentialStore {
    private static let keyPrefix = "tb.credential"

    public static func value(providerId: String, modeId: String, fieldId: String) -> String? {
        UserDefaults.standard.string(forKey: prefixedKey(providerId, modeId, fieldId))
    }

    @discardableResult
    public static func setValue(_ value: String, providerId: String, modeId: String, fieldId: String) -> Bool {
        UserDefaults.standard.set(value, forKey: prefixedKey(providerId, modeId, fieldId))
        return true
    }

    public static func hasCredentials(providerId: String, mode: ProviderFetchMode) -> Bool {
        mode.credentialFields.allSatisfy {
            !(value(providerId: providerId, modeId: mode.id, fieldId: $0.id) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func prefixedKey(_ providerId: String, _ modeId: String, _ fieldId: String) -> String {
        "\(keyPrefix).\(providerId).\(modeId).\(fieldId)"
    }
}
