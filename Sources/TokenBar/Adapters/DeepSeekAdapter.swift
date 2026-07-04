import Foundation

public struct DeepSeekAdapter: ProviderAdapter {
    public let id = "deepseek"
    public var displayName: String { "DeepSeek" }
    public var iconSystemName: String { "magnifyingglass" }
    public var loginURL: URL { URL(string: "https://platform.deepseek.com")! }

    private let inner = HTTPAdapter(
        id: "deepseek",
        displayName: "DeepSeek",
        iconSystemName: "magnifyingglass",
        loginURL: URL(string: "https://platform.deepseek.com")!,
        method: "GET",
        url: URL(string: "https://platform.deepseek.com/api/v1/balance")!,
        headers: ["Accept": "application/json"],
        decoder: { data in
            // Placeholder — research file has selector details.
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let balance = obj["balance"] as? Double else {
                return Snapshot(providerId: "deepseek", quotas: [], status: .error("decode"))
            }
            let quota = Quota(id: "balance", label: "余额", used: 0, total: balance, unit: "¥")
            return Snapshot(providerId: "deepseek", quotas: [quota], status: .ok)
        }
    )

    public func fetch() async -> Snapshot { await inner.fetch() }
}
