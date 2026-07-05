import Foundation

/// Adapter for 火山引擎 (Volcano Engine).
///
/// ## Endpoint (verified 2026-07-05)
/// ```
/// GET https://console.volcengine.com/api/top/bill_volcano_engine/cn-north-1/2020-01-01/GetBalanceFromTradeBalance
/// ```
///
/// Response shape:
/// ```json
/// {
///   "ResponseMetadata": { ... },
///   "Result": {
///     "Acct": {
///       "AvailableBalance": "20.29",
///       "CashBalance":      "20.29",
///       "CarryOverBalance": "20.29",
///       "Currency":         "CNY"
///     }
///   }
/// }
/// ```
///
/// The primary balance field is `Result.Acct.AvailableBalance` (String → Double, CNY).
///
/// See `docs/research/volcano-research.md` for details.
public struct VolcanoEngineAdapter: ProviderAdapter {
    public let id = "volcano"
    public var displayName: String { "火山引擎" }
    public var iconSystemName: String { "flame.fill" }
    public var loginURL: URL { URL(string: "https://console.volcengine.com/finance/account-overview/")! }

    private let inner = HTTPAdapter(
        id: "volcano",
        displayName: "火山引擎",
        iconSystemName: "flame.fill",
        loginURL: URL(string: "https://console.volcengine.com/finance/account-overview/")!,
        method: "GET",
        url: URL(string: "https://console.volcengine.com/api/top/bill_volcano_engine/cn-north-1/2020-01-01/GetBalanceFromTradeBalance")!,
        headers: ["Accept": "application/json"],
        pageFallbackDecoder: { page in
            guard let balance = TextAmountParser.cnyAmount(
                in: page.text,
                near: ["可用余额", "现金余额", "账户余额", "余额"]
            ), balance > 0 else {
                // balance ≤ 0 → return nil so the caller won't show ¥0.00
                // (the error snapshot from the failed decoder/HTTP status will be shown instead)
                return nil
            }
            let quota = Quota(id: "balance", label: "余额", used: 0, total: balance, unit: "¥")
            return Snapshot(providerId: "volcano", quotas: [quota], status: .ok)
        },
        decoder: { data in
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return Snapshot(providerId: "volcano", quotas: [], status: .error("解析失败: \(DiagnosticPreview.from(data))"))
            }
            // Check for API-level error in ResponseMetadata
            if let meta = obj["ResponseMetadata"] as? [String: Any],
               let err = meta["Error"] as? [String: Any],
               let code = err["Code"] as? String, !code.isEmpty {
                let msg = err["Message"] as? String ?? code
                return Snapshot(providerId: "volcano", quotas: [], status: .error("API错误: \(msg)"))
            }
            guard let result = obj["Result"] as? [String: Any],
                  let acct = result["Acct"] as? [String: Any],
                  let balanceStr = acct["AvailableBalance"] as? String,
                  let balance = Double(balanceStr) else {
                return Snapshot(providerId: "volcano", quotas: [], status: .error("解析失败: \(DiagnosticPreview.from(data))"))
            }
            let quota = Quota(id: "balance", label: "余额",
                              used: 0, total: balance, unit: "¥")
            return Snapshot(providerId: "volcano", quotas: [quota], status: .ok)
        }
    )

    public func fetch() async -> Snapshot { await inner.fetch() }
}
