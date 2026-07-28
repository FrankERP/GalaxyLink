import Foundation
import CoreMedia

/// Owns the whole pipeline: virtual display -> capture -> encoder -> servers.
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
        guard let webRoot = WebRoot.url() else {
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
