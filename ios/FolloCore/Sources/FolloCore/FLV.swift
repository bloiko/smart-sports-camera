import Foundation
import CoreMedia

/// Own FLV packaging (Adobe FLV v10.1 spec): the format YouTube's RTMP ingest carries. The tag *bodies* built here are
/// exactly the payloads of RTMP audio/video/data messages, so the RTMP client (stage 1c) reuses them; `FLVWriter` puts
/// them into an .flv file for tests.
public enum FLV {
    // ---------------------------------------------------------------- video (AVC)

    /// AVC sequence header body: 0x17, packet type 0, composition time 0, AVCDecoderConfigurationRecord ("avcC").
    public static func videoSequenceHeader(avcC: Data) -> Data {
        var d = Data([0x17, 0x00, 0x00, 0x00, 0x00]); d.append(avcC); return d
    }

    /// AVC NALU body: frame type (1 key / 2 inter) | codec 7, packet type 1, composition time 0 (no B-frames), AVCC NAL units.
    public static func videoPacket(_ avcc: Data, isKey: Bool) -> Data {
        var d = Data([isKey ? 0x17 : 0x27, 0x01, 0x00, 0x00, 0x00]); d.append(avcc); return d
    }

    /// AVC end of sequence (packet type 2), sent once when the stream ends (ffmpeg writes it too).
    public static func videoEndOfSequence() -> Data { Data([0x17, 0x02, 0x00, 0x00, 0x00]) }

    /// The avcC record exactly as VideoToolbox describes the stream (SPS/PPS and, for High profile, the chroma fields).
    public static func avcC(of format: CMFormatDescription) -> Data? {
        guard let atoms = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any] else { return nil }
        return atoms["avcC"] as? Data
    }

    // ---------------------------------------------------------------- audio (AAC), used from stage 1e

    /// AAC sequence header body: 0xAF (AAC, 44 kHz, 16 bit, stereo flags as the spec requires for AAC), type 0, AudioSpecificConfig.
    public static func audioSequenceHeader(asc: Data) -> Data { var d = Data([0xAF, 0x00]); d.append(asc); return d }
    public static func audioPacket(_ raw: Data) -> Data { var d = Data([0xAF, 0x01]); d.append(raw); return d }

    // ---------------------------------------------------------------- script data (onMetaData) in AMF0

    public static func metadata(width: Int, height: Int, fps: Double, videoKbps: Double, audio: Bool) -> Data {
        var d = AMF0.string("onMetaData")
        var props: [(String, AMF0.Value)] = [("width", .number(Double(width))), ("height", .number(Double(height))), ("framerate", .number(fps)),
                                              ("videocodecid", .number(7)), ("videodatarate", .number(videoKbps)), ("encoder", .string("Follo"))]
        if audio { props += [("audiocodecid", .number(10)), ("audiosamplerate", .number(44100)), ("stereo", .bool(true))] }
        d.append(AMF0.ecmaArray(props)); return d
    }
}

/// AMF0 encoding (the subset RTMP and FLV metadata need).
public enum AMF0 {
    public indirect enum Value { case number(Double), bool(Bool), string(String), object([(String, Value)]), null }
    public static func number(_ v: Double) -> Data { var d = Data([0x00]); d.append(contentsOf: withUnsafeBytes(of: v.bitPattern.bigEndian, Array.init)); return d }
    public static func bool(_ v: Bool) -> Data { Data([0x01, v ? 1 : 0]) }
    public static func string(_ s: String) -> Data { var d = Data([0x02]); d.append(rawString(s)); return d }
    static func rawString(_ s: String) -> Data { let u = Data(s.utf8); var d = Data([UInt8(u.count >> 8), UInt8(u.count & 0xFF)]); d.append(u); return d }
    public static func null() -> Data { Data([0x05]) }
    public static func value(_ v: Value) -> Data {
        switch v {
        case .number(let x): return number(x)
        case .bool(let b): return bool(b)
        case .string(let s): return string(s)
        case .null: return null()
        case .object(let p): var d = Data([0x03]); for (k, x) in p { d.append(rawString(k)); d.append(value(x)) }; d.append(contentsOf: [0, 0, 9]); return d
        }
    }
    public static func object(_ p: [(String, Value)]) -> Data { value(.object(p)) }
    public static func ecmaArray(_ p: [(String, Value)]) -> Data {
        var d = Data([0x08]); d.append(contentsOf: withUnsafeBytes(of: UInt32(p.count).bigEndian, Array.init))
        for (k, x) in p { d.append(rawString(k)); d.append(value(x)) }
        d.append(contentsOf: [0, 0, 9]); return d
    }
}

/// Writes FLV tags into a file (tests: compare with ffmpeg's FLV of the same packets).
public final class FLVWriter {
    public enum TagType: UInt8 { case audio = 8, video = 9, script = 18 }
    private let h: FileHandle
    public init(path: String, audio: Bool) throws {
        FileManager.default.createFile(atPath: path, contents: nil)
        h = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        h.write(Data([0x46, 0x4C, 0x56, 0x01, audio ? 0x05 : 0x01, 0, 0, 0, 9, 0, 0, 0, 0]))    // "FLV", v1, flags, header size, PreviousTagSize0
    }
    /// One tag: type, 24-bit size, 24-bit timestamp + 8-bit extension (ms), stream id 0, body, PreviousTagSize.
    public func write(_ type: TagType, ms: UInt32, body: Data) {
        let n = UInt32(body.count)
        var t = Data([type.rawValue, UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF),
                      UInt8(ms >> 16 & 0xFF), UInt8(ms >> 8 & 0xFF), UInt8(ms & 0xFF), UInt8(ms >> 24 & 0xFF), 0, 0, 0])
        t.append(body); t.append(contentsOf: withUnsafeBytes(of: (n + 11).bigEndian, Array.init))
        h.write(t)
    }
    public func close() { try? h.close() }
}
