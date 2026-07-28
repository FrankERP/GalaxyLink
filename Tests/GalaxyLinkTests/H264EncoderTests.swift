import XCTest
import CoreMedia
import CoreVideo
@testable import GalaxyLink

final class H264EncoderTests: XCTestCase {
    private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
        CVPixelBufferCreate(nil, width, height,
                            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attrs, &pb)
        let buffer = try XCTUnwrap(pb)
        CVPixelBufferLockBaseAddress(buffer, [])
        for plane in 0..<2 {
            let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane)!
            let size = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane)
                     * CVPixelBufferGetHeightOfPlane(buffer, plane)
            memset(base, plane == 0 ? 0x80 : 0x40, size)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    func testEncodesKeyframeWithAnnexBAndCodecString() throws {
        let encoder = try H264Encoder(width: 640, height: 400, fps: 30, bitrate: 2_000_000)
        let frameExp = expectation(description: "frame")
        let codecExp = expectation(description: "codec")
        var firstFrame: H264Encoder.EncodedFrame?
        var codec: String?
        encoder.onFrame = { frame in
            if firstFrame == nil { firstFrame = frame; frameExp.fulfill() }
        }
        encoder.onCodecString = { codec = $0; codecExp.fulfill() }

        let pixelBuffer = try makePixelBuffer(width: 640, height: 400)
        for i in 0..<5 {
            encoder.encode(pixelBuffer, presentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
        }
        wait(for: [frameExp, codecExp], timeout: 10)
        encoder.invalidate()

        let frame = try XCTUnwrap(firstFrame)
        XCTAssertTrue(frame.isKeyframe)
        XCTAssertEqual(Array(frame.annexB.prefix(4)), [0, 0, 0, 1])
        XCTAssertTrue(try XCTUnwrap(codec).hasPrefix("avc1."))
        XCTAssertEqual(try XCTUnwrap(codec).count, 11)
    }
}
