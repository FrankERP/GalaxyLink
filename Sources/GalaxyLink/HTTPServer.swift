import Foundation
import Network

struct HTTPRequest: Equatable {
    let method: String
    let path: String
}

enum HTTPCodec {
    static func parseRequest(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
        let parts = head.split(separator: "\r\n")[0].split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return HTTPRequest(method: String(parts[0]), path: String(parts[1]))
    }

    static func contentType(forPath path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "text/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        case "webmanifest": return "application/manifest+json"
        case "png": return "image/png"
        case "svg": return "image/svg+xml"
        default: return "application/octet-stream"
        }
    }

    static func response(status: String, contentType: String, body: Data) -> Data {
        var out = Data("HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        out.append(body)
        return out
    }
}

final class HTTPServer {
    private let port: UInt16
    private let webRoot: URL
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "galaxylink.http")

    init(port: UInt16, webRoot: URL) {
        self.port = port
        self.webRoot = webRoot
    }

    func start() throws {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            conn.start(queue: self.queue)
            self.receive(on: conn, buffer: Data())
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func receive(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, error in
            guard let self, error == nil else { conn.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = HTTPCodec.parseRequest(buffer) {
                let response = self.makeResponse(for: request)
                conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
            } else if done || buffer.count > 64 * 1024 {
                conn.cancel()
            } else {
                self.receive(on: conn, buffer: buffer)
            }
        }
    }

    private func makeResponse(for request: HTTPRequest) -> Data {
        let rawPath = request.path.split(separator: "?")[0]
        let path = rawPath == "/" ? "/index.html" : String(rawPath)
        let file = webRoot.appendingPathComponent(path).standardizedFileURL
        guard request.method == "GET",
              file.path.hasPrefix(webRoot.standardizedFileURL.path),
              let body = try? Data(contentsOf: file) else {
            return HTTPCodec.response(status: "404 Not Found", contentType: "text/plain", body: Data("not found".utf8))
        }
        return HTTPCodec.response(status: "200 OK", contentType: HTTPCodec.contentType(forPath: path), body: body)
    }
}
