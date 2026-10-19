import Foundation
import WebKit

/// Adapter for opencode go.
///
/// Reads the current Console's accessible progress bars from the logged-in
/// WebKit session. An optional API-key mode uses the official Go usage API.
///
/// See `docs/research/opencode-go-research.md` for details.
public final class OpenCodeGoAdapter: WebViewAdapter, MultiModeProviderAdapter {
    public let defaultFetchModeId = "webSession"
    public let fetchModes = [
        ProviderFetchMode(id: "webSession", title: "网页登录"),
        ProviderFetchMode(id: "api", title: "官方 API", credentialFields: [
            ProviderCredentialField(id: "apiKey", title: "OpenCode Go API Key", placeholder: "sk-...", isSecret: true),
        ]),
    ]

    public init() {
        let js = """
        (function() {
          const compact = (value) => (value || '').replace(/\\s+/g, ' ').trim();
          const result = {};
          const idForLabel = (label) => {
            const value = compact(label).toLowerCase();
            if (value.includes('滚动') || value.includes('rolling') || value.includes('5-hour')) return 'rolling';
            if (value.includes('每周') || value.includes('weekly')) return 'weekly';
            if (value.includes('每月') || value.includes('monthly')) return 'monthly';
            return null;
          };
          // Legacy workspace page, retained for accounts still on the old Console.
          const items = document.querySelectorAll('[data-slot="usage-item"]');
          for (const item of items) {
            const labelEl = item.querySelector('[data-slot="usage-label"]');
            const valueEl = item.querySelector('[data-slot="usage-value"]');
            const resetEl = item.querySelector('[data-slot="reset-time"]');
            if (!labelEl || !valueEl) continue;
            const id = idForLabel(labelEl.textContent);
            if (!id) continue;
            const pctMatch = compact(valueEl.textContent).match(/^(\\d+(?:\\.\\d+)?)\\s*%/);
            if (!pctMatch) continue;
            result[id] = { used: Number(pctMatch[1]), reset: compact(resetEl && resetEl.textContent) };
          }

          // New Console: each meter has a named progressbar with aria-valuenow.
          for (const bar of document.querySelectorAll('[role="progressbar"][aria-valuenow]')) {
            const id = idForLabel(bar.getAttribute('aria-label'));
            if (!id || result[id]) continue;
            const used = Number(bar.getAttribute('aria-valuenow'));
            if (!Number.isFinite(used) || used < 0 || used > 100) continue;
            const card = bar.parentElement && bar.parentElement.parentElement;
            const reset = card && card.querySelector('[title]');
            result[id] = { used, reset: compact(reset && reset.textContent) };
          }

          // The Console home selects the user's organization dynamically.
          // Follow its Go link instead of embedding one person's workspace ID.
          let navigating = false;
          if (!Object.keys(result).length && location.pathname.startsWith('/console/') &&
              !/\\/go\\/?$/.test(location.pathname)) {
            const link = Array.from(document.querySelectorAll('a[href]')).find((anchor) => {
              const url = new URL(anchor.href, location.href);
              return url.origin === location.origin && /\\/console\\/(?:org_|wrk_)[^/]+\\/go\\/?$/.test(url.pathname);
            });
            if (link) { navigating = true; setTimeout(() => location.assign(link.href), 0); }
          }
          const text = document.body ? compact(document.body.innerText).slice(0, 240) : '';
          return JSON.stringify({
            quotas: result,
            itemCount: items.length,
            navigating: navigating,
            href: location.href,
            title: document.title,
            text: text
          });
        })()
        """
        super.init(id: "opencode-go", displayName: "opencode go",
                   iconSystemName: "bolt.fill",
                   loginURL: URL(string: "https://opencode.ai/console/")!,
                   harvestScript: js,
                   brandIcon: .openCode)
    }

    public override func fetch() async -> Snapshot {
        guard ProviderFetchModeStore.selectedModeId(for: self) == "api" else {
            return await super.fetch()
        }
        guard let key = ProviderCredentialStore.value(providerId: id, modeId: "api", fieldId: "apiKey")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            return Snapshot(providerId: id, quotas: [], status: .error("请在右键菜单的“爬取模式 → 官方 API”中配置 OpenCode Go API Key"))
        }
        return await OpenCodeGoAPI.fetch(apiKey: key)
    }

    public override var harvestDelay: TimeInterval { 2 }
    public override var maximumHarvestAttempts: Int { 15 }
    public override var harvestRetryDelay: TimeInterval { 2 }

    public override func shouldRetry(harvest: Any?) -> Bool {
        guard let json = harvest as? String,
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quotas = root["quotas"] as? [String: Any],
              quotas.isEmpty else { return false }
        return !Self.looksLikeLoginPage(root)
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
               let used = Self.doubleValue(entry["used"]),
               used.isFinite, (0...100).contains(used) {
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
        return href.contains("auth.opencode.ai") || href.contains("/auth") || href.contains("/login")
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
