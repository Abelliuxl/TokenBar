import XCTest
import Foundation
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
    func test_defaultRegistry_containsEightProviders() {
        XCTAssertEqual(ProvidersRegistry.default.adapters.count, 8)
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "opencode-go" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "minimax" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "siliconflow" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "deepseek" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "volcano" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "openrouter" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "codex" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "command-code" })
    }

    func testDeepSeekAndOpenRouterExposeWebAndAPIModes() {
        for providerId in ["deepseek", "openrouter"] {
            guard let provider = ProvidersRegistry.default.adapters.first(where: { $0.id == providerId }),
                  let multiMode = provider as? any MultiModeProviderAdapter else {
                return XCTFail("Expected \(providerId) to support multiple fetch modes")
            }
            XCTAssertEqual(multiMode.defaultFetchModeId, "webSession")
            XCTAssertEqual(multiMode.fetchModes.map(\.id), ["webSession", "api"])
            XCTAssertEqual(multiMode.fetchModes.last?.credentialFields.map(\.id), ["apiKey"])
        }
    }
}

final class OfficialBalanceAPITests: XCTestCase {
    func test_deepSeekAPI_decodesCurrencyBalance() {
        let data = Data("""
        {
          "is_available": true,
          "balance_infos": [
            { "currency": "CNY", "total_balance": "21.84", "granted_balance": "1.84", "topped_up_balance": "20.00" }
          ]
        }
        """.utf8)

        let snapshot = DeepSeekAPI.decode(data: data)

        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.quotas.map(\.id), ["balance-cny"])
        XCTAssertEqual(snapshot.quotas.first?.total ?? -1, 21.84, accuracy: 0.000001)
        XCTAssertEqual(snapshot.quotas.first?.unit, "¥")
    }

    func test_deepSeekAPI_keepsNegativeCurrencyBalance() {
        let data = Data("""
        {
          "is_available": true,
          "balance_infos": [
            { "currency": "CNY", "total_balance": "-2.50" }
          ]
        }
        """.utf8)

        let snapshot = DeepSeekAPI.decode(data: data)

        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.quotas.first?.total ?? 0, -2.50, accuracy: 0.000001)
        XCTAssertEqual(snapshot.quotas.first?.unit, "¥")
    }

    func test_openRouterAPI_decodesRemainingCredits() {
        let data = Data("""
        {
          "data": { "total_credits": 170, "total_usage": 158.505987168 }
        }
        """.utf8)

        let snapshot = OpenRouterAPI.decode(data: data)

        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.quotas.first?.total ?? -1, 11.494012832, accuracy: 0.000001)
        XCTAssertEqual(snapshot.quotas.first?.unit, "$")
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

final class CommandCodeAdapterTests: XCTestCase {
    func test_parseUsesFiveHourWeeklyAndMonthlyPercentages() {
        let harvest = """
        {
          "limits": {
            "fiveHour": { "used": 12, "reset": "Resets in 4h 53m" },
            "weekly": { "used": 34, "reset": "Resets in 6d 23h" },
            "monthly": { "used": 56, "reset": "Resets on Sep 26" }
          },
          "href": "https://commandcode.ai/Abelliuxl/settings/usage"
        }
        """

        let snapshot = CommandCodeAdapter().parse(harvest: harvest)

        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.quotas.map(\.id), ["fiveHour", "weekly", "monthly"])
        XCTAssertEqual(snapshot.quotas.map(\.used), [12, 34, 56])
        XCTAssertEqual(snapshot.quotas.map(\.resetText), ["Resets in 4h 53m", "Resets in 6d 23h", "Resets on Sep 26"])
    }

    func test_parseRecognizesUnauthenticatedPage() {
        let harvest = """
        {
          "limits": {},
          "href": "https://commandcode.ai/login?redirect=%2Fsettings%2Fusage",
          "text": "Log in to Command Code"
        }
        """

        let snapshot = CommandCodeAdapter().parse(harvest: harvest)

        XCTAssertEqual(snapshot.status, .needsRelogin)
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

private final class CodexTestClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_000)

    func now() -> Date { date }
    func advance(by interval: TimeInterval) { date.addTimeInterval(interval) }
}

private final class CodexReadCounter: @unchecked Sendable {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

final class CodexReadCacheTests: XCTestCase {
    func test_reusesSnapshotWithinFiveSeconds_thenReadsAgain() async {
        let clock = CodexTestClock()
        let counter = CodexReadCounter()
        let cache = CodexReadCache(cooldown: 5, clock: { clock.now() })

        let first = await cache.snapshot {
            counter.increment()
            return Snapshot(providerId: "codex", quotas: [], status: .ok)
        }

        clock.advance(by: 4.9)
        let cached = await cache.snapshot {
            counter.increment()
            return Snapshot(providerId: "codex", quotas: [], status: .error("should not read yet"))
        }

        clock.advance(by: 0.2)
        let refreshed = await cache.snapshot {
            counter.increment()
            return Snapshot(providerId: "codex", quotas: [], status: .ok)
        }

        XCTAssertEqual(counter.value, 2)
        XCTAssertEqual(cached, first)
        XCTAssertEqual(refreshed.status, .ok)
    }
}
