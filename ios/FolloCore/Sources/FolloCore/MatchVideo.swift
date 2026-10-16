import Foundation
import AVFoundation

/// The wide recording of one match is a series of chunk files (3 min each). These helpers play them as one video and
/// join them into one file without re-encoding (for "Зберегти у Фото").
public enum MatchVideo {
    /// All chunks one after another (video and, when present, audio).
    public static func composition(_ chunks: [URL]) async throws -> AVMutableComposition {
        let comp = AVMutableComposition()
        let v = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        var a: AVMutableCompositionTrack?
        var at = CMTime.zero
        for u in chunks {
            let asset = AVURLAsset(url: u)
            let dur = try await asset.load(.duration)
            guard dur.seconds > 0 else { continue }
            if let t = try await asset.loadTracks(withMediaType: .video).first {
                try v?.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: t, at: at)
                if at == .zero { v?.preferredTransform = try await t.load(.preferredTransform) }
            }
            if let t = try await asset.loadTracks(withMediaType: .audio).first {
                if a == nil { a = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) }
                try a?.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: t, at: at)
            }
            at = CMTimeAdd(at, dur)
        }
        return comp
    }

    /// Join the chunks into one .mp4 at `out` without re-encoding (passthrough). Needs free space about the size of the chunks.
    public static func join(_ chunks: [URL], to out: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let comp = try await composition(chunks)
        try? FileManager.default.removeItem(at: out)
        guard let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else { throw NSError(domain: "MatchVideo", code: 1) }
        ex.outputURL = out; ex.outputFileType = .mp4; ex.shouldOptimizeForNetworkUse = false
        nonisolated(unsafe) let session = ex                       // read-only progress polling
        let poll = Task { while !Task.isCancelled { progress?(Double(session.progress)); try? await Task.sleep(nanoseconds: 500_000_000) } }
        await ex.export()
        poll.cancel()
        if ex.status != .completed { throw ex.error ?? NSError(domain: "MatchVideo", code: 2) }
        progress?(1)
    }

    /// Total size of the files in bytes.
    public static func bytes(_ urls: [URL]) -> Int64 {
        urls.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}
