import Foundation

/// Official DeepSeek API balance endpoint.
///
/// Endpoint: GET https://api.deepseek.com/user/balance
/// Authentication: Authorization: Bearer <API key>
public enum DeepSeekAPI {
    private static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!

    public static func fetchBalance(apiKey: String) async -> Snapshot {
        var request = URLRequest(url: balanceURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return Snapshot(providerId: "deepseek", quotas: [], status: .error("官方 API 未返回 HTTP 响应"))
            }
            guard (200..<300).contains(http.statusCode) else {
                let reason = http.statusCode == 401 || http.statusCode == 403
                    ? "API Key 无效或无权限"
                    : DiagnosticPreview.from(data)
                return Snapshot(providerId: "deepseek", quotas: [], status: .error("官方 API HTTP \(http.statusCode): \(reason)"))
            }
            return decode(data: data)
        } catch {
            return Snapshot(providerId: "deepseek", quotas: [], status: .error("官方 API 请求失败: \(error.localizedDescription)"))
        }
    }

    static func decode(data: Data) -> Snapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawInfos = root["balance_infos"] as? [[String: Any]] else {
            return Snapshot(providerId: "deepseek", quotas: [], status: .error("官方 API 解析失败: \(DiagnosticPreview.from(data))"))
        }

        let quotas = rawInfos.compactMap { raw -> Quota? in
            guard let currency = raw["currency"] as? String,
                  let total = number(raw["total_balance"]),
                  total.isFinite else {
                return nil
            }
            let normalizedCurrency = currency.uppercased()
            let unit: String
            switch normalizedCurrency {
            case "CNY": unit = "¥"
            case "USD": unit = "$"
            default: unit = normalizedCurrency
            }
            return Quota(
                id: "balance-\(normalizedCurrency.lowercased())",
                label: "余额 \(normalizedCurrency)",
                used: 0,
                total: total,
                unit: unit
            )
        }

        guard !quotas.isEmpty else {
            return Snapshot(providerId: "deepseek", quotas: [], status: .error("官方 API 未返回有效余额"))
        }
        return Snapshot(providerId: "deepseek", quotas: quotas, status: .ok)
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
