import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public struct SettingsStore {
    @AppStorage("tb.enabledProviderIds") var enabledProviderIdsJSON: String = ""
    @AppStorage("tb.providerOrderIds") var providerOrderIdsJSON: String = ""
    public init() {}

    public var enabledProviderIds: Set<String> {
        guard let data = enabledProviderIdsJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(arr)
    }

    public var providerOrderIds: [String] {
        guard let data = providerOrderIdsJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }
}
