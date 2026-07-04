import Foundation
import WebKit

public final class OpenCodeGoAdapter: WebViewAdapter {
    public init() {
        // The JS should return a JSON-encoded string like:
        //   '{"5h":{"used":80,"total":500},"week":{...},"month":{...}}'
        let js = """
        (function() {
          const pick = (label) => {
            const card = [...document.querySelectorAll('[data-quota]')].find(e => e.textContent.includes(label));
            if (!card) return null;
            const used = parseInt(card.querySelector('[data-used]')?.textContent || '0', 10);
            const total = parseInt(card.querySelector('[data-total]')?.textContent || '0', 10);
            return { used, total };
          };
          return JSON.stringify({
            '5h': pick('5h'),
            'week': pick('week'),
            'month': pick('month')
          });
        })()
        """
        super.init(id: "opencode-go", displayName: "opencode go",
                   iconSystemName: "bolt.fill",
                   loginURL: URL(string: "https://opencode.ai/dashboard")!,
                   harvestScript: js)
    }

    public override func parse(harvest: Any?) -> Snapshot {
        guard let jsonStr = harvest as? String,
              let data = jsonStr.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Int]] else {
            return Snapshot(providerId: id, quotas: [], status: .error("parse"))
        }
        var quotas: [Quota] = []
        for (label, kv) in raw {
            quotas.append(Quota(id: label, label: label,
                                used: Double(kv["used"] ?? 0),
                                total: Double(kv["total"] ?? 1), unit: "%"))
        }
        return Snapshot(providerId: id, quotas: quotas, status: .ok)
    }
}
