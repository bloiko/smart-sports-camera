import Foundation

/// Live stream with a network-drop buffer (stage 1d): encoded frames go into a ring of `capacityS` seconds; a sender
/// paces them to our RTMPClient. When the connection drops (closed, failed, or stalled: nothing confirmed as sent for
/// `stallS`), it reconnects every `reconnectS` and resends from the last keyframe that was surely sent, so viewers miss
/// nothing; the stream then runs behind live by the length of the drop ("delay line"). `catchUp` > 1 sends the backlog
/// faster than real time (only if the uplink allows); `jumpToLive()` drops the backlog (half-time, owner's button).
public final class FolloStreamer: @unchecked Sendable {   // all state on `queue`
    public struct Config {
        public var capacityS = 180.0, catchUp = 1.0, reconnectS = 2.0, stallS = 5.0, maxInFlightBytes = 2_000_000
        /// With server acknowledgements: no new acknowledgement for this long while more than 2 windows are unacknowledged
        /// means the network is gone (faster than waiting for the system's send buffer to fill).
        public var ackStallS = 3.0
        /// Used only when the server sends no acknowledgements: after a drop, resend this much before the last frame the
        /// network stack took (those bytes may still have been in the system's send buffer). Duplicates beat a missed goal.
        public var resendMarginS = 8.0
        public init() {}
    }
    public enum Kind { case video, audio }
    struct Item { let ms: UInt32; let isKey: Bool; let kind: Kind; let body: Data }

    public let config: Config
    public var log: ((String) -> Void)?
    public var trustAnyCertificateForTests = false
    public var requestAcksForTests = true
    // stats (read on any thread; written on `queue`)
    public private(set) var reconnects = 0, droppedFromRing = 0, sentFrames = 0, resentFrames = 0, ackedDrops = 0
    public private(set) var ringBytes = 0, ringPeakBytes = 0
    public private(set) var isPublishing = false
    /// Diagnostics for the app log: items in the ring, next item to send, total items pushed.
    public var diag: String { queue.sync { "ring \(ring.count) next \(sendIndex - base) pushed \(base + ring.count) sent \(sentFrames) inflight \(client?.bytesInFlight ?? 0)" } }
    /// Seconds the stream runs behind live (0 when it keeps up).
    public private(set) var delayS = 0.0

    let queue = DispatchQueue(label: "follo.streamer")
    private let url: String, key: String
    private var client: RTMPClient?
    private var ring: [Item] = [], base = 0                  // global index of ring[0]
    private var sendIndex = 0                                 // next global index to send
    private var sentTags: [(index: Int, tag: Int)] = []       // per item sent on this connection: its message number
    private var headers: (meta: Data?, avc: Data?, aac: Data?) = (nil, nil, nil)
    private var anchorWall = 0.0, anchorMs: UInt32 = 0, anchored = false
    private var lastProgressWall = 0.0, lastBytesSent = 0, lastAckCount = 0, lastAckWall = 0.0, ackInterval = 0.0
    private var timer: DispatchSourceTimer?, stopped = false, connecting = false, wantClose = false
    private var everSent = 0                                  // highest global index ever sent (resent frames are counted separately)
    private var headersSent = false                           // on this connection: a server cannot decode frames before the AVC header

    public init(url: String, key: String, config: Config = Config()) { self.url = url; self.key = key; self.config = config }

    public func start() {
        queue.async { [self] in
            let t = DispatchSource.makeTimerSource(queue: queue); t.schedule(deadline: .now(), repeating: .milliseconds(10))
            t.setEventHandler { [weak self] in self?.pump() }; t.resume(); timer = t
            connect()
        }
    }

    /// Stream headers: onMetaData body (`FLV.metadata`), AVC sequence header (`FLV.videoSequenceHeader`), optional AAC header. Re-sent on every connection.
    public func setHeaders(meta: Data, avc: Data, aac: Data? = nil) { queue.async { [self] in headers = (meta, avc, aac) } }

