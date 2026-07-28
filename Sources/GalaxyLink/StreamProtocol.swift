import Foundation

enum FrameType: UInt8 {
    case config = 0x01
    case video = 0x02
    // 0x10+ reserved for future input events (tablet -> Mac)
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
