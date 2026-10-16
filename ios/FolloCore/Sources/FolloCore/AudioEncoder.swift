import Foundation
import AVFoundation

/// Own AAC-LC encoder on AVAudioConverter (system framework) for the live stream (stage 1e): PCM from the microphone in,
/// raw AAC packets (1024 samples each) out, with the AudioSpecificConfig for the stream header. Replaces the audio path
/// inside HaishinKit.
public final class AudioEncoder {
    public struct Settings: Equatable {
        public var sampleRate = 48_000.0, channels = 1, bitrate = 128_000
        public init() {}
    }
    public let settings: Settings
    /// One AAC packet and the index of its first sample (timestamp = sample / sampleRate).
    public var onPacket: ((Data, Int64) -> Void)?
    public private(set) var packets = 0

    private let converter: AVAudioConverter
    private let inFormat: AVAudioFormat, outFormat: AVAudioFormat
    private var pending: [AVAudioPCMBuffer] = []
    private var nextSample: Int64 = 0

    public init(_ s: Settings) throws {
        settings = s
        guard let inF = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: s.sampleRate, channels: AVAudioChannelCount(s.channels), interleaved: false) else { throw NSError(domain: "AudioEncoder", code: 1) }
        var desc = AudioStreamBasicDescription(mSampleRate: s.sampleRate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: UInt32(MPEG4ObjectID.AAC_LC.rawValue),
                                               mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0, mChannelsPerFrame: UInt32(s.channels), mBitsPerChannel: 0, mReserved: 0)
        guard let outF = AVAudioFormat(streamDescription: &desc), let conv = AVAudioConverter(from: inF, to: outF) else { throw NSError(domain: "AudioEncoder", code: 2) }
        conv.bitRate = s.bitrate
        inFormat = inF; outFormat = outF; converter = conv
    }

    /// AudioSpecificConfig (ISO 14496-3): AAC LC, sampling frequency index, channel configuration.
    public var audioSpecificConfig: Data {
        let rates: [Double] = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
        let fi = UInt16(rates.firstIndex(of: settings.sampleRate) ?? 3)
        let v: UInt16 = 2 << 11 | fi << 7 | UInt16(settings.channels) << 3
        return Data([UInt8(v >> 8), UInt8(v & 0xFF)])
    }

    /// Float32 non-interleaved PCM at `settings.sampleRate` / `channels`.
    public func append(_ buffer: AVAudioPCMBuffer) {
        pending.append(buffer)
        while true {
            let out = AVAudioCompressedBuffer(format: outFormat, packetCapacity: 1, maximumPacketSize: converter.maximumOutputPacketSize)
            var err: NSError?
            let st = converter.convert(to: out, error: &err) { [weak self] _, status in
                guard let self, !self.pending.isEmpty else { status.pointee = .noDataNow; return nil }
                status.pointee = .haveData; return self.pending.removeFirst()
            }
            if out.packetCount > 0, let d = out.packetDescriptions?[0] {
                let data = Data(bytes: out.data.advanced(by: Int(d.mStartOffset)), count: Int(d.mDataByteSize))
                onPacket?(data, nextSample); nextSample += 1024; packets += 1
            }
            if st != .haveData || out.packetCount == 0 { break }
        }
    }

    /// The input format the encoder expects (convert the microphone or file audio to it first).
    public var inputFormat: AVAudioFormat { inFormat }
}
