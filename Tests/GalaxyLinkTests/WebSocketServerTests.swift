import XCTest
@testable import GalaxyLink

final class WebSocketServerTests: XCTestCase {
    func testClientReceivesConfigThenVideo() async throws {
        let port = UInt16.random(in: 20000...40000)
        let server = WebSocketServer(port: port)
        try server.start()
        defer { server.stop() }
        server.broadcastConfig(Data([0x01, 0x7B, 0x7D])) // set before client joins
        try await Task.sleep(nanoseconds: 200_000_000)

        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)")!)
        task.resume()

        // late joiner still gets the remembered config frame
        let first = try await task.receive()
        guard case .data(let cfg) = first else { return XCTFail("expected data") }
        XCTAssertEqual(cfg.first, 0x01)

        server.broadcastVideo(Data([0x02, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0xAB]), isKeyframe: true)
        let second = try await task.receive()
        guard case .data(let video) = second else { return XCTFail("expected data") }
        XCTAssertEqual(video.first, 0x02)
        XCTAssertEqual(video.last, 0xAB)
        task.cancel(with: .normalClosure, reason: nil)
    }

    func testOnClientConnectedFires() async throws {
        let port = UInt16.random(in: 20000...40000)
        let server = WebSocketServer(port: port)
        let exp = expectation(description: "connected")
        server.onClientConnected = { exp.fulfill() }
        try server.start()
        defer { server.stop() }
        try await Task.sleep(nanoseconds: 200_000_000)

        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)")!)
        task.resume()
        await fulfillment(of: [exp], timeout: 5)
        task.cancel(with: .normalClosure, reason: nil)
    }
}
