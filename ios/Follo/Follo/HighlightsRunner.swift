import Foundation
import AVFoundation
import FolloCore

/// Пункт «після Стоп»: хайлайти з записаних 4K-файлів і live-траєкторії (без повторної детекції).
/// Кольори форми зібрано під час ефіру (LivePipeline.jerseys), кікоф → гол, кліпи 16:9 і 9:16 у Documents/highlights/.
final class HighlightsRunner {
    struct Clip { let file: URL; let vertical: URL; let label: String; let kind: String; let start: Double; let end: Double }

    /// `chunks`: файли запису по порядку; `cam`, `pipe`, `env` — з LiveCameraRunner після Стоп.
    static func make(chunks: [URL], cam: LiveCamera, jerseys: [JerseySample], env: LiveEnv, progress: @escaping (String) -> Void) throws -> [Clip] {
        guard let goals = cam.goals, !chunks.isEmpty else { return [] }
        progress("Склеюю запис…")
        let comp = AVMutableComposition(); let track = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        var at = CMTime.zero
        for u in chunks { let a = AVURLAsset(url: u); if let t = a.tracks(withMediaType: .video).first { try track.insertTimeRange(CMTimeRange(start: .zero, duration: a.duration), of: t, at: at); at = CMTimeAdd(at, a.duration) } }
        let joined = FileManager.default.temporaryDirectory.appendingPathComponent("joined.mov")
        try? FileManager.default.removeItem(at: joined)
        let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough)!; ex.outputURL = joined; ex.outputFileType = .mov
        let sem = DispatchSemaphore(value: 0); ex.exportAsynchronously { sem.signal() }; sem.wait()
        guard ex.status == .completed else { throw ex.error ?? NSError(domain: "Highlights", code: 1) }
        progress("Шукаю голи…")
        let (T, S) = Kickoff.separation(jerseys, centreX: (goals[0].x + goals[1].x) / 2, fps: cam.fps); let kicks = Kickoff.find(T, S)
        let zc = cam.zoneCounts(); var ms = Highlights.moments(cam.frames, fps: cam.fps, goals: goals, sFrames: zc.frames, zn: zc.zn, base: zc.base)
        Highlights.markGoals(&ms, kickoffs: kicks); ms = ms.filter { $0.score >= Highlights.minScore }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("highlights")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("vertical"), withIntermediateDirectories: true)
        let paths = [ClosePath.make(cam.frames, fps: cam.fps, W: env.W, H: env.H, top: env.top, bot: env.bot, goals: goals),
                     ClosePath.make(cam.frames, fps: cam.fps, W: env.W, H: env.H, top: env.top, bot: env.bot, goals: goals, vertical: true)]
        let rend = ClipRenderer(); var out: [Clip] = []
        for (k, m) in ms.enumerated() {
            progress("Кліп \(k + 1) з \(ms.count)…")
            let name = String(format: "clip_%02d_%dm%02ds.mp4", k + 1, Int(m.peak) / 60, Int(m.peak) % 60)
            let f = dir.appendingPathComponent(name), v = dir.appendingPathComponent("vertical/" + name)
            try rend.render(video: joined.path, path: paths[0], out: f, t0: m.start, t1: m.end, size: (1920, 1080), label: m.label)
            try rend.render(video: joined.path, path: paths[1], out: v, t0: m.start, t1: m.end, size: (1080, 1920), label: m.label)
            out.append(Clip(file: f, vertical: v, label: m.label, kind: m.kind, start: m.start, end: m.end))
        }
        return out
    }
}
