import Foundation
import CoreGraphics
import ObjectiveC
import AppKit

let arguments = CommandLine.arguments

if arguments.contains("--probe-api") {
    for name in ["CGVirtualDisplay", "CGVirtualDisplayDescriptor",
                 "CGVirtualDisplaySettings", "CGVirtualDisplayMode"] {
        guard let cls: AnyClass = NSClassFromString(name) else {
            print("\(name): NOT FOUND"); continue
        }
        print("=== \(name) ===")
        var methodCount: UInt32 = 0
        if let methods = class_copyMethodList(cls, &methodCount) {
            for i in 0..<Int(methodCount) {
                print("  -\(NSStringFromSelector(method_getName(methods[i])))")
            }
            free(methods)
        }
    }
    exit(0)
}

if arguments.contains("--probe-display") {
    guard let display = VirtualDisplay(preset: .default) else {
        print("FAILED to create virtual display (private API may have changed)")
        exit(1)
    }
    print("Created virtual display id=\(display.displayID)")
    var count: UInt32 = 0
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    CGGetOnlineDisplayList(16, &ids, &count)
    let online = ids.prefix(Int(count))
    print("Online displays: \(Array(online))")
    print(online.contains(display.displayID) ? "PROBE OK: virtual display is online" : "PROBE FAILED: not in online list")
    let modeOptions = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
    if let modes = CGDisplayCopyAllDisplayModes(display.displayID, modeOptions) as? [CGDisplayMode] {
        for mode in modes {
            print("available mode: \(mode.width)x\(mode.height) pt, \(mode.pixelWidth)x\(mode.pixelHeight) px, \(mode.refreshRate)Hz")
        }
        // Mode selection happens inside VirtualDisplay.init; the list is
        // printed here for diagnostics only.
    }
    if let current = CGDisplayCopyDisplayMode(display.displayID) {
        print("current mode: \(current.width)x\(current.height) pt, \(current.pixelWidth)x\(current.pixelHeight) px")
        print(current.pixelWidth == current.width * 2 ? "HiDPI ACTIVE" : "HiDPI NOT ACTIVE (1x)")
    }
    // Ground truth: the framebuffer snapshot's real pixel size.
    if let snapshot = CGDisplayCreateImage(display.displayID) {
        print("framebuffer snapshot: \(snapshot.width)x\(snapshot.height) px")
    } else {
        print("framebuffer snapshot: unavailable")
    }
    print("display.hiDPI readback: \(display.appliedHiDPI)")
    let screen = NSScreen.screens.first {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
    }
    if let screen {
        print("NSScreen backingScaleFactor: \(screen.backingScaleFactor)")
    } else {
        print("NSScreen: not found for display \(display.displayID)")
    }
    print("Holding display for 15s — check System Settings ▸ Displays…")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 15))
    exit(online.contains(display.displayID) ? 0 : 1)
}

if arguments.contains("--probe-capture") {
    guard let display = VirtualDisplay(preset: .default) else {
        print("FAILED to create virtual display"); exit(1)
    }
    let capture = CaptureEngine()
    var frames = 0
    capture.onFrame = { _, _ in frames += 1 }
    Task {
        do {
            try await capture.start(displayID: display.displayID,
                                    pixelWidth: DisplayPreset.default.pixelWidth,
                                    pixelHeight: DisplayPreset.default.pixelHeight, fps: 60)
        } catch {
            print("Capture failed: \(error.localizedDescription)"); exit(1)
        }
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 5))
    print(frames > 30 ? "PROBE OK: \(frames) frames in 5s" : "PROBE FAILED: only \(frames) frames")
    exit(frames > 30 ? 0 : 1)
}

if arguments.contains("--serve") {
    let controller = StreamController()
    controller.onStatusChange = { status in print("Status: \(status)") }
    var preset: DisplayPreset = .default
    if let flagIndex = arguments.firstIndex(of: "--preset"), flagIndex + 1 < arguments.count {
        switch arguments[flagIndex + 1] {
        case "balanced": preset = DisplayPreset.all[1]
        case "compat": preset = DisplayPreset.all[2]
        default: break
        }
    }
    print("Preset: \(preset.name)")
    controller.startServers()
    controller.start(preset: preset)
    print("Serving. Ctrl-C to quit.")
    RunLoop.main.run()
}

// Default: run as menu-bar app.
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
