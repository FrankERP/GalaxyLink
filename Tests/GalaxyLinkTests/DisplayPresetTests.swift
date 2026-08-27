import XCTest
@testable import GalaxyLink

final class DisplayPresetTests: XCTestCase {
    func testDefaultIsTabS10UltraHiDPI() {
        XCTAssertEqual(DisplayPreset.default.pixelWidth, 2960)
        XCTAssertEqual(DisplayPreset.default.pixelHeight, 1848)
        XCTAssertTrue(DisplayPreset.default.hiDPI)
        XCTAssertEqual(DisplayPreset.default.pointSize.width, 1480)
        XCTAssertEqual(DisplayPreset.default.pointSize.height, 924)
    }

    func testNonHiDPIPointSizeEqualsPixels() {
        let p = DisplayPreset(name: "x", pixelWidth: 1480, pixelHeight: 924, hiDPI: false)
        XCTAssertEqual(p.pointSize.width, 1480)
        XCTAssertEqual(p.pointSize.height, 924)
    }

    func testThreePresets() {
        XCTAssertEqual(DisplayPreset.all.count, 3)
    }

    func testMenuTitlesAreSharpBalancedCompatible() {
        XCTAssertEqual(DisplayPreset.all.map(\.menuTitle), ["Sharp", "Balanced", "Compatible"])
        XCTAssertEqual(DisplayPreset.default.menuTitle, "Sharp")
        XCTAssertEqual(DisplayPreset.all[0].footnote, "2960×1848 HiDPI")
        XCTAssertEqual(DisplayPreset.all[1].footnote, "2560×1600 HiDPI")
        XCTAssertEqual(DisplayPreset.all[2].footnote, "1480×924 1×")
        XCTAssertFalse(DisplayPreset.all.contains(where: { $0.menuTitle == "Resolution" }))
    }
}
