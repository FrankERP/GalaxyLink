import Foundation
import CoreMedia

/// Owns the pipeline: virtual display -> capture -> encoder, attached to
/// HTTP/WebSocket servers that stay up from app launch so pairing works
/// before capture starts.
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

    var isStreaming: Bool {
        if case .running = status { return true }
        return false
    }

    private var virtualDisplay: VirtualDisplay?
    private var capture: CaptureEngine?
    private var encoder: H264Encoder?
    private var httpServer: HTTPServer?
    private var wsServer: WebSocketServer?
    private var keepAliveTimer: DispatchSourceTimer?
    private var captureGeneration = 0

    func startServers() {
        guard httpServer == nil, wsServer == nil else { return }
        guard let webRoot = WebRoot.url() else {
            status = .failed("web resources missing from bundle")
            return
        }
        do {
            let http = HTTPServer(port: Ports.http, webRoot: webRoot)
            let ws = WebSocketServer(port: Ports.ws)
            try http.start()
            try ws.start()
            self.httpServer = http
            self.wsServer = ws
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func stopServers() {
        httpServer?.stop()
        wsServer?.stop()
        httpServer = nil
        wsServer = nil
    }

    func start(preset: DisplayPreset, fps: Int = 60, bitrate: Int = 30_000_000) {
        stopCapture()
        guard let ws = wsServer else { return }
        let generation = captureGeneration
        guard let display = VirtualDisplay(preset: preset) else {
            status = .failed("Could not create virtual display (macOS private API changed?)")
            return
        }
        do {
            let encoder = try H264Encoder(width: preset.pixelWidth, height: preset.pixelHeight,
                                          fps: fps, bitrate: bitrate)
            let capture = CaptureEngine()

            encoder.onCodecString = { [weak ws] codec in
                ws?.broadcastConfig(StreamProtocol.configFrame(
                    codec: codec, width: preset.pixelWidth, height: preset.pixelHeight, fps: fps))
            }
            encoder.onFrame = { [weak ws] frame in
                ws?.broadcastVideo(StreamProtocol.videoFrame(annexB: frame.annexB,
                                                            isKeyframe: frame.isKeyframe,
                                                            timestampMicros: frame.timestampMicros),
                                  isKeyframe: frame.isKeyframe)
            }
            ws.onClientConnected = { [weak encoder] in encoder?.forceKeyframe() }
            ws.onKeyframeNeeded = { [weak encoder] in encoder?.forceKeyframe() }

            // ScreenCaptureKit only delivers frames when the display content
            // changes. Re-encode the last frame while the screen is static so
            // late-joining clients get a picture without waiting for motion.
            let frameSync = DispatchQueue(label: "galaxylink.lastframe")
            var lastBuffer: CVPixelBuffer?
            var lastFrameAt = Date.distantPast
            capture.onFrame = { pixelBuffer, pts in
                frameSync.async { lastBuffer = pixelBuffer; lastFrameAt = Date() }
                encoder.encode(pixelBuffer, presentationTime: pts)
            }
            let timer = DispatchSource.makeTimerSource(queue: frameSync)
            timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
            timer.setEventHandler { [weak encoder] in
                guard let encoder, let buffer = lastBuffer,
                      Date().timeIntervalSince(lastFrameAt) > 0.45 else { return }
                encoder.encode(buffer, presentationTime: CMClockGetTime(CMClockGetHostTimeClock()))
            }
            timer.resume()
            self.keepAliveTimer = timer

            self.virtualDisplay = display
            self.encoder = encoder
            self.capture = capture

            Task {
                do {
                    // brief delay lets WindowServer finish bringing the display online
                    try await Task.sleep(nanoseconds: 500_000_000)
                    guard generation == self.captureGeneration else { return }
                    try await capture.start(displayID: display.displayID,
                                            pixelWidth: preset.pixelWidth,
                                            pixelHeight: preset.pixelHeight, fps: fps)
                    guard generation == self.captureGeneration else { return }
                    encoder.forceKeyframe()
                    self.status = .running(url: Pairing.usbURL)
                } catch {
                    guard generation == self.captureGeneration else { return }
                    self.stopCapture()
                    self.status = .failed("Capture failed: \(error.localizedDescription)")
                }
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func stop() {
        stopCapture()
    }

    func shutdown() {
        stopCapture()
        stopServers()
    }

    private func stopCapture() {
        captureGeneration += 1
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        wsServer?.onClientConnected = nil
        wsServer?.onKeyframeNeeded = nil
        wsServer?.resetBroadcastState()
        let capture = self.capture
        Task { await capture?.stop() }
        encoder?.invalidate()
        self.capture = nil
        encoder = nil
        virtualDisplay = nil
        if status != .stopped { status = .stopped }
    }
}
