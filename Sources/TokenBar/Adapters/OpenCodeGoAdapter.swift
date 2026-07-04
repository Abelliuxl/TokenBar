import Foundation

public struct OpenCodeGoAdapter: ProviderAdapter {
    public let id = "opencode-go"
    public var displayName: String { "opencode go" }
    public var iconSystemName: String { "bolt.fill" }
    public var loginURL: URL { URL(string: "https://opencode.ai")! }
    public func fetch() async -> Snapshot {
        Snapshot(providerId: id, quotas: [], status: .needsRelogin)
    }
}
