# GalaxyLink Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu-bar app that turns a Samsung Galaxy Tab S10 Ultra into a second monitor: virtual display → ScreenCaptureKit → H.264 → WebSocket → browser page with WebCodecs.

**Architecture:** Swift Package (no Xcode project) with a C shim target exposing the private `CGVirtualDisplay` API. Capture via ScreenCaptureKit, encode via VideoToolbox low-latency H.264, serve a static web client over HTTP (port 8080) and stream Annex-B frames over a WebSocket (port 8081) using Network.framework. Tablet client is one static HTML/JS page using WebCodecs `VideoDecoder` → canvas.

**Tech Stack:** Swift 5.9+, AppKit (NSStatusItem), ScreenCaptureKit, VideoToolbox, Network.framework, CoreImage (QR), vanilla JS + WebCodecs. Zero third-party dependencies.

## Global Constraints

- Platform floor: macOS 14 (`platforms: [.macOS(.v14)]`).
- No third-party dependencies anywhere (SwiftPM dependencies list stays empty).
- Ports: HTTP `8080`, WebSocket `8081` (both hardcoded constants in `Ports.swift`).
- Default display geometry: 2960×1848 pixels, HiDPI (shows as 1480×924 points), 60 fps, 15 Mbps.
- Video codec: H.264 Annex-B on the wire; keyframes carry SPS/PPS in-band; WebCodecs client configures **without** `description` (Annex-B mode).
- Binary protocol frame types: `0x01` CONFIG, `0x02` VIDEO; `0x10+` reserved for future input events. All multi-byte integers little-endian.
- Everything user-facing says "GalaxyLink".
- No secrets/env vars in this project (nothing to document under the global secrets rule; if one is ever added, create `docs/SECRETS.md` per user global CLAUDE.md).
- Tests: `swift test` must pass after every task. Pipeline pieces that need TCC permission or a display are verified by CLI probe modes, not unit tests.

---

### Task 1: Package scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/CGVirtualDisplayShim/include/CGVirtualDisplayShim.h`
- Create: `Sources/CGVirtualDisplayShim/shim.c`
- Create: `Sources/GalaxyLink/main.swift`
- Create: `Tests/GalaxyLinkTests/SmokeTests.swift`
- Create: `.gitignore`

**Interfaces:**
- Produces: buildable SwiftPM executable `GalaxyLink`, library target `CGVirtualDisplayShim` (Obj-C headers for the private API), test target.

- [ ] **Step 1: Write files**

`Package.swift`:
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GalaxyLink",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CGVirtualDisplayShim", publicHeadersPath: "include"),
        .executableTarget(
            name: "GalaxyLink",
            dependencies: ["CGVirtualDisplayShim"],
            resources: [.copy("Resources/web")]
        ),
        .testTarget(name: "GalaxyLinkTests", dependencies: ["GalaxyLink"]),
    ]
)
```

`Sources/CGVirtualDisplayShim/include/CGVirtualDisplayShim.h` (private API declarations, same shape FluffyDisplay/Deskreen use):
```objc
#ifndef CGVirtualDisplayShim_h
#define CGVirtualDisplayShim_h
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class CGVirtualDisplay;

@interface CGVirtualDisplayDescriptor : NSObject
@property(strong, nonatomic) dispatch_queue_t queue;
@property(strong, nonatomic) NSString *name;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) CGPoint redPrimary;
@property(nonatomic) CGPoint greenPrimary;
@property(nonatomic) CGPoint bluePrimary;
@property(nonatomic) CGPoint whitePoint;
@property(copy, nonatomic) void (^terminationHandler)(id, CGVirtualDisplay *);
@property(nonatomic) unsigned int vendorID;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int serialNum;
- (instancetype)init;
@end

