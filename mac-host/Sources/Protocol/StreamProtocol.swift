import Foundation

public enum PacketType: UInt8 {
    case videoFrame = 0x01
    case displayInfo = 0x02
    case inputEvent = 0x10
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
