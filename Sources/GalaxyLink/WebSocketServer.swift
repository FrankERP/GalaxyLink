import Foundation
import Network

final class WebSocketServer {
    private final class Client {
        let connection: NWConnection
        var queuedBytes = 0
        var policy = BackpressurePolicy()
        init(connection: NWConnection) { self.connection = connection }
    }

    var onClientConnected: (() -> Void)?
    var onKeyframeNeeded: (() -> Void)?
    var clientCount: Int { queue.sync { clients.count } }

    private let port: UInt16
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private var lastConfig: Data?
    private let queue = DispatchQueue(label: "galaxylink.ws")

    init(port: UInt16) { self.port = port }

    func start() throws {
        let params = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] conn in
            self?.queue.async { self?.accept(conn) }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            clients.values.forEach { $0.connection.cancel() }
            clients.removeAll()
            lastConfig = nil
        }
    }

    func resetBroadcastState() {
        queue.sync { lastConfig = nil }
    }

    func broadcastConfig(_ data: Data) {
        queue.async {
            self.lastConfig = data
            self.clients.values.forEach { self.send(data, to: $0) }
        }
    }

    func broadcastVideo(_ data: Data, isKeyframe: Bool) {
        queue.async {
            var keyframeNeeded = false
            for client in self.clients.values {
                let decision = client.policy.decide(isKeyframe: isKeyframe, queuedBytes: client.queuedBytes)
                if decision.send { self.send(data, to: client) }
                if decision.requestKeyframe { keyframeNeeded = true }
            }
            if keyframeNeeded { self.onKeyframeNeeded?() }
        }
    }

    // MARK: - private (all on `queue`)

    private func accept(_ conn: NWConnection) {
        let client = Client(connection: conn)
        clients[ObjectIdentifier(conn)] = client
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn else { return }
            switch state {
            case .ready:
                if let config = self.lastConfig { self.send(config, to: client) }
                self.onClientConnected?()
            case .failed, .cancelled:
                self.clients.removeValue(forKey: ObjectIdentifier(conn))
            default: break
            }
        }
        receiveLoop(client)
        conn.start(queue: queue)
    }

    private func receiveLoop(_ client: Client) {
        client.connection.receiveMessage { [weak self, weak client] _, _, _, error in
            guard let self, let client else { return }
            if error != nil {
                self.clients.removeValue(forKey: ObjectIdentifier(client.connection))
                client.connection.cancel()
                return
            }
            self.receiveLoop(client) // ignore inbound payloads for now (input events reserved)
        }
    }

    private func send(_ data: Data, to client: Client) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])
        client.queuedBytes += data.count
        client.connection.send(content: data, contentContext: context, isComplete: true,
                               completion: .contentProcessed { [weak self, weak client] _ in
            self?.queue.async { client?.queuedBytes -= data.count }
        })
    }
}
