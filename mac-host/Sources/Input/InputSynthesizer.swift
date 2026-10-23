import Foundation
import CoreGraphics

public final class InputSynthesizer {
    private var targetDisplayBounds: CGRect
    private var targetDisplayID: CGDirectDisplayID?
    private var isDragging = false
    
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
        
        if event.action == .scroll {
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
        case .scroll:
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
}
