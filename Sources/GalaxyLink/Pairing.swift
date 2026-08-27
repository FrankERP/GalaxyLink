import AppKit
import CoreGraphics

enum PairingCopy {
    static let windowTitle = "GalaxyLink"
    static let title = "Your second screen"
    static let line = "Plug in the tablet."
    static let useACable = "Use a cable"
    static let start = "Start"
    static let sameWiFi = "Same Wi-Fi"
    static let needsScreenRecording = "GalaxyLink needs Screen Recording"
    static let openSettings = "Open Settings"
    static let cableReady = "Cable ready."
}

enum FirstRun {
    static let defaultsKey = "pairing.didCompleteFirstStart"

    static func shouldShowPairing(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: defaultsKey)
    }

    static func markCompleteIfRunning(_ status: StreamController.Status, defaults: UserDefaults = .standard) {
        if case .running = status {
            defaults.set(true, forKey: defaultsKey)
        }
    }
}

enum CableAlert {
    struct Content: Equatable {
        let message: String
        let detail: String?
    }

    static let ready = PairingCopy.cableReady
    static let noTablet = "No tablet. Plug in, turn on USB debugging, try again."
    static let adbMissing = "adb not found"
    static let adbMissingDetail = "Install Android platform-tools (brew install android-platform-tools) and retry."

    static func content(for result: Result<String, USBHelper.USBError>) -> Content {
        switch result {
        case .success(_):
            return Content(message: ready, detail: nil)
        case .failure(.adbNotFound):
            return Content(message: adbMissing, detail: adbMissingDetail)
        case .failure(.noDevice), .failure(.commandFailed(_)):
            return Content(message: noTablet, detail: nil)
        }
    }

    static func presentsAlert(for result: Result<String, USBHelper.USBError>) -> Bool {
        if case .failure = result { return true }
        return false
    }
}

enum MenuCopy {
    static let start = "Start"
    static let stop = "Stop"
    static let showPairing = "Show pairing"
    static let useACable = "Use a cable"
    static let quit = "Quit"

    static func statusLine(isOn: Bool) -> String {
        isOn ? "GalaxyLink · On" : "GalaxyLink · Off"
    }

    static func presetParentTitle(_ preset: DisplayPreset) -> String {
        preset.menuTitle
    }
}

enum Pairing {
    static let usbURL = "http://localhost:\(Ports.http)"

    static func wifiURL(host: String? = LANAddress.primaryIPv4()) -> String {
        "http://\(host ?? "localhost"):\(Ports.http)"
    }
}

enum ScreenRecordingAccess {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
