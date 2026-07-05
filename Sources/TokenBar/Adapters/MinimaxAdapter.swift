import Foundation
import WebKit

/// Adapter for MiniMax.
///
/// MiniMax's quota page is server-side rendered (Next.js SSR), so there is no
/// client-side API endpoint that returns the quota data.  We use the
/// WebViewAdapter approach: load the page in a WKWebView and scrape the DOM
/// for quota information.
///
/// The quotas are displayed in cards with aria-labels like:
///   `aria-label="5h 限额 0%"`  and  `aria-label="周限额 35%"`
/// The percentage is already the used percentage.
///
/// See `docs/research/minimax-research.md` for details.
public final class MinimaxAdapter: WebViewAdapter {
    public init() {
        let js = """
        (function() {
          const resetFrom = (el) => {
            const text = (el && el.innerText ? el.innerText : '').replace(/\\s+/g, ' ').trim();
            const match = text.match(/((?:\\d+\\s*天\\s*)?(?:\\d+\\s*小时\\s*)?(?:\\d+\\s*分钟\\s*)?后重置)/);
            return match ? match[1].replace(/\\s+/g, ' ').trim() : '';
          };
          const find = (keyword) => {
            const el = document.querySelector('[aria-label*="' + keyword + '"]');
            if (!el) return null;
            const label = el.getAttribute('aria-label') || '';
            // aria-label format: "5h 限额 0%" or "周限额 35%"; value is used percent.
            const match = label.match(/[\\d.]+(?=%$)/);
            const pct = match ? parseFloat(match[0]) : null;
            return { percent: pct, reset: resetFrom(el) };
          };
          const text = document.body ? document.body.innerText.replace(/\\s+/g, ' ').slice(0, 180) : '';
          const fullText = document.body ? document.body.innerText.replace(/\\s+/g, ' ') : '';
          const findInText = (keyword) => {
            const idx = fullText.indexOf(keyword);
            if (idx < 0) return null;
            const snippet = fullText.slice(idx, idx + 100);
            const match = snippet.match(/(\\d+(?:\\.\\d+)?)\\s*%/);
            const reset = snippet.match(/((?:\\d+\\s*天\\s*)?(?:\\d+\\s*小时\\s*)?(?:\\d+\\s*分钟\\s*)?后重置)/);
            return match ? { percent: parseFloat(match[1]), reset: reset ? reset[1].replace(/\\s+/g, ' ').trim() : '' } : null;
          };
          const fiveH = find('5h') ?? findInText('5h 限额') ?? findInText('5h');
          const weekly = find('周限额') ?? findInText('周限额');
          return JSON.stringify({
            fiveHour: fiveH,
            weekly: weekly,
            ariaCount: document.querySelectorAll('[aria-label]').length,
            href: location.href,
            title: document.title,
            text: text
          });
        })()
        """
        super.init(id: "minimax",
                   displayName: "MiniMax",
                   iconSystemName: "sparkles",
                   loginURL: URL(string: "https://platform.minimaxi.com/console/usage")!,
                   harvestScript: js)
    }

    public override func parse(harvest: Any?) -> Snapshot {
        guard let jsonStr = harvest as? String,
              let data = jsonStr.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Snapshot(providerId: id, quotas: [], status: .error("页面脚本返回解析失败"))
        }

        var quotas: [Quota] = []

        // MiniMax aria-label percent is used percent, e.g. "5h 限额 0%" means 0% used.
        if let quota = raw["fiveHour"] as? [String: Any],
           let pct = quota["percent"] as? Double {
            quotas.append(Quota(id: "5h", label: "5h 限额",
                                used: pct, total: 100, unit: "%",
                                resetText: quota["reset"] as? String))
        }

        if let quota = raw["weekly"] as? [String: Any],
           let pct = quota["percent"] as? Double {
            quotas.append(Quota(id: "weekly", label: "周限额",
                                used: pct, total: 100, unit: "%",
                                resetText: quota["reset"] as? String))
        }

        guard !quotas.isEmpty else {
            if Self.looksLikeLoginPage(raw) {
                return Snapshot(providerId: id, quotas: [], status: .needsRelogin)
            }
            return Snapshot(providerId: id, quotas: [], status: .error("未找到用量元素: \(Self.pageInfo(raw))"))
        }
        return Snapshot(providerId: id, quotas: quotas, status: .ok)
    }

    private static func looksLikeLoginPage(_ root: [String: Any]) -> Bool {
        let href = (root["href"] as? String ?? "").lowercased()
        return href.contains("login") || href.contains("account.minimaxi.com")
    }

    private static func pageInfo(_ root: [String: Any]) -> String {
        let href = root["href"] as? String ?? "<unknown>"
        let title = root["title"] as? String ?? ""
        let text = root["text"] as? String ?? ""
        return "\(title) \(href) \(text)"
    }
}
