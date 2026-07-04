import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public struct SettingsStore {
    @AppStorage("tb.enabledProviderIds") var enabledProviderIdsJSON: String = ""
    public init() {}
    public var enabledProviderIds: Set<String> {
        guard let data = enabledProviderIdsJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(arr)
    }
}
