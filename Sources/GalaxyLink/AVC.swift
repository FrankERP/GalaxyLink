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
