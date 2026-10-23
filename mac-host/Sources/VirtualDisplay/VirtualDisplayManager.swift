import Foundation
import CoreGraphics

public final class VirtualDisplayManager {
    private var virtualDisplay: NSObject?
    public private(set) var displayID: CGDirectDisplayID?
    
    public init() {}
    
    @discardableResult
    public func create(
        width: Int = 2560,
        height: Int = 1600,
        fps: Double = 60.0,
        hiDPI: Bool = true,
        name: String = "Galaxy Tab S7"
    ) -> CGDirectDisplayID? {
        guard let descClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let modeClass = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type,
              let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
              let displayClass = NSClassFromString("CGVirtualDisplay") as? NSObject.Type else {
            print("[VirtualDisplay] CoreGraphics virtual display classes not available")
            return nil
        }
        
        let desc = descClass.init()
        desc.setValue(name, forKey: "name")
        let maxDim = max(width, height)
        desc.setValue(maxDim, forKey: "maxPixelsWide")
        desc.setValue(maxDim, forKey: "maxPixelsHigh")
        desc.setValue(CGSize(width: 260, height: 162), forKey: "sizeInMillimeters")
        desc.setValue(0x1234, forKey: "vendorID")
        desc.setValue(0x5678, forKey: "productID")
        desc.setValue(DispatchQueue.main, forKey: "queue")
        
        guard let displayAlloc = displayClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let display = displayAlloc.perform(NSSelectorFromString("initWithDescriptor:"), with: desc)?.takeRetainedValue() as? NSObject else {
            print("[VirtualDisplay] Failed to instantiate CGVirtualDisplay")
            return nil
        }
        
        typealias ModeInitFunc = @convention(c) (AnyObject, Selector, UInt, UInt, Double) -> AnyObject
        var modes: [AnyObject] = []
        
        // Multi-resolution modes for optimal cursor speed and scaling
        // 1280x800 is the 2x Retina equivalent: fast, natural cursor travel
        let resolutions: [(UInt, UInt)] = [
            (1280, 800),
            (1440, 900),
            (1600, 1000),
            (1920, 1200),
            (UInt(width), UInt(height))
        ]
        
        let targetRates = [fps, 60.0, 120.0].sorted(by: >)
        var seenRates = Set<Double>()
        for rate in targetRates {
            seenRates.insert(rate)
        }
        
        for res in resolutions {
            for rate in seenRates {
                if let modeAlloc = modeClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() {
                    let sel = NSSelectorFromString("initWithWidth:height:refreshRate:")
                    let method = modeAlloc.method(for: sel)
                    let modeInit = unsafeBitCast(method, to: ModeInitFunc.self)
                    let mode = modeInit(modeAlloc, sel, res.0, res.1, rate)
                    modes.append(mode)
                }
            }
        }
        
        let settings = settingsClass.init()
        settings.setValue(modes, forKey: "modes")
        settings.setValue(hiDPI ? 1 : 0, forKey: "hiDPI")
        
        let applySel = NSSelectorFromString("applySettings:")
        let applyMethod = display.method(for: applySel)
        typealias ApplyFunc = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        let apply = unsafeBitCast(applyMethod, to: ApplyFunc.self)
        
        guard apply(display, applySel, settings) else {
            print("[VirtualDisplay] Failed to apply settings")
            return nil
        }
        
        guard let id = display.value(forKey: "displayID") as? CGDirectDisplayID else {
            print("[VirtualDisplay] Failed to retrieve displayID from virtual display")
            return nil
        }
        
        // Ensure the display is NOT mirrored and positioned immediately to the right of the main display
        var config: CGDisplayConfigRef?
        if CGBeginDisplayConfiguration(&config) == .success, let cfg = config {
            CGConfigureDisplayMirrorOfDisplay(cfg, id, kCGNullDirectDisplay)
            let mainBounds = CGDisplayBounds(CGMainDisplayID())
            // Position to the right edge of the main screen so mouse flows seamlessly
            CGConfigureDisplayOrigin(cfg, id, Int32(mainBounds.maxX), 0)
            CGCompleteDisplayConfiguration(cfg, .permanently)
        }
        
        self.virtualDisplay = display
        self.displayID = id
        
        let activeBounds = CGDisplayBounds(id)
        print("[VirtualDisplay] Created native virtual extended display: '\(name)'")
        print("[VirtualDisplay] Display ID: \(id) | Bounds: \(activeBounds) | UI Scale: \(Int(activeBounds.width))x\(Int(activeBounds.height))")
        print("[VirtualDisplay] Supported Refresh: \(seenRates.sorted().map { "\(Int($0))Hz" }.joined(separator: ", ")) | HiDPI: \(hiDPI)")
        print("[VirtualDisplay] Positioned to the RIGHT of main screen at x=\(Int(activeBounds.origin.x))")
        
        return id
    }
    
    @discardableResult
    public func setOrientation(width: Int, height: Int, fps: Double = 120.0, hiDPI: Bool = true) -> Bool {
        guard let display = virtualDisplay,
              let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
              let modeClass = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type else {
            return false
        }
        
        typealias ModeInitFunc = @convention(c) (AnyObject, Selector, UInt, UInt, Double) -> AnyObject
        guard let modeAlloc = modeClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return false }
        let sel = NSSelectorFromString("initWithWidth:height:refreshRate:")
        let method = modeAlloc.method(for: sel)
        let modeInit = unsafeBitCast(method, to: ModeInitFunc.self)
        
        // Use 2x Retina points for UI scaling (e.g. 2560x1600 -> 1280x800, 2880x1800 -> 1440x900)
        let uiWidth = UInt(width / 2)
        let uiHeight = UInt(height / 2)
        let mode = modeInit(modeAlloc, sel, uiWidth, uiHeight, fps)
        
        let settings = settingsClass.init()
        settings.setValue([mode], forKey: "modes")
        settings.setValue(hiDPI ? 1 : 0, forKey: "hiDPI")
        
        let applySel = NSSelectorFromString("applySettings:")
        let applyMethod = display.method(for: applySel)
        typealias ApplyFunc = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        let apply = unsafeBitCast(applyMethod, to: ApplyFunc.self)
        
        let success = apply(display, applySel, settings)
        if success, let id = displayID {
            // Reconfigure position next to main display
            var config: CGDisplayConfigRef?
            if CGBeginDisplayConfiguration(&config) == .success, let cfg = config {
                let mainBounds = CGDisplayBounds(CGMainDisplayID())
                CGConfigureDisplayOrigin(cfg, id, Int32(mainBounds.maxX), 0)
                CGCompleteDisplayConfiguration(cfg, .permanently)
            }
            let activeBounds = CGDisplayBounds(id)
            print("[VirtualDisplay] 🔄 Dynamically updated orientation: \(width)x\(height) (UI: \(Int(activeBounds.width))x\(Int(activeBounds.height)))")
        }
        return success
    }
    
    public func destroy() {
        if let id = displayID {
            print("[VirtualDisplay] Releasing virtual display ID: \(id)")
        }
        virtualDisplay = nil
        displayID = nil
    }
    
    deinit {
        destroy()
    }
}
