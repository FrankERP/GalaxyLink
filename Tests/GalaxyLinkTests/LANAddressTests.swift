import XCTest
@testable import GalaxyLink

final class LANAddressTests: XCTestCase {
    func testReturnsDottedQuadOrNil() {
        guard let ip = LANAddress.primaryIPv4() else { return } // machines without network: nil is valid
        let parts = ip.split(separator: ".")
        XCTAssertEqual(parts.count, 4)
        XCTAssertNotEqual(ip, "127.0.0.1")
        parts.forEach { XCTAssertNotNil(UInt8($0)) }
    }
}
