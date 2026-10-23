import Foundation
import CoreGraphics
import AppKit

typealias CGSConnectionID = Int32
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?

@_silgen_name("CGSManagedDisplaySetCurrentSpace")
func CGSManagedDisplaySetCurrentSpace(_ cid: CGSConnectionID, _ displayUUID: CFString, _ spaceID: UInt64) -> Int32

public final class InputSynthesizer {
    private var targetDisplayBounds: CGRect
    private var targetDisplayID: CGDirectDisplayID?
    private var isDragging = false
    private var isPinchActive = false
    private var endPinchWorkItem: DispatchWorkItem?
    public var onSpaceChanged: (() -> Void)?
    
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

            // Native Apple trackpad gesture event (Type 29, field 110=8, field 132=phase, field 113=delta)
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
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.12, execute: workItem)
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
            let centerPoint = CGPoint(x: currentBounds.midX, y: currentBounds.midY)
            CGWarpMouseCursorPosition(centerPoint)
            print("[Input] ⚡️ Mission Control triggered on target display!")
            let mcURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: mcURL, configuration: config, completionHandler: nil)
            synthesizeKeyShortcut(virtualKey: 0x7E, flags: .maskControl)
            return

        case .appExpose:
            // 3-finger swipe DOWN: Application Windows or dismiss Mission Control
            let centerPoint = CGPoint(x: currentBounds.midX, y: currentBounds.midY)
            CGWarpMouseCursorPosition(centerPoint)
            print("[Input] ⚡️ 3-finger Swipe Down triggered!")

            // 1. Send Escape key (0x35) to dismiss Mission Control if it was open
            let src = CGEventSource(stateID: .hidSystemState)
            if let escDown = CGEvent(keyboardEventSource: src, virtualKey: 0x35, keyDown: true),
               let escUp = CGEvent(keyboardEventSource: src, virtualKey: 0x35, keyDown: false) {
                escDown.post(tap: .cghidEventTap)
                escUp.post(tap: .cghidEventTap)
            }

            // 2. Synthesize proper Control + Down Arrow sequence with physical modifier state
            let ctrlKey: CGKeyCode = 0x3B
            let downArrow: CGKeyCode = 0x7D
            if let cDown = CGEvent(keyboardEventSource: src, virtualKey: ctrlKey, keyDown: true),
               let dDown = CGEvent(keyboardEventSource: src, virtualKey: downArrow, keyDown: true),
               let dUp = CGEvent(keyboardEventSource: src, virtualKey: downArrow, keyDown: false),
               let cUp = CGEvent(keyboardEventSource: src, virtualKey: ctrlKey, keyDown: false) {
                cDown.flags = .maskControl
                dDown.flags = .maskControl
                dUp.flags = .maskControl
                cUp.flags = []
                cDown.post(tap: .cghidEventTap)
                dDown.post(tap: .cghidEventTap)
                DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.03) {
                    dUp.post(tap: .cghidEventTap)
                    cUp.post(tap: .cghidEventTap)
                }
            }
            return

        case .swipeSpacesLeft:
            // 3-finger swipe RIGHT: Switch to space on the left
            print("[Input] ⚡️ Switch Space Left triggered!")
            let centerPoint = CGPoint(x: currentBounds.midX, y: currentBounds.midY)
            CGWarpMouseCursorPosition(centerPoint)
            if !switchSpaceOnDisplay(targetBounds: currentBounds, direction: -1) {
                synthesizeKeyShortcut(virtualKey: 0x7B, flags: .maskControl)
            }
            return

        case .swipeSpacesRight:
            // 3-finger swipe LEFT: Switch to space on the right
            print("[Input] ⚡️ Switch Space Right triggered!")
            let centerPoint = CGPoint(x: currentBounds.midX, y: currentBounds.midY)
            CGWarpMouseCursorPosition(centerPoint)
            if !switchSpaceOnDisplay(targetBounds: currentBounds, direction: 1) {
                synthesizeKeyShortcut(virtualKey: 0x7C, flags: .maskControl)
            }
            return

        case .down, .move, .up:
            break
        }
        
        let screenX = currentBounds.origin.x + CGFloat(event.normalizedX) * currentBounds.width
        let screenY = currentBounds.origin.y + CGFloat(event.normalizedY) * currentBounds.height
        let point = CGPoint(x: screenX, y: screenY)
        
        var eventType: CGEventType
        let mouseButton: CGMouseButton = .left
        
        switch event.action {
        case .down:
            eventType = .leftMouseDown
            isDragging = true
            // Instantly snap system mouse pointer to initial touch coordinate
            CGWarpMouseCursorPosition(point)
        case .move:
            eventType = isDragging ? .leftMouseDragged : .mouseMoved
            // Do NOT call CGWarpMouseCursorPosition on move: posting cgEvent with mouseCursorPosition
            // allows macOS WindowServer to compute smooth deltas and apply native trackpad/mouse acceleration curves!
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

    private func switchSpaceOnDisplay(targetBounds: CGRect, direction: Int) -> Bool {
        let cid = CGSMainConnectionID()
        guard let displays = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else { return false }

        for d in displays {
            let displayUUID = d["Display Identifier"] as? String ?? ""
            var matches = false
            if let currentDict = d["Current Space"] as? [String: Any],
               let layout = currentDict["TileLayoutManager"] as? [String: Any],
               let rect = layout["Layout Rect"] as? [String: Any],
               let x = rect["X"] as? Double,
               let y = rect["Y"] as? Double {
                if abs(x - Double(targetBounds.origin.x)) < 5 && abs(y - Double(targetBounds.origin.y)) < 5 {
                    matches = true
                }
            }
            
            // Fallback for secondary display
            if !matches && displays.count >= 2 && d as NSDictionary != displays[0] as NSDictionary {
                matches = true
            }

            guard matches else { continue }

            guard let spaces = d["Spaces"] as? [[String: Any]],
                  let currentDict = d["Current Space"] as? [String: Any],
                  let currentID = currentDict["ManagedSpaceID"] as? UInt64 else { continue }

            guard let currentIndex = spaces.firstIndex(where: { ($0["ManagedSpaceID"] as? UInt64) == currentID }) else { continue }

            var nextIndex = currentIndex + direction
            if nextIndex < 0 {
                nextIndex = spaces.count - 1
            } else if nextIndex >= spaces.count {
                nextIndex = 0
            }

            guard nextIndex != currentIndex else {
                print("[Input] Only 1 space on display \(displayUUID), nothing to switch to.")
                return false
            }

            if let nextSpaceID = spaces[nextIndex]["ManagedSpaceID"] as? UInt64 {
                let res = CGSManagedDisplaySetCurrentSpace(cid, displayUUID as CFString, nextSpaceID)
                print("[Input] 🚀 Switched space on display \(displayUUID) from \(currentIndex) to \(nextIndex) (ID: \(nextSpaceID), res: \(res))")
                if res == 0 {
                    onSpaceChanged?()
                    return true
                }
            }
        }
        return false
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