@interface CGVirtualDisplayMode : NSObject
@property(readonly, nonatomic) unsigned int width;
@property(readonly, nonatomic) unsigned int height;
@property(readonly, nonatomic) double refreshRate;
- (instancetype)initWithWidth:(unsigned int)width
                       height:(unsigned int)height
                  refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(strong, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
@property(nonatomic) unsigned int hiDPI;
- (instancetype)init;
@end

@interface CGVirtualDisplay : NSObject
@property(readonly, nonatomic) CGDirectDisplayID displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

#endif
```

`Sources/CGVirtualDisplayShim/shim.c`:
```c
// SwiftPM requires at least one compiled source in a C target.
// The header declares private CoreGraphics classes; nothing to compile.
int galaxylink_shim_unused = 0;
```

`Sources/GalaxyLink/main.swift`:
```swift
print("GalaxyLink scaffold")
```

`Tests/GalaxyLinkTests/SmokeTests.swift`:
```swift
import XCTest

final class SmokeTests: XCTestCase {
    func testSmoke() { XCTAssertTrue(true) }
}
```

`.gitignore`:
```
.build/
.DS_Store
```

Also create an empty resources dir placeholder so the package builds: `Sources/GalaxyLink/Resources/web/.gitkeep` (empty file).

- [ ] **Step 2: Build and test**

Run: `swift build && swift test`
Expected: build succeeds; 1 test passes.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "chore: SwiftPM scaffold with CGVirtualDisplay shim target"
```

---

### Task 2: Binary stream protocol

**Files:**
- Create: `Sources/GalaxyLink/Ports.swift`
- Create: `Sources/GalaxyLink/StreamProtocol.swift`
- Test: `Tests/GalaxyLinkTests/StreamProtocolTests.swift`

**Interfaces:**
- Produces:
  - `enum Ports { static let http: UInt16 = 8080; static let ws: UInt16 = 8081 }`
  - `StreamProtocol.configFrame(codec: String, width: Int, height: Int, fps: Int) -> Data`
  - `StreamProtocol.videoFrame(annexB: Data, isKeyframe: Bool, timestampMicros: UInt64) -> Data`
  - Wire layout: CONFIG = `[0x01][UTF-8 JSON {"codec","width","height","fps"}]`; VIDEO = `[0x02][flags: bit0 keyframe][timestampMicros u64 LE][payload]` (header = 10 bytes).

- [ ] **Step 1: Write failing tests**

`Tests/GalaxyLinkTests/StreamProtocolTests.swift`:
```swift
import XCTest
@testable import GalaxyLink

final class StreamProtocolTests: XCTestCase {
    func testConfigFrame() throws {
        let frame = StreamProtocol.configFrame(codec: "avc1.4D0028", width: 2960, height: 1848, fps: 60)
        XCTAssertEqual(frame[0], 0x01)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: frame.dropFirst()) as? [String: Any])
        XCTAssertEqual(json["codec"] as? String, "avc1.4D0028")
        XCTAssertEqual(json["width"] as? Int, 2960)
        XCTAssertEqual(json["height"] as? Int, 1848)
        XCTAssertEqual(json["fps"] as? Int, 60)
    }

    func testVideoFrameKeyframe() {
        let payload = Data([0x00, 0x00, 0x00, 0x01, 0x65, 0xAA])
        let frame = StreamProtocol.videoFrame(annexB: payload, isKeyframe: true, timestampMicros: 0x0102030405060708)
        XCTAssertEqual(frame[0], 0x02)
        XCTAssertEqual(frame[1], 0x01)
        // little-endian u64
        XCTAssertEqual(Array(frame[2..<10]), [0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01])
        XCTAssertEqual(Data(frame[10...]), payload)
    }

    func testVideoFrameDelta() {
        let frame = StreamProtocol.videoFrame(annexB: Data([0x61]), isKeyframe: false, timestampMicros: 0)
        XCTAssertEqual(frame[1], 0x00)
        XCTAssertEqual(frame.count, 11)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter StreamProtocolTests`
Expected: compile FAILS ("cannot find 'StreamProtocol'").

- [ ] **Step 3: Implement**

`Sources/GalaxyLink/Ports.swift`:
```swift
enum Ports {
    static let http: UInt16 = 8080
    static let ws: UInt16 = 8081
}
```

`Sources/GalaxyLink/StreamProtocol.swift`:
```swift
import Foundation

enum FrameType: UInt8 {
    case config = 0x01
    case video = 0x02
}

enum StreamProtocol {
    static func configFrame(codec: String, width: Int, height: Int, fps: Int) -> Data {
        let json: [String: Any] = ["codec": codec, "width": width, "height": height, "fps": fps]
        var data = Data([FrameType.config.rawValue])
        data.append(try! JSONSerialization.data(withJSONObject: json))
        return data
    }

    static func videoFrame(annexB: Data, isKeyframe: Bool, timestampMicros: UInt64) -> Data {
        var data = Data(capacity: annexB.count + 10)
        data.append(FrameType.video.rawValue)
        data.append(isKeyframe ? 0x01 : 0x00)
        withUnsafeBytes(of: timestampMicros.littleEndian) { data.append(contentsOf: $0) }
        data.append(annexB)
        return data
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter StreamProtocolTests`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: binary stream protocol (CONFIG/VIDEO frames)"
```

---

### Task 3: AVC helpers (AVCC→Annex-B, codec string, parameter-set prefix)

**Files:**
- Create: `Sources/GalaxyLink/AVC.swift`
- Test: `Tests/GalaxyLinkTests/AVCTests.swift`

**Interfaces:**
- Produces:
  - `AVC.annexB(fromAVCC: Data, nalLengthSize: Int) -> Data` — converts length-prefixed NALs to `00 00 00 01`-prefixed.
  - `AVC.codecString(sps: Data) -> String` — SPS **including** its NAL header byte → `"avc1.PPCCLL"` (hex of bytes 1..3).
  - `AVC.parameterSetPrefix(sps: Data, pps: Data) -> Data` — `00 00 00 01 <sps> 00 00 00 01 <pps>`.

- [ ] **Step 1: Write failing tests**

`Tests/GalaxyLinkTests/AVCTests.swift`:
```swift
import XCTest
@testable import GalaxyLink

final class AVCTests: XCTestCase {
    func testAnnexBConversionTwoNALs() {
        // Two NALs, 4-byte lengths: [len=2][0x65 0x88], [len=1][0x41]
        let avcc = Data([0, 0, 0, 2, 0x65, 0x88, 0, 0, 0, 1, 0x41])
        let annexB = AVC.annexB(fromAVCC: avcc, nalLengthSize: 4)
        XCTAssertEqual(annexB, Data([0, 0, 0, 1, 0x65, 0x88, 0, 0, 0, 1, 0x41]))
    }

    func testAnnexBTruncatedInputStopsCleanly() {
        // Declared length 10 but only 2 bytes follow — must not crash, drops the bad NAL
        let avcc = Data([0, 0, 0, 10, 0x65, 0x88])
        XCTAssertEqual(AVC.annexB(fromAVCC: avcc, nalLengthSize: 4), Data())
    }

    func testCodecString() {
        // NAL header 0x67, profile 0x64 (High), compat 0x00, level 0x28 (4.0)
        let sps = Data([0x67, 0x64, 0x00, 0x28, 0xAC])
        XCTAssertEqual(AVC.codecString(sps: sps), "avc1.640028")
    }

    func testParameterSetPrefix() {
        let prefix = AVC.parameterSetPrefix(sps: Data([0x67, 0x4D]), pps: Data([0x68, 0xEE]))
        XCTAssertEqual(prefix, Data([0, 0, 0, 1, 0x67, 0x4D, 0, 0, 0, 1, 0x68, 0xEE]))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter AVCTests`
Expected: compile FAILS ("cannot find 'AVC'").

- [ ] **Step 3: Implement**

`Sources/GalaxyLink/AVC.swift`:
```swift
import Foundation

enum AVC {
    static let startCode = Data([0x00, 0x00, 0x00, 0x01])

    static func annexB(fromAVCC data: Data, nalLengthSize: Int) -> Data {
        var out = Data(capacity: data.count + 16)
        var offset = data.startIndex
        while offset + nalLengthSize <= data.endIndex {
            var length = 0
            for i in 0..<nalLengthSize { length = (length << 8) | Int(data[offset + i]) }
            offset += nalLengthSize
            guard length > 0, offset + length <= data.endIndex else { break }
            out.append(startCode)
            out.append(data[offset..<(offset + length)])
            offset += length
        }
        return out
    }

    static func codecString(sps: Data) -> String {
        guard sps.count >= 4 else { return "avc1.42E01F" }
        let b = Array(sps)
        return String(format: "avc1.%02X%02X%02X", b[1], b[2], b[3])
    }

    static func parameterSetPrefix(sps: Data, pps: Data) -> Data {
        var out = Data()
        out.append(startCode); out.append(sps)
        out.append(startCode); out.append(pps)
        return out
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AVCTests`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: AVC helpers (AVCC->AnnexB, codec string, SPS/PPS prefix)"
```

---

### Task 4: Backpressure policy

**Files:**
- Create: `Sources/GalaxyLink/BackpressurePolicy.swift`
- Test: `Tests/GalaxyLinkTests/BackpressurePolicyTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct BackpressurePolicy {
      init(highWatermark: Int = 3_000_000, lowWatermark: Int = 500_000)
      mutating func decide(isKeyframe: Bool, queuedBytes: Int) -> Decision
  }
  struct Decision: Equatable { let send: Bool; let requestKeyframe: Bool }
  ```
- State machine: `normal` (send everything) → queued > high → `dropping` (send nothing) → queued < low → emit `requestKeyframe`, enter `awaitingKeyframe` (drop deltas, send+resume on next keyframe).

- [ ] **Step 1: Write failing tests**

`Tests/GalaxyLinkTests/BackpressurePolicyTests.swift`:
```swift
import XCTest
@testable import GalaxyLink

final class BackpressurePolicyTests: XCTestCase {
    func testNormalSendsEverything() {
        var p = BackpressurePolicy(highWatermark: 100, lowWatermark: 10)
        XCTAssertEqual(p.decide(isKeyframe: false, queuedBytes: 0), Decision(send: true, requestKeyframe: false))
        XCTAssertEqual(p.decide(isKeyframe: true, queuedBytes: 50), Decision(send: true, requestKeyframe: false))
    }

    func testEntersDroppingAboveHighWatermark() {
        var p = BackpressurePolicy(highWatermark: 100, lowWatermark: 10)
        XCTAssertEqual(p.decide(isKeyframe: false, queuedBytes: 101), Decision(send: false, requestKeyframe: false))
        // still dropping, even keyframes, while congested
        XCTAssertEqual(p.decide(isKeyframe: true, queuedBytes: 60), Decision(send: false, requestKeyframe: false))
    }

    func testRecoveryRequestsKeyframeThenResumesOnKeyframe() {
        var p = BackpressurePolicy(highWatermark: 100, lowWatermark: 10)
        _ = p.decide(isKeyframe: false, queuedBytes: 101)              // -> dropping
        XCTAssertEqual(p.decide(isKeyframe: false, queuedBytes: 5),    // drained -> ask for keyframe
                       Decision(send: false, requestKeyframe: true))
        XCTAssertEqual(p.decide(isKeyframe: false, queuedBytes: 5),    // deltas still dropped
                       Decision(send: false, requestKeyframe: false))
        XCTAssertEqual(p.decide(isKeyframe: true, queuedBytes: 5),     // keyframe resumes
                       Decision(send: true, requestKeyframe: false))
        XCTAssertEqual(p.decide(isKeyframe: false, queuedBytes: 5),
                       Decision(send: true, requestKeyframe: false))
    }

    func testRecongestionWhileAwaitingKeyframe() {
        var p = BackpressurePolicy(highWatermark: 100, lowWatermark: 10)
        _ = p.decide(isKeyframe: false, queuedBytes: 101)
        _ = p.decide(isKeyframe: false, queuedBytes: 5)                // awaitingKeyframe
        XCTAssertEqual(p.decide(isKeyframe: true, queuedBytes: 200),   // congested again -> drop
                       Decision(send: false, requestKeyframe: false))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter BackpressurePolicyTests`
Expected: compile FAILS.

- [ ] **Step 3: Implement**

`Sources/GalaxyLink/BackpressurePolicy.swift`:
```swift
struct Decision: Equatable {
    let send: Bool
    let requestKeyframe: Bool
}

struct BackpressurePolicy {
    private enum State { case normal, dropping, awaitingKeyframe }
    private var state: State = .normal
    let highWatermark: Int
    let lowWatermark: Int

    init(highWatermark: Int = 3_000_000, lowWatermark: Int = 500_000) {
        self.highWatermark = highWatermark
        self.lowWatermark = lowWatermark
    }

    mutating func decide(isKeyframe: Bool, queuedBytes: Int) -> Decision {
        if queuedBytes > highWatermark { state = .dropping }
        switch state {
        case .normal:
            return Decision(send: true, requestKeyframe: false)
        case .dropping:
            if queuedBytes < lowWatermark {
                state = .awaitingKeyframe
                return Decision(send: false, requestKeyframe: true)
            }
            return Decision(send: false, requestKeyframe: false)
        case .awaitingKeyframe:
            if isKeyframe {
                state = .normal
                return Decision(send: true, requestKeyframe: false)
            }
            return Decision(send: false, requestKeyframe: false)
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter BackpressurePolicyTests`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: backpressure policy state machine"
```

---

### Task 5: HTTP static server

**Files:**
- Create: `Sources/GalaxyLink/HTTPServer.swift`
- Test: `Tests/GalaxyLinkTests/HTTPServerTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct HTTPRequest: Equatable { let method: String; let path: String }
  enum HTTPCodec {
      static func parseRequest(_ data: Data) -> HTTPRequest?          // nil until "\r\n\r\n" seen
      static func response(status: String, contentType: String, body: Data) -> Data
      static func contentType(forPath path: String) -> String
  }
  final class HTTPServer {
      init(port: UInt16, webRoot: URL)
      func start() throws
      func stop()
  }
  ```
- Maps `/` → `index.html`; serves only files inside `webRoot`; 404 otherwise; `Connection: close` per request.

- [ ] **Step 1: Write failing tests (codec + end-to-end GET)**

`Tests/GalaxyLinkTests/HTTPServerTests.swift`:
```swift
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
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter HTTPServerTests`
Expected: compile FAILS.

- [ ] **Step 3: Implement**

`Sources/GalaxyLink/HTTPServer.swift`:
```swift
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
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter HTTPServerTests`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: minimal HTTP static file server (Network.framework)"
```

---

### Task 6: WebSocket broadcast server

**Files:**
- Create: `Sources/GalaxyLink/WebSocketServer.swift`
- Test: `Tests/GalaxyLinkTests/WebSocketServerTests.swift`

**Interfaces:**
- Produces:
  ```swift
  final class WebSocketServer {
      var onClientConnected: (() -> Void)?          // called on server queue
      var onKeyframeNeeded: (() -> Void)?
      var clientCount: Int { get }
      init(port: UInt16)
      func start() throws
      func stop()
      func broadcastConfig(_ data: Data)            // remembered; re-sent to late joiners
      func broadcastVideo(_ data: Data, isKeyframe: Bool)  // applies BackpressurePolicy per client
  }
  ```
- Consumes: `BackpressurePolicy`/`Decision` (Task 4).
- Each connection tracks `queuedBytes` (incremented on send, decremented in send-completion) and owns a `BackpressurePolicy`. If any client's policy asks for a keyframe, fire `onKeyframeNeeded` once.

- [ ] **Step 1: Write failing test (real WS round-trip via URLSessionWebSocketTask)**

`Tests/GalaxyLinkTests/WebSocketServerTests.swift`:
```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter WebSocketServerTests`
Expected: compile FAILS.

- [ ] **Step 3: Implement**

`Sources/GalaxyLink/WebSocketServer.swift`:
```swift
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
        }
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
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter WebSocketServerTests`
Expected: 2 tests PASS. (`send` completion runs on connection queue == server queue; the `queue.async` keeps mutation single-threaded.)

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: WebSocket broadcast server with per-client backpressure"
```

---

### Task 7: Virtual display wrapper + probe mode

**Files:**
- Create: `Sources/GalaxyLink/VirtualDisplay.swift`
- Create: `Sources/GalaxyLink/DisplayPreset.swift`
- Modify: `Sources/GalaxyLink/main.swift`
- Test: `Tests/GalaxyLinkTests/DisplayPresetTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct DisplayPreset: Equatable {
      let name: String
      let pixelWidth: Int
      let pixelHeight: Int
      let hiDPI: Bool
      static let all: [DisplayPreset]        // Best/Balanced/Compatibility
      static let `default`: DisplayPreset    // Best: 2960×1848 HiDPI
      var pointSize: (width: Int, height: Int)
  }
  final class VirtualDisplay {
      let displayID: CGDirectDisplayID
      init?(preset: DisplayPreset, refreshRate: Double)  // nil if private API fails
  }
  ```
- Display is destroyed by releasing the `VirtualDisplay` instance (drop all refs).
- Consumes: `CGVirtualDisplayShim` header (Task 1).

- [ ] **Step 1: Write failing preset tests**

`Tests/GalaxyLinkTests/DisplayPresetTests.swift`:
```swift
import XCTest
@testable import GalaxyLink

final class DisplayPresetTests: XCTestCase {
    func testDefaultIsTabS10UltraHiDPI() {
        XCTAssertEqual(DisplayPreset.default.pixelWidth, 2960)
        XCTAssertEqual(DisplayPreset.default.pixelHeight, 1848)
        XCTAssertTrue(DisplayPreset.default.hiDPI)
        XCTAssertEqual(DisplayPreset.default.pointSize.width, 1480)
        XCTAssertEqual(DisplayPreset.default.pointSize.height, 924)
    }

    func testNonHiDPIPointSizeEqualsPixels() {
        let p = DisplayPreset(name: "x", pixelWidth: 1480, pixelHeight: 924, hiDPI: false)
        XCTAssertEqual(p.pointSize.width, 1480)
        XCTAssertEqual(p.pointSize.height, 924)
    }

    func testThreePresets() {
        XCTAssertEqual(DisplayPreset.all.count, 3)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter DisplayPresetTests`
Expected: compile FAILS.

- [ ] **Step 3: Implement**

`Sources/GalaxyLink/DisplayPreset.swift`:
```swift
struct DisplayPreset: Equatable {
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
    let hiDPI: Bool

    var pointSize: (width: Int, height: Int) {
        hiDPI ? (pixelWidth / 2, pixelHeight / 2) : (pixelWidth, pixelHeight)
    }

    static let all: [DisplayPreset] = [
        DisplayPreset(name: "Best (2960×1848 HiDPI)", pixelWidth: 2960, pixelHeight: 1848, hiDPI: true),
        DisplayPreset(name: "Balanced (2560×1600 HiDPI)", pixelWidth: 2560, pixelHeight: 1600, hiDPI: true),
        DisplayPreset(name: "Compatibility (1480×924 1×)", pixelWidth: 1480, pixelHeight: 924, hiDPI: false),
    ]
    static let `default` = all[0]
}
```

`Sources/GalaxyLink/VirtualDisplay.swift`:
```swift
import Foundation
import CoreGraphics
import CGVirtualDisplayShim

final class VirtualDisplay {
    let displayID: CGDirectDisplayID
    private let display: CGVirtualDisplay   // retained to keep display alive

    init?(preset: DisplayPreset, refreshRate: Double = 60) {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.queue = DispatchQueue.main
        descriptor.name = "GalaxyLink (Tab S10 Ultra)"
        descriptor.maxPixelsWide = UInt32(preset.pixelWidth)
        descriptor.maxPixelsHigh = UInt32(preset.pixelHeight)
        // Tab S10 Ultra: 14.6" 16:10 panel ≈ 315 × 196 mm
        descriptor.sizeInMillimeters = CGSize(width: 315, height: 196)
        descriptor.redPrimary = CGPoint(x: 0.68, y: 0.32)
        descriptor.greenPrimary = CGPoint(x: 0.265, y: 0.69)
        descriptor.bluePrimary = CGPoint(x: 0.15, y: 0.06)
        descriptor.whitePoint = CGPoint(x: 0.3127, y: 0.329)
        descriptor.vendorID = 0x6A6C   // "jl"
        descriptor.productID = 0x5310
        descriptor.serialNum = 1
        descriptor.terminationHandler = { _, _ in }

        guard let display = CGVirtualDisplay(descriptor: descriptor) else { return nil }

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = preset.hiDPI ? 1 : 0
        settings.modes = [CGVirtualDisplayMode(width: UInt32(preset.pixelWidth),
                                               height: UInt32(preset.pixelHeight),
                                               refreshRate: refreshRate)]
        guard display.apply(settings) else { return nil }
        self.display = display
        self.displayID = display.displayID
    }
}
```
Note: the Swift name for `-applySettings:` imports as `display.apply(settings)`. If the compiler reports a different imported name, check with `swift build 2>&1 | head` and use `applySettings(settings)`.

`Sources/GalaxyLink/main.swift` — replace contents:
```swift
import Foundation
import CoreGraphics

let arguments = CommandLine.arguments

if arguments.contains("--probe-display") {
    guard let display = VirtualDisplay(preset: .default) else {
        print("FAILED to create virtual display (private API may have changed)")
        exit(1)
    }
    print("Created virtual display id=\(display.displayID)")
    var count: UInt32 = 0
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    CGGetOnlineDisplayList(16, &ids, &count)
    let online = ids.prefix(Int(count))
    print("Online displays: \(Array(online))")
    print(online.contains(display.displayID) ? "PROBE OK: virtual display is online" : "PROBE FAILED: not in online list")
    print("Holding display for 15s — check System Settings ▸ Displays…")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 15))
    exit(online.contains(display.displayID) ? 0 : 1)
}

print("GalaxyLink scaffold")
```

- [ ] **Step 4: Run tests + probe**

Run: `swift test --filter DisplayPresetTests`
Expected: 3 tests PASS.

Run: `swift run GalaxyLink --probe-display`
Expected: prints `PROBE OK: virtual display is online`; during the 15 s hold, a "GalaxyLink (Tab S10 Ultra)" display appears in System Settings ▸ Displays. If instead it prints FAILED, stop and investigate the private API shape before proceeding (this is the plan's one designated risk point).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: CGVirtualDisplay wrapper, display presets, --probe-display"
```

---

### Task 8: H.264 low-latency encoder

**Files:**
- Create: `Sources/GalaxyLink/H264Encoder.swift`
- Test: `Tests/GalaxyLinkTests/H264EncoderTests.swift`

**Interfaces:**
- Produces:
  ```swift
  final class H264Encoder {
      struct EncodedFrame {
          let annexB: Data          // keyframes already include SPS/PPS prefix
          let isKeyframe: Bool
          let timestampMicros: UInt64
      }
      var onFrame: ((EncodedFrame) -> Void)?
      var onCodecString: ((String) -> Void)?   // fired once, from first keyframe's SPS
      init(width: Int, height: Int, fps: Int, bitrate: Int) throws
      func encode(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime)
      func forceKeyframe()
      func invalidate()
  }
  ```
- Consumes: `AVC` helpers (Task 3).

- [ ] **Step 1: Write failing test**

`Tests/GalaxyLinkTests/H264EncoderTests.swift`:
```swift
import XCTest
import CoreMedia
import CoreVideo
@testable import GalaxyLink

final class H264EncoderTests: XCTestCase {
    private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
        CVPixelBufferCreate(nil, width, height,
                            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attrs, &pb)
        let buffer = try XCTUnwrap(pb)
        CVPixelBufferLockBaseAddress(buffer, [])
        for plane in 0..<2 {
            let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane)!
            let size = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane)
                     * CVPixelBufferGetHeightOfPlane(buffer, plane)
            memset(base, plane == 0 ? 0x80 : 0x40, size)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    func testEncodesKeyframeWithAnnexBAndCodecString() throws {
        let encoder = try H264Encoder(width: 640, height: 400, fps: 30, bitrate: 2_000_000)
        let frameExp = expectation(description: "frame")
        let codecExp = expectation(description: "codec")
        var firstFrame: H264Encoder.EncodedFrame?
        var codec: String?
        encoder.onFrame = { frame in
            if firstFrame == nil { firstFrame = frame; frameExp.fulfill() }
        }
        encoder.onCodecString = { codec = $0; codecExp.fulfill() }

        let pixelBuffer = try makePixelBuffer(width: 640, height: 400)
        for i in 0..<5 {
            encoder.encode(pixelBuffer, presentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
        }
        wait(for: [frameExp, codecExp], timeout: 10)
        encoder.invalidate()

        let frame = try XCTUnwrap(firstFrame)
        XCTAssertTrue(frame.isKeyframe)
        XCTAssertEqual(Array(frame.annexB.prefix(4)), [0, 0, 0, 1])
        XCTAssertTrue(try XCTUnwrap(codec).hasPrefix("avc1."))
        XCTAssertEqual(try XCTUnwrap(codec).count, 11)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter H264EncoderTests`
Expected: compile FAILS.

- [ ] **Step 3: Implement**

`Sources/GalaxyLink/H264Encoder.swift`:
```swift
import Foundation
import VideoToolbox
import CoreMedia

final class H264Encoder {
    struct EncodedFrame {
        let annexB: Data
        let isKeyframe: Bool
        let timestampMicros: UInt64
    }

    var onFrame: ((EncodedFrame) -> Void)?
    var onCodecString: ((String) -> Void)?

    private var session: VTCompressionSession?
    private var forceNextKeyframe = false
    private var sentCodecString = false
    private let queue = DispatchQueue(label: "galaxylink.encoder")

    init(width: Int, height: Int, fps: Int, bitrate: Int) throws {
        let spec: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true
        ]
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: spec as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &session)
        guard status == noErr, let session else {
            throw NSError(domain: "GalaxyLink", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "VTCompressionSessionCreate failed (\(status))"])
        }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: bitrate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 2 as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(session)
        self.session = session
    }

    func forceKeyframe() {
        queue.async { self.forceNextKeyframe = true }
    }

    func encode(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        queue.async {
            guard let session = self.session else { return }
            var properties: [CFString: Any] = [:]
            if self.forceNextKeyframe {
                properties[kVTEncodeFrameOptionKey_ForceKeyFrame] = kCFBooleanTrue!
                self.forceNextKeyframe = false
            }
            VTCompressionSessionEncodeFrame(
                session, imageBuffer: pixelBuffer,
                presentationTimeStamp: presentationTime, duration: .invalid,
                frameProperties: properties.isEmpty ? nil : properties as CFDictionary,
                infoFlagsOut: nil
            ) { [weak self] status, _, sampleBuffer in
                guard status == noErr, let sampleBuffer else { return }
                self?.handleEncoded(sampleBuffer)
            }
        }
    }

    func invalidate() {
        queue.sync {
            if let session {
                VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
                VTCompressionSessionInvalidate(session)
            }
            session = nil
        }
    }

    private func handleEncoded(_ sampleBuffer: CMSampleBuffer) {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[CFString: Any]]
        let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        let isKeyframe = !notSync

        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var nalLengthSize: Int32 = 4
        var sps = Data(), pps = Data()
        var pointer: UnsafePointer<UInt8>?
        var size = 0, count = 0
        if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format, parameterSetIndex: 0, parameterSetPointerOut: &pointer,
            parameterSetSizeOut: &size, parameterSetCountOut: &count,
            nalUnitHeaderLengthOut: &nalLengthSize) == noErr, let pointer {
            sps = Data(bytes: pointer, count: size)
        }
        if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format, parameterSetIndex: 1, parameterSetPointerOut: &pointer,
            parameterSetSizeOut: &size, parameterSetCountOut: &count,
            nalUnitHeaderLengthOut: nil) == noErr, let pointer {
            pps = Data(bytes: pointer, count: size)
        }

        var dataLength = 0
        var dataPointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &dataLength, dataPointerOut: &dataPointer) == noErr,
              let dataPointer else { return }
        let avcc = Data(bytes: dataPointer, count: dataLength)

        var annexB = Data()
        if isKeyframe, !sps.isEmpty, !pps.isEmpty {
            annexB.append(AVC.parameterSetPrefix(sps: sps, pps: pps))
        }
        annexB.append(AVC.annexB(fromAVCC: avcc, nalLengthSize: Int(nalLengthSize)))

        if !sentCodecString, !sps.isEmpty {
            sentCodecString = true
            onCodecString?(AVC.codecString(sps: sps))
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let micros = pts.isNumeric ? UInt64(max(0, CMTimeGetSeconds(pts) * 1_000_000)) : 0
        onFrame?(EncodedFrame(annexB: annexB, isKeyframe: isKeyframe, timestampMicros: micros))
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter H264EncoderTests`
Expected: 1 test PASSES (hardware encoder runs headless on Apple Silicon). If `EnableLowLatencyRateControl` makes session creation fail on this machine, retry once without that spec key and note it in the code with a fallback:
```swift
// fallback inside init if status != noErr on first attempt:
// retry VTCompressionSessionCreate with encoderSpecification: nil
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: VideoToolbox low-latency H.264 encoder emitting Annex-B"
```

---

### Task 9: Screen capture engine + probe mode

**Files:**
- Create: `Sources/GalaxyLink/CaptureEngine.swift`
- Modify: `Sources/GalaxyLink/main.swift` (add `--probe-capture`)

**Interfaces:**
- Produces:
  ```swift
  final class CaptureEngine: NSObject {
      var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
      func start(displayID: CGDirectDisplayID, pixelWidth: Int, pixelHeight: Int, fps: Int) async throws
      func stop() async
  }
  ```
- No unit test (requires Screen Recording TCC); verified by probe.

- [ ] **Step 1: Implement**

`Sources/GalaxyLink/CaptureEngine.swift`:
```swift
import Foundation
import ScreenCaptureKit
import CoreMedia

final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "galaxylink.capture")

    func start(displayID: CGDirectDisplayID, pixelWidth: Int, pixelHeight: Int, fps: Int) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "GalaxyLink", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Display \(displayID) not found in shareable content"])
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = pixelWidth
        config.height = pixelHeight
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 5
        config.showsCursor = true

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              statusRaw == SCFrameStatus.complete.rawValue,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Capture stopped: \(error.localizedDescription)")
    }
}
```

Add to `main.swift`, before the final `print`:
```swift
if arguments.contains("--probe-capture") {
    guard let display = VirtualDisplay(preset: .default) else {
        print("FAILED to create virtual display"); exit(1)
    }
    let capture = CaptureEngine()
    var frames = 0
    capture.onFrame = { _, _ in frames += 1 }
    Task {
        do {
            try await capture.start(displayID: display.displayID,
                                    pixelWidth: DisplayPreset.default.pixelWidth,
                                    pixelHeight: DisplayPreset.default.pixelHeight, fps: 60)
        } catch {
            print("Capture failed: \(error.localizedDescription)"); exit(1)
        }
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 5))
    print(frames > 30 ? "PROBE OK: \(frames) frames in 5s" : "PROBE FAILED: only \(frames) frames")
    exit(frames > 30 ? 0 : 1)
}
```

- [ ] **Step 2: Build + probe**

Run: `swift build && swift test` (all existing tests still pass), then:
Run: `swift run GalaxyLink --probe-capture`
Expected: first run may trigger the macOS **Screen Recording** permission prompt — grant it for the terminal app and rerun. Then `PROBE OK: ~300 frames in 5s`. Note: rebuilding the binary can occasionally require re-granting; documented in Task 13's README.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: ScreenCaptureKit capture engine + --probe-capture"
```

---

### Task 10: Stream controller + headless serve mode

**Files:**
- Create: `Sources/GalaxyLink/StreamController.swift`
- Create: `Sources/GalaxyLink/LANAddress.swift`
- Modify: `Sources/GalaxyLink/main.swift` (add `--serve`)
- Test: `Tests/GalaxyLinkTests/LANAddressTests.swift`

**Interfaces:**
- Produces:
  ```swift
  final class StreamController {
      enum Status: Equatable { case stopped, running(url: String), failed(String) }
      var onStatusChange: ((Status) -> Void)?
      private(set) var status: Status
      func start(preset: DisplayPreset, fps: Int = 60, bitrate: Int = 15_000_000)
      func stop()
  }
  enum LANAddress {
      static func primaryIPv4() -> String?   // e.g. "192.168.1.23"
  }
  ```
- Consumes: everything from Tasks 2–9.
- Wiring: capture.onFrame → encoder.encode; encoder.onFrame → `StreamProtocol.videoFrame` → `ws.broadcastVideo`; encoder.onCodecString → `StreamProtocol.configFrame` → `ws.broadcastConfig`; `ws.onClientConnected` and `ws.onKeyframeNeeded` → `encoder.forceKeyframe()`.

- [ ] **Step 1: Write failing LANAddress test**

`Tests/GalaxyLinkTests/LANAddressTests.swift`:
```swift
import XCTest
@testable import GalaxyLink

final class LANAddressTests: XCTestCase {
    func testReturnsDottedQuadOrNil() {
        guard let ip = LANAddress.primaryIPv4() else { return } // machines without network: nil is valid
        let parts = ip.split(separator: ".")
        XCTAssertEqual(parts.count, 4)
        XCTAssertNotEqual(ip, "127.0.0.1")
        parts.forEach { XCTAssertNotNil(UInt8($0)) }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter LANAddressTests`
Expected: compile FAILS.

- [ ] **Step 3: Implement**

`Sources/GalaxyLink/LANAddress.swift`:
```swift
import Foundation

enum LANAddress {
    static func primaryIPv4() -> String? {
        var addrList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrList) == 0, let first = addrList else { return nil }
        defer { freeifaddrs(addrList) }

        var best: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard ifa.ifa_addr?.pointee.sa_family == UInt8(AF_INET),
                  (ifa.ifa_flags & UInt32(IFF_UP)) != 0,
                  (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(ifa.ifa_addr, socklen_t(ifa.ifa_addr.pointee.sa_len),
                              &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let name = String(cString: host)
            let iface = String(cString: ifa.ifa_name)
            if iface == "en0" { return name }   // prefer primary interface
            if best == nil { best = name }
        }
        return best
    }
}
```

`Sources/GalaxyLink/StreamController.swift`:
```swift
import Foundation
import CoreMedia

final class StreamController {
    enum Status: Equatable {
        case stopped
        case running(url: String)
        case failed(String)
    }

    var onStatusChange: ((Status) -> Void)?
    private(set) var status: Status = .stopped {
        didSet { onStatusChange?(status) }
    }

    private var virtualDisplay: VirtualDisplay?
    private var capture: CaptureEngine?
    private var encoder: H264Encoder?
    private var httpServer: HTTPServer?
    private var wsServer: WebSocketServer?

    func start(preset: DisplayPreset, fps: Int = 60, bitrate: Int = 15_000_000) {
        stop()
        guard let webRoot = Bundle.module.url(forResource: "web", withExtension: nil) else {
            status = .failed("web resources missing from bundle"); return
        }
        guard let display = VirtualDisplay(preset: preset) else {
            status = .failed("Could not create virtual display (macOS private API changed?)"); return
        }
        do {
            let encoder = try H264Encoder(width: preset.pixelWidth, height: preset.pixelHeight,
                                          fps: fps, bitrate: bitrate)
            let http = HTTPServer(port: Ports.http, webRoot: webRoot)
            let ws = WebSocketServer(port: Ports.ws)
            let capture = CaptureEngine()

            encoder.onCodecString = { codec in
                ws.broadcastConfig(StreamProtocol.configFrame(
                    codec: codec, width: preset.pixelWidth, height: preset.pixelHeight, fps: fps))
            }
            encoder.onFrame = { frame in
                ws.broadcastVideo(StreamProtocol.videoFrame(annexB: frame.annexB,
                                                            isKeyframe: frame.isKeyframe,
                                                            timestampMicros: frame.timestampMicros),
                                  isKeyframe: frame.isKeyframe)
            }
            ws.onClientConnected = { encoder.forceKeyframe() }
            ws.onKeyframeNeeded = { encoder.forceKeyframe() }
            capture.onFrame = { pixelBuffer, pts in encoder.encode(pixelBuffer, presentationTime: pts) }

            try http.start()
            try ws.start()

            self.virtualDisplay = display
            self.encoder = encoder
            self.httpServer = http
            self.wsServer = ws
            self.capture = capture

            Task {
                do {
                    // brief delay lets WindowServer finish bringing the display online
                    try await Task.sleep(nanoseconds: 500_000_000)
                    try await capture.start(displayID: display.displayID,
                                            pixelWidth: preset.pixelWidth,
                                            pixelHeight: preset.pixelHeight, fps: fps)
                    let host = LANAddress.primaryIPv4() ?? "<mac-ip>"
                    self.status = .running(url: "http://\(host):\(Ports.http)")
                } catch {
                    self.stop()
                    self.status = .failed("Capture failed: \(error.localizedDescription)")
                }
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func stop() {
        let capture = self.capture
        Task { await capture?.stop() }
        encoder?.invalidate()
        httpServer?.stop()
        wsServer?.stop()
        self.capture = nil
        encoder = nil
        httpServer = nil
        wsServer = nil
        virtualDisplay = nil
        if status != .stopped { status = .stopped }
    }
}
```

Add to `main.swift` before the final `print`:
```swift
if arguments.contains("--serve") {
    let controller = StreamController()
    controller.onStatusChange = { status in print("Status: \(status)") }
    controller.start(preset: .default)
    print("Serving. Ctrl-C to quit.")
    RunLoop.main.run()
}
```

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: all tests PASS (LANAddress test included).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: StreamController wiring + --serve headless mode"
```

(End-to-end verification happens in Task 11 once the web client exists.)

---

### Task 11: Web client (WebCodecs page)

**Files:**
- Create: `Sources/GalaxyLink/Resources/web/index.html`
- Create: `Sources/GalaxyLink/Resources/web/client.js`
- Create: `Sources/GalaxyLink/Resources/web/manifest.webmanifest`
- Create: `scripts/make_icons.py`
- Create (generated): `Sources/GalaxyLink/Resources/web/icon-192.png`, `icon-512.png`
- Delete: `Sources/GalaxyLink/Resources/web/.gitkeep`

**Interfaces:**
- Consumes: wire protocol from Task 2 (CONFIG JSON keys `codec/width/height/fps`; VIDEO header `[type][flags][u64 LE ts]`), WS on port 8081.

- [ ] **Step 1: Write the client**

`Sources/GalaxyLink/Resources/web/index.html`:
```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no, viewport-fit=cover">
<meta name="theme-color" content="#000000">
<link rel="manifest" href="manifest.webmanifest">
<title>GalaxyLink</title>
<style>
  html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
  #screen { width: 100%; height: 100%; object-fit: contain; display: block;
            image-rendering: auto; touch-action: none; }
  #overlay { position: fixed; inset: 0; display: flex; flex-direction: column;
             align-items: center; justify-content: center; gap: 12px;
             color: #ddd; font: 16px -apple-system, Roboto, sans-serif;
             background: rgba(0,0,0,.75); text-align: center; padding: 24px; }
  #overlay.hidden { display: none; }
  #overlay button { font-size: 18px; padding: 12px 28px; border-radius: 10px;
                    border: 1px solid #555; background: #1a1a1a; color: #eee; }
</style>
</head>
<body>
<canvas id="screen"></canvas>
<div id="overlay">
  <div id="status">Connecting…</div>
  <button id="go" hidden>Tap for fullscreen</button>
</div>
<script src="client.js"></script>
</body>
</html>
```

`Sources/GalaxyLink/Resources/web/client.js`:
```js
"use strict";

const canvas = document.getElementById("screen");
const ctx = canvas.getContext("2d", { alpha: false, desynchronized: true });
const overlay = document.getElementById("overlay");
const statusEl = document.getElementById("status");
const goBtn = document.getElementById("go");

let ws = null;
let decoder = null;
let seenKeyframe = false;
let wakeLock = null;

function setStatus(text) {
  statusEl.textContent = text;
  overlay.classList.remove("hidden");
}

function hideOverlay() {
  overlay.classList.add("hidden");
}

function paint(frame) {
  if (canvas.width !== frame.displayWidth || canvas.height !== frame.displayHeight) {
    canvas.width = frame.displayWidth;
    canvas.height = frame.displayHeight;
  }
  ctx.drawImage(frame, 0, 0);
  frame.close();
}

function setupDecoder(cfg) {
  if (decoder) { try { decoder.close(); } catch (_) {} }
  seenKeyframe = false;
  decoder = new VideoDecoder({
    output: paint,
    error: (e) => { console.error("decoder error", e); reconnect(); },
  });
  // No `description` => Annex-B mode; keyframes carry SPS/PPS in-band.
  decoder.configure({ codec: cfg.codec, optimizeForLatency: true });
  hideOverlay();
  goBtn.hidden = false;
}

function handleMessage(buffer) {
  const view = new DataView(buffer);
  const type = view.getUint8(0);
  if (type === 0x01) {
    const cfg = JSON.parse(new TextDecoder().decode(new Uint8Array(buffer, 1)));
    setupDecoder(cfg);
  } else if (type === 0x02 && decoder && decoder.state === "configured") {
    const isKey = (view.getUint8(1) & 1) === 1;
    if (!seenKeyframe && !isKey) return;
    seenKeyframe = true;
    const timestamp = Number(view.getBigUint64(2, true));
    decoder.decode(new EncodedVideoChunk({
      type: isKey ? "key" : "delta",
      timestamp,
      data: new Uint8Array(buffer, 10),
    }));
  }
}

let reconnectTimer = null;
function reconnect() {
  if (reconnectTimer) return;
  if (ws) { try { ws.close(); } catch (_) {} ws = null; }
  setStatus("Reconnecting…");
  reconnectTimer = setTimeout(() => { reconnectTimer = null; connect(); }, 1000);
}

function connect() {
  if (!("VideoDecoder" in window)) {
    setStatus("This browser lacks WebCodecs. Use Chrome or Samsung Internet.");
    return;
  }
  ws = new WebSocket(`ws://${location.hostname}:8081`);
  ws.binaryType = "arraybuffer";
  ws.onmessage = (e) => handleMessage(e.data);
  ws.onclose = reconnect;
  ws.onerror = reconnect;
}

goBtn.addEventListener("click", async () => {
  try { await document.documentElement.requestFullscreen({ navigationUI: "hide" }); } catch (_) {}
  try { if (screen.orientation && screen.orientation.lock) await screen.orientation.lock("landscape"); } catch (_) {}
  hideOverlay();
});

async function acquireWakeLock() {
  try { wakeLock = await navigator.wakeLock.request("screen"); } catch (_) {}
}
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") { acquireWakeLock(); if (!ws || ws.readyState > 1) reconnect(); }
});

acquireWakeLock();
connect();
```

`Sources/GalaxyLink/Resources/web/manifest.webmanifest`:
```json
{
  "name": "GalaxyLink",
  "short_name": "GalaxyLink",
  "start_url": "/",
  "display": "fullscreen",
  "orientation": "landscape",
  "background_color": "#000000",
  "theme_color": "#000000",
  "icons": [
    { "src": "icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
```

`scripts/make_icons.py` (stdlib-only PNG writer, solid indigo squares):
```python
#!/usr/bin/env python3
"""Generate solid-color PNG icons for the PWA manifest. Stdlib only."""
import struct, zlib, os

def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + \
        struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

def solid_png(size, rgb):
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    row = b"\x00" + bytes(rgb) * size
    idat = zlib.compress(row * size)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", idat) + chunk(b"IEND", b""))

out_dir = os.path.join(os.path.dirname(__file__), "..",
                       "Sources", "GalaxyLink", "Resources", "web")
for size in (192, 512):
    path = os.path.join(out_dir, f"icon-{size}.png")
    with open(path, "wb") as f:
        f.write(solid_png(size, (76, 91, 175)))
    print("wrote", path)
```

- [ ] **Step 2: Generate icons, syntax-check JS, build**

```bash
python3 scripts/make_icons.py
node --check Sources/GalaxyLink/Resources/web/client.js || true  # skip if node absent
rm -f Sources/GalaxyLink/Resources/web/.gitkeep
swift build && swift test
```
Expected: icons written; build + tests pass.

- [ ] **Step 3: End-to-end verify on the Mac itself**

```bash
swift run GalaxyLink --serve
```
Then open `http://localhost:8080` in Chrome **on the Mac**. Expected: the virtual display's desktop appears live in the page (drag a window onto the GalaxyLink display in System Settings ▸ Displays to see motion). This validates capture → encode → protocol → WebCodecs before touching the tablet.

- [ ] **Step 4: Verify on the tablet (requires user/tablet present — if unattended, note it and continue; Task 14's checklist covers it)**

On the Tab S10 Ultra (same Wi-Fi), open `http://<mac-ip>:8080` in Chrome; tap fullscreen. Expected: live second monitor.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: WebCodecs web client with fullscreen, wake lock, reconnect"
```

---

### Task 12: Menu-bar app

**Files:**
- Create: `Sources/GalaxyLink/AppDelegate.swift`
- Create: `Sources/GalaxyLink/QRCode.swift`
- Modify: `Sources/GalaxyLink/main.swift`

**Interfaces:**
- Consumes: `StreamController` (Task 10), `DisplayPreset` (Task 7), `LANAddress` (Task 10), `USBHelper` arrives in Task 13 (menu item added there).
- Produces: `QRCode.image(for: String, scale: CGFloat) -> NSImage?`; app runs as `.accessory` (menu bar only, no Dock icon). Preset choice persisted in `UserDefaults` key `"preset.name"`.

- [ ] **Step 1: Implement**

`Sources/GalaxyLink/QRCode.swift`:
```swift
import AppKit
import CoreImage

enum QRCode {
    static func image(for string: String, scale: CGFloat = 6) -> NSImage? {
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(Data(string.utf8), forKey: "inputMessage")
        filter?.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter?.outputImage?
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
```

`Sources/GalaxyLink/AppDelegate.swift`:
```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let controller = StreamController()
    private var currentPreset: DisplayPreset {
        get {
            let name = UserDefaults.standard.string(forKey: "preset.name")
            return DisplayPreset.all.first { $0.name == name } ?? .default
        }
        set { UserDefaults.standard.set(newValue.name, forKey: "preset.name") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⬒"
        statusItem.button?.toolTip = "GalaxyLink"
        controller.onStatusChange = { [weak self] _ in
            DispatchQueue.main.async { self?.rebuildMenu() }
        }
        rebuildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        switch controller.status {
        case .stopped:
            menu.addItem(withTitle: "Status: stopped", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Start Streaming", action: #selector(startStreaming), keyEquivalent: "s")
        case .running(let url):
            menu.addItem(withTitle: "Status: streaming", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "On the tablet, open: \(url)", action: #selector(copyURL(_:)), keyEquivalent: "c")
                .representedObject = url
            if let qr = QRCode.image(for: url) {
                let item = NSMenuItem()
                item.image = qr
                menu.addItem(item)
            }
            menu.addItem(withTitle: "Stop Streaming", action: #selector(stopStreaming), keyEquivalent: "x")
        case .failed(let message):
            menu.addItem(withTitle: "Failed: \(message)", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Start Streaming", action: #selector(startStreaming), keyEquivalent: "s")
        }

        menu.addItem(.separator())
        let presetMenu = NSMenu()
        for preset in DisplayPreset.all {
            let item = presetMenu.addItem(withTitle: preset.name, action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.representedObject = preset.name
            item.state = preset == currentPreset ? .on : .off
            item.target = self
        }
        let presetItem = menu.addItem(withTitle: "Resolution", action: nil, keyEquivalent: "")
        menu.setSubmenu(presetMenu, for: presetItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit GalaxyLink", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = $0.target ?? self }
        statusItem.menu = menu
    }

    @objc private func startStreaming() { controller.start(preset: currentPreset) }
    @objc private func stopStreaming() { controller.stop() }

    @objc private func copyURL(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let preset = DisplayPreset.all.first(where: { $0.name == name }) else { return }
        currentPreset = preset
        if case .running = controller.status { controller.start(preset: preset) }
        rebuildMenu()
    }

    @objc private func quit() {
        controller.stop()
        NSApp.terminate(nil)
    }
}
```

`main.swift` — replace the trailing `print("GalaxyLink scaffold")` with:
```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```
(Keep the probe/serve blocks above it; they `exit()`/`run()` before reaching here.)

- [ ] **Step 2: Build, test, manual check**

Run: `swift build && swift test`
Expected: PASS.
Run: `swift run GalaxyLink` — a "⬒" menu-bar item appears; Start Streaming creates the display and menu shows URL + QR; Stop Streaming removes the display. Quit works.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: menu-bar app with start/stop, URL, QR, resolution presets"
```

---

### Task 13: USB mode helper (adb reverse)

**Files:**
- Create: `Sources/GalaxyLink/USBHelper.swift`
- Modify: `Sources/GalaxyLink/AppDelegate.swift` (add menu item)
- Test: `Tests/GalaxyLinkTests/USBHelperTests.swift`

**Interfaces:**
- Produces:
  ```swift
  enum USBHelper {
      static func parseDevices(_ adbDevicesOutput: String) -> [String]  // serials in "device" state
      static func findADB() -> String?          // checks PATH + common install locations
      static func enableUSBMode() -> Result<String, USBError>  // runs adb reverse for 8080+8081
      enum USBError: Error, Equatable { case adbNotFound, noDevice, commandFailed(String) }
  }
  ```

- [ ] **Step 1: Write failing parse tests**

`Tests/GalaxyLinkTests/USBHelperTests.swift`:
```swift
import XCTest
@testable import GalaxyLink

final class USBHelperTests: XCTestCase {
    func testParsesConnectedDevice() {
        let out = """
        List of devices attached
        R52X123ABC\tdevice
        emulator-5554\toffline

        """
        XCTAssertEqual(USBHelper.parseDevices(out), ["R52X123ABC"])
    }

    func testUnauthorizedDeviceExcluded() {
        let out = "List of devices attached\nR52X123ABC\tunauthorized\n"
        XCTAssertEqual(USBHelper.parseDevices(out), [])
    }

    func testEmptyList() {
        XCTAssertEqual(USBHelper.parseDevices("List of devices attached\n\n"), [])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter USBHelperTests`
Expected: compile FAILS.

- [ ] **Step 3: Implement**

`Sources/GalaxyLink/USBHelper.swift`:
```swift
import Foundation

enum USBHelper {
    enum USBError: Error, Equatable {
        case adbNotFound
        case noDevice
        case commandFailed(String)
    }

    static func parseDevices(_ adbDevicesOutput: String) -> [String] {
        adbDevicesOutput
            .split(separator: "\n")
            .dropFirst() // "List of devices attached"
            .compactMap { line in
                let cols = line.split(separator: "\t")
                guard cols.count == 2, cols[1] == "device" else { return nil }
                return String(cols[0])
            }
    }

    static func findADB() -> String? {
        let candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            NSString(string: "~/Library/Android/sdk/platform-tools/adb").expandingTildeInPath,
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        // fall back to PATH
        let which = run("/usr/bin/which", ["adb"])
        if case .success(let path) = which, !path.isEmpty {
            return path.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func enableUSBMode() -> Result<String, USBError> {
        guard let adb = findADB() else { return .failure(.adbNotFound) }
        guard case .success(let list) = run(adb, ["devices"]),
              let device = parseDevices(list).first else { return .failure(.noDevice) }
        for port in [Ports.http, Ports.ws] {
            let result = run(adb, ["-s", device, "reverse", "tcp:\(port)", "tcp:\(port)"])
            if case .failure(let message) = result { return .failure(.commandFailed(message)) }
        }
        return .success("USB ready — open http://localhost:\(Ports.http) on the tablet")
    }

    private static func run(_ launchPath: String, _ args: [String]) -> Result<String, String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return process.terminationStatus == 0 ? .success(out) : .failure(out)
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

extension String: @retroactive Error {}
```
(If the `@retroactive` conformance produces a build error on the toolchain in use, replace `Result<String, String>` with `Result<String, USBError>` internally and map errors to `.commandFailed`.)

In `AppDelegate.rebuildMenu()`, add before the final separator:
```swift
menu.addItem(.separator())
menu.addItem(withTitle: "Enable USB Mode (adb)", action: #selector(enableUSB), keyEquivalent: "u")
```
And add the action:
```swift
@objc private func enableUSB() {
    let alert = NSAlert()
    switch USBHelper.enableUSBMode() {
    case .success(let message):
        alert.messageText = "USB mode enabled"
        alert.informativeText = message
    case .failure(.adbNotFound):
        alert.messageText = "adb not found"
        alert.informativeText = "Install Android platform-tools (brew install android-platform-tools) and retry."
    case .failure(.noDevice):
        alert.messageText = "No tablet detected"
        alert.informativeText = "Connect the tablet via USB, enable USB debugging (Settings ▸ Developer options), accept the prompt on the tablet, and retry."
    case .failure(.commandFailed(let output)):
        alert.messageText = "adb reverse failed"
        alert.informativeText = output
    }
    alert.runModal()
}
```

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: all PASS (USBHelperTests: 3 new).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: USB mode via adb reverse with device detection"
```

---

### Task 14: README + end-to-end checklist

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README**

`README.md` must contain (write real prose, not placeholders):
- What GalaxyLink is (one paragraph) and the architecture diagram from the spec.
- **Requirements:** macOS 14+, Apple Silicon or Intel with H.264 hardware encode, Galaxy Tab S10 Ultra (any WebCodecs-capable Android browser works), same Wi-Fi network or USB cable.
- **Build & run:** `swift run GalaxyLink` (menu bar), `swift run GalaxyLink --serve` (headless), probe commands `--probe-display`, `--probe-capture`.
- **First-run permissions:** Screen Recording prompt for the terminal app; note that rebuilding the binary may require re-granting (System Settings ▸ Privacy & Security ▸ Screen Recording, toggle off/on).
- **Tablet setup (Wi-Fi):** open the URL from the menu (or scan the QR), tap fullscreen; optional: Chrome ⋮ ▸ "Add to Home screen" installs the PWA for a chrome-free fullscreen launch.
- **Tablet setup (USB):** one-time — Settings ▸ About tablet ▸ Software information ▸ tap Build number 7×; Settings ▸ Developer options ▸ USB debugging ON; `brew install android-platform-tools`; then menu ▸ Enable USB Mode; open `http://localhost:8080` on the tablet.
- **End-to-end checklist** (manual verification, run after any pipeline change):
  1. `swift test` passes.
  2. `--probe-display` OK.
  3. `--probe-capture` OK.
  4. `--serve` + Mac Chrome `http://localhost:8080` shows the virtual desktop live.
  5. Tablet Wi-Fi: URL loads, fullscreen works, dragging a window is smooth (~60 fps), screen stays awake.
  6. Kill the app; tablet shows "Reconnecting…"; restart app; stream resumes without reloading the page.
  7. USB: `Enable USB Mode` then `http://localhost:8080` on the tablet works with Wi-Fi off.
- **Known limitations:** display-only (no touch input yet — protocol reserves frame types `0x10+`), single client at full quality, private `CGVirtualDisplay` API may break on a future macOS release (isolated in `VirtualDisplay.swift`; fallback is a headless HDMI dongle + capture of that display).

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "docs: README with setup, permissions, and e2e checklist"
```

---

## Self-review notes

- **Spec coverage:** virtual display (T7), capture (T9), encode (T8), protocol (T2/T3), servers (T5/T6), backpressure (T4), client incl. fullscreen/wake-lock/reconnect/PWA (T11), menu bar + QR + presets (T12), USB (T13), docs/checklist (T14). Input events intentionally out of scope; protocol reserves `0x10+`.
- **Type consistency:** `Decision`, `DisplayPreset`, `StreamProtocol`, `AVC`, `Ports` names match across tasks; `EncodedFrame` consumed in T10 as defined in T8.
- **Known risk:** private-API import name (`apply(_:)` vs `applySettings(_:)`) and low-latency encoder spec both have explicit in-task fallbacks.
