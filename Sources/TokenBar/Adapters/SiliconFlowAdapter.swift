import Foundation

/// Adapter for 硅基流动 (SiliconFlow).
///
/// Authentication: cookie-based — the user logs into `https://cloud.siliconflow.cn`
/// in the host browser; we capture the resulting session cookie into the keychain
/// and replay it on every fetch as a `Cookie:` header.
///
/// Endpoint: `GET https://cloud.siliconflow.cn/api/v1/bills/balance`
/// Response shape (tentative, see `docs/research/siliconflow-research.md`):
///   { "balance": <Double> }   // remaining CNY balance
public struct SiliconFlowAdapter: ProviderAdapter {
    public let id = "siliconflow"
    public var displayName: String { "硅基流动" }
    public var iconSystemName: String { "cloud.fill" }
    public var loginURL: URL { URL(string: "https://cloud.siliconflow.cn")! }

    private let inner: HTTPAdapter

    public init() {
        let providerId = "siliconflow"
        self.inner = HTTPAdapter(
            id: providerId,
            displayName: "硅基流动",
            iconSystemName: "cloud.fill",
            loginURL: URL(string: "https://cloud.siliconflow.cn/")!,
            method: "GET",
            url: URL(string: "https://cloud.siliconflow.cn/api/v1/bills/balance")!,
            headers: ["Accept": "application/json"],
            decoder: { data in
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let balance = obj["balance"] as? Double else {
                    return Snapshot(providerId: providerId, quotas: [], status: .error("decode"))
                }
                let quota = Quota(id: "balance", label: "余额",
                                  used: 0, total: balance, unit: "¥")
                return Snapshot(providerId: providerId, quotas: [quota], status: .ok)
            }
        )
    }

    public func fetch() async -> Snapshot {
        await inner.fetch()
    }
}