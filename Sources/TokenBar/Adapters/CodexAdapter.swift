import Foundation

/// Adapter for local Codex usage.
///
/// This does not start a Codex session. It reads recent local Codex session
/// JSONL files and extracts the latest `token_count` event, which includes
/// rate-limit percentages emitted by Codex itself.
public struct CodexAdapter: ProviderAdapter {
    public let id = "codex"
    public var displayName: String { "Codex" }
    public var iconSystemName: String { "terminal.fill" }
    public var loginURL: URL { URL(string: "https://chatgpt.com/codex")! }

    public init() {}

    public func fetch() async -> Snapshot {
        let sessionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)

        guard FileManager.default.fileExists(atPath: sessionsDir.path) else {
            return Snapshot(providerId: id, quotas: [], status: .error("未找到 Codex 会话目录"))
        }

        guard let event = Self.latestTokenCountEvent(in: sessionsDir) else {
            return Snapshot(providerId: id, quotas: [], status: .error("未找到 Codex 用量记录；先在 Codex 中运行 /status"))
        }

        var quotas: [Quota] = []
        if let primary = event.primary {
            quotas.append(Self.quota(id: "primary", label: Self.windowLabel(primary.windowMinutes), limit: primary))
        }
        if let secondary = event.secondary {
            quotas.append(Self.quota(id: "secondary", label: Self.windowLabel(secondary.windowMinutes), limit: secondary))
        }

        if quotas.isEmpty {
            return Snapshot(providerId: id, quotas: [], status: .error("Codex 用量记录缺少 rate limit 字段"))
        }
        return Snapshot(providerId: id, quotas: quotas, status: .ok)
    }

    private static func latestTokenCountEvent(in root: URL) -> TokenCountEvent? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var files: [(url: URL, modifiedAt: Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            files.append((url, values?.contentModificationDate ?? .distantPast))
        }

        for file in files.sorted(by: { $0.modifiedAt > $1.modifiedAt }).prefix(40) {
            if let event = latestTokenCountEvent(inFile: file.url) {
                return event
            }
        }
        return nil
    }

    private static func latestTokenCountEvent(inFile url: URL) -> TokenCountEvent? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let maxBytes: UInt64 = 1_048_576
        let start = size > maxBytes ? size - maxBytes : 0
        try? handle.seek(toOffset: start)
        let data = handle.readDataToEndOfFile()
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        if start > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard line.contains(#""token_count""#),
                  let data = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let limits = payload["rate_limits"] as? [String: Any] else {
                continue
            }
            return TokenCountEvent(
                primary: RateLimit(limits["primary"] as? [String: Any]),
                secondary: RateLimit(limits["secondary"] as? [String: Any])
            )
        }
        return nil
    }

    private static func quota(id: String, label: String, limit: RateLimit) -> Quota {
        let resetText: String?
        if let resetsAt = limit.resetsAt {
            resetText = "重置 \(Self.timeFormatter.string(from: resetsAt))"
        } else {
            resetText = nil
        }
        return Quota(
            id: id,
            label: label,
            used: limit.usedPercent,
            total: 100,
            unit: "%",
            resetsAt: limit.resetsAt,
            resetText: resetText
        )
    }

    private static func windowLabel(_ minutes: Int?) -> String {
        guard let minutes else { return "额度" }
        if minutes >= 60 * 24 {
            return "\(minutes / (60 * 24))天"
        }
        if minutes >= 60 {
            return "\(minutes / 60)小时"
        }
        return "\(minutes)分"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

private struct TokenCountEvent {
    let primary: RateLimit?
    let secondary: RateLimit?
}

private struct RateLimit {
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?

    init?(_ obj: [String: Any]?) {
        guard let obj,
              let usedPercent = obj["used_percent"] as? Double ?? (obj["used_percent"] as? NSNumber)?.doubleValue else {
            return nil
        }
        self.usedPercent = usedPercent
        self.windowMinutes = obj["window_minutes"] as? Int ?? (obj["window_minutes"] as? NSNumber)?.intValue
        if let seconds = obj["resets_at"] as? Double ?? (obj["resets_at"] as? NSNumber)?.doubleValue {
            self.resetsAt = Date(timeIntervalSince1970: seconds)
        } else {
            self.resetsAt = nil
        }
    }
}
