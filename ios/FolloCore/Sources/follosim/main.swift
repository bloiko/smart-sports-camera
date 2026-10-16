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
    // stage 1c: --rtmp URL --key KEY publishes the same packets with our RTMP client (--realtime paces them at fps)
    var rtmp: RTMPClient?
    if let i = args.firstIndex(of: "--rtmp") {
        let r = RTMPClient(); r.log = { log("rtmp: " + $0) }; r.trustAnyCertificateForTests = args.contains("--insecure-tls")
        let ready = DispatchSemaphore(value: 0)
        r.onState = { st in if st == .publishing { ready.signal() }; if case .failed = st { ready.signal() } }
        r.connect(url: args[i + 1], key: args.firstIndex(of: "--key").map { args[$0 + 1] } ?? "test")
        if ready.wait(timeout: .now() + 15) == .timedOut || r.state != .publishing { log("rtmp: not publishing (\(r.state))"); exit(2) }
        rtmp = r
    }
    let realtime = args.contains("--realtime"); var sentHeader = false
    let tsOffset = UInt32(args.firstIndex(of: "--ts-offset").map { args[$0 + 1] } ?? "0")!     // test the extended-timestamp path
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
                flv!.write(.video, ms: tsOffset, body: FLV.videoSequenceHeader(avcC: avcC))
                log("avcC \(avcC.count) bytes: \(avcC.prefix(8).map { String(format: "%02x", $0) }.joined())")
            }
        }
        let ms = UInt32((CMTimeGetSeconds(fr.pts) * 1000).rounded()) + tsOffset
        flv?.write(.video, ms: ms, body: FLV.videoPacket(fr.data, isKey: fr.isKey))
        if let r = rtmp {
            if !sentHeader, let avcC = FLV.avcC(of: fr.format) {
                r.sendMetadata(FLV.metadata(width: OW, height: OH, fps: fps, videoKbps: Double(es.bitrate) / 1000, audio: false))
                r.sendVideo(FLV.videoSequenceHeader(avcC: avcC), ms: tsOffset); sentHeader = true
            }
            r.sendVideo(FLV.videoPacket(fr.data, isKey: fr.isKey), ms: ms)
        }
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
                if realtime { let due = t0.addingTimeInterval(Double(i) / fps).timeIntervalSinceNow; if due > 0 { usleep(useconds_t(due * 1_000_000)) } }
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
    if let r = rtmp {
        r.sendVideo(FLV.videoEndOfSequence(), ms: UInt32(((Double(sizes.count - 1) / fps) * 1000).rounded()) + tsOffset)
        let closed = DispatchSemaphore(value: 0); r.close { closed.signal() }; _ = closed.wait(timeout: .now() + 30)
        log("rtmp: sent \(r.bytesSent) bytes, state \(r.state)")
    }
    if let f = flv { f.write(.video, ms: UInt32(((Double(sizes.count - 1) / fps) * 1000).rounded()) + tsOffset, body: FLV.videoEndOfSequence()); f.close() }
    let done = DispatchSemaphore(value: 0); input?.markAsFinished(); writer?.finishWriting { done.signal() }; done.wait()
    let secs = Double(sizes.count) / fps, kbps = Double(sizes.reduce(0, +)) * 8 / secs / 1000
    var perSecond: [Double] = []; var j = 0
    while j < sizes.count { perSecond.append(Double(sizes[j..<min(j + Int(fps), sizes.count)].reduce(0, +)) * 8 / 1000); j += Int(fps) }
    let gaps = zip(keys.dropFirst(), keys).map { $0 - $1 }
    if args.contains("--per-second") { log("per-second kbit/s: " + perSecond.map { "\(Int($0))" }.joined(separator: " ")) }
    log("encoded \(sizes.count)/\(n) frames (dropped \(enc.dropped)) in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s; average \(Int(kbps)) kbit/s (target \(es.bitrate / 1000)); per-second max \(Int(perSecond.max() ?? 0)) min \(Int(perSecond.min() ?? 0)); keyframes at \(keys.prefix(6))…, gaps \(Set(gaps).sorted()); latency median \(Int(Stats.percentile(latency, 50) * 1000)) ms p95 \(Int(Stats.percentile(latency, 95) * 1000)) ms → \(args[4])")
case "stream":   // follosim stream VIDEO PATH.json --rtmp URL --key K --sent SENT.flv [--from S] [--seconds N] [--capacity C] [--catchup F] [--insecure-tls]
    // Stage 1d: real-time encode → FolloStreamer (ring buffer + reconnect) → RTMP. SENT.flv holds every frame produced.
    func log(_ t: String) { FileHandle.standardError.write(("\(String(format: "%7.1f", ProcessInfo.processInfo.systemUptime.truncatingRemainder(dividingBy: 100000))) " + t + "\n").data(using: .utf8)!) }
    func arg(_ k: String) -> String? { args.firstIndex(of: k).map { args[$0 + 1] } }
    let reader = try! VideoReader(path: args[2]); let fps = reader.fps
    let path = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[3]))) as! [String: Any]
    let PX = path["X"] as! [Double], PY = path["Y"] as! [Double], PW = path["CW"] as! [Double], PH = path["CH"] as! [Double]
    let f0 = Int((arg("--from").map { Double($0)! } ?? 0) * fps), n = Int((arg("--seconds").map { Double($0)! } ?? 60) * fps)
    var es = VideoEncoder.Settings(); es.fps = fps
    let enc = try! VideoEncoder(es); enc.onEvent = { log("encoder: " + $0) }
    var cfg = FolloStreamer.Config(); if let c = arg("--capacity") { cfg.capacityS = Double(c)! }; if let c = arg("--catchup") { cfg.catchUp = Double(c)! }
    let st = FolloStreamer(url: arg("--rtmp")!, key: arg("--key") ?? "test", config: cfg)
    st.trustAnyCertificateForTests = args.contains("--insecure-tls"); st.requestAcksForTests = !args.contains("--no-ack-request"); st.log = { log("streamer: " + $0) }
    let withAudio = args.contains("--audio")
    let sent = try! FLVWriter(path: arg("--sent")!, audio: withAudio); var headerDone = false; var produced = 0
    let q = DispatchQueue(label: "enc.out")
    // --audio: the match audio through our AAC encoder, fed in step with the video frames (stage 1e)
    var ae: AudioEncoder?; var pcmChunks: [(Double, AVAudioPCMBuffer)] = []; var nextChunk = 0; var audioPackets = 0
    if withAudio {
        let asset = AVURLAsset(url: URL(fileURLWithPath: args[2])); let tr = asset.tracks(withMediaType: .audio)[0]
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(tr.formatDescriptions.first as! CMAudioFormatDescription)!.pointee
        var aset = AudioEncoder.Settings(); aset.sampleRate = asbd.mSampleRate; aset.channels = Int(asbd.mChannelsPerFrame); let e = try! AudioEncoder(aset); ae = e
        let r = try! AVAssetReader(asset: asset)
        r.timeRange = CMTimeRange(start: CMTime(seconds: Double(f0) / fps, preferredTimescale: 48000), duration: CMTime(seconds: Double(n) / fps + 1, preferredTimescale: 48000))
        let o = AVAssetReaderTrackOutput(track: tr, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: true, AVLinearPCMIsBigEndianKey: false])
        r.add(o); r.startReading(); var at = 0.0
        while let sb = o.copyNextSampleBuffer() {
            let k = CMSampleBufferGetNumSamples(sb); guard k > 0 else { continue }
            let pcm = AVAudioPCMBuffer(pcmFormat: e.inputFormat, frameCapacity: AVAudioFrameCount(k))!; pcm.frameLength = AVAudioFrameCount(k)
            CMSampleBufferCopyPCMDataIntoAudioBufferList(sb, at: 0, frameCount: Int32(k), into: pcm.mutableAudioBufferList)
            pcmChunks.append((at, pcm)); at += Double(k) / aset.sampleRate
        }
        e.onPacket = { d, sample in
            let ms = UInt32((Double(sample) / aset.sampleRate * 1000).rounded()), body = FLV.audioPacket(d)
            q.sync { sent.write(.audio, ms: ms, body: body) }; st.push(.audio, body: body, ms: ms, isKey: false); audioPackets += 1
        }
        log("audio: \(Int(aset.sampleRate)) Hz × \(aset.channels), \(pcmChunks.count) PCM chunks preloaded")
    }
    enc.onFrame = { fr in q.sync {
        let ms = UInt32((CMTimeGetSeconds(fr.pts) * 1000).rounded())
        if !headerDone, let avcC = FLV.avcC(of: fr.format) {
            let meta = FLV.metadata(width: 1920, height: 1080, fps: fps, videoKbps: 4500, audio: ae != nil), avc = FLV.videoSequenceHeader(avcC: avcC)
            let aac = ae.map { FLV.audioSequenceHeader(asc: $0.audioSpecificConfig) }
            sent.write(.script, ms: 0, body: meta); sent.write(.video, ms: 0, body: avc); if let a = aac { sent.write(.audio, ms: 0, body: a) }
            st.setHeaders(meta: meta, avc: avc, aac: aac); headerDone = true
        }
        let body = FLV.videoPacket(fr.data, isKey: fr.isKey)
        sent.write(.video, ms: ms, body: body); st.push(.video, body: body, ms: ms, isKey: fr.isKey); produced += 1
    } }
    let ctx = CIContext(options: [.cacheIntermediates: false]); var pool: CVPixelBufferPool?
    CVPixelBufferPoolCreate(nil, nil, [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 1920,
                                       kCVPixelBufferHeightKey as String: 1080, kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &pool)
    st.start(); try! reader.start(from: f0); let t0 = Date()
    for i in 0..<n {
        let more: Bool = autoreleasepool {
            guard let pb = reader.next() else { return false }
            let f = f0 + i, H = Double(CVPixelBufferGetHeight(pb))
            let rect = CGRect(x: PX[f] - PW[f] / 2, y: H - (PY[f] + PH[f] / 2), width: PW[f], height: PH[f])
            var img = CIImage(cvPixelBuffer: pb).cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            img = img.transformed(by: CGAffineTransform(scaleX: 1920 / PW[f], y: 1080 / PH[f]))
            var o: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, pool!, &o)
            ctx.render(img, to: o!, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080), colorSpace: CGColorSpaceCreateDeviceRGB())
            let due = t0.addingTimeInterval(Double(i) / fps).timeIntervalSinceNow; if due > 0 { usleep(useconds_t(due * 1_000_000)) }
            enc.encode(o!, pts: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps.rounded())))
            if let e = ae { while nextChunk < pcmChunks.count && pcmChunks[nextChunk].0 < Double(i + 1) / fps { e.append(pcmChunks[nextChunk].1); nextChunk += 1 } }
            if let j = arg("--kill-encoder-at").map({ Int(Double($0)! * fps) }), i == j { log("test: invalidating the encoder session"); enc.simulateInvalidation() }
            if let j = arg("--jump-at").map({ Int(Double($0)! * fps) }), i == j { log("jump to live (delay was \(String(format: "%.1f", st.delayS)) s)"); st.jumpToLive() }
            if i % Int(5 * fps) == 0 { log(String(format: "t=%3.0f s publishing %@ delay %.1f s reconnects %d ring %.1f MB (peak %.1f) resent %d dropped-from-ring %d", Double(i) / fps, st.isPublishing ? "yes" : "NO ", st.delayS, st.reconnects, Double(st.ringBytes) / 1e6, Double(st.ringPeakBytes) / 1e6, st.resentFrames, st.droppedFromRing)) }
            return true
        }
        if !more { break }
    }
    enc.flush(); q.sync {}; sent.close()
    log("produced \(produced) frames, \(audioPackets) audio packets; draining…")
    let done = DispatchSemaphore(value: 0); st.stop(drainS: Double(arg("--drain") ?? "150")!) { done.signal() }; done.wait()
    log(String(format: "final: reconnects %d, drops resolved by server acks %d, resent %d, dropped-from-ring %d, ring peak %.1f MB, sent items %d", st.reconnects, st.ackedDrops, st.resentFrames, st.droppedFromRing, Double(st.ringPeakBytes) / 1e6, st.sentFrames))
case "aacenc":   // follosim aacenc VIDEO OUT.flv [--from S] [--seconds N] [--bitrate B] — stage 1e: the match audio through our AAC encoder
    func log(_ t: String) { FileHandle.standardError.write((t + "\n").data(using: .utf8)!) }
    let asset = AVURLAsset(url: URL(fileURLWithPath: args[2])); let tr = asset.tracks(withMediaType: .audio)[0]
    let fd = tr.formatDescriptions.first as! CMAudioFormatDescription
    let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)!.pointee
    var aset = AudioEncoder.Settings(); aset.sampleRate = asbd.mSampleRate; aset.channels = Int(asbd.mChannelsPerFrame)
    if let b = args.firstIndex(of: "--bitrate").map({ Int(args[$0 + 1])! }) { aset.bitrate = b }
    let ae = try! AudioEncoder(aset)
    let from = args.firstIndex(of: "--from").map { Double(args[$0 + 1])! } ?? 0, secs = args.firstIndex(of: "--seconds").map { Double(args[$0 + 1])! } ?? 10
    let r = try! AVAssetReader(asset: asset); r.timeRange = CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 48000), duration: CMTime(seconds: secs, preferredTimescale: 48000))
    let o = AVAssetReaderTrackOutput(track: tr, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                                                                AVLinearPCMIsNonInterleaved: true, AVLinearPCMIsBigEndianKey: false])
    r.add(o); r.startReading()
    let flv = try! FLVWriter(path: args[3], audio: true)
    flv.write(.audio, ms: 0, body: FLV.audioSequenceHeader(asc: ae.audioSpecificConfig))
    var sizes: [Int] = []
    ae.onPacket = { d, sample in flv.write(.audio, ms: UInt32((Double(sample) / aset.sampleRate * 1000).rounded()), body: FLV.audioPacket(d)); sizes.append(d.count) }
    var frames = 0
    while let sb = o.copyNextSampleBuffer() {
        let n = CMSampleBufferGetNumSamples(sb); guard n > 0 else { continue }
        let pcm = AVAudioPCMBuffer(pcmFormat: ae.inputFormat, frameCapacity: AVAudioFrameCount(n))!; pcm.frameLength = AVAudioFrameCount(n)
        CMSampleBufferCopyPCMDataIntoAudioBufferList(sb, at: 0, frameCount: Int32(n), into: pcm.mutableAudioBufferList)
        ae.append(pcm); frames += n
    }
    flv.close()
    let kbps = Double(sizes.reduce(0, +)) * 8 / (Double(frames) / aset.sampleRate) / 1000
    log("audio \(Int(aset.sampleRate)) Hz × \(aset.channels): \(frames) samples in, \(ae.packets) AAC packets out, \(Int(kbps)) kbit/s, ASC \(ae.audioSpecificConfig.map { String(format: "%02x", $0) }.joined()) → \(args[3])")
case "interleave":   // follosim interleave — stage 1f: audio arriving 2 s before its video still leaves as one time-ordered stream
    var il = MediaInterleaver(); var out: [(Int64, Bool)] = []; var audioIn = 0
    let fps = 30.0, sr = 48_000.0, seconds = 60.0
    var nextAudio = 0                                                  // audio packet k covers 1024 samples
    for f in 0..<Int(seconds * fps) {
        let videoMs = Int64((Double(f) / fps * 1000).rounded())
        let wall = Double(f) / fps + 2.0                               // the frame leaves the virtual camera 2 s after capture
        while Double(nextAudio) * 1024 / sr <= wall {                  // all audio captured up to now has arrived
            il.audio(ms: Int64((Double(nextAudio) * 1024 / sr * 1000).rounded()) - Int64(Int.random(in: 0...1) * 0), body: Data([0])); audioIn += 1; nextAudio += 1
        }
        for o in il.video(ms: videoMs, body: Data([1]), isKey: f % 60 == 0) {
            switch o { case .audio(let ms, _): out.append((ms, true)); case .video(let ms, _, _): out.append((ms, false)) }
        }
    }
    let ordered = zip(out, out.dropFirst()).allSatisfy { $0.0 <= $1.0 }
    let audioOut = out.filter { $0.1 }.count, videoOut = out.filter { !$0.1 }.count
    let maxLead = out.filter { $0.1 }.map { a in a.0 }.max() ?? 0
    print("interleaver: video \(videoOut)/\(Int(seconds * fps)), audio out \(audioOut) of \(audioIn) in (rest wait for later video: \(audioIn - audioOut - il.droppedAudio)), dropped \(il.droppedAudio); time-ordered \(ordered); last audio \(maxLead) ms ≤ last video \(out.last { !$0.1 }!.0) ms")
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
