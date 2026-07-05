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
    func test_defaultRegistry_containsSixProviders() {
        XCTAssertEqual(ProvidersRegistry.default.adapters.count, 6)
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "opencode-go" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "minimax" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "siliconflow" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "deepseek" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "volcano" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "openrouter" })
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
