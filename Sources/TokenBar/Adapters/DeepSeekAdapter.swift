import Foundation

public struct DeepSeekAdapter: ProviderAdapter {
    public let id = "deepseek"
    public var displayName: String { "DeepSeek" }
    public var iconSystemName: String { "magnifyingglass" }
    public var loginURL: URL { URL(string: "https://platform.deepseek.com")! }
    public func fetch() async -> Snapshot {
        Snapshot(providerId: id, quotas: [], status: .needsRelogin)
    }
}
