import Foundation
import CoreGraphics

public final class InputSynthesizer {
    private let targetDisplayBounds: CGRect
    
    public init(displayBounds: CGRect = CGDisplayBounds(CGMainDisplayID())) {
        self.targetDisplayBounds = displayBounds
    }
    
    public func handleInput(event: TabletInputEvent) {
        let screenX = targetDisplayBounds.origin.x + CGFloat(event.normalizedX) * targetDisplayBounds.width
        let screenY = targetDisplayBounds.origin.y + CGFloat(event.normalizedY) * targetDisplayBounds.height
        let point = CGPoint(x: screenX, y: screenY)
        
        var eventType: CGEventType
        var mouseButton: CGMouseButton = .left
        
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
            cgEvent.setDoubleValueField(.tabletPointPressure, Double(event.pressure))
        }
        
        cgEvent.post(tap: .cghidEventTap)
    }
}
