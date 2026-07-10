import Foundation
import WebKit

/// Adapter for OpenRouter credits.
///
/// Official API endpoint:
/// `GET https://openrouter.ai/api/v1/credits`
///
/// The public API documents this as Bearer-token authenticated. In TokenBar we
/// avoid storing API keys, so this adapter runs inside the logged-in WebKit
/// session and falls back to the visible credits page text.
public final class OpenRouterAdapter: WebViewAdapter {
    public init() {
        let js = """
        (function() {
          const api = { status: 0, body: "" };
          try {
            const xhr = new XMLHttpRequest();
            xhr.open("GET", "https://openrouter.ai/api/v1/credits", false);
            xhr.withCredentials = true;
            xhr.setRequestHeader("Accept", "application/json");
            xhr.send(null);
            api.status = xhr.status;
            api.body = xhr.responseText || "";
          } catch (error) {
            api.error = String(error && error.message ? error.message : error);
          }

          const text = document.body ? document.body.innerText.replace(/\\s+/g, " ") : "";
          function parseNumber(value) {
            const match = String(value || "").match(/([0-9][0-9,]*(?:\\.[0-9]+)?)/);
            return match ? Number(match[1].replace(/,/g, "")) : null;
          }

          let remainingCredits = null;
          const creditLabels = ["remaining credits", "available credits", "current balance", "剩余积分", "可用积分", "余额"];
          const creditCard = Array.from(document.querySelectorAll("[aria-label]"))
            .find((element) => creditLabels.some((label) => (element.getAttribute("aria-label") || "").toLowerCase().includes(label.toLowerCase())));
          if (creditCard) {
            remainingCredits = parseNumber(creditCard.getAttribute("aria-label"));
          }
          if (remainingCredits == null) {
            for (const script of Array.from(document.scripts)) {
              const match = (script.textContent || "").match(/Remaining credits:\\s*([0-9][0-9,]*(?:\\.[0-9]+)?)/i);
              if (match) {
                remainingCredits = Number(match[1].replace(/,/g, ""));
                break;
              }
            }
          }

          return JSON.stringify({
            api: api,
            remainingCredits: remainingCredits,
            href: location.href,
            title: document.title,
            text: text.slice(0, 1200)
          });
        })()
        """
        super.init(id: "openrouter",
                   displayName: "OpenRouter",
                   iconSystemName: "arrow.triangle.branch",
                   loginURL: URL(string: "https://openrouter.ai/settings/credits")!,
                   harvestScript: js)
    }

    public override func parse(harvest: Any?) -> Snapshot {
        guard let jsonStr = harvest as? String,
              let data = jsonStr.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Snapshot(providerId: id, quotas: [], status: .error("页面脚本返回解析失败"))
        }

        if Self.looksLikeLoginPage(raw) {
            return Snapshot(providerId: id, quotas: [], status: .needsRelogin)
        }

        if let balance = Self.balanceFromAPI(raw) ?? Self.balanceFromPage(raw) {
            let quota = Quota(id: "credits", label: "Credits", used: 0, total: balance, unit: "$")
            return Snapshot(providerId: id, quotas: [quota], status: .ok)
        }

        return Snapshot(providerId: id, quotas: [], status: .error("未找到 credits 余额: \(Self.pageInfo(raw))"))
    }

    private static func balanceFromAPI(_ raw: [String: Any]) -> Double? {
        guard let api = raw["api"] as? [String: Any],
              let status = api["status"] as? Int,
              (200..<300).contains(status),
              let body = api["body"] as? String,
              let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = obj["data"] as? [String: Any],
              let totalCredits = number(payload["total_credits"]),
              let totalUsage = number(payload["total_usage"]) else {
            return nil
        }
        return totalCredits - totalUsage
    }

    private static func balanceFromPage(_ raw: [String: Any]) -> Double? {
        if let remaining = number(raw["remainingCredits"]) {
            return remaining
        }
        let text = raw["text"] as? String ?? ""
        return strictUSD(in: text, near: [
            "Remaining credits", "Current balance", "Credit balance", "Available credits",
            "剩余积分", "可用积分", "积分余额", "余额"
        ])
    }

    private static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func strictUSD(in text: String, near labels: [String]) -> Double? {
        for label in labels {
            guard let range = text.range(of: label, options: [.caseInsensitive, .diacriticInsensitive]) else {
                continue
            }
            let lower = text.index(range.lowerBound, offsetBy: -min(40, text.distance(from: text.startIndex, to: range.lowerBound)))
            let distance = text.distance(from: range.upperBound, to: text.endIndex)
            let upper = text.index(range.upperBound, offsetBy: min(220, distance))
            if let amount = strictUSD(in: String(text[lower..<upper])) {
                return amount
            }
        }
        return nil
    }

    private static func strictUSD(in text: String) -> Double? {
        let patterns = [
            #"\$\s*([0-9][0-9,]*(?:\.[0-9]+)?)"#,
            #"([0-9][0-9,]*(?:\.[0-9]+)?)\s*USD\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else {
                continue
            }
            let raw = text[range].replacingOccurrences(of: ",", with: "")
            if let amount = Double(raw) {
                return amount
            }
        }
        return nil
    }

    private static func looksLikeLoginPage(_ raw: [String: Any]) -> Bool {
        let href = (raw["href"] as? String ?? "").lowercased()
        let text = (raw["text"] as? String ?? "").lowercased()
        return href.contains("/sign-in") || text.contains("sign in to openrouter") || text.contains("登录")
    }

    private static func pageInfo(_ raw: [String: Any]) -> String {
        let href = raw["href"] as? String ?? "<unknown>"
        let title = raw["title"] as? String ?? ""
        let text = raw["text"] as? String ?? ""
        return "\(title) \(href) \(text)"
    }
}
