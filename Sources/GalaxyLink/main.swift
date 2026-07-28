import Foundation
import CoreGraphics

let arguments = CommandLine.arguments

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
    controller.start(preset: .default)
    print("Serving. Ctrl-C to quit.")
    RunLoop.main.run()
}

print("GalaxyLink scaffold")
