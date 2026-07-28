import XCTest
@testable import GalaxyLink

final class HTTPServerTests: XCTestCase {
    func testParseIncompleteReturnsNil() {
        XCTAssertNil(HTTPCodec.parseRequest(Data("GET / HTTP/1.1\r\nHost: x".utf8)))
    }

    func testParseCompleteRequest() {
        let req = HTTPCodec.parseRequest(Data("GET /client.js HTTP/1.1\r\nHost: x\r\n\r\n".utf8))
        XCTAssertEqual(req, HTTPRequest(method: "GET", path: "/client.js"))
    }

    func testContentTypes() {
        XCTAssertEqual(HTTPCodec.contentType(forPath: "/index.html"), "text/html; charset=utf-8")
        XCTAssertEqual(HTTPCodec.contentType(forPath: "/client.js"), "text/javascript")
        XCTAssertEqual(HTTPCodec.contentType(forPath: "/manifest.webmanifest"), "application/manifest+json")
        XCTAssertEqual(HTTPCodec.contentType(forPath: "/icon-192.png"), "image/png")
        XCTAssertEqual(HTTPCodec.contentType(forPath: "/x.bin"), "application/octet-stream")
    }

    func testServesFileOverTCP() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("glhttp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("<h1>hi</h1>".utf8).write(to: dir.appendingPathComponent("index.html"))

        let port = UInt16.random(in: 20000...40000)
        let server = HTTPServer(port: port, webRoot: dir)
        try server.start()
        defer { server.stop() }
        try await Task.sleep(nanoseconds: 200_000_000)

        let (data, resp) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/")!)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "<h1>hi</h1>")

        let (_, resp404) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/nope")!)
        XCTAssertEqual((resp404 as? HTTPURLResponse)?.statusCode, 404)
    }

    func testServesRealBundledWebClient() async throws {
        let webRoot = try XCTUnwrap(WebRoot.url(), "web resources missing from bundle")
        let port = UInt16.random(in: 20000...40000)
        let server = HTTPServer(port: port, webRoot: webRoot)
        try server.start()
        defer { server.stop() }
        try await Task.sleep(nanoseconds: 200_000_000)

        for (path, expectedType) in [("/", "text/html; charset=utf-8"),
                                     ("/client.js", "text/javascript"),
                                     ("/manifest.webmanifest", "application/manifest+json"),
                                     ("/icon-192.png", "image/png")] {
            let (data, resp) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)\(path)")!)
            let http = try XCTUnwrap(resp as? HTTPURLResponse)
            XCTAssertEqual(http.statusCode, 200, "path \(path)")
            XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Type"), expectedType, "path \(path)")
            XCTAssertFalse(data.isEmpty, "path \(path)")
        }
    }
}
