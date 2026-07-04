import Foundation
import WebKit

public final class MinimaxAdapter: WebViewAdapter {
    public init() {
        // The JS returns JSON: {"quota":{"used":<used>,"total":<total>}}
        // Selectors are placeholder — controller will verify and edit before Task 17 smoke.
        let js = """
        (function() {
          // Find the subscription quota card; ADJUST selectors per research.
          const card = document.querySelector('[data-subscription-quota]');
          if (!card) return JSON.stringify({quota: null});
          const used = parseInt(card.querySelector('[data-used]')?.textContent || '0', 10);
          const total = parseInt(card.querySelector('[data-total]')?.textContent || '1', 10);
          return JSON.stringify({ quota: { used, total } });
        })()
        """
        super.init(id: "minimax",
                   displayName: "MiniMax",
                   iconSystemName: "sparkles",
                   loginURL: URL(string: "https://api.minimax.chat")!,
                   harvestScript: js)
    }

    public override func parse(harvest: Any?) -> Snapshot {
        guard let jsonStr = harvest as? String,
              let data = jsonStr.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let q = raw["quota"] as? [String: Int] else {
            return Snapshot(providerId: id, quotas: [], status: .error("parse"))
        }
        let used = Double(q["used"] ?? 0)
        let total = Double(q["total"] ?? 1)
        let quota = Quota(id: "subscription", label: "订阅",
                          used: used, total: total, unit: "%")
        return Snapshot(providerId: id, quotas: [quota], status: .ok)
    }
}