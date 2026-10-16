import VideoToolbox
import AVFoundation
import ImageIO
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
case "ballroi":   // follosim ballroi VIDEO DIR [--cvlike] — the Core ML ball model on Python's own ROIs: agreement with Python's candidates
    let reader = try! VideoReader(path: args[2]); let dir = args[3]
    let bd = try! Detector(url: URL(fileURLWithPath: "models/coreml/ball.mlpackage")); bd.cvLike = args.contains("--cvlike")
    var recs: [Int: FrameRecord] = [:]
    for line in try! String(contentsOfFile: dir + "/live_det.jsonl").split(separator: "\n") { if let r = FrameRecord(jsonLine: String(line)), r.rois != nil { recs[r.frame] = r } }
    try! reader.start(); var f = 0; var py = 0, pyHit = 0, ml = 0, mlHit = 0, confD: [Double] = []
    while let pb = reader.next() {
        autoreleasepool {
            if let r = recs[f + (args.firstIndex(of: "--shift").map { Int(args[$0 + 1])! } ?? 0)], let rois = r.rois {
                let img = CIImage(cvPixelBuffer: pb); var c: [Box] = []
                for (x0, y0) in rois { c += bd.run(img, rect: CGRect(x: x0, y: y0, width: 320, height: 320), scale: 2, conf: 0.1).map { $0.box } }
                let p = (r.balls ?? []).map { $0.box }
                for b in p where b.conf >= 0.4 { py += 1; if let m = c.first(where: { abs($0.cx - b.cx) < 4 && abs($0.cy - b.cy) < 4 }) { pyHit += 1; confD.append(m.conf - b.conf) }
                    else if args.contains("--show"), py % 50 == 0 { print("miss f\(f) py (\(Int(b.cx)),\(Int(b.cy))) \(b.conf) | coreml " + c.map { "(\(Int($0.cx)),\(Int($0.cy))) \(String(format: "%.2f", $0.conf))" }.joined(separator: " ")) } }
                for b in c where b.conf >= 0.4 { ml += 1; if p.contains(where: { abs($0.cx - b.cx) < 4 && abs($0.cy - b.cy) < 4 }) { mlHit += 1 } }
            }
        }
        f += 1
    }
    print("python balls ≥0.4: \(py), found by Core ML \(pyHit) (\(pyHit * 100 / max(py, 1))%); Core ML balls ≥0.4: \(ml), also in Python \(mlHit) (\(mlHit * 100 / max(ml, 1))%); conf diff median \(Stats.percentile(confD, 50))")
case "frames":   // follosim frames VIDEO — sample timestamps as AVAssetReader gives them (frame alignment with cv2)
    let a = AVURLAsset(url: URL(fileURLWithPath: args[2])); let t = a.tracks(withMediaType: .video)[0]
    let r = try! AVAssetReader(asset: a); let o = AVAssetReaderTrackOutput(track: t, outputSettings: args.contains("--decoded") ? [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA] : nil); r.add(o); r.startReading()
    var n = 0; var first: [String] = []
    while let sb = o.copyNextSampleBuffer() {
        if CMSampleBufferGetNumSamples(sb) > 0 { if n < 4 { first.append(String(format: "%.3f", CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb)))) }; n += 1 }
    }
    print("samples \(n), first PTS \(first), track timeRange start \(CMTimeGetSeconds(t.timeRange.start)) segments \(t.segments.prefix(3).map { "\(CMTimeGetSeconds($0.timeMapping.source.start))→\(CMTimeGetSeconds($0.timeMapping.target.start)) empty \($0.isEmpty)" })")
case "encode":   // follosim encode VIDEO PATH.json OUT.mp4 [--from S] [--seconds N] [--bitrate B] [--raw-stdout]
    // Stage 1a: the stream frames (1080p crops of the camera path) through our VideoEncoder → OUT.mp4 (passthrough).
    // --raw-stdout writes the uncompressed BGRA crops to stdout instead (reference for ffmpeg: same frames, other encoder).
    let raw = args.contains("--raw-stdout")
    func log(_ t: String) { FileHandle.standardError.write((t + "\n").data(using: .utf8)!) }
    let reader = try! VideoReader(path: args[2]); let fps = reader.fps
    let path = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[3]))) as! [String: Any]
    let PX = path["X"] as! [Double], PY = path["Y"] as! [Double], PW = path["CW"] as! [Double], PH = path["CH"] as! [Double]
    let f0 = Int((args.firstIndex(of: "--from").map { Double(args[$0 + 1])! } ?? 0) * fps)
    let n = Int((args.firstIndex(of: "--seconds").map { Double(args[$0 + 1])! } ?? 10) * fps)
    let size = (args.firstIndex(of: "--size").map { args[$0 + 1] } ?? "1920x1080").split(separator: "x").map { Int($0)! }
    let OW = size[0], OH = size[1]
    var es = VideoEncoder.Settings(); es.width = OW; es.height = OH; es.fps = fps; es.bitrate = args.firstIndex(of: "--bitrate").map { Int(args[$0 + 1])! } ?? 4_500_000
    let enc = try! VideoEncoder(es)
    // --steps 4:3000000,7:2000000 → setBitrate at those seconds (adaptive bitrate); --force-key 3.3 → forced keyframe
    let steps: [(Int, Int)] = (args.firstIndex(of: "--steps").map { args[$0 + 1] } ?? "").split(separator: ",").map { p in let a = p.split(separator: ":"); return (Int(Double(a[0])! * fps), Int(a[1])!) }
    let forceAt = args.firstIndex(of: "--force-key").map { Int(Double(args[$0 + 1])! * fps) } ?? -1
    let ctx = CIContext(options: [.cacheIntermediates: false])
    var pool: CVPixelBufferPool?
    CVPixelBufferPoolCreate(nil, nil, [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: OW,
                                       kCVPixelBufferHeightKey as String: OH, kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &pool)
    var writer: AVAssetWriter?, input: AVAssetWriterInput?
    let flvPath = args.firstIndex(of: "--flv").map { args[$0 + 1] }; var flv: FLVWriter?      // stage 1b: our FLV of the same packets
    var sizes: [Int] = [], keys: [Int] = [], submitted: [Double] = [], latency: [Double] = []
    let out = URL(fileURLWithPath: args[4]); try? FileManager.default.removeItem(at: out)
    let q = DispatchQueue(label: "enc.out")
    enc.onFrame = { fr in q.sync {
        if writer == nil {
            let w = try! AVAssetWriter(outputURL: out, fileType: .mp4)
            let i = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: fr.format); i.expectsMediaDataInRealTime = false
            w.add(i); w.startWriting(); w.startSession(atSourceTime: fr.pts); writer = w; input = i
            log("parameter sets: \(fr.parameterSets.map { $0.count }) bytes")
            if let fp = flvPath, let avcC = FLV.avcC(of: fr.format) {
                flv = try! FLVWriter(path: fp, audio: false)
                flv!.write(.script, ms: 0, body: FLV.metadata(width: OW, height: OH, fps: fps, videoKbps: Double(es.bitrate) / 1000, audio: false))
                flv!.write(.video, ms: 0, body: FLV.videoSequenceHeader(avcC: avcC))
                log("avcC \(avcC.count) bytes: \(avcC.prefix(8).map { String(format: "%02x", $0) }.joined())")
            }
        }
        flv?.write(.video, ms: UInt32((CMTimeGetSeconds(fr.pts) * 1000).rounded()), body: FLV.videoPacket(fr.data, isKey: fr.isKey))
        while !input!.isReadyForMoreMediaData { usleep(1000) }
        input!.append(fr.sampleBuffer()!)
        let k = sizes.count
        if fr.isKey { keys.append(k) }
        sizes.append(fr.data.count); latency.append(CACurrentMediaTime() - submitted[k])
    } }
    try! reader.start(from: f0)
    let stdout = FileHandle.standardOutput; let t0 = Date()
    for i in 0..<n {
        let more: Bool = autoreleasepool {
            guard let pb = reader.next() else { return false }
            let f = f0 + i, H = Double(CVPixelBufferGetHeight(pb))
            let rect = CGRect(x: PX[f] - PW[f] / 2, y: H - (PY[f] + PH[f] / 2), width: PW[f], height: PH[f])    // as LiveCameraRunner.emit
            var img = CIImage(cvPixelBuffer: pb).cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            img = img.transformed(by: CGAffineTransform(scaleX: Double(OW) / PW[f], y: Double(OH) / PH[f]))
            var o: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, pool!, &o); let ob = o!
            ctx.render(img, to: ob, bounds: CGRect(x: 0, y: 0, width: OW, height: OH), colorSpace: CGColorSpaceCreateDeviceRGB())
            if raw {
                CVPixelBufferLockBaseAddress(ob, .readOnly); let bpr = CVPixelBufferGetBytesPerRow(ob), base = CVPixelBufferGetBaseAddress(ob)!
                var d = Data(capacity: OW * OH * 4); for y in 0..<OH { d.append(Data(bytes: base + y * bpr, count: OW * 4)) }
                CVPixelBufferUnlockBaseAddress(ob, .readOnly); stdout.write(d)
            } else {
                q.sync { submitted.append(CACurrentMediaTime()) }
                if let st = steps.first(where: { $0.0 == i }) { enc.setBitrate(st.1); log("bitrate → \(st.1 / 1000) at frame \(i)") }
                enc.encode(ob, pts: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps.rounded())), forceKey: i == forceAt)
            }
            return true
        }
        if !more { break }
    }
    if raw { log("raw: \(n) frames"); break }
    enc.flush(); q.sync {}
    if let f = flv { f.write(.video, ms: UInt32(((Double(sizes.count - 1) / fps) * 1000).rounded()), body: FLV.videoEndOfSequence()); f.close() }
    let done = DispatchSemaphore(value: 0); input?.markAsFinished(); writer?.finishWriting { done.signal() }; done.wait()
    let secs = Double(sizes.count) / fps, kbps = Double(sizes.reduce(0, +)) * 8 / secs / 1000
    var perSecond: [Double] = []; var j = 0
    while j < sizes.count { perSecond.append(Double(sizes[j..<min(j + Int(fps), sizes.count)].reduce(0, +)) * 8 / 1000); j += Int(fps) }
    let gaps = zip(keys.dropFirst(), keys).map { $0 - $1 }
    if args.contains("--per-second") { log("per-second kbit/s: " + perSecond.map { "\(Int($0))" }.joined(separator: " ")) }
    log("encoded \(sizes.count)/\(n) frames (dropped \(enc.dropped)) in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s; average \(Int(kbps)) kbit/s (target \(es.bitrate / 1000)); per-second max \(Int(perSecond.max() ?? 0)) min \(Int(perSecond.min() ?? 0)); keyframes at \(keys.prefix(6))…, gaps \(Set(gaps).sorted()); latency median \(Int(Stats.percentile(latency, 50) * 1000)) ms p95 \(Int(Stats.percentile(latency, 95) * 1000)) ms → \(args[4])")
case "scoreboards":   // follosim scoreboards DIR — every style in four states (design review)
    var st = ScoreState(home: ScoreTeam(name: "ФК Іваничі", r: 0.95, g: 0.95, b: 0.95), away: ScoreTeam(name: "ФК Андердог", r: 0.1, g: 0.3, b: 0.85))
    let states: [(String, Int, Int, ScoreExtras)] = [
        ("play", 1, 0, ScoreExtras(clock: "23:15", half: 1)), ("added", 2, 1, ScoreExtras(clock: "90:00", half: 2, added: 3)),
        ("break", 1, 1, ScoreExtras(clock: "45:00", half: 1, phase: "ПЕРЕРВА")), ("goal", 2, 1, ScoreExtras(clock: "67:42", half: 2, goalFor: 0)),
        ("red", 2, 1, ScoreExtras(clock: "71:05", half: 2, redFor: 1))]
    for (style, full) in ScoreStyle.allCases.map({ ($0, false) }) + [(.classic, true)] { for (name, h, a, var ex) in states {
        st.homeGoals = h; st.awayGoals = a; ex.fullNames = full; st.homeRed = name == "red" ? 1 : 0; st.awayRed = name == "red" ? 2 : 0
        let img = Scoreboard.renderStyled(st, style: style, extras: ex)!
        let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(args[2])/\(style.rawValue)\(full ? "full" : "")_\(name).png") as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst)
    } }
    st.homeGoals = 2; st.awayGoals = 1; st.homeRed = 1; st.awayRed = 2
    for cs in RedCardStyle.allCases {                     // red card placements on the chosen design
        var ex = ScoreExtras(clock: "71:05", half: 2, fullNames: true); ex.cards = cs
        let img = Scoreboard.renderStyled(st, style: .classic, extras: ex)!
        let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(args[2])/cards_\(cs.rawValue).png") as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst)
    }
    print("written to \(args[2])")
case "scoreboard":   // follosim scoreboard OUT.png — the score bug as the stream shows it (for a look on the Mac)
    var st = ScoreState(home: ScoreTeam(name: "Tsukuba", r: 0.95, g: 0.95, b: 0.95), away: ScoreTeam(name: "Kyiv United FC", r: 0.1, g: 0.35, b: 0.9))
    st.homeGoals = 2; st.awayGoals = 1
    let img = Scoreboard.render(st, clock: Scoreboard.clock(37 * 60 + 12))!
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst); print("\(img.width)×\(img.height) → \(args[2])")
case "position":   // follosim position work/mN/live_pre — the Go live position check on a saved environment
    let e = try LiveEnv.load(dir: args[2])
    let fb = e.fm?.farBand
    print("far band \(fb.map { "\(Int($0.0))..\(Int($0.1)) of \(e.W)" } ?? "none"): \(e.positionProblem ?? "ok")")
case "envq":       // follosim envq VIDEO DIR K — the environment as the phone builds it: 7 frames downscaled K× (box), then scaled(K)
    let reader = try! VideoReader(path: args[2]); let k = Int(args[4])!
    try! reader.start(); let n = min(reader.frames, Int(LiveEnv.prerollS * reader.fps))
    let idx = (0..<7).map { Int(Double(n) * (Double($0) + 0.5) / 7) }
    var frames: [Image8] = []; var f = 0
    while f <= idx.last!, let pb = reader.next() {
        if idx.contains(f) {
            let im = Image8(bgra: pb); let w = im.w / k, h = im.h / k; var d = [UInt8](repeating: 0, count: w * h * 3)
            for y in 0..<h { for x in 0..<w { for c in 0..<3 { var sum = 0
                for yy in 0..<k { for xx in 0..<k { sum += Int(im.data[((y * k + yy) * im.w + x * k + xx) * 3 + c]) } }
                d[(y * w + x) * 3 + c] = UInt8(sum / (k * k)) } } }
            frames.append(Image8(w: w, h: h, ch: 3, data: d))
        }
        f += 1
    }
    let e = LiveEnv.make(frames: frames, fps: reader.fps).scaled(k)
    try! e.save(dir: args[3], prefix: "q\(k)_"); print("saved q\(k)_env: fmd share \(e.fmd.share), position \(e.positionProblem ?? "ok")")
case "camera":
    guard args.count >= 4, let B = Double(args[3]) else { die("usage: follosim camera DIR B") }
    let dir = args[2]; let swift = args.contains("--swift")      // --swift: Swift detections and environment instead of Python's
    let envPrefix = args.firstIndex(of: "--env").map { args[$0 + 1] } ?? (swift ? "swift_" : "")   // --env q4_: the phone's environment
    let env = try! LiveEnv.load(dir: dir, prefix: envPrefix)
    var cfg = CameraConfig()
    if let i = args.firstIndex(of: "--prior") { let v = args[i + 1].split(separator: ",").map { Double($0)! }; cfg.goalsPrior = [Pt(v[0], v[1]), Pt(v[2], v[3])] }
    let cam = LiveCamera(W: env.W, H: env.H, fps: env.fps, fmd: env.fmd, top: env.top, bot: env.bot, centre: env.centre, bufferS: B, config: cfg)
    let t0 = Date(); var n = 0
    for line in try! String(contentsOfFile: dir + (swift ? "/swift_det.jsonl" : "/live_det.jsonl")).split(separator: "\n") {
        if let r = FrameRecord(jsonLine: String(line)) { cam.push(r); n += 1 }
    }
    cam.finish()
    let out = dir + (swift ? "/swiftdet_B\(B.formatted()).json" : "/swift_B\(B.formatted()).json").replacingOccurrences(of: "_B", with: args.contains("--env") ? "_\(envPrefix)B" : "_B")
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
    if args.contains("--full-tiles") {          // the old full-height tiles on any frame (to compare on 16:9)
        let tw = (reader.W + 100) / 2; pipe.playerRects = (0..<2).map { k in CGRect(x: max(0, min(k * (tw - 50), reader.W - tw)), y: 0, width: tw, height: reader.H) }
    }
    print("player tiles: " + pipe.playerRects.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))×\(Int($0.height))" }.joined(separator: " | "))
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
