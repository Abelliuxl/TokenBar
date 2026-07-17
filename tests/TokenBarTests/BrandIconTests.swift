import XCTest
@testable import TokenBar

final class BrandIconTests: XCTestCase {
    func test_allBuiltInProviders_haveBrandIcons() {
        for adapter in ProvidersRegistry.default.adapters {
            XCTAssertNotNil(adapter.brandIcon, "\(adapter.id) missing brandIcon")
        }
    }

    func test_parser_openCodeFrame_bbox() {
        let rect = SVGPathParser.parse(BrandGlyphPaths.openCode).boundingRect
        XCTAssertEqual(rect.minX, 2, accuracy: 0.5)
        XCTAssertEqual(rect.minY, 0, accuracy: 0.5)
        XCTAssertEqual(rect.width, 20, accuracy: 0.5)
        XCTAssertEqual(rect.height, 24, accuracy: 0.5)
    }

    func test_parser_allGlyphs_haveFiniteNonEmptyBounds() {
        let paths: [String: String] = [
            "deepSeek": BrandGlyphPaths.deepSeek,
            "miniMax": BrandGlyphPaths.miniMax,
            "openCode": BrandGlyphPaths.openCode,
            "openRouter": BrandGlyphPaths.openRouter,
            "siliconFlow": BrandGlyphPaths.siliconFlow,
            "volcano": BrandGlyphPaths.volcanoCyan + BrandGlyphPaths.volcanoBlue,
            "codex": BrandGlyphPaths.codex,
        ]
        for (name, data) in paths {
            let rect = SVGPathParser.parse(data).boundingRect
            XCTAssertTrue(rect.isFinite, name)
            XCTAssertGreaterThan(rect.width, 0, name)
            XCTAssertGreaterThan(rect.height, 0, name)
        }
    }
}
