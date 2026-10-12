import Foundation
import CoreImage
import FolloCore

// follosim: run FolloCore on a recorded match on the Mac and compare with the Python simulator.
//   follosim camera DIR B [--swift] [--prior x0,y0,x1,y1]   DIR = work/mN/live (live_det.jsonl + env.json + fmd.png from `live_sim.py --dump`) → DIR/swift_B{B}.json
//   follosim env VIDEO DIR       field mask, content bounds, halfway line from the first 10 s → DIR/swift_env.json + swift_fm.png (compare with env.json)
//   follosim detect VIDEO DIR [--models models/coreml]   Core ML detection + tracker on the whole video → DIR/swift_det.jsonl (+ swift_env.json); then `follosim camera DIR B --swift`
//   follosim highlights DIR VIDEO [--swift] [--no-render]   highlights after Stop from the live path: kick-offs by jersey colour, clips 16:9 + 9:16 → DIR/swift_highlights/
//   follosim track DIR           replay the Python ball candidates through the Swift tracker: ROIs and accepted balls must match
setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments
func die(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }
guard args.count >= 2 else { die("usage: follosim camera DIR B") }

switch args[1] {
case "camera":
    guard args.count >= 4, let B = Double(args[3]) else { die("usage: follosim camera DIR B") }
    let dir = args[2]; let swift = args.contains("--swift")      // --swift: Swift detections and environment instead of Python's
    let env = try! LiveEnv.load(dir: dir, prefix: swift ? "swift_" : "")
    var cfg = CameraConfig()
    if let i = args.firstIndex(of: "--prior") { let v = args[i + 1].split(separator: ",").map { Double($0)! }; cfg.goalsPrior = [Pt(v[0], v[1]), Pt(v[2], v[3])] }
    let cam = LiveCamera(W: env.W, H: env.H, fps: env.fps, fmd: env.fmd, top: env.top, bot: env.bot, centre: env.centre, bufferS: B, config: cfg)
    let t0 = Date(); var n = 0
    for line in try! String(contentsOfFile: dir + (swift ? "/swift_det.jsonl" : "/live_det.jsonl")).split(separator: "\n") {
        if let r = FrameRecord(jsonLine: String(line)) { cam.push(r); n += 1 }
    }
    cam.finish()
    let out = dir + (swift ? "/swiftdet_B\(B.formatted()).json" : "/swift_B\(B.formatted()).json")
    try! CameraPathJSON.write(cam, to: out)
    print("camera B=\(B)s: \(n) frames in \(Int(Date().timeIntervalSince(t0))) s; goals \(cam.goals.map { $0.map { "[\(Int($0.x.rounded())), \(Int($0.y.rounded()))]" } } ?? []) → \(out)")
case "track":
    let dir = args[2]; let env = try! LiveEnv.load(dir: dir)
    let tr = BallTracker(W: env.W, H: env.H, fps: env.fps, fm: try! Mask.loadPNG(dir + "/fm.png"), fmd: env.fmd)
    var n = 0, roiBad = 0, ballBad = 0, firstBad = -1
    for line in try! String(contentsOfFile: dir + "/live_det.jsonl").split(separator: "\n") {
        guard let r = FrameRecord(jsonLine: String(line)) else { continue }
        if let ps = r.persons { tr.playersSeen(ps); for h in r.hints ?? [] { tr.addHint(h, frame: r.frame) } }
        guard let prois = r.rois else { continue }
        n += 1
        let rois = tr.rois(frame: r.frame)
        if rois.count != prois.count || zip(rois, prois).contains(where: { $0.0 != $1.0 || $0.1 != $1.1 }) {
            roiBad += 1; if firstBad < 0 { firstBad = r.frame }
            if let dbg = args.firstIndex(of: "--debug"), Int(args[dbg + 1]) == r.frame { print("frame \(r.frame): python rois \(prois) swift \(rois)\n  swift candidates \(tr.debugCands(frame: r.frame))") }
        }
        let (ball, black) = tr.accept(frame: r.frame, r.balls ?? [])
        let same = (ball == nil) == (r.ball == nil) && (black == nil) == (r.black == nil) && (ball == nil || (abs(ball!.x - r.ball!.x) < 0.06 && abs(ball!.y - r.ball!.y) < 0.06))
        if !same { ballBad += 1; if firstBad < 0 { firstBad = r.frame } }
    }
    print("track: \(n) ball frames, ROI mismatches \(roiBad), ball mismatches \(ballBad)" + (firstBad >= 0 ? ", first at frame \(firstBad)" : "") + (roiBad + ballBad == 0 ? " → SAME TRACK" : " → DIFFERENT"))
case "env", "detect":
    guard args.count >= 4 else { die("usage: follosim \(args[1]) VIDEO DIR") }
    let video = args[2], dir = args[3]
    let reader = try! VideoReader(path: video); print("video \(reader.W)×\(reader.H) @ \(reader.fps) fps, \(reader.frames) frames")
    let t0 = Date(); let env = try! LiveEnv.make(reader: reader)
    try! env.save(dir: dir, prefix: "swift_"); print("env (field mask, bounds, halfway line) in \(Int(Date().timeIntervalSince(t0))) s: field share \(env.fmd.share.formatted(.number.precision(.fractionLength(3))))")
    if args[1] == "env" { break }
    let models = URL(fileURLWithPath: args.firstIndex(of: "--models").map { args[$0 + 1] } ?? "models/coreml")   // from the repository root
    let pl = try! Detector(url: models.appendingPathComponent("players.mlpackage")), bd = try! Detector(url: models.appendingPathComponent("ball.mlpackage"))
    let pipe = LivePipeline(W: reader.W, H: reader.H, fps: reader.fps, fm: env.fm!, fmd: env.fmd, players: pl, ball: bd)
    let limit = args.firstIndex(of: "--frames").map { Int(args[$0 + 1])! } ?? Int.max      // --frames N: stop early (tests)
    try! reader.start(); var f = 0; let t1 = Date(); var lines: [String] = []; var found = 0, passes = 0
    while f < limit {
        // autoreleasepool: without it the ObjC objects of every frame (sample buffers, CIImages, model outputs) pile up
        let more: Bool = autoreleasepool {
            guard let pb = reader.next() else { return false }
            let rec = pipe.process(frame: f, image: CIImage(cvPixelBuffer: pb), grey: { Image8.grey(from: pb) })
            lines.append(rec.jsonLine); if rec.rois != nil { passes += 1; if rec.ball != nil { found += 1 } }
            f += 1; if f % 1000 == 0 { print("  \(f)/\(reader.frames) \(Int(Date().timeIntervalSince(t1))) s") }
            return true
        }
        if !more { break }
    }
    try! lines.joined(separator: "\n").appending("\n").write(toFile: dir + "/swift_det.jsonl", atomically: true, encoding: .utf8)
    let n = Double(f)
    print("detection: \(Int(Date().timeIntervalSince(t1))) s for \(f) frames; players pass \(Int(pipe.timePlayers / (n / Double(pipe.playerEvery)) * 1000)) ms every \(pipe.playerEvery) frames, ball ROI \(Int(pipe.timeBall / Double(max(pipe.ballCalls, 1)) * 1000)) ms × \((Double(pipe.ballCalls) / (n / Double(pipe.ballEvery))).formatted(.number.precision(.fractionLength(2)))) per pass every \(pipe.ballEvery) frames (Core ML on this Mac)")
    print("live ball found on \((Double(found) / Double(max(passes, 1)) * 100).formatted(.number.precision(.fractionLength(1))))% of ball passes → \(dir)/swift_det.jsonl")
case "highlights":
    guard args.count >= 4 else { die("usage: follosim highlights DIR VIDEO [--swift] [--no-render]") }
    let dir = args[2], video = args[3], swift = args.contains("--swift"); let prefix = swift ? "swift_" : ""
    let env = try! LiveEnv.load(dir: dir, prefix: prefix)
    let cam = LiveCamera(W: env.W, H: env.H, fps: env.fps, fmd: env.fmd, top: env.top, bot: env.bot, centre: env.centre, bufferS: 2)
    var persons: [Int: [Box]] = [:]
    for line in try! String(contentsOfFile: dir + (swift ? "/swift_det.jsonl" : "/live_det.jsonl")).split(separator: "\n") {
        if let r = FrameRecord(jsonLine: String(line)) { cam.push(r); if let p = r.persons, r.frame % Jersey.every == 0 { persons[r.frame] = p } }
    }
    cam.finish()
    guard let goals = cam.goals else { die("no goals found") }
    // jersey colours from the video at the sampled frames (the phone does this during the live)
    let reader = try! VideoReader(path: video); try! reader.start(); var F: [JerseySample] = []; var f = 0; let last = persons.keys.max() ?? 0
    while f <= last { let more: Bool = autoreleasepool { guard let pb = reader.next() else { return false }; if let ps = persons[f] { F += Jersey.samples(frame: f, img: Image8(bgra: pb), persons: ps, fmd: env.fmd) }; f += 1; return true }; if !more { break } }
    let (T, S) = Kickoff.separation(F, centreX: (goals[0].x + goals[1].x) / 2, fps: env.fps); let kicks = Kickoff.find(T, S)
    print("separation max \((S.max() ?? 0).formatted(.number.precision(.fractionLength(2)))) at \(S.isEmpty ? 0 : T[S.indices.max(by: { S[$0] < S[$1] })!]) s; kickoffs \(kicks)")
    let zc = cam.zoneCounts(); var ms = Highlights.moments(cam.frames, fps: env.fps, goals: goals, sFrames: zc.frames, zn: zc.zn, base: zc.base)
    Highlights.markGoals(&ms, kickoffs: kicks); ms = ms.filter { $0.score >= Highlights.minScore }
    let hd = dir + (swift ? "/swiftdet_highlights" : "/swift_highlights"); try! FileManager.default.createDirectory(atPath: hd + "/vertical", withIntermediateDirectories: true)
    let paths = [ClosePath.make(cam.frames, fps: env.fps, W: env.W, H: env.H, top: env.top, bot: env.bot, goals: goals), ClosePath.make(cam.frames, fps: env.fps, W: env.W, H: env.H, top: env.top, bot: env.bot, goals: goals, vertical: true)]
    let rend = ClipRenderer(); var report: [[String: Any]] = []
    for (k, var m) in ms.enumerated() {
        let name = String(format: "clip_%02d_%dm%02ds.mp4", k + 1, Int(m.peak) / 60, Int(m.peak) % 60); m.file = name
        if !args.contains("--no-render") {
            try! rend.render(video: video, path: paths[0], out: URL(fileURLWithPath: hd + "/" + name), t0: m.start, t1: m.end, size: (1920, 1080), label: m.label)
            try! rend.render(video: video, path: paths[1], out: URL(fileURLWithPath: hd + "/vertical/" + name), t0: m.start, t1: m.end, size: (1080, 1920), label: m.label)
        }
        print(String(format: "%6.1f-%6.1fs  %@ %@ danger %.2f  %@", m.start, m.end, m.goal == 0 ? "left " : "right", m.kind, m.score, name))
        report.append(["start": m.start, "end": m.end, "peak": m.peak, "goal": m.goal == 0 ? "left" : "right", "kind": m.kind, "ep_end": m.epEnd, "score": m.score, "ball": m.ball, "players": m.players, "file": name])
    }
    let rep: [String: Any] = ["kickoffs": kicks.map { [$0.0, $0.1] }, "separation": zip(T, S).map { [$0, $1] }, "clips": report,
                              "jerseys": F.map { [Double($0.frame), $0.x, $0.a, $0.b] }]
    try! JSONSerialization.data(withJSONObject: rep).write(to: URL(fileURLWithPath: hd + "/live_highlights.json"))
    print("\(ms.count) clips → \(hd)")
default: die("unknown command \(args[1])")
}
