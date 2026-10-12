import Foundation
import CoreImage
import FolloCore

// follosim: run FolloCore on a recorded match on the Mac and compare with the Python simulator.
//   follosim camera DIR B        DIR = work/mN/live (live_det.jsonl + env.json + fmd.png from `live_sim.py --dump`) → DIR/swift_B{B}.json
//   follosim env VIDEO DIR       field mask, content bounds, halfway line from the first 10 s → DIR/swift_env.json + swift_fm.png (compare with env.json)
//   follosim detect VIDEO DIR [--models models/coreml]   Core ML detection + tracker on the whole video → DIR/swift_det.jsonl (+ swift_env.json); then `follosim camera DIR B --swift`
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
    let cam = LiveCamera(W: env.W, H: env.H, fps: env.fps, fmd: env.fmd, top: env.top, bot: env.bot, centre: env.centre, bufferS: B)
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
default: die("unknown command \(args[1])")
}
