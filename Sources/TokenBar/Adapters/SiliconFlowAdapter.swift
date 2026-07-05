import Foundation

/// Adapter for 硅基流动 (SiliconFlow).
///
/// ## Endpoint (verified 2026-07-05)
/// ```
/// GET https://cloud.siliconflow.cn/walletd-server/api/v1/subject/profile/peek
/// ```
///
/// Response shape:
/// ```json
/// {
///   "code": 20000,
///   "data": {
///     "financialInfo": {
///       "balance":    "63060715770000",
///       "available":  "63060715770000",
///       "used":       "86939284230000",
///       "recharged":  "150000000000000"
///     }
///   }
/// }
/// ```
///
/// Values are in `×10^12` units (the page divides by 10^12 for display).
/// `balance` and `used` are strings that need to be parsed as Double.
///
/// See `docs/research/siliconflow-research.md` for details.
public struct SiliconFlowAdapter: ProviderAdapter {
    public let id = "siliconflow"
    public var displayName: String { "硅基流动" }
    public var iconSystemName: String { "cloud.fill" }
    public var loginURL: URL { URL(string: "https://cloud.siliconflow.cn/me/expensebill")! }

    private let inner: HTTPAdapter

    public init() {
        let providerId = "siliconflow"
        self.inner = HTTPAdapter(
            id: providerId,
            displayName: "硅基流动",
            iconSystemName: "cloud.fill",
            loginURL: URL(string: "https://cloud.siliconflow.cn/me/expensebill")!,
            method: "GET",
            url: URL(string: "https://cloud.siliconflow.cn/walletd-server/api/v1/subject/profile/peek")!,
            headers: ["Accept": "application/json"],
            pageFallbackDecoder: { page in
                guard let balance = TextAmountParser.cnyAmount(
                    in: page.text,
                    near: ["当前余额", "可用余额", "账户余额", "余额"]
                ) else {
                    return nil
                }
                let quota = Quota(id: "balance", label: "余额", used: 0, total: balance, unit: "¥")
                return Snapshot(providerId: providerId, quotas: [quota], status: .ok)
            },
            decoder: { data in
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let data = obj["data"] as? [String: Any],
                      let finInfo = data["financialInfo"] as? [String: Any],
                      let balanceStr = finInfo["balance"] as? String,
                      let rawBalance = Double(balanceStr) else {
                    return Snapshot(providerId: providerId, quotas: [], status: .error("解析失败: \(DiagnosticPreview.from(data))"))
                }
                // API returns values in ×10^12 units; display CNY value.
                let balance = rawBalance / 1_000_000_000_000
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
