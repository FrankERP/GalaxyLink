import Foundation
import VideoToolbox
import CoreMedia

final class H264Encoder {
    struct EncodedFrame {
        let annexB: Data          // keyframes already include SPS/PPS prefix
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
        var status = VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: spec as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &session)
        if status != noErr {
            // Some encoders reject the low-latency spec; retry without it.
            status = VTCompressionSessionCreate(
                allocator: nil, width: Int32(width), height: Int32(height),
                codecType: kCMVideoCodecType_H264,
                encoderSpecification: nil,
                imageBufferAttributes: nil, compressedDataAllocator: nil,
                outputCallback: nil, refcon: nil, compressionSessionOut: &session)
        }
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
