import Foundation
import Network

public final class TCPServer {
    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []
    private var latestVideoPacket: Data?
    private let queue = DispatchQueue(label: "com.display.tcpServer", qos: .userInteractive)
    private let port: UInt16
    
    public var onInputEventReceived: ((TabletInputEvent) -> Void)?
    public var onOrientationChanged: ((UInt32, UInt32) -> Void)?
    public var onClientConnected: (() -> Void)?
    public var onClientDisconnected: (() -> Void)?
    
    public init(port: UInt16 = 8080) {
        self.port = port
    }
    
    public func start() throws {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.allowFastOpen = true
        
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let listener = try NWListener(using: params, on: nwPort)
        
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[Server] TCP Server listening on port \(self.port). Ready for Android tablet connection!")
            case .failed(let error):
                print("[Server] TCP Server failed with error: \(error)")
            default:
                break
            }
        }
        
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener.start(queue: queue)
        self.listener = listener
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        print("[Server] New connection received from: \(connection.endpoint)")
        connection.start(queue: queue)
        activeConnections.append(connection)
        
        if let initialPacket = latestVideoPacket {
            connection.send(content: initialPacket, completion: .contentProcessed { _ in })
        }
        
        onClientConnected?()
        receiveNextPacket(from: connection)
    }
    
    private func receiveNextPacket(from connection: NWConnection) {
        // First read packet type (1 byte)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] content, _, isComplete, error in
            guard let self = self, let content = content, !content.isEmpty else {
                if isComplete || error != nil {
                    self?.removeConnection(connection)
                }
                return
            }
            
            let packetType = content[0]
            if packetType == PacketType.inputEvent.rawValue {
                // Input event is 14 bytes
                connection.receive(minimumIncompleteLength: 14, maximumLength: 14) { inputData, _, _, _ in
                    if let inputData = inputData, let event = TabletInputEvent.parse(from: inputData) {
                        self.onInputEventReceived?(event)
                    }
                    self.receiveNextPacket(from: connection)
                }
            } else if packetType == PacketType.orientationChange.rawValue {
                // Orientation change is 8 bytes: [4 bytes width][4 bytes height]
                connection.receive(minimumIncompleteLength: 8, maximumLength: 8) { [weak self] orientData, _, _, _ in
                    if let orientData = orientData, let event = OrientationChangeEvent.parse(from: orientData) {
                        self?.onOrientationChanged?(event.width, event.height)
                    }
                    self?.receiveNextPacket(from: connection)
                }
            } else {
                // Unknown packet, continue receiving
                self.receiveNextPacket(from: connection)
            }
        }
    }
    
    public func sendVideoFrame(naluData: Data, isHEVC: Bool = false) {
        var packet = Data(capacity: 5 + naluData.count)
        // 1 byte packet type (0x04 for HEVC / H.265, 0x01 for H.264)
        packet.append(isHEVC ? PacketType.videoFrameHEVC.rawValue : PacketType.videoFrameH264.rawValue)
        // 4 bytes payload length (big-endian)
        var length = UInt32(naluData.count).bigEndian
        packet.append(Data(bytes: &length, count: 4))
        // Video payload
        packet.append(naluData)
        
        self.latestVideoPacket = packet
        guard !activeConnections.isEmpty else { return }
        
        for conn in activeConnections {
            conn.send(content: packet, completion: .contentProcessed { [weak self] error in
                if let error = error {
                    print("[Server] Send error: \(error)")
                    self?.removeConnection(conn)
                }
            })
        }
    }
    
    public func sendAudioFrame(pcmData: Data) {
        guard !activeConnections.isEmpty else { return }
        
        var packet = Data(capacity: 5 + pcmData.count)
        // 1 byte packet type
        packet.append(PacketType.audioFrame.rawValue)
        // 4 bytes payload length (big-endian)
        var length = UInt32(pcmData.count).bigEndian
        packet.append(Data(bytes: &length, count: 4))
        // Audio payload
        packet.append(pcmData)
        
        for conn in activeConnections {
            conn.send(content: packet, completion: .contentProcessed { [weak self] error in
                if let error = error {
                    print("[Server] Audio send error: \(error)")
                    self?.removeConnection(conn)
                }
            })
        }
    }
    
    private func removeConnection(_ connection: NWConnection) {
        connection.cancel()
        activeConnections.removeAll { $0 === connection }
        print("[Server] Client disconnected. Active clients: \(activeConnections.count)")
        if activeConnections.isEmpty {
            onClientDisconnected?()
        }
    }
    
    public func stop() {
        listener?.cancel()
        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
    }
}
