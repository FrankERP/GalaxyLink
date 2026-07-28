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

print("GalaxyLink scaffold")
