import Foundation
import WebKit

/// Adapter for MiniMax.
///
/// MiniMax's quota page is server-side rendered (Next.js SSR), so there is no
/// client-side API endpoint that returns the quota data. We load the page in a
/// WKWebView and read the actual quota cards.
///
/// MiniMax has changed the surrounding copy a few times. A percentage may now
/// be explicitly described as "可用" or "剩余", so the scraper records that
/// meaning instead of blindly treating every percentage as used quota.
public final class MinimaxAdapter: WebViewAdapter {
    public init() {
        let js = """
        (function() {
          const compact = (value) => (value || '').replace(/\\s+/g, ' ').trim();
          const elementText = (el) => compact((el && el.innerText ? el.innerText : '') + ' ' + (el && el.textContent ? el.textContent : ''));
          const resetFrom = (el) => {
            const text = elementText(el);
            const match = text.match(/((?:\\d+\\s*天\\s*)?(?:\\d+\\s*小时\\s*)?(?:\\d+\\s*分钟\\s*)?后重置)/);
            if (match) return match[1].replace(/\\s+/g, ' ').trim();
            const english = text.match(/(reset(?:s)?\\s+(?:in\\s+)?(?:\\d+\\s*(?:days?|hours?|minutes?)\\s*)+)/i);
            return english ? english[1].replace(/\\s+/g, ' ').trim() : '';
          };
          const rowTextFor = (text, exactLabel) => {
            const start = text.indexOf(exactLabel);
            if (start < 0) return '';
            let row = text.slice(start);
            const nextLabel = exactLabel === '5h 限额' ? '周限额' : '';
            const end = nextLabel ? row.indexOf(nextLabel) : -1;
            if (end >= 0) row = row.slice(0, end);
            return row;
          };
          const explicitUsageFor = (text, exactLabel) => {
            const row = rowTextFor(text, exactLabel);
            if (!row) return null;
            // The new card contains both “总额度 100%” and “已用 10%”.
            // Only the latter is usage; the total must never be reported as it.
            const used = row.match(/已(?:用|使用)(?:额度)?\\s*[:：]?\\s*(\\d+(?:\\.\\d+)?)\\s*%/);
            if (used) return { percent: parseFloat(used[1]), semantic: 'used', row: row };
            const remaining = row.match(/(?:可用|剩余)(?:额度)?\\s*[:：]?\\s*(\\d+(?:\\.\\d+)?)\\s*%/);
            if (remaining) return { percent: parseFloat(remaining[1]), semantic: 'remaining', row: row };
            return null;
          };
          const barePercentageFor = (text) => {
            const match = text.match(/(\\d+(?:\\.\\d+)?)\\s*%\\s*$/) || text.match(/(\\d+(?:\\.\\d+)?)\\s*%/);
            return match ? parseFloat(match[1]) : null;
          };
          const findCard = (labelPattern, exactLabel) => {
            const ariaCandidate = Array.from(document.querySelectorAll('[aria-label]')).find((el) =>
              labelPattern.test(el.getAttribute('aria-label') || '')
            );
            if (ariaCandidate) {
              const ariaLabel = ariaCandidate.getAttribute('aria-label') || '';
              // Current MiniMax markup: "5h 限额 16% / 100%". The value
              // before the slash is the progress/used amount; the last value
              // is only the total and must not be reported as usage.
              const ratio = ariaLabel.match(/(\\d+(?:\\.\\d+)?)\\s*%\\s*\\/\\s*(\\d+(?:\\.\\d+)?)\\s*%/);
              if (ratio) {
                return { percent: parseFloat(ratio[1]), semantic: 'used', reset: resetFrom(ariaCandidate), source: 'aria-ratio' };
              }
            }

            const labelNode = Array.from(document.querySelectorAll('body *')).find((el) => elementText(el) === exactLabel);
            // Find the smallest surrounding row that states an explicit usage
            // value. This is deliberately attempted before aria-label, because
            // MiniMax now puts the total (100%) in that aria-label.
            for (let node = labelNode, depth = 0; node && depth < 7; depth += 1, node = node.parentElement) {
              const text = elementText(node);
              const usage = explicitUsageFor(text, exactLabel);
              if (usage) {
                return { percent: usage.percent, semantic: usage.semantic, reset: resetFrom({ innerText: usage.row }), source: 'explicit-row' };
              }
            }

            // The percentage labels on the right side of the current page are
            // siblings of the element carrying aria-label. They are nevertheless
            // present in body text, where the two quota rows have stable labels.
            // Scope the search to one row and require an explicit "已用/可用/剩余"
            // marker, so this cannot mistake "总额度 100%" for usage.
            const pageText = elementText(document.body);
            const pageUsage = explicitUsageFor(pageText, exactLabel);
            if (pageUsage) {
              return { percent: pageUsage.percent, semantic: pageUsage.semantic, reset: resetFrom({ innerText: pageUsage.row }), source: 'explicit-page-row' };
            }

            if (ariaCandidate) {
              for (let node = ariaCandidate, depth = 0; node && depth < 7; depth += 1, node = node.parentElement) {
                const text = elementText(node);
                const usage = explicitUsageFor(text, exactLabel);
                if (usage) {
                  return { percent: usage.percent, semantic: usage.semantic, reset: resetFrom({ innerText: usage.row }), source: 'explicit-aria-row' };
                }
              }
              // Old pages contain only a bare progress percentage in aria-label.
              const ariaLabel = ariaCandidate.getAttribute('aria-label') || '';
              const text = compact(ariaLabel + ' ' + elementText(ariaCandidate));
              const percent = barePercentageFor(text);
              if (percent !== null) {
                return { percent: percent, semantic: 'used', reset: resetFrom(ariaCandidate), source: 'legacy-aria' };
              }
            }

            return null;
          };
          // Current markup exposes a language-neutral `used% / total%` ratio
          // in aria-label. Match both Chinese and English quota names so that
          // ratio remains the primary source after a locale switch.
          const fiveH = findCard(/(?:5\\s*h|5-hour|5\\s*hours?)(?:\\s*(?:限额|limit))?/i, '5h 限额');
          const weekly = findCard(/(?:周\\s*限额|weekly?\\s*(?:limit|usage)?)/i, '周限额');
          const text = document.body ? elementText(document.body).slice(0, 180) : '';
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
                   harvestScript: js,
                   brandIcon: .miniMax)
    }

    public override func parse(harvest: Any?) -> Snapshot {
        guard let jsonStr = harvest as? String,
              let data = jsonStr.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Snapshot(providerId: id, quotas: [], status: .error("页面脚本返回解析失败"))
        }

        var quotas: [Quota] = []
        if let quota = miniMaxQuota(raw["fiveHour"], id: "5h", label: "5h 限额") {
            quotas.append(quota)
        }
        if let quota = miniMaxQuota(raw["weekly"], id: "weekly", label: "周限额") {
            quotas.append(quota)
        }

        guard !quotas.isEmpty else {
            if Self.looksLikeLoginPage(raw) {
                return Snapshot(providerId: id, quotas: [], status: .needsRelogin)
            }
            return Snapshot(providerId: id, quotas: [], status: .error("未找到用量元素: \(Self.pageInfo(raw))"))
        }
        return Snapshot(providerId: id, quotas: quotas, status: .ok)
    }

    private func miniMaxQuota(_ value: Any?, id: String, label: String) -> Quota? {
        guard let rawQuota = value as? [String: Any],
              let percent = rawQuota["percent"] as? Double,
              percent.isFinite,
              (0...100).contains(percent) else {
            return nil
        }
        let semantic = rawQuota["semantic"] as? String
        let used = semantic == "remaining" ? 100 - percent : percent
        return Quota(id: id, label: label, used: used, total: 100, unit: "%",
                     resetText: rawQuota["reset"] as? String)
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
