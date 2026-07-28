import XCTest
@testable import GalaxyLink

final class USBHelperTests: XCTestCase {
    func testParsesConnectedDevice() {
        let out = """
        List of devices attached
        R52X123ABC\tdevice
        emulator-5554\toffline

        """
        XCTAssertEqual(USBHelper.parseDevices(out), ["R52X123ABC"])
    }

    func testUnauthorizedDeviceExcluded() {
        let out = "List of devices attached\nR52X123ABC\tunauthorized\n"
        XCTAssertEqual(USBHelper.parseDevices(out), [])
    }

    func testEmptyList() {
        XCTAssertEqual(USBHelper.parseDevices("List of devices attached\n\n"), [])
    }
}
