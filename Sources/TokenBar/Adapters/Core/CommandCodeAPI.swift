import Foundation
import CoreFoundation

/// Read-only use of the same API key and billing endpoints as the official CLI.
public enum CommandCodeAPI {
    public static func loadKey(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let path = home.appendingPathComponent(".commandcode/auth.json")
        guard let data = try? Data(contentsOf: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = root["apiKey"] as? String else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func read(_ path: String, apiKey: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.commandcode.ai/alpha/" + path)!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("command-code", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "CommandCodeAPI", code: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }

    public static func fetch(apiKey: String) async -> Snapshot {
        do {
            // Resolve the CLI's organization before reading its billing scope.
            let identityData = try await read("whoami?limits=1", apiKey: apiKey)
            let identity = try JSONSerialization.jsonObject(with: identityData) as? [String: Any]
            let org = (identity?["org"] as? [String: Any])?["id"] as? String
            var query = URLComponents()
            if let org { query.queryItems = [URLQueryItem(name: "orgId", value: org)] }
            let suffix = query.percentEncodedQuery.map { "?" + $0 } ?? ""
            let credits = try await read("billing/credits" + suffix, apiKey: apiKey)
            // A subscription outage should not discard the two valid rolling windows.
            let subscription = try? await read("billing/subscriptions" + suffix, apiKey: apiKey)
            return decode(credits: credits, subscription: subscription)
        } catch {
            return Snapshot(providerId: "command-code", quotas: [], status: .error("Command Code API 请求失败（\((error as NSError).code)）"))
        }
    }

    public static func decode(credits: Data, subscription: Data?) -> Snapshot {
        let root = (try? JSONSerialization.jsonObject(with: credits)) as? [String: Any] ?? [:]
        let windows = root["windowLimits"] as? [String: Any] ?? [:]
        var quotas: [Quota] = []
        for (id, label) in [("fiveHour", "5 小时限额"), ("weekly", "每周限额")] {
            guard let window = windows[id] as? [String: Any],
                  let used = number(window["used"]), let cap = number(window["cap"]),
                  used >= 0, cap > 0, let reset = date(window["resetAt"]) else { continue }
            quotas.append(quota(id: id, label: label, percent: min(100, used / cap * 100), reset: reset))
        }
        let subRoot = subscription.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        let sub = subRoot?["data"] as? [String: Any]
        let ledger = root["credits"] as? [String: Any]
        // Only GOAT's confirmed allocation is used; unknown plans never fabricate a monthly cap.
        if sub?["planId"] as? String == "individual-goat", sub?["status"] as? String == "active",
           let remaining = number(ledger?["monthlyCredits"]), (0...70).contains(remaining),
           let reset = date(sub?["currentPeriodEnd"]) {
            quotas.append(quota(id: "monthly", label: "每月限额", percent: (70 - remaining) / 70 * 100, reset: reset))
        }
        let missing = ["fiveHour", "weekly", "monthly"].filter { id in !quotas.contains { $0.id == id } }
        let status: ProviderStatus = missing.isEmpty ? .ok : .stale("部分额度未更新：\(missing.joined(separator: ", "))")
        return Snapshot(providerId: "command-code", quotas: quotas, status: quotas.isEmpty ? .error("Command Code API 未返回有效额度") : status)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull), CFGetTypeID(value as CFTypeRef) != CFBooleanGetTypeID() else { return nil }
        let result = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        return result.flatMap { $0.isFinite ? $0 : nil }
    }

    private static func date(_ value: Any?) -> Date? {
        if let epoch = number(value), epoch > 0 {
            return Date(timeIntervalSince1970: epoch > 100_000_000_000 ? epoch / 1000 : epoch)
        }
        guard let text = value as? String else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: text) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: text)
    }

    private static func quota(id: String, label: String, percent: Double, reset: Date) -> Quota {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return Quota(id: id, label: label, used: percent, total: 100, unit: "%", resetsAt: reset,
                     resetText: "\(formatter.string(from: reset)) 重置")
    }
}
