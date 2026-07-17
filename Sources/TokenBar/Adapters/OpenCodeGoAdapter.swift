import Foundation
import WebKit

/// Adapter for opencode go.
///
/// opencode go's usage page is server-side rendered (SSR), so there is no
/// HTTP API returning structured quota data.  We use the WebViewAdapter
/// approach: load the workspace Go page in a WKWebView and scrape the DOM.
///
/// The quotas are displayed in cards with `data-slot` attributes:
/// ```html
/// <div data-slot="usage-item">
///   <span data-slot="usage-label">滚动用量</span>
///   <span data-slot="usage-value">2%</span>
///   <span data-slot="reset-time">重置于 36 分钟</span>
/// </div>
/// ```
///
/// Three quota types: 滚动用量 (rolling), 每周用量 (weekly), 每月用量 (monthly).
/// The displayed value is already the used percentage.
///
/// See `docs/research/opencode-go-research.md` for details.
public final class OpenCodeGoAdapter: WebViewAdapter {
    public init() {
        let js = """
        (function() {
          const items = document.querySelectorAll('[data-slot="usage-item"]');
          const result = {};
          const fallbackIds = ['rolling', 'weekly', 'monthly'];
          const idForLabel = (label, index) => {
            const value = (label || '').toLowerCase();
            if (value.includes('滚动') || value.includes('rolling')) return 'rolling';
            if (value.includes('每周') || value.includes('weekly')) return 'weekly';
            if (value.includes('每月') || value.includes('monthly')) return 'monthly';
            // The card order is stable. This handles a future locale without
            // making display text a data key.
            return fallbackIds[index] || null;
          };
          for (const [index, item] of Array.from(items).entries()) {
            const labelEl = item.querySelector('[data-slot="usage-label"]');
            const valueEl = item.querySelector('[data-slot="usage-value"]');
            const resetEl = item.querySelector('[data-slot="reset-time"]');
            if (!labelEl || !valueEl) continue;
            const label = labelEl.textContent.trim();
            const id = idForLabel(label, index);
            if (!id) continue;
            // Extract the number before the '%' sign
            const pctMatch = valueEl.textContent.trim().match(/^(\\d+(?:\\.\\d+)?)/);
            if (!pctMatch) continue;
            const usedPct = parseFloat(pctMatch[1]);
            const resetText = resetEl ? resetEl.textContent.trim() : '';
            result[id] = { used: usedPct, reset: resetText };
          }
          const text = document.body ? document.body.innerText.replace(/\\s+/g, ' ').slice(0, 180) : '';
          const fullText = document.body ? document.body.innerText.replace(/\\s+/g, ' ') : '';
          const fillFromText = (id, labels) => {
            if (result[id]) return;
            const label = labels.find((candidate) => fullText.toLowerCase().includes(candidate.toLowerCase()));
            if (!label) return;
            const idx = fullText.toLowerCase().indexOf(label.toLowerCase());
            if (idx < 0) return;
            const snippet = fullText.slice(idx, idx + 100);
            const match = snippet.match(/(\\d+(?:\\.\\d+)?)\\s*%/);
            if (!match) return;
            result[id] = { used: parseFloat(match[1]), reset: '' };
          };
          fillFromText('rolling', ['滚动用量', 'Rolling usage', 'Rolling']);
          fillFromText('weekly', ['每周用量', 'Weekly usage', 'Weekly']);
          fillFromText('monthly', ['每月用量', 'Monthly usage', 'Monthly']);
          return JSON.stringify({
            quotas: result,
            itemCount: items.length,
            href: location.href,
            title: document.title,
            text: text
          });
        })()
        """
        super.init(id: "opencode-go", displayName: "opencode go",
                   iconSystemName: "bolt.fill",
                   loginURL: URL(string: "https://opencode.ai/workspace/wrk_01KVB7CEDBFN8VF6FYA2DJ1GR3/go")!,
                   harvestScript: js,
                   brandIcon: .openCode)
    }

    public override func parse(harvest: Any?) -> Snapshot {
        guard let jsonStr = harvest as? String,
              let data = jsonStr.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["quotas"] as? [String: [String: Any]] else {
            return Snapshot(providerId: id, quotas: [], status: .error("页面脚本返回解析失败"))
        }

        let quotaMap: [(id: String, label: String)] = [
            ("rolling", "滚动用量"),
            ("weekly", "每周用量"),
            ("monthly", "每月用量"),
        ]

        var quotas: [Quota] = []
        for (qid, qlabel) in quotaMap {
            if let entry = raw[qid],
               let used = Self.doubleValue(entry["used"]) {
                quotas.append(Quota(id: qid, label: qlabel,
                                    used: used, total: 100, unit: "%",
                                    resetText: entry["reset"] as? String))
            }
        }

        guard !quotas.isEmpty else {
            if Self.looksLikeLoginPage(root) {
                return Snapshot(providerId: id, quotas: [], status: .needsRelogin)
            }
            return Snapshot(providerId: id, quotas: [], status: .error("未找到用量元素: \(Self.pageInfo(root))"))
        }
        return Snapshot(providerId: id, quotas: quotas, status: .ok)
    }

    private static func looksLikeLoginPage(_ root: [String: Any]) -> Bool {
        let href = (root["href"] as? String ?? "").lowercased()
        return href.contains("auth.opencode.ai") || href.contains("/auth")
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func pageInfo(_ root: [String: Any]) -> String {
        let href = root["href"] as? String ?? "<unknown>"
        let title = root["title"] as? String ?? ""
        let text = root["text"] as? String ?? ""
        return "\(title) \(href) \(text)"
    }
}