    /// One encoded video frame (FLV body) or audio packet, in presentation order, on any thread.
    public func push(_ kind: Kind, body: Data, ms: UInt32, isKey: Bool) {
        queue.async { [self] in
            ring.append(Item(ms: ms, isKey: isKey, kind: kind, body: body)); ringBytes += body.count; ringPeakBytes = max(ringPeakBytes, ringBytes)
            trim()
        }
    }

    /// Drop the backlog: continue from the newest keyframe (half-time, "Наздогнати ефір").
    public func jumpToLive() {
        queue.async { [self] in
            guard let k = ring.lastIndex(where: { $0.isKey && $0.kind == .video }) else { return }
            if base + k > sendIndex { log?("jump to live: skip \(base + k - sendIndex) items"); sendIndex = base + k; anchored = false }
        }
    }

    /// Send what is left (up to `drainS`), then close politely.
    public func stop(drainS: Double = 30, then done: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            let deadline = Date().addingTimeInterval(drainS)
            func check() {
                if (sendIndex >= base + ring.count && (client?.bytesInFlight ?? 0) == 0) || Date() > deadline || !isPublishing {
                    stopped = true; timer?.cancel()
                    if let c = client { c.close { done() } } else { done() }
                } else { queue.asyncAfter(deadline: .now() + 0.1) { check() } }
            }
            check()
        }
    }

    // ---------------------------------------------------------------- connection

    private func connect() {
        guard !stopped, !connecting else { return }
        connecting = true; isPublishing = false
        let c = RTMPClient(); c.trustAnyCertificateForTests = trustAnyCertificateForTests; c.requestAcks = requestAcksForTests
        c.log = { [weak self] m in if m.hasPrefix("FAILED") || m.contains("Publish") { self?.log?("rtmp: " + m) } }
        c.onState = { [weak self, weak c] st in self?.queue.async { if let c, c === self?.client { self?.clientState(st) } } }
        client = c; c.connect(url: url, key: key)
    }

    private func clientState(_ st: RTMPClient.State) {
        switch st {
        case .publishing:
            connecting = false; isPublishing = true; headersSent = false
            sendHeadersIfReady()
            sentTags = []; lastBytesSent = 0; lastProgressWall = now(); lastAckCount = 0; lastAckWall = now(); ackInterval = 0
            // resend from the last keyframe at or before the first frame not surely sent on the previous connection
            let from = max(sendIndex, base)
            if let k = (base..<min(from + 1, base + ring.count)).reversed().first(where: { ring[$0 - base].isKey && ring[$0 - base].kind == .video }) {
                sendIndex = k
            } else if let k = ring.firstIndex(where: { $0.isKey && $0.kind == .video }) { sendIndex = base + k }
            anchored = false
            log?("publishing (connection \(reconnects + 1)); sending from item \(sendIndex), backlog \(String(format: "%.1f", backlogS())) s")
        case .failed(let why):
            dropped(why)
        case .closed:
            if !stopped { dropped("closed") }
        default: break
        }
    }

    private func dropped(_ why: String) {
        guard !stopped else { return }
        // Only a connection that was sending can leave frames unconfirmed (a failed reconnect attempt sent nothing:
        // before this guard it reset the position to the start and re-sent the whole ring, found on the Mac).
        if isPublishing, let c = client, !sentTags.isEmpty {
            var next: Int
            if let d = c.deliveredTag() {                                              // exact: the server's acknowledgement
                next = sentTags.last(where: { $0.tag <= d }).map { $0.index + 1 } ?? sentTags[0].index
                ackedDrops += 1
            } else {                                                                   // no acknowledgements: margin
                let confirmed = c.confirmedTag
                next = sentTags.last(where: { $0.tag <= confirmed }).map { $0.index + 1 } ?? sentTags[0].index
                if next > base, next - base <= ring.count {
                    let edge = Int64(ring[next - base - 1].ms) - Int64(config.resendMarginS * 1000)
                    while next > base && Int64(ring[next - base - 1].ms) > edge { next -= 1 }
                }
            }
            let old = sendIndex; sendIndex = min(sendIndex, max(next, base)); resentFrames += old - sendIndex
        }
        sentTags = []
        client?.abort(); client = nil; isPublishing = false; connecting = false; reconnects += 1
        log?("connection dropped (\(why)); resend from item \(sendIndex); reconnect in \(config.reconnectS) s")
        queue.asyncAfter(deadline: .now() + config.reconnectS) { [weak self] in self?.connect() }
    }

    // ---------------------------------------------------------------- sending

    /// Metadata + AVC (+ AAC) sequence headers once per connection, before any frame (found on the Mac: a server that got
    /// frames first could not read the stream and closed the connection).
    private func sendHeadersIfReady() {
        guard !headersSent, let c = client, let avc = headers.avc else { return }
        let ms = sendIndex >= base && sendIndex < base + ring.count ? ring[sendIndex - base].ms : (ring.last?.ms ?? 0)
        if let m = headers.meta { c.sendMetadata(m) }
        c.sendVideo(avc, ms: ms)
        if let a = headers.aac { c.sendAudio(a, ms: ms) }
        headersSent = true
    }

    private func pump() {
        guard isPublishing, let c = client else { return }
        sendHeadersIfReady(); guard headersSent else { return }
        let t = now()
        // stall: bytes waiting but nothing confirmed for stallS (network gone without an error)
        let sent = c.bytesSent
        if sent != lastBytesSent { lastBytesSent = sent; lastProgressWall = t }
        else if c.bytesInFlight > 0 && t - lastProgressWall > config.stallS { dropped("stalled \(Int(config.stallS)) s"); return }
        let a = c.ackState()
        // adaptive to the server's real cadence: a server may acknowledge less often than we asked (e.g. every 2.5 MB)
        if a.acks != lastAckCount { if lastAckCount > 0 { ackInterval = max(ackInterval * 0.9, t - lastAckWall) }; lastAckCount = a.acks; lastAckWall = t }
        else if a.acks > 1 {
            let bytesLimit = 2 * max(c.ackWindow, a.spacing), timeLimit = max(config.ackStallS, 2 * ackInterval)
            if a.queued - a.acked > bytesLimit && t - lastAckWall > timeLimit { dropped("no acknowledgement for \(String(format: "%.1f", timeLimit)) s"); return }
        }
        while sendIndex < base + ring.count {
            guard sendIndex >= base else { sendIndex = base; anchored = false; continue }
            let it = ring[sendIndex - base]
            if !anchored { anchorWall = t; anchorMs = it.ms; anchored = true }
            let due = anchorWall + Double(Int64(it.ms) - Int64(anchorMs)) / 1000 / config.catchUp
            guard t >= due, c.bytesInFlight < config.maxInFlightBytes else { break }
            let tag = it.kind == .video ? c.sendVideo(it.body, ms: it.ms) : c.sendAudio(it.body, ms: it.ms)
            sentTags.append((sendIndex, tag)); if sentTags.count > 6000 { sentTags.removeFirst(1000) }
            if sendIndex > everSent { everSent = sendIndex }
            sentFrames += 1; sendIndex += 1
        }
        delayS = backlogS()
    }

    /// Seconds between the newest item and the next one to send.
    private func backlogS() -> Double {
        guard let last = ring.last, sendIndex < base + ring.count, sendIndex >= base else { return 0 }
        return Double(Int64(last.ms) - Int64(ring[sendIndex - base].ms)) / 1000
    }

    private func trim() {
        guard let newest = ring.last?.ms else { return }
        var n = 0
        while n < ring.count && Double(Int64(newest) - Int64(ring[n].ms)) / 1000 > config.capacityS { n += 1 }
        guard n > 0 else { return }
        if sendIndex < base + n { droppedFromRing += base + n - sendIndex; log?("ring full: \(base + n - sendIndex) unsent items dropped"); sendIndex = base + n; anchored = false }
        for i in 0..<n { ringBytes -= ring[i].body.count }
        ring.removeFirst(n); base += n
    }

    private func now() -> Double { ProcessInfo.processInfo.systemUptime }
}
