import XCTest
@testable import GalaxyLink

final class StreamProtocolTests: XCTestCase {
    func testConfigFrame() throws {
        let frame = StreamProtocol.configFrame(codec: "avc1.4D0028", width: 2960, height: 1848, fps: 60)
        XCTAssertEqual(frame[0], 0x01)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: frame.dropFirst()) as? [String: Any])
        XCTAssertEqual(json["codec"] as? String, "avc1.4D0028")
        XCTAssertEqual(json["width"] as? Int, 2960)
        XCTAssertEqual(json["height"] as? Int, 1848)
        XCTAssertEqual(json["fps"] as? Int, 60)
    }

    func testVideoFrameKeyframe() {
        let payload = Data([0x00, 0x00, 0x00, 0x01, 0x65, 0xAA])
        let frame = StreamProtocol.videoFrame(annexB: payload, isKeyframe: true, timestampMicros: 0x0102030405060708)
        XCTAssertEqual(frame[0], 0x02)
        XCTAssertEqual(frame[1], 0x01)
        // little-endian u64
        XCTAssertEqual(Array(frame[2..<10]), [0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01])
        XCTAssertEqual(Data(frame[10...]), payload)
    }

    func testVideoFrameDelta() {
        let frame = StreamProtocol.videoFrame(annexB: Data([0x61]), isKeyframe: false, timestampMicros: 0)
        XCTAssertEqual(frame[1], 0x00)
        XCTAssertEqual(frame.count, 11)
    }
}
