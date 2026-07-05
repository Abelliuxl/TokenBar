import Foundation

/// Adapter for DeepSeek.
///
/// ## Endpoint (verified 2026-07-05)
/// ```
/// GET https://platform.deepseek.com/auth-api/v0/users/current
/// ```
///
/// Response shape:
/// ```json
/// {
///   "code": 0,
///   "data": {
///     "biz_data": {
///       "normal_wallets": [{
///         "balance":           "21.84",
///         "currency":          "CNY",
///         "token_estimation":  "7278336"
///       }],
///       "monthly_costs": [{
///         "amount":   "2.06",
///         "currency": "CNY"
///       }],
///       "monthly_usage": "24095722",
///       "total_available_token_estimation": "7278336"
///     }
///   }
/// }
/// ```
///
/// The primary balance field is `normal_wallets[0].balance` (String → Double).
/// Token estimation is also available via `token_estimation`.
///
/// See `docs/research/deepseek-research.md` for details.
public struct DeepSeekAdapter: ProviderAdapter {
    public let id = "deepseek"
    public var displayName: String { "DeepSeek" }
    public var iconSystemName: String { "brain.head.profile" }
    public var loginURL: URL { URL(string: "https://platform.deepseek.com/usage")! }

    private let inner = HTTPAdapter(
        id: "deepseek",
        displayName: "DeepSeek",
        iconSystemName: "brain.head.profile",
        loginURL: URL(string: "https://platform.deepseek.com/usage")!,
        method: "GET",
        url: URL(string: "https://platform.deepseek.com/auth-api/v0/users/current")!,
        headers: ["Accept": "application/json"],
        pageFallbackDecoder: { page in
            guard let balance = TextAmountParser.cnyAmount(
                in: page.text,
                near: ["余额", "可用余额", "账户余额", "钱包余额"]
            ) else {
                return nil
            }
            let quota = Quota(id: "balance", label: "余额", used: 0, total: balance, unit: "¥")
            return Snapshot(providerId: "deepseek", quotas: [quota], status: .ok)
        },
        decoder: { data in
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let data = obj["data"] as? [String: Any],
                  let bizData = data["biz_data"] as? [String: Any],
                  let wallets = bizData["normal_wallets"] as? [[String: Any]],
                  let firstWallet = wallets.first,
                  let balanceStr = firstWallet["balance"] as? String,
                  let balance = Double(balanceStr) else {
                return Snapshot(providerId: "deepseek", quotas: [], status: .error("解析失败: \(DiagnosticPreview.from(data))"))
            }
            let quota = Quota(id: "balance", label: "余额",
                              used: 0, total: balance, unit: "¥")
            return Snapshot(providerId: "deepseek", quotas: [quota], status: .ok)
        }
    )

    public func fetch() async -> Snapshot { await inner.fetch() }
}
