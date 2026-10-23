import Foundation
import Network

public final class TCPServer {
    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.display.tcpServer", qos: .userInteractive)
    private let port: UInt16
    
    public var onInputEventReceived: ((TabletInputEvent) -> Void)?
    
    public init(port: UInt16 = 8080) {
        self.port = port
    }
    
    public func start() throws {
        let params = NWParameters.tcp
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
            } else {
                // Unknown packet, continue receiving
                self.receiveNextPacket(from: connection)
            }
        }
    }
    
    public func sendVideoFrame(naluData: Data) {
        guard !activeConnections.isEmpty else { return }
        
        var packet = Data()
        // 1 byte packet type
        packet.append(PacketType.videoFrame.rawValue)
        // 4 bytes payload length (big-endian)
        var length = UInt32(naluData.count).bigEndian
        packet.append(Data(bytes: &length, count: 4))
        // Video payload
        packet.append(naluData)
        
        for conn in activeConnections {
            conn.send(content: packet, completion: .contentProcessed { [weak self] error in
                if let error = error {
                    print("[Server] Send error: \(error)")
                    self?.removeConnection(conn)
                }
            })
        }
    }
    
    private func removeConnection(_ connection: NWConnection) {
        connection.cancel()
        activeConnections.removeAll { $0 === connection }
        print("[Server] Client disconnected. Active clients: \(activeConnections.count)")
    }
    
    public func stop() {
        listener?.cancel()
        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
    }
}
