import Foundation

/// Command Code's account credits endpoint used by the official CLI.
///
/// Endpoint: GET https://api.commandcode.ai/alpha/billing/credits
/// Authentication: Authorization: Bearer <Command Code API key>
///
/// This is an undocumented `/alpha` endpoint rather than part of the
/// published Provider API. Keep the decoder tolerant because the endpoint is
/// not a versioned public contract.
public enum CommandCodeAPI {
    private static let creditsURL = URL(string: "https://api.commandcode.ai/alpha/billing/credits")!

    public static func fetchBalance(apiKey: String) async -> Snapshot {
        var request = URLRequest(url: creditsURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return Snapshot(providerId: "command-code", quotas: [], status: .error("余额 API 未返回 HTTP 响应"))
            }
            guard (200..<300).contains(http.statusCode) else {
                let reason = http.statusCode == 401 || http.statusCode == 403
                    ? "API Key 无效或无权限"
                    : DiagnosticPreview.from(data)
                return Snapshot(providerId: "command-code", quotas: [], status: .error("余额 API HTTP \(http.statusCode): \(reason)"))
            }
            return decode(data: data)
        } catch {
            return Snapshot(providerId: "command-code", quotas: [], status: .error("余额 API 请求失败: \(error.localizedDescription)"))
        }
    }

    static func decode(data: Data) -> Snapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let credits = root["credits"] as? [String: Any] else {
            return Snapshot(providerId: "command-code", quotas: [], status: .error("余额 API 解析失败: \(DiagnosticPreview.from(data))"))
        }

        var quotas: [Quota] = []
        let creditFields: [(key: String, id: String, label: String)] = [
            ("monthlyCredits", "credits-monthly", "月度余额"),
            ("purchasedCredits", "credits-purchased", "购买余额"),
            ("freeCredits", "credits-free", "免费余额"),
        ]
        for field in creditFields {
            guard let value = nonNegativeNumber(credits[field.key]) else { continue }
            quotas.append(Quota(id: field.id, label: field.label, used: 0, total: value, unit: "$"))
        }

        if let windowLimits = root["windowLimits"] as? [String: Any] {
            quotas.append(contentsOf: quotaForWindow(
                windowLimits["fiveHour"],
                id: "fiveHour",
                label: "5 小时限额"
            ))
            quotas.append(contentsOf: quotaForWindow(
                windowLimits["weekly"],
                id: "weekly",
                label: "每周限额"
            ))
        }

        guard !quotas.isEmpty else {
            return Snapshot(providerId: "command-code", quotas: [], status: .error("余额 API 未返回有效额度"))
        }
        return Snapshot(providerId: "command-code", quotas: quotas, status: .ok)
    }

    private static func quotaForWindow(_ value: Any?, id: String, label: String) -> [Quota] {
        guard let raw = value as? [String: Any],
              let used = nonNegativeNumber(raw["used"]),
              let cap = nonNegativeNumber(raw["cap"]),
              cap > 0 else {
            return []
        }

        let resetDate = date(fromMilliseconds: raw["resetAt"])
        return [Quota(
            id: id,
            label: label,
            used: min(used, cap),
            total: cap,
            unit: "%",
            resetsAt: resetDate,
            resetText: resetText(for: resetDate)
        )]
    }

    private static func nonNegativeNumber(_ value: Any?) -> Double? {
        let number: Double?
        if let value = value as? NSNumber {
            number = value.doubleValue
        } else if let value = value as? String {
            number = Double(value)
        } else {
            number = nil
        }
        guard let number, number.isFinite, number >= 0 else { return nil }
        return number
    }

    private static func date(fromMilliseconds value: Any?) -> Date? {
        guard let milliseconds = nonNegativeNumber(value) else { return nil }
        let seconds = milliseconds > 10_000_000_000 ? milliseconds / 1_000 : milliseconds
        return Date(timeIntervalSince1970: seconds)
    }

    private static func resetText(for date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "MM-dd HH:mm"
        return "重置 \(formatter.string(from: date))"
    }
}
