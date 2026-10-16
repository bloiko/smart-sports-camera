import Foundation
import Network

/// Own RTMP(S) publisher on Network.framework (system): handshake, connect → createStream → publish, chunking, and the
/// protocol control messages a server sends (chunk size, window acknowledgement, peer bandwidth, ping). Payloads come from
/// `FLV` (the same bodies as FLV tags). Replaces HaishinKit's RTMP layer (stage 1c of docs/detector-licence-plan.md).
/// All work happens on one serial queue; callbacks arrive on it too.
public final class RTMPClient {
    public enum State: Equatable { case idle, connecting, publishing, failed(String), closed }
    public private(set) var state: State = .idle { didSet { if state != oldValue { onState?(state) } } }
    public var onState: ((State) -> Void)?
    public var log: ((String) -> Void)?
    /// Bytes handed to the network and not yet confirmed as sent (backpressure for the buffer of stage 1d).
    public private(set) var bytesInFlight = 0
    public private(set) var bytesSent = 0
    /// Every audio/video message gets a number; `confirmedTag` is the highest number whose bytes the network stack has
    /// taken (stage 1d: which frames left the phone before a drop).
    public private(set) var confirmedTag = 0
    private var tagCounter = 0
    private let tagLock = NSLock()
    /// Bytes the server says it received (RTMP Acknowledgement, sent every `ackWindow` bytes after we ask for it), and the
    /// stream offset where each numbered message ends: together they tell which frames surely reached the server.
    public private(set) var serverAckedBytes = 0
    public private(set) var acksReceived = 0
    /// Largest number of bytes between two acknowledgements seen on this connection (the server's real cadence).
    public private(set) var ackSpacing = 0
    public let ackWindow = 262_144
    private var queuedBytes = 0, tagEnd: [(tag: Int, end: Int)] = []

    public let queue = DispatchQueue(label: "follo.rtmp")
    private var conn: NWConnection?
    private var url = "", app = "", key = "", tcUrl = ""
    private var outChunk = 128, inChunk = 128
    private var streamId: UInt32 = 0
    private var inBuf = Data(), handshaking = true
    private var bytesIn = 0, windowAck = 2_500_000, lastAckAt = 0
    private struct Header { var ts: UInt32 = 0, len = 0, type: UInt8 = 0, sid: UInt32 = 0, delta: UInt32 = 0, extended = false }
    private var inHeaders: [UInt32: Header] = [:], inPartial: [UInt32: Data] = [:]

    /// Tests only (`follosim --insecure-tls` against a local TLS proxy with a self-signed certificate). Never set in the app.
    public var trustAnyCertificateForTests = false
    /// Tests only: do not ask the server for frequent acknowledgements (a server that acknowledges on its own schedule).
    public var requestAcks = true

    public init() {}

    private func parameters(tls: Bool) -> NWParameters {
        guard tls else { return .tcp }
        let t = NWProtocolTLS.Options()
        if trustAnyCertificateForTests {
            sec_protocol_options_set_verify_block(t.securityProtocolOptions, { _, _, done in done(true) }, queue)
        }
        return NWParameters(tls: t)
    }

    // ---------------------------------------------------------------- public API

