import Foundation

public struct VolcanoEngineAdapter: ProviderAdapter {
    public let id = "volcano"
    public var displayName: String { "火山引擎" }
    public var iconSystemName: String { "flame.fill" }
    public var loginURL: URL { URL(string: "https://console.volcengine.com")! }

    private let inner = HTTPAdapter(
        id: "volcano",
        displayName: "火山引擎",
        iconSystemName: "flame.fill",
        loginURL: URL(string: "https://console.volcengine.com")!,
        method: "GET",
        // Endpoint TBD: research will pin it. Using a plausible placeholder.
        url: URL(string: "https://console.volcengine.com/api/balance")!,
        headers: ["Accept": "application/json"],
        decoder: { data in
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let balance = obj["balance"] as? Double else {
                return Snapshot(providerId: "volcano", quotas: [], status: .error("decode"))
            }
            let quota = Quota(id: "balance", label: "余额", used: 0, total: balance, unit: "¥")
            return Snapshot(providerId: "volcano", quotas: [quota], status: .ok)
        }
    )

    public func fetch() async -> Snapshot { await inner.fetch() }
}
