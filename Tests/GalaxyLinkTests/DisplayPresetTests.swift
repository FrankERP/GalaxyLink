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
}
