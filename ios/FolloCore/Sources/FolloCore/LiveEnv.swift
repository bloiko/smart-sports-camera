import Foundation
import CoreGraphics
import ImageIO

/// What the camera knows about the pitch before the game: dilated field mask, image content bounds per column,
/// halfway line x(y). On the Mac it is loaded from the files written by `live_sim.py --dump`; on the phone it is
/// computed by FieldMask.swift during the position check.
public struct LiveEnv {
    public var W: Int, H: Int, fps: Double
    public var fmd: Mask
    public var top: [Double], bot: [Double]
    public var centre: ((Double) -> Double)?
    public var fm: Mask? = nil                 // undilated mask (ball filter in the tracker)
    public var centreEnds: (Double, Double)? = nil
    public var farLine: FarLine? = nil          // far touchline: mask cut above it, its ends = ends of the pitch

    public static let prerollS = 10.0

    /// Compute from the first prerollS seconds of a video (the position check on the phone does the same with live frames).
    public static func make(reader: VideoReader) throws -> LiveEnv {
        try reader.start(); let n = min(reader.frames, Int(prerollS * reader.fps)); var want: [Int: Image8] = [:]
        let idx = (0..<7).map { Int(Double(n) * (Double($0) + 0.5) / 7) }
        var f = 0
        while f <= idx.last!, let pb = reader.next() { if idx.contains(f) { want[f] = Image8(bgra: pb) }; f += 1 }
        return make(frames: idx.compactMap { want[$0] }, fps: reader.fps)
    }

    public static func make(frames: [Image8], fps: Double) -> LiveEnv {
        let med = Image8.median(frames); let (fm, line) = FieldMask.makeWithLine(median: med); let (top, bot) = FieldMask.contentBounds(med)
        let cl = CentreLine.find(mask: fm, median: med)
        var e = LiveEnv(W: med.w, H: med.h, fps: fps, fmd: fm.dilated(41), top: top, bot: bot, centre: cl)
        e.fm = fm; e.farLine = line; if let c = cl { e.centreEnds = (c(0), c(Double(med.h))) }
        return e
    }

    public func save(dir: String, prefix: String) throws {
        let o: [String: Any] = ["W": W, "H": H, "fps": fps, "top": top, "bot": bot, "preroll_s": Self.prerollS,
                                "cline": ["x0": centreEnds?.0 ?? Double.nan, "x1": centreEnds?.1 ?? Double.nan], "far_line": farLine?.json ?? NSNull()]
        try JSONSerialization.data(withJSONObject: o).write(to: URL(fileURLWithPath: dir + "/\(prefix)env.json"))
        try fmd.savePNG(dir + "/\(prefix)fmd.png"); try fm?.savePNG(dir + "/\(prefix)fm.png")
    }

    public static func load(dir: String, prefix: String = "") throws -> LiveEnv {
        let d = try Data(contentsOf: URL(fileURLWithPath: dir + "/\(prefix)env.json"))
        let o = try JSONSerialization.jsonObject(with: d) as! [String: Any]
        let W = o["W"] as! Int, H = o["H"] as! Int, fps = o["fps"] as! Double
        let cl = o["cline"] as! [String: Any]; let x0 = cl["x0"] as! Double, x1 = cl["x1"] as! Double
        let centre: ((Double) -> Double)? = x0.isNaN ? nil : { y in x0 + (x1 - x0) * y / Double(H) }
        var e = LiveEnv(W: W, H: H, fps: fps, fmd: try Mask.loadPNG(dir + "/\(prefix)fmd.png"), top: o["top"] as! [Double], bot: o["bot"] as! [Double], centre: centre)
        e.fm = try? Mask.loadPNG(dir + "/\(prefix)fm.png"); e.farLine = FarLine(json: o["far_line"]); return e
    }
}

extension Mask {
    /// Load a grey PNG (0 / 255) as a mask.
    public static func loadPNG(_ path: String) throws -> Mask {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw NSError(domain: "Mask", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot read \(path)"])
        }
        let w = img.width, h = img.height; var buf = [UInt8](repeating: 0, count: w * h)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Mask(w: w, h: h, data: buf.map { $0 > 127 ? 1 : 0 })
    }

    public func savePNG(_ path: String) throws {
        var buf = data.map { $0 != 0 ? UInt8(255) : 0 }
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        guard let img = ctx.makeImage(), let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { throw NSError(domain: "Mask", code: 2) }
        CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst)
    }
}

/// Camera path as JSON (arrays per frame), for comparison with the Python npz (src/compare_swift.py).
public enum CameraPathJSON {
    public static func write(_ cam: LiveCamera, to path: String) throws {
        let fr = cam.frames
        func nan(_ v: Double?) -> Any { v.map { $0 } ?? NSNull() }
        let o: [String: Any] = [
            "X": fr.map { $0.x }, "Y": fr.map { $0.y }, "CW": fr.map { $0.cw }, "CH": fr.map { $0.ch },
            "GON": fr.map { $0.gon }, "GI": fr.map { $0.gi },
            "BX": fr.map { nan($0.ball?.x) }, "BY": fr.map { nan($0.ball?.y) },
            "GOALS": cam.goals.map { $0.map { [$0.x, $0.y] } } ?? [], "goals_first_s": nan(cam.goalsFirstS)]
        try JSONSerialization.data(withJSONObject: o).write(to: URL(fileURLWithPath: path))
    }
}