    /// `url`: rtmp://host[:port]/app or rtmps://host[:port]/app (YouTube: rtmps://a.rtmps.youtube.com:443/live2), `key`: stream key.
    public func connect(url: String, key: String) {
        queue.async { [self] in
            guard let u = URL(string: url), let host = u.host, let scheme = u.scheme?.lowercased(), scheme == "rtmp" || scheme == "rtmps" else { fail("bad url \(url)"); return }
            let tls = scheme == "rtmps", port = u.port ?? (tls ? 443 : 1935)
            self.url = url; self.key = key; app = String(u.path.dropFirst()); tcUrl = "\(scheme)://\(host):\(port)/\(app)"
            state = .connecting; handshaking = true; inBuf = Data(); outChunk = 128; inChunk = 128; inHeaders = [:]; inPartial = [:]; bytesIn = 0; lastAckAt = 0
            let c = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: parameters(tls: tls))
            conn = c
            c.stateUpdateHandler = { [weak self] st in
                guard let self else { return }
                switch st {
                case .ready: self.log?("tcp ready \(host):\(port)\(tls ? " tls" : "")"); self.sendC0C1(); self.receive()
                case .failed(let e): self.fail("network: \(e)")
                case .waiting(let e): self.fail("network waiting: \(e)")
                default: break
                }
            }
            c.start(queue: queue)
        }
    }

    /// onMetaData via @setDataFrame (body from `FLV.metadata`, which starts with the "onMetaData" string).
    public func sendMetadata(_ body: Data) { var d = AMF0.string("@setDataFrame"); d.append(body); sendMessage(csid: 4, type: 18, sid: streamId, ts: 0, d) }
    @discardableResult public func sendVideo(_ body: Data, ms: UInt32) -> Int { let t = newTag(); sendMessage(csid: 6, type: 9, sid: streamId, ts: ms, body, tag: t); return t }
    @discardableResult public func sendAudio(_ body: Data, ms: UInt32) -> Int { let t = newTag(); sendMessage(csid: 4, type: 8, sid: streamId, ts: ms, body, tag: t); return t }
    private func newTag() -> Int { tagLock.lock(); defer { tagLock.unlock() }; tagCounter += 1; return tagCounter }

    /// Polite end: FCUnpublish, deleteStream, then close the socket once everything queued has been sent.
    public func close(then done: (() -> Void)? = nil) {
        queue.async { [self] in
            guard let c = conn else { done?(); return }
            if state == .publishing {
                command("FCUnpublish", txn: 6, [.null, .string(key)])
                command("deleteStream", txn: 7, [.null, .number(Double(streamId))])
            }
            c.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
                c.cancel(); self?.conn = nil; self?.state = .closed; done?()
            })
        }
    }

    /// Drop the connection without the polite end (network lost, tests of stage 1d).
    public func abort() { queue.async { [self] in conn?.cancel(); conn = nil; if state != .closed { state = .failed("aborted") } } }

    // ---------------------------------------------------------------- handshake

    private func sendC0C1() {
        var c1 = Data(count: 1536)
        for i in 8..<1536 { c1[i] = UInt8.random(in: 0...255) }
        var d = Data([0x03]); d.append(c1); write(d)
    }

    private func receive() {
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { return }
            if let data, !data.isEmpty { self.inBuf.append(data); self.bytesIn += data.count; self.process() }
            if let err { self.fail("receive: \(err)"); return }
            if done { if self.state != .closed { self.fail("server closed the connection") }; return }
            self.receive()
        }
    }

    private func process() {
        if handshaking {
            guard inBuf.count >= 1 + 1536 + 1536 else { return }
            guard inBuf[inBuf.startIndex] == 0x03 else { fail("handshake: server version \(inBuf[inBuf.startIndex])"); return }
            let s1 = inBuf.subdata(in: (inBuf.startIndex + 1)..<(inBuf.startIndex + 1537))
            inBuf.removeFirst(1 + 1536 + 1536)
            write(s1)                                                   // C2 = echo of S1
            handshaking = false; log?("handshake done")
            sendMessage(csid: 2, type: 1, sid: 0, ts: 0, be32(4096)); outChunk = 4096
            if requestAcks { sendMessage(csid: 2, type: 5, sid: 0, ts: 0, be32(UInt32(ackWindow))) }   // ask the server to acknowledge every 256 KB
            command("connect", txn: 1, [.object([("app", .string(app)), ("type", .string("nonprivate")), ("flashVer", .string("FMLE/3.0 (compatible; Follo)")),
                                                ("tcUrl", .string(tcUrl))])])
        }
        while let (type, sid, payload) = readMessage() { handle(type: type, sid: sid, payload) }
        if bytesIn - lastAckAt >= windowAck { lastAckAt = bytesIn; sendMessage(csid: 2, type: 3, sid: 0, ts: 0, be32(UInt32(truncatingIfNeeded: bytesIn))) }
    }

    // ---------------------------------------------------------------- incoming chunks

    /// One complete message from the chunk stream, or nil when more bytes are needed (bytes stay in inBuf).
    private func readMessage() -> (UInt8, UInt32, Data)? {
        while true {
            let b = [UInt8](inBuf.prefix(18)); guard !b.isEmpty else { return nil }
            let fmt = b[0] >> 6; var csid = UInt32(b[0] & 0x3F); var o = 1
            if csid == 0 { guard b.count > 1 else { return nil }; csid = 64 + UInt32(b[1]); o = 2 }
            else if csid == 1 { guard b.count > 2 else { return nil }; csid = 64 + UInt32(b[1]) + UInt32(b[2]) * 256; o = 3 }
            let mh = [11, 7, 3, 0][Int(fmt)]
            guard b.count >= o + mh else { return nil }
            var h = inHeaders[csid] ?? Header()
            func u24(_ i: Int) -> UInt32 { UInt32(b[i]) << 16 | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) }
            var tsField: UInt32 = 0
            if fmt <= 2 { tsField = u24(o) }
            if fmt <= 1 { h.len = Int(u24(o + 3)); h.type = b[o + 6] }
            if fmt == 0 { h.sid = UInt32(b[o + 7]) | UInt32(b[o + 8]) << 8 | UInt32(b[o + 9]) << 16 | UInt32(b[o + 10]) << 24 }
            var hdr = o + mh
            let ext = fmt <= 2 ? tsField == 0xFFFFFF : h.extended
            if ext {
                let all = [UInt8](inBuf.prefix(hdr + 4)); guard all.count == hdr + 4 else { return nil }
                tsField = UInt32(all[hdr]) << 24 | UInt32(all[hdr + 1]) << 16 | UInt32(all[hdr + 2]) << 8 | UInt32(all[hdr + 3]); hdr += 4
            }
            let have = inPartial[csid]?.count ?? 0
            let n = min(inChunk, h.len - have)
            guard inBuf.count >= hdr + n else { return nil }
            if have == 0 {                                           // timestamps change only at the start of a message
                switch fmt { case 0: h.ts = tsField; h.delta = 0; case 1, 2: h.delta = tsField; h.ts &+= tsField; default: h.ts &+= h.delta }
            }
            h.extended = ext
            let start = inBuf.startIndex + hdr
            var part = inPartial[csid] ?? Data(); part.append(inBuf.subdata(in: start..<(start + n)))
            inBuf.removeFirst(hdr + n); inHeaders[csid] = h
            if part.count >= h.len { inPartial[csid] = nil; return (h.type, h.sid, part) }
            inPartial[csid] = part
        }
    }

    private func handle(type: UInt8, sid: UInt32, _ p: Data) {
        let b = [UInt8](p)
        func be32at(_ i: Int) -> UInt32 { b.count >= i + 4 ? UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3]) : 0 }
        switch type {
        case 1: inChunk = Int(be32at(0) & 0x7FFF_FFFF); log?("server chunk size \(inChunk)")
        case 3:                                                                        // acknowledgement: bytes the server got
            let v = Int(be32at(0)); if acksReceived > 0 { ackSpacing = max(ackSpacing, v - serverAckedBytes) }
            serverAckedBytes = v; acksReceived += 1
        case 5: windowAck = Int(be32at(0)); log?("window ack size \(windowAck)")
        case 6: sendMessage(csid: 2, type: 5, sid: 0, ts: 0, be32(be32at(0)))          // set peer bandwidth → our window ack size
        case 4:                                                                        // user control: ping request → ping response
            if b.count >= 6, b[0] == 0, b[1] == 6 { var d = Data([0, 7]); d.append(contentsOf: b[2..<6]); sendMessage(csid: 2, type: 4, sid: 0, ts: 0, d) }
        case 20:
            let v = AMF0.decodeAll(p)
            guard case .string(let name)? = v.first else { return }
            let txn: Double = { if v.count > 1, case .number(let t) = v[1] { return t }; return 0 }()
            log?("← \(name) \(txn)\(statusCode(v).map { " " + $0 } ?? "")")
            if name == "_result" && txn == 1 {
                command("releaseStream", txn: 2, [.null, .string(key)])
                command("FCPublish", txn: 3, [.null, .string(key)])
                command("createStream", txn: 4, [.null])
            } else if name == "_result" && txn == 4 {
                if v.count > 3, case .number(let s) = v[3] { streamId = UInt32(s) }
                command("publish", txn: 5, [.null, .string(key), .string("live")], csid: 8, sid: streamId)
            } else if name == "_error" {
                fail("server error: \(statusCode(v) ?? "txn \(txn)")")
            } else if name == "onStatus" {
                let code = statusCode(v) ?? ""
                if code == "NetStream.Publish.Start" { state = .publishing }
                else if code.contains("Failed") || code.contains("BadName") || code.contains("Rejected") { fail(code) }
            }
        default: break
        }
    }

    private func statusCode(_ v: [AMF0.Value]) -> String? {
        for x in v { if case .object(let o) = x, let c = o.first(where: { $0.0 == "code" }), case .string(let s) = c.1 { return s } }
        return nil
    }

    // ---------------------------------------------------------------- outgoing messages

    private func command(_ name: String, txn: Double, _ args: [AMF0.Value], csid: UInt32 = 3, sid: UInt32 = 0) {
        var d = AMF0.string(name); d.append(AMF0.number(txn)); for a in args { d.append(AMF0.value(a)) }
        log?("→ \(name) \(Int(txn))")
        sendMessage(csid: csid, type: 20, sid: sid, ts: 0, d)
    }

    /// A message as chunks: type-0 header on the first chunk, type-3 headers on continuations; extended timestamp when needed.
    private func sendMessage(csid: UInt32, type: UInt8, sid: UInt32, ts: UInt32, _ payload: Data, tag: Int = 0) {
        queue.async { [self] in
            guard conn != nil else { return }
            let ext = ts >= 0xFFFFFF, t24 = ext ? 0xFFFFFF : ts
            var out = Data(capacity: payload.count + payload.count / outChunk * 5 + 20)
            out.append(UInt8(csid & 0x3F))                                     // fmt 0, csid < 64
            out.append(contentsOf: [UInt8(t24 >> 16 & 0xFF), UInt8(t24 >> 8 & 0xFF), UInt8(t24 & 0xFF)])
            let n = payload.count
            out.append(contentsOf: [UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF), type])
            out.append(contentsOf: [UInt8(sid & 0xFF), UInt8(sid >> 8 & 0xFF), UInt8(sid >> 16 & 0xFF), UInt8(sid >> 24 & 0xFF)])
            if ext { out.append(be32(ts)) }
            var o = 0
            while o < n {
                if o > 0 { out.append(0xC0 | UInt8(csid & 0x3F)); if ext { out.append(be32(ts)) } }
                let k = min(outChunk, n - o)
                out.append(payload.subdata(in: (payload.startIndex + o)..<(payload.startIndex + o + k))); o += k
            }
            queuedBytes += out.count
            if tag > 0 { tagEnd.append((tag, queuedBytes)); if tagEnd.count > 8000 { tagEnd.removeFirst(2000) } }
            write(out, tag: tag)
        }
    }

    /// The highest message number whose bytes the server acknowledged (nil before the first acknowledgement).
    /// `slack` covers servers that also count the handshake (3073 bytes) in their sequence number.
    /// Bytes queued after the handshake and the server's acknowledged count, read together (stall detection).
    public func ackState() -> (queued: Int, acked: Int, acks: Int, spacing: Int) { queue.sync { (queuedBytes, serverAckedBytes, acksReceived, ackSpacing) } }

    public func deliveredTag(slack: Int = 3073) -> Int? {
        queue.sync {
            guard acksReceived > 0 else { return nil }
            return tagEnd.last(where: { $0.end <= serverAckedBytes - slack })?.tag ?? 0
        }
    }

    private func write(_ d: Data, tag: Int = 0) {
        guard let c = conn else { return }
        bytesInFlight += d.count
        c.send(content: d, completion: .contentProcessed { [weak self] err in
            guard let self else { return }
            self.bytesInFlight -= d.count; self.bytesSent += d.count
            if err == nil, tag > self.confirmedTag { self.confirmedTag = tag }
            if let err { self.fail("send: \(err)") }
        })
    }

    private func fail(_ why: String) {
        if case .failed = state { return }
        if state == .closed { return }
        log?("FAILED: \(why)"); state = .failed(why); conn?.cancel(); conn = nil
    }

    private func be32(_ v: UInt32) -> Data { Data([UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]) }
}

