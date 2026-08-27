import AppKit
import CoreGraphics

enum PairingCopy {
    static let title = "Your second screen"
    static let line = "Plug in the tablet. Then open http://localhost:8080"
    static let useACable = "Use a cable"
    static let start = "Start"
    static let sameWiFi = "Same Wi-Fi"
    static let needsScreenRecording = "GalaxyLink needs Screen Recording"
    static let openSettings = "Open Settings"
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
