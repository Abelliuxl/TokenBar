import Foundation

/// Official OpenCode Go usage endpoint, authenticated with a Go API key.
public enum OpenCodeGoAPI {
    private static let endpoint = URL(string: "https://opencode.ai/zen/go/v1/usage")!
    private static let providerId = "opencode-go"

    public static func fetch(apiKey: String) async -> Snapshot {
        var request = URLRequest(url: endpoint)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return failure("用量接口未返回 HTTP 响应")
            }
            switch http.statusCode {
            case 200..<300:
                return decode(data: data)
            case 401, 403:
                return failure("API Key 无效或账号没有 Go 订阅（HTTP \(http.statusCode)）")
            default:
                return failure("用量接口 HTTP \(http.statusCode): \(DiagnosticPreview.from(data))")
            }
        } catch {
            return failure("用量接口请求失败: \(error.localizedDescription)")
        }
    }

    static func decode(data: Data) -> Snapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = root["usage"] as? [String: [String: Any]] else {
            return failure("用量接口返回格式错误")
        }
        let windows: [(String, String)] = [
            ("rolling", "滚动用量"), ("weekly", "每周用量"), ("monthly", "每月用量")
        ]
        var quotas: [Quota] = []
        for (id, label) in windows {
            guard let entry = usage[id],
                  let percent = (entry["percent"] as? NSNumber)?.doubleValue,
                  percent.isFinite, (0...100).contains(percent) else {
                return failure("用量接口缺少有效的 \(label) 百分比")
            }
            guard let resetString = entry["resetsAt"] as? String,
                  let reset = resetDate(resetString) else {
                return failure("用量接口缺少有效的 \(label) 重置时间")
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            quotas.append(Quota(id: id, label: label, used: percent, total: 100, unit: "%",
                                resetsAt: reset, resetText: "重置 \(formatter.string(from: reset))"))
        }
        return Snapshot(providerId: providerId, quotas: quotas, status: .ok)
    }

    private static func resetDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func failure(_ message: String) -> Snapshot {
        Snapshot(providerId: providerId, quotas: [], status: .error(message))
    }
}