extension AMF0 {
    /// Decode a sequence of AMF0 values (command messages from the server).
    public static func decodeAll(_ d: Data) -> [Value] {
        let b = [UInt8](d); var i = 0; var out: [Value] = []
        func u16() -> Int? { guard i + 2 <= b.count else { return nil }; defer { i += 2 }; return Int(b[i]) << 8 | Int(b[i + 1]) }
        func str(_ n: Int) -> String? { guard i + n <= b.count else { return nil }; defer { i += n }; return String(decoding: b[i..<(i + n)], as: UTF8.self) }
        func props() -> [(String, Value)]? {
            var p: [(String, Value)] = []
            while i + 3 <= b.count {
                if b[i] == 0, b[i + 1] == 0, b[i + 2] == 9 { i += 3; return p }
                guard let n = u16(), let k = str(n), let v = one() else { return nil }; p.append((k, v))
            }
            return nil
        }
        func one() -> Value? {
            guard i < b.count else { return nil }
            let t = b[i]; i += 1
            switch t {
            case 0x00: guard i + 8 <= b.count else { return nil }; var u: UInt64 = 0; for k in 0..<8 { u = u << 8 | UInt64(b[i + k]) }; i += 8; return .number(Double(bitPattern: u))
            case 0x01: guard i < b.count else { return nil }; i += 1; return .bool(b[i - 1] != 0)
            case 0x02: guard let n = u16(), let s = str(n) else { return nil }; return .string(s)
            case 0x03: return props().map { .object($0) }
            case 0x05, 0x06: return .null
            case 0x08: i += 4; return props().map { .object($0) }
            case 0x0C: guard i + 4 <= b.count else { return nil }; let n = Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3]); i += 4; return str(n).map { .string($0) }
            default: return nil
            }
        }
        while i < b.count, let v = one() { out.append(v) }
        return out
    }
}
