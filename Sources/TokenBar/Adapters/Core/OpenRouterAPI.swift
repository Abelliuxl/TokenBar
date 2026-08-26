import Foundation

/// Official OpenRouter Credits API.
///
/// Endpoint: GET https://openrouter.ai/api/v1/credits
/// Authentication: Authorization: Bearer <API key>
/// The remaining amount is total_credits - total_usage, in USD credits.
public enum OpenRouterAPI {
    private static let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!

    public static func fetchBalance(apiKey: String) async -> Snapshot {
        var request = URLRequest(url: creditsURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return Snapshot(providerId: "openrouter", quotas: [], status: .error("Credits API 未返回 HTTP 响应"))
            }
            guard (200..<300).contains(http.statusCode) else {
                let reason = http.statusCode == 401 || http.statusCode == 403
                    ? "API Key 无效或无权限"
                    : DiagnosticPreview.from(data)
                return Snapshot(providerId: "openrouter", quotas: [], status: .error("Credits API HTTP \(http.statusCode): \(reason)"))
            }
            return decode(data: data)
        } catch {
            return Snapshot(providerId: "openrouter", quotas: [], status: .error("Credits API 请求失败: \(error.localizedDescription)"))
        }
    }

    static func decode(data: Data) -> Snapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let totalCredits = number(payload["total_credits"]),
              let totalUsage = number(payload["total_usage"]),
              totalCredits.isFinite,
              totalUsage.isFinite,
              totalCredits >= 0,
              totalUsage >= 0 else {
            return Snapshot(providerId: "openrouter", quotas: [], status: .error("Credits API 解析失败: \(DiagnosticPreview.from(data))"))
        }

        let remaining = max(0, totalCredits - totalUsage)
        let quota = Quota(id: "credits", label: "Credits", used: 0, total: remaining, unit: "$")
        return Snapshot(providerId: "openrouter", quotas: [quota], status: .ok)
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
