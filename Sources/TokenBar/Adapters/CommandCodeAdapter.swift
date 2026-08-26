import Foundation
import WebKit

/// Adapter for Command Code's account usage page.
///
/// The page exposes each quota as an accessible `progressbar`, including a
/// language-neutral `aria-valuenow` percentage and a human-readable reset
/// message. The data is read from the authenticated WebView session so no
/// Command Code credential is stored by TokenBar.
public final class CommandCodeAdapter: WebViewAdapter {
    public init() {
        let js = """
        (function() {
          const compact = (value) => (value || '').replace(/\\s+/g, ' ').trim();
          const definitions = [
            { id: 'fiveHour', labels: ['5-hour', '5 hour', '5h', '5 小时', '5小时'] },
            { id: 'weekly', labels: ['weekly', '每周'] },
            { id: 'monthly', labels: ['monthly', '每月'] }
          ];
          const fallbackIds = definitions.map((definition) => definition.id);
          const normalized = (value) => compact(value).toLowerCase();
          const idFor = (label, index) => {
            const value = normalized(label);
            const definition = definitions.find((candidate) =>
              candidate.labels.some((candidateLabel) => value.includes(candidateLabel.toLowerCase()))
            );
            return definition ? definition.id : (fallbackIds[index] || null);
          };
          const resetFor = (progress) => {
            const scope = progress.parentElement;
            const reset = scope ? scope.querySelector('p') : null;
            if (reset) return compact(reset.innerText || reset.textContent);
            const text = compact(scope ? scope.innerText : '');
            const match = text.match(/(resets?\\s+(?:in|on)\\s+.+)$/i);
            return match ? match[1] : '';
          };

          const progressBars = Array.from(document.querySelectorAll('[role="progressbar"]'))
            .filter((element) => {
              const label = normalized(element.getAttribute('aria-label') || '');
              return label.includes('limit') || label.includes('usage') ||
                     label.includes('额度') || label.includes('用量');
            });
          const limits = {};
          for (const [index, progress] of progressBars.entries()) {
            const label = compact(progress.getAttribute('aria-label') || '');
            const id = idFor(label, index);
            if (!id) continue;
            let used = Number(progress.getAttribute('aria-valuenow'));
            if (!Number.isFinite(used)) {
              const text = compact(progress.parentElement ? progress.parentElement.innerText : '');
              const match = text.match(/(\\d+(?:\\.\\d+)?)\\s*%/);
              if (match) used = Number(match[1]);
            }
            if (!Number.isFinite(used) || used < 0 || used > 100) continue;
            limits[id] = { used: used, reset: resetFor(progress) };
          }

          const text = document.body ? compact(document.body.innerText).slice(0, 600) : '';
          return JSON.stringify({
            limits: limits,
            progressCount: progressBars.length,
            href: location.href,
            title: document.title,
            text: text
          });
        })()
        """
        super.init(id: "command-code",
                   displayName: "command code",
                   iconSystemName: "command.square",
                   loginURL: URL(string: "https://commandcode.ai/Abelliuxl/settings/usage")!,
                   harvestScript: js,
                   brandIcon: .commandCode)
    }

    public override var maximumHarvestAttempts: Int { 3 }
    public override var harvestRetryDelay: TimeInterval { 1 }

    public override func shouldRetry(harvest: Any?) -> Bool {
        guard let json = harvest as? String,
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = root["limits"] as? [String: Any],
              limits.isEmpty else {
            return false
        }
        return !Self.looksLikeLoginPage(root)
    }

    public override func parse(harvest: Any?) -> Snapshot {
        guard let json = harvest as? String,
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawLimits = root["limits"] as? [String: [String: Any]] else {
            return Snapshot(providerId: id, quotas: [], status: .error("页面脚本返回解析失败"))
        }

        let quotaMap: [(id: String, label: String)] = [
            ("fiveHour", "5 小时限额"),
            ("weekly", "每周限额"),
            ("monthly", "每月限额")
        ]
        var quotas: [Quota] = []
        for (quotaID, label) in quotaMap {
            guard let entry = rawLimits[quotaID],
                  let used = Self.doubleValue(entry["used"]),
                  used.isFinite,
                  (0...100).contains(used) else {
                continue
            }
            quotas.append(Quota(id: quotaID, label: label, used: used, total: 100, unit: "%",
                                resetText: entry["reset"] as? String))
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
        if href.range(of: #"/(?:login|log-in|signin|sign-in|auth)(?:[/?#]|$)"#, options: .regularExpression) != nil {
            return true
        }
        let text = (root["text"] as? String ?? "").lowercased()
        return text.contains("log in") || text.contains("sign in") || text.contains("登录")
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
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
