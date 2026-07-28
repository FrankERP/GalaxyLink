import Foundation
import CoreGraphics
import CGVirtualDisplayShim

/// Wrapper around the private CGVirtualDisplay API. The display lives as long
/// as this instance is retained; releasing it removes the display.
final class VirtualDisplay {
    let displayID: CGDirectDisplayID
    private let display: CGVirtualDisplay   // retained to keep display alive

    init?(preset: DisplayPreset, refreshRate: Double = 60) {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.queue = DispatchQueue.main
        descriptor.name = "GalaxyLink (Tab S10 Ultra)"
        descriptor.maxPixelsWide = UInt32(preset.pixelWidth)
        descriptor.maxPixelsHigh = UInt32(preset.pixelHeight)
        // Tab S10 Ultra: 14.6" 16:10 panel ≈ 315 × 196 mm
        descriptor.sizeInMillimeters = CGSize(width: 315, height: 196)
        descriptor.redPrimary = CGPoint(x: 0.68, y: 0.32)
        descriptor.greenPrimary = CGPoint(x: 0.265, y: 0.69)
        descriptor.bluePrimary = CGPoint(x: 0.15, y: 0.06)
        descriptor.whitePoint = CGPoint(x: 0.3127, y: 0.329)
        descriptor.vendorID = 0x6A6C   // "jl"
        descriptor.productID = 0x5310
        descriptor.serialNum = 1
        descriptor.terminationHandler = { _, _ in }

        guard let display = CGVirtualDisplay(descriptor: descriptor) else { return nil }

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = preset.hiDPI ? 1 : 0
        settings.modes = [CGVirtualDisplayMode(width: UInt32(preset.pixelWidth),
                                               height: UInt32(preset.pixelHeight),
                                               refreshRate: refreshRate)]
        guard display.apply(settings) else { return nil }
        self.display = display
        self.displayID = display.displayID
    }
}
