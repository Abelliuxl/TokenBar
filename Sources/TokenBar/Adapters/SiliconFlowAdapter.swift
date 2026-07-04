import Foundation

public struct SiliconFlowAdapter: ProviderAdapter {
    public let id = "siliconflow"
    public var displayName: String { "硅基流动" }
    public var iconSystemName: String { "cloud.fill" }
    public var loginURL: URL { URL(string: "https://cloud.siliconflow.cn")! }
    public func fetch() async -> Snapshot {
        Snapshot(providerId: id, quotas: [], status: .needsRelogin)
    }
}
