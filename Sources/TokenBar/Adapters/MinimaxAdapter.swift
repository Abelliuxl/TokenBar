import Foundation

public struct MinimaxAdapter: ProviderAdapter {
    public let id = "minimax"
    public var displayName: String { "MiniMax" }
    public var iconSystemName: String { "sparkles" }
    public var loginURL: URL { URL(string: "https://api.minimax.chat")! }
    public func fetch() async -> Snapshot {
        Snapshot(providerId: id, quotas: [], status: .needsRelogin)
    }
}
