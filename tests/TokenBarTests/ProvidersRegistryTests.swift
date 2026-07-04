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
    func test_defaultRegistry_containsFiveProviders() {
        XCTAssertEqual(ProvidersRegistry.default.adapters.count, 5)
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "opencode-go" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "minimax" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "siliconflow" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "deepseek" })
        XCTAssertTrue(ProvidersRegistry.default.adapters.contains { $0.id == "volcano" })
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
