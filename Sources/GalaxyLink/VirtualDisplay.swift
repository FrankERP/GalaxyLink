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
        // hiDPI is the backing scale factor (2 = Retina), not a boolean.
        // Modes are declared in points; maxPixels carries the full pixels.
        settings.hiDPI = preset.hiDPI ? 2 : 1
        settings.modes = [CGVirtualDisplayMode(width: UInt32(preset.pointSize.width),
                                               height: UInt32(preset.pointSize.height),
                                               refreshRate: refreshRate)]
        guard display.apply(settings) else { return nil }
        self.display = display
        self.displayID = display.displayID

        // The WindowServer defaults to a synthesized 1x mode; the true Retina
        // mode (points @2x backing) is hidden behind the duplicate-low-res
        // flag and must be selected explicitly.
        Self.selectMode(displayID: display.displayID, preset: preset)
    }

    var appliedHiDPI: UInt32 { display.hiDPI }

    @discardableResult
    private static func selectMode(displayID: CGDirectDisplayID, preset: DisplayPreset) -> Bool {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode],
              let target = modes.first(where: { mode in
                  mode.width == preset.pointSize.width &&
                  mode.height == preset.pointSize.height &&
                  mode.pixelWidth == preset.pixelWidth &&
                  mode.pixelHeight == preset.pixelHeight
              }) else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        CGConfigureDisplayWithDisplayMode(config, displayID, target, nil)
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
}
