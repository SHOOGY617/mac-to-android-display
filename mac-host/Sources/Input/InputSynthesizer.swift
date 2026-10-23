import Foundation
import CoreGraphics

public final class InputSynthesizer {
    private var targetDisplayBounds: CGRect
    private var targetDisplayID: CGDirectDisplayID?
    
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
        let screenX = currentBounds.origin.x + CGFloat(event.normalizedX) * currentBounds.width
        let screenY = currentBounds.origin.y + CGFloat(event.normalizedY) * currentBounds.height
        let point = CGPoint(x: screenX, y: screenY)
        
        var eventType: CGEventType
        let mouseButton: CGMouseButton = .left
        
        switch event.action {
        case .down:
            eventType = .leftMouseDown
        case .move:
            eventType = .leftMouseDragged
        case .up:
            eventType = .leftMouseUp
        }
        
        guard let cgEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: eventType,
            mouseCursorPosition: point,
            mouseButton: mouseButton
        ) else { return }
        
        // If it's a stylus / S-Pen, inject pressure value into the event
        if event.toolType == .stylus {
            cgEvent.setDoubleValueField(.mouseEventPressure, value: Double(event.pressure))
            cgEvent.setDoubleValueField(.tabletEventPointPressure, value: Double(event.pressure))
        }
        
        cgEvent.post(tap: .cghidEventTap)
    }
}
