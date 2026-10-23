import Foundation

public enum PacketType: UInt8 {
    case videoFrameH264 = 0x01
    case displayInfo = 0x02
    case audioFrame = 0x03
    case videoFrameHEVC = 0x04
    case inputEvent = 0x10
    case orientationChange = 0x11
}

public struct OrientationChangeEvent {
    public let width: UInt32
    public let height: UInt32
    
    public static func parse(from data: Data) -> OrientationChangeEvent? {
        guard data.count >= 8 else { return nil }
        let w = UInt32(bigEndian: data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) })
        let h = UInt32(bigEndian: data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) })
        return OrientationChangeEvent(width: w, height: h)
    }
}

public enum InputToolType: UInt8 {
    case finger = 0
    case stylus = 1
}

public enum InputAction: UInt8 {
    case down = 0
    case move = 1
    case up = 2
    case scroll = 3
    case rightClick = 4
    case magnify = 5
    case missionControl = 6
    case appExpose = 7
    case swipeSpacesLeft = 8
    case swipeSpacesRight = 9
}

public struct TabletInputEvent {
    public let action: InputAction
    public let normalizedX: Float
    public let normalizedY: Float
    public let pressure: Float
    public let toolType: InputToolType

    public static func parse(from data: Data) -> TabletInputEvent? {
        // [1 byte action][4 bytes float X][4 bytes float Y][4 bytes float Pressure][1 byte toolType] = 14 bytes
        guard data.count >= 14 else { return nil }
        
        let actionRaw = data[data.startIndex]
        guard let action = InputAction(rawValue: actionRaw) else { return nil }
        
        var xBits: UInt32 = 0
        var yBits: UInt32 = 0
        var pBits: UInt32 = 0
        
        let start = data.startIndex
        xBits = UInt32(bigEndian: data.subdata(in: (start + 1)..<(start + 5)).withUnsafeBytes { $0.load(as: UInt32.self) })
        yBits = UInt32(bigEndian: data.subdata(in: (start + 5)..<(start + 9)).withUnsafeBytes { $0.load(as: UInt32.self) })
        pBits = UInt32(bigEndian: data.subdata(in: (start + 9)..<(start + 13)).withUnsafeBytes { $0.load(as: UInt32.self) })
        
        let toolRaw = data[start + 13]
        let toolType = InputToolType(rawValue: toolRaw) ?? .finger
        
        return TabletInputEvent(
            action: action,
            normalizedX: Float(bitPattern: xBits),
            normalizedY: Float(bitPattern: yBits),
            pressure: Float(bitPattern: pBits),
            toolType: toolType
        )
    }
}
