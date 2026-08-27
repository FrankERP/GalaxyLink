import XCTest
@testable import GalaxyLink

final class PortsTests: XCTestCase {
    func testUSBAndPairingStayOnPlaintext8080And8081() {
        XCTAssertEqual(Ports.http, 8080)
        XCTAssertEqual(Ports.ws, 8081)
    }
}

final class PairingTests: XCTestCase {
    func testUSBURLIsLocalhostOn8080() {
        XCTAssertEqual(Pairing.usbURL, "http://localhost:8080")
        XCTAssertTrue(Pairing.usbURL.hasPrefix("http://"))
        XCTAssertFalse(Pairing.usbURL.contains("https"))
        XCTAssertFalse(Pairing.usbURL.contains("8443"))
        XCTAssertFalse(Pairing.usbURL.contains("8444"))
    }

    func testWifiURLIsPlainHTTPOn8080AndIsNotTheHero() {
        XCTAssertEqual(Pairing.wifiURL(host: "192.168.1.23"), "http://192.168.1.23:8080")
        XCTAssertEqual(Pairing.wifiURL(host: nil), "http://localhost:8080")
        XCTAssertNotEqual(PairingCopy.line, Pairing.wifiURL(host: "192.168.1.23"))
        XCTAssertTrue(PairingCopy.line.contains(Pairing.usbURL))
        XCTAssertFalse(PairingCopy.line.contains("192.168."))
    }

    func testPairingCopyIsUSBFirst() {
        XCTAssertEqual(PairingCopy.title, "Your second screen")
        XCTAssertEqual(PairingCopy.line, "Plug in the tablet. Then open http://localhost:8080")
        XCTAssertEqual(PairingCopy.useACable, "Use a cable")
        XCTAssertEqual(PairingCopy.start, "Start")
        XCTAssertEqual(PairingCopy.sameWiFi, "Same Wi-Fi")
        XCTAssertEqual(PairingCopy.needsScreenRecording, "GalaxyLink needs Screen Recording")
        XCTAssertEqual(PairingCopy.openSettings, "Open Settings")
        XCTAssertEqual(PairingCopy.useACable, MenuCopy.useACable)
    }

    func testPairingCopyHasNoLANQRHeroOrInterstitial() {
        let card = [
            PairingCopy.title,
            PairingCopy.line,
            PairingCopy.useACable,
            PairingCopy.start,
            PairingCopy.sameWiFi,
            PairingCopy.needsScreenRecording,
            PairingCopy.openSettings,
        ].joined(separator: " ")
        XCTAssertFalse(card.contains("Scan"))
        XCTAssertFalse(card.contains("QR"))
        XCTAssertFalse(card.contains("Advanced"))
        XCTAssertFalse(card.contains("Proceed"))
        XCTAssertFalse(card.contains("isn’t private"))
        XCTAssertFalse(card.contains("isn't private"))
        XCTAssertFalse(card.contains("chrome://flags"))
        XCTAssertFalse(card.contains("unsafely-treat-insecure-origin"))
        XCTAssertFalse(card.lowercased().contains("adb"))
    }

    func testMenuCopyIsLocked() {
        XCTAssertEqual(MenuCopy.statusLine(isOn: false), "GalaxyLink · Off")
        XCTAssertEqual(MenuCopy.statusLine(isOn: true), "GalaxyLink · On")
        XCTAssertEqual(MenuCopy.start, "Start")
        XCTAssertEqual(MenuCopy.stop, "Stop")
        XCTAssertEqual(MenuCopy.showPairing, "Show pairing")
        XCTAssertEqual(MenuCopy.useACable, "Use a cable")
        XCTAssertEqual(MenuCopy.quit, "Quit")
        XCTAssertFalse(MenuCopy.useACable.lowercased().contains("adb"))
        XCTAssertNotEqual(MenuCopy.statusLine(isOn: false), "Status: stopped")
        XCTAssertNotEqual(MenuCopy.statusLine(isOn: true), "Streaming")
        XCTAssertNotEqual(MenuCopy.quit, "Quit GalaxyLink")
    }
}
