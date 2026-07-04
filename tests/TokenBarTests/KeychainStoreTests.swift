import XCTest
@testable import TokenBar

final class KeychainStoreTests: XCTestCase {
    let store = KeychainStore(service: "com.liuxiaoliang.tokenbar.test")
    let pid = "test-provider-\(UUID().uuidString)"

    override func tearDown() {
        try? store.delete(providerId: pid)
    }

    func test_save_load_delete_roundtrip() throws {
        let blob = "session-cookie-data-\(UUID().uuidString)".data(using: .utf8)!
        XCTAssertNil(try store.load(providerId: pid))

        try store.save(providerId: pid, data: blob)
        let loaded = try store.load(providerId: pid)
        XCTAssertEqual(loaded, blob)

        try store.delete(providerId: pid)
        XCTAssertNil(try store.load(providerId: pid))
    }

    func test_missing_key_returns_nil_no_throw() throws {
        XCTAssertNil(try store.load(providerId: "nonexistent-\(UUID())"))
    }
}