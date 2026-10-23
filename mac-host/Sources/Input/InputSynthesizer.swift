import Foundation
import CoreGraphics
import AppKit

public final class InputSynthesizer {
    private var targetDisplayBounds: CGRect
    private var targetDisplayID: CGDirectDisplayID?
    private var isDragging = false
    private var isPinchActive = false
    private var endPinchWorkItem: DispatchWorkItem?
    
    public init(displayID: CGDirectDisplayID? = nil, displayBounds: CGRect? = nil) {
        self.targetDisplayID = displayID
        if let bounds = displayBounds {
            self.targetDisplayBounds = bounds
        } else if let id = displayID {
            self.targetDisplayBounds = CGDisplayBounds(id)
        } else {
            self.targetDisplayBounds = CGDisplayBounds(CGMainDisplayID())
        }
    }
    
    public func updateDisplay(id: CGDirectDisplayID) {
        self.targetDisplayID = id
        self.targetDisplayBounds = CGDisplayBounds(id)
    }
    
    public func handleInput(event: TabletInputEvent) {
        let currentBounds = targetDisplayID.map { CGDisplayBounds($0) } ?? targetDisplayBounds
        
        switch event.action {
        case .scroll:
            // Scroll delta values passed in normalizedX (deltaX) and normalizedY (deltaY)
            let scrollY = Int32(event.normalizedY)
            let scrollX = Int32(event.normalizedX)
            if let scrollEvent = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: scrollY,
                wheel2: scrollX,
                wheel3: 0
            ) {
                scrollEvent.post(tap: .cghidEventTap)
            }
            return

        case .magnify:
            // Pinch-to-zoom: focal point in normalizedX/Y, zoom step in pressure
            let screenX = currentBounds.origin.x + CGFloat(event.normalizedX) * currentBounds.width
            let screenY = currentBounds.origin.y + CGFloat(event.normalizedY) * currentBounds.height
            let point = CGPoint(x: screenX, y: screenY)
            CGWarpMouseCursorPosition(point)

            let steps = Double(event.pressure)
            guard steps != 0 else { return }

            print("[Input] 🔍 Pinch Zoom: \(steps > 0 ? "IN" : "OUT") (\(steps)) at (\(Int(screenX)), \(Int(screenY)))")

            // 1. Native Apple trackpad gesture event (Type 29, field 110=8, field 132=phase, field 113=delta)
            // Handled natively by Safari, Preview, Maps, Photos, Figma, etc.
            let delta = steps * 0.05
            if !isPinchActive {
                isPinchActive = true
                postNativePinch(delta: delta, point: point, phase: 1) // Began
            }
            postNativePinch(delta: delta, point: point, phase: 2) // Changed

            // Debounced gesture completion
            endPinchWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.isPinchActive else { return }
                self.postNativePinch(delta: 0, point: point, phase: 4) // Ended
                self.isPinchActive = false
            }
            endPinchWorkItem = workItem
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.15, execute: workItem)

            // 2. Synthesize line-based scroll wheel with Command modifier for browsers/editors
            if let zoomEvent = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: Int32(steps * 2),
                wheel2: 0,
                wheel3: 0
            ) {
                zoomEvent.flags = .maskCommand
                zoomEvent.post(tap: .cghidEventTap)
            }
            return

        case .rightClick:
            // Two-finger tap or long press: context click at coordinates
            let screenX = currentBounds.origin.x + CGFloat(event.normalizedX) * currentBounds.width
            let screenY = currentBounds.origin.y + CGFloat(event.normalizedY) * currentBounds.height
            let point = CGPoint(x: screenX, y: screenY)
            CGWarpMouseCursorPosition(point)

            print("[Input] 🖱️ Right Click at (\(Int(screenX)), \(Int(screenY)))")

            if let down = CGEvent(
                mouseEventSource: nil,
                mouseType: .rightMouseDown,
                mouseCursorPosition: point,
                mouseButton: .right
            ), let up = CGEvent(
                mouseEventSource: nil,
                mouseType: .rightMouseUp,
                mouseCursorPosition: point,
                mouseButton: .right
            ) {
                down.setIntegerValueField(.mouseEventClickState, value: 1)
                up.setIntegerValueField(.mouseEventClickState, value: 1)
                down.post(tap: .cghidEventTap)
                DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.015) {
                    up.post(tap: .cghidEventTap)
                }
            }
            return

        case .missionControl:
            // 3-finger swipe UP: Mission Control
            print("[Input] ⚡️ Mission Control triggered!")
            let mcURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: mcURL, configuration: config, completionHandler: nil)
            synthesizeKeyShortcut(virtualKey: 0x7E, flags: .maskControl)
            return

        case .appExpose:
            // 3-finger swipe DOWN: Application Windows (Ctrl + Down Arrow)
            print("[Input] ⚡️ App Exposé triggered!")
            synthesizeKeyShortcut(virtualKey: 0x7D, flags: .maskControl)
            return

        case .swipeSpacesLeft:
            // 3-finger swipe RIGHT: Switch to space on the left (Ctrl + Left Arrow)
            print("[Input] ⚡️ Switch Space Left triggered!")
            synthesizeKeyShortcut(virtualKey: 0x7B, flags: .maskControl)
            return

        case .swipeSpacesRight:
            // 3-finger swipe LEFT: Switch to space on the right (Ctrl + Right Arrow)
            print("[Input] ⚡️ Switch Space Right triggered!")
            synthesizeKeyShortcut(virtualKey: 0x7C, flags: .maskControl)
            return

        case .down, .move, .up:
            break
        }
        
        let screenX = currentBounds.origin.x + CGFloat(event.normalizedX) * currentBounds.width
        let screenY = currentBounds.origin.y + CGFloat(event.normalizedY) * currentBounds.height
        let point = CGPoint(x: screenX, y: screenY)
        
        // Instantly warp system mouse pointer so clicks register under the touched element
        CGWarpMouseCursorPosition(point)
        
        var eventType: CGEventType
        let mouseButton: CGMouseButton = .left
        
        switch event.action {
        case .down:
            eventType = .leftMouseDown
            isDragging = true
        case .move:
            eventType = isDragging ? .leftMouseDragged : .mouseMoved
        case .up:
            eventType = .leftMouseUp
            isDragging = false
        default:
            return
        }
        
        guard let cgEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: eventType,
            mouseCursorPosition: point,
            mouseButton: mouseButton
        ) else { return }
        
        // Ensure single-click events register properly with macOS AppKit
        if eventType == .leftMouseDown || eventType == .leftMouseUp {
            cgEvent.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        
        // If it's a stylus / S-Pen, inject pressure value into the event
        if event.toolType == .stylus {
            cgEvent.setDoubleValueField(.mouseEventPressure, value: Double(event.pressure))
            cgEvent.setDoubleValueField(.tabletEventPointPressure, value: Double(event.pressure))
        }
        
        cgEvent.post(tap: .cghidEventTap)
    }

    private func postNativePinch(delta: Double, point: CGPoint, phase: Int64) {
        guard let event = CGEvent(source: nil) else { return }
        event.type = CGEventType(rawValue: 29)! // gesture
        event.setIntegerValueField(CGEventField(rawValue: 110)!, value: 8) // Zoom HID type
        event.setIntegerValueField(CGEventField(rawValue: 132)!, value: phase) // Began=1, Changed=2, Ended=4
        event.setDoubleValueField(CGEventField(rawValue: 113)!, value: delta) // Magnification
        event.location = point
        event.post(tap: .cghidEventTap)
    }

    private func synthesizeKeyShortcut(virtualKey: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.025) {
            up.post(tap: .cghidEventTap)
        }
    }
}
