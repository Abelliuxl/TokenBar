import Foundation

public struct VolcanoEngineAdapter: ProviderAdapter {
    public let id = "volcano"
    public var displayName: String { "火山引擎" }
    public var iconSystemName: String { "flame.fill" }
    public var loginURL: URL { URL(string: "https://console.volcengine.com")! }
    public func fetch() async -> Snapshot {
        Snapshot(providerId: id, quotas: [], status: .needsRelogin)
    }
}
