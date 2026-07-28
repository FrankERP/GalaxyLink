import XCTest
@testable import GalaxyLink

final class AVCTests: XCTestCase {
    func testAnnexBConversionTwoNALs() {
        // Two NALs, 4-byte lengths: [len=2][0x65 0x88], [len=1][0x41]
        let avcc = Data([0, 0, 0, 2, 0x65, 0x88, 0, 0, 0, 1, 0x41])
        let annexB = AVC.annexB(fromAVCC: avcc, nalLengthSize: 4)
        XCTAssertEqual(annexB, Data([0, 0, 0, 1, 0x65, 0x88, 0, 0, 0, 1, 0x41]))
    }

    func testAnnexBTruncatedInputStopsCleanly() {
        // Declared length 10 but only 2 bytes follow — must not crash, drops the bad NAL
        let avcc = Data([0, 0, 0, 10, 0x65, 0x88])
        XCTAssertEqual(AVC.annexB(fromAVCC: avcc, nalLengthSize: 4), Data())
    }

    func testCodecString() {
        // NAL header 0x67, profile 0x64 (High), compat 0x00, level 0x28 (4.0)
        let sps = Data([0x67, 0x64, 0x00, 0x28, 0xAC])
        XCTAssertEqual(AVC.codecString(sps: sps), "avc1.640028")
    }

    func testParameterSetPrefix() {
        let prefix = AVC.parameterSetPrefix(sps: Data([0x67, 0x4D]), pps: Data([0x68, 0xEE]))
        XCTAssertEqual(prefix, Data([0, 0, 0, 1, 0x67, 0x4D, 0, 0, 0, 1, 0x68, 0xEE]))
    }
}
