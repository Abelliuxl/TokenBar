import XCTest
@testable import TokenBar

struct StubAdapter: ProviderAdapter {
    let id: String
    var displayName: String { id }
    var iconSystemName: String { "circle" }
    var loginURL: URL { URL(string: "https://example.com")! }
    func fetch() async -> Snapshot {
        Snapshot(providerId: id, quotas: [], status: .ok)
    }
}

final class ProvidersRegistryTests: XCTestCase {
    func test_defaultRegistry_containsSevenProviders() {
        XCTAssertEqual(ProvidersRegistry.default.adapters.count, 7)
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "opencode-go" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "minimax" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "siliconflow" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "deepseek" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "volcano" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "openrouter" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "codex" })
    }
}

final class OpenRouterAdapterTests: XCTestCase {
    func test_parse_prefersRemainingCreditsOverTransactionAmounts() {
        let adapter = OpenRouterAdapter()
        let harvest = """
        {
          "api": { "status": 401, "body": "" },
          "remainingCredits": 7.258,
          "href": "https://openrouter.ai/settings/credits",
          "title": "Credits | OpenRouter",
          "text": "Credits Personal Account $ Buy Credits Recent Transactions Jul 1, 2026 $10.00 Apr 9, 2026 $5.00"
        }
        """

        let snapshot = adapter.parse(harvest: harvest)

        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.quotas.first?.total, 7.258)
    }

    func test_parse_doesNotUseBareTransactionDollarAmountsAsBalance() {
        let adapter = OpenRouterAdapter()
        let harvest = """
        {
          "api": { "status": 401, "body": "" },
          "href": "https://openrouter.ai/settings/credits",
          "title": "Credits | OpenRouter",
          "text": "Credits Personal Account $ Buy Credits Recent Transactions Jul 1, 2026 $10.00 Apr 9, 2026 $5.00"
        }
        """

        let snapshot = adapter.parse(harvest: harvest)

        guard case .error = snapshot.status else {
            return XCTFail("Expected parser to reject transaction history amounts")
        }
        XCTAssertTrue(snapshot.quotas.isEmpty)
    }
}

final class MinimaxAdapterTests: XCTestCase {
    func test_parseConvertsExplicitRemainingPercentToUsedPercent() {
        let harvest = """
        {
          "fiveHour": { "percent": 12, "semantic": "remaining", "reset": "2 小时后重置" },
          "href": "https://platform.minimaxi.com/console/usage"
        }
        """

        let snapshot = MinimaxAdapter().parse(harvest: harvest)

        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.quotas.first?.used, 88)
        XCTAssertEqual(snapshot.quotas.first?.resetText, "2 小时后重置")
    }

    func test_parseKeepsHistoricalBarePercentAsUsedPercent() {
        let harvest = """
        {
          "weekly": { "percent": 35, "semantic": "used" },
          "href": "https://platform.minimaxi.com/console/usage"
        }
        """

        let snapshot = MinimaxAdapter().parse(harvest: harvest)

        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.quotas.first?.used, 35)
    }

    func test_parseRejectsOutOfRangePercentInsteadOfShowingAFalseFullQuota() {
        let harvest = """
        {
          "fiveHour": { "percent": 250, "semantic": "remaining" },
          "href": "https://platform.minimaxi.com/console/usage"
        }
        """

        let snapshot = MinimaxAdapter().parse(harvest: harvest)

        XCTAssertTrue(snapshot.quotas.isEmpty)
        guard case .error = snapshot.status else {
            return XCTFail("Expected out-of-range percentage to fail parsing")
        }
    }
}

final class OpenCodeGoAdapterTests: XCTestCase {
    func test_parseUsesStableQuotaIdsInsteadOfLocalizedLabels() {
        let harvest = """
        {
          "quotas": {
            "rolling": { "used": 2, "reset": "Resets in 30 minutes" },
            "weekly": { "used": 42, "reset": "Resets in 4 days" },
            "monthly": { "used": 73, "reset": "Resets in 20 days" }
          },
          "href": "https://opencode.ai/workspace/example/go"
        }
        """

        let snapshot = OpenCodeGoAdapter().parse(harvest: harvest)

        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.quotas.map(\.id), ["rolling", "weekly", "monthly"])
        XCTAssertEqual(snapshot.quotas.map(\.used), [2, 42, 73])
    }
}

final class AppStateTests: XCTestCase {
    @MainActor func test_updateSnapshot_replacesExisting() {
        let state = AppState()
        let snap = Snapshot(providerId: "x", quotas: [], status: .ok)
        state.update(snapshot: snap)
        XCTAssertEqual(state.snapshots["x"]?.status, .ok)
        let snap2 = Snapshot(providerId: "x", quotas: [], status: .needsRelogin)
        state.update(snapshot: snap2)
        XCTAssertEqual(state.snapshots["x"]?.status, .needsRelogin)
    }
}
