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
        XCTAssertFalse(PairingCopy.line.contains("192.168."))
        XCTAssertFalse(PairingCopy.line.contains(Pairing.usbURL))
        XCTAssertFalse(PairingCopy.line.contains("http"))
    }

    func testPairingCopyIsUSBFirst() {
        XCTAssertEqual(PairingCopy.windowTitle, "GalaxyLink")
        XCTAssertEqual(PairingCopy.title, "Your second screen")
        XCTAssertNotEqual(PairingCopy.windowTitle, PairingCopy.title)
        XCTAssertEqual(PairingCopy.line, "Plug in the tablet.")
        XCTAssertEqual(PairingCopy.useACable, "Use a cable")
        XCTAssertEqual(PairingCopy.start, "Start")
        XCTAssertEqual(PairingCopy.sameWiFi, "Same Wi-Fi")
        XCTAssertEqual(PairingCopy.needsScreenRecording, "GalaxyLink needs Screen Recording")
        XCTAssertEqual(PairingCopy.openSettings, "Open Settings")
        XCTAssertEqual(PairingCopy.useACable, MenuCopy.useACable)
    }

    func testPairingCopyHasNoLANQRHeroOrInterstitial() {
        let card = [
            PairingCopy.windowTitle,
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
        XCTAssertFalse(card.contains("Then open"))
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
        XCTAssertEqual(MenuCopy.presetParentTitle(.default), "Sharp")
        XCTAssertEqual(MenuCopy.presetParentTitle(DisplayPreset.all[1]), "Balanced")
        XCTAssertFalse(MenuCopy.presetParentTitle(.default).contains("▾"))
        XCTAssertFalse(MenuCopy.useACable.lowercased().contains("adb"))
        XCTAssertNotEqual(MenuCopy.statusLine(isOn: false), "Status: stopped")
        XCTAssertNotEqual(MenuCopy.statusLine(isOn: true), "Streaming")
        XCTAssertNotEqual(MenuCopy.quit, "Quit GalaxyLink")
    }

    func testFirstRunPersistsOnlyAfterSuccessfulStart() {
        XCTAssertEqual(FirstRun.defaultsKey, "pairing.didCompleteFirstStart")
        XCTAssertNotEqual(FirstRun.defaultsKey, "pairing.didShowOnFirstLaunch")
        let suite = "galaxylink.first-run.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        XCTAssertTrue(FirstRun.shouldShowPairing(defaults: defaults))
        FirstRun.markCompleteIfRunning(.stopped, defaults: defaults)
        XCTAssertTrue(FirstRun.shouldShowPairing(defaults: defaults),
                      "dismiss / appear must not persist first-run")
        FirstRun.markCompleteIfRunning(.failed("capture"), defaults: defaults)
        XCTAssertTrue(FirstRun.shouldShowPairing(defaults: defaults))
        FirstRun.markCompleteIfRunning(.running(url: Pairing.usbURL), defaults: defaults)
        XCTAssertFalse(FirstRun.shouldShowPairing(defaults: defaults))
        defaults.removePersistentDomain(forName: suite)
    }

    func testCableAlerts() {
        XCTAssertEqual(CableAlert.content(for: .success("ignored")).message, "Cable ready.")
        XCTAssertNil(CableAlert.content(for: .success("ignored")).detail)
        XCTAssertFalse(CableAlert.content(for: .success("ignored")).message.contains("USB mode"))
        XCTAssertFalse(CableAlert.ready.lowercased().contains("brew"))

        let missing = CableAlert.content(for: .failure(.adbNotFound))
        XCTAssertEqual(missing.message, "adb not found")
        XCTAssertEqual(missing.detail, "Install Android platform-tools (brew install android-platform-tools) and retry.")
        XCTAssertTrue(missing.detail?.contains("brew") == true)

        let noTablet = CableAlert.content(for: .failure(.noDevice))
        XCTAssertEqual(noTablet.message, "No tablet. Plug in, turn on USB debugging, try again.")
        XCTAssertNil(noTablet.detail)
        XCTAssertFalse((noTablet.detail ?? "").contains("brew"))

        let reverse = CableAlert.content(for: .failure(.commandFailed("adb: error")))
        XCTAssertEqual(reverse.message, "No tablet. Plug in, turn on USB debugging, try again.")
        XCTAssertNil(reverse.detail)
        XCTAssertFalse((reverse.detail ?? noTablet.message).contains("brew"))
    }
}
