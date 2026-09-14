import Foundation

/// ChatGPT plan usage, as shown on Codex's web analytics page
/// `https://chatgpt.com/codex/cloud/settings/analytics#usage`.
///
/// TokenBar used to read the `token_count` rate-limit events Codex CLI appended
/// to `~/.codex/sessions/**/*.jsonl`. Codex stopped writing them, so the adapter
/// now calls the backend that analytics page reads instead.
///
/// ## Endpoint (verified 2026-09-14)
/// ```
/// GET https://chatgpt.com/backend-api/wham/usage
/// Authorization: Bearer <ChatGPT access token>
/// ```
///
/// Response shape, trimmed to the fields TokenBar uses:
/// ```json
/// {
///   "plan_type": "plus",
///   "rate_limit": {
///     "limit_reached": false,
///     "primary_window":   { "used_percent":  0, "limit_window_seconds":  18000, "reset_at": 1789392717 },
///     "secondary_window": { "used_percent": 16, "limit_window_seconds": 604800, "reset_at": 1789959481 }
///   }
/// }
/// ```
///
/// `primary_window` is the 5-hour budget and `secondary_window` the weekly one.
/// A missing or expired credential answers `401 {"detail":"Unauthorized"}`.
public enum CodexUsageAPI {
    public static let providerId = "codex"
    public static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    public static func fetch(accessToken: String, accountId: String?) async -> Snapshot {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The token alone identifies the ChatGPT account. The header only pins
        // down which workspace account to report, so it stays optional.
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "chatgpt-account-id")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return Snapshot(providerId: providerId, quotas: [], status: .error("Codex 用量接口未返回 HTTP 响应"))
            }
            switch http.statusCode {
            case 200..<300:
                return snapshot(from: data)
            case 401, 403:
                return Snapshot(providerId: providerId, quotas: [], status: .needsRelogin)
            default:
                return Snapshot(providerId: providerId, quotas: [], status: .error(
                    "Codex 用量接口 HTTP \(http.statusCode): \(DiagnosticPreview.from(data))"
                ))
            }
        } catch {
            return Snapshot(providerId: providerId, quotas: [], status: .error(
                "Codex 用量接口请求失败: \(error.localizedDescription)"
            ))
        }
    }

    /// Turns a `wham/usage` body into the two percentage quotas the popover shows.
    public static func snapshot(from data: Data) -> Snapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Snapshot(providerId: providerId, quotas: [], status: .error(
                "Codex 用量解析失败: \(DiagnosticPreview.from(data))"
            ))
        }
        guard let rateLimit = root["rate_limit"] as? [String: Any] else {
            return Snapshot(providerId: providerId, quotas: [], status: .error(
                "Codex 用量接口未返回额度: \(DiagnosticPreview.from(data))"
            ))
        }

        var quotas: [Quota] = []
        for window in [("primary", "primary_window"), ("secondary", "secondary_window")] {
            guard let raw = rateLimit[window.1] as? [String: Any],
                  let used = number(raw["used_percent"]),
                  used.isFinite else {
                continue
            }
            let resetsAt = number(raw["reset_at"]).map { Date(timeIntervalSince1970: $0) }
            quotas.append(Quota(
                id: window.0,
                label: windowLabel(seconds: number(raw["limit_window_seconds"])),
                used: used,
                total: 100,
                unit: "%",
                resetsAt: resetsAt,
                resetText: resetsAt.map { "重置 \(timeFormatter.string(from: $0))" }
            ))
        }

        guard !quotas.isEmpty else {
            return Snapshot(providerId: providerId, quotas: [], status: .error(
                "Codex 用量接口未返回有效额度: \(DiagnosticPreview.from(data))"
            ))
        }
        return Snapshot(providerId: providerId, quotas: quotas, status: .ok)
    }

    /// `18000` → `5小时`, `604800` → `7天`.
    static func windowLabel(seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "额度" }
        let minutes = Int(seconds / 60)
        if minutes >= 60 * 24 {
            return "\(minutes / (60 * 24))天"
        }
        if minutes >= 60 {
            return "\(minutes / 60)小时"
        }
        return "\(minutes)分"
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

/// The ChatGPT login Codex CLI keeps on disk.
public struct CodexCLICredentials: Sendable, Equatable {
    public let accessToken: String
    public let accountId: String?

    public init(accessToken: String, accountId: String?) {
        self.accessToken = accessToken
        self.accountId = accountId
    }
}

public enum CodexAuthFile {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)
    }

    /// Reads the tokens Codex CLI stores for its ChatGPT login.
    ///
    /// Returns nil when Codex is not logged in, or when it was logged in with
    /// `codex login --api-key` (that stores an API key, which cannot read plan
    /// usage). TokenBar only ever reads this file — refreshing and writing it
    /// back stays Codex CLI's job, so rotating refresh tokens are never
    /// invalidated behind its back.
    public static func load(from url: URL = CodexAuthFile.defaultURL) -> CodexCLICredentials? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              !accessToken.isEmpty else {
            return nil
        }
        let accountId = tokens["account_id"] as? String
        return CodexCLICredentials(
            accessToken: accessToken,
            accountId: (accountId?.isEmpty == false) ? accountId : nil
        )
    }
}
