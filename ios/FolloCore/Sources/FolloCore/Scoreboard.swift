import Foundation
import CoreGraphics
import CoreText

/// Score bug burned into the 1920×1080 stream (top left), like a TV broadcast: team colour, short name, score, clock.
/// The owner types the team names and picks the jersey colours before the game and changes the score with +/− during it.
public struct ScoreTeam: Codable, Equatable {
    public var name: String
    public var r: Double, g: Double, b: Double
    public init(name: String, r: Double, g: Double, b: Double) { self.name = name; self.r = r; self.g = g; self.b = b }
}

public struct ScoreState: Codable, Equatable {
    public var home: ScoreTeam, away: ScoreTeam
    public var homeGoals = 0, awayGoals = 0
    public var homeRed = 0, awayRed = 0              // red cards, shown as small cards next to the club name
    public var shown = true
    public init(home: ScoreTeam = ScoreTeam(name: "Home", r: 1, g: 1, b: 1), away: ScoreTeam = ScoreTeam(name: "Away", r: 0.1, g: 0.35, b: 0.9)) {
        self.home = home; self.away = away
    }
    /// Older saved states have no red cards: missing fields take their defaults.
    public init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        home = try c.decode(ScoreTeam.self, forKey: .home); away = try c.decode(ScoreTeam.self, forKey: .away)
        homeGoals = try c.decodeIfPresent(Int.self, forKey: .homeGoals) ?? 0; awayGoals = try c.decodeIfPresent(Int.self, forKey: .awayGoals) ?? 0
        homeRed = try c.decodeIfPresent(Int.self, forKey: .homeRed) ?? 0; awayRed = try c.decodeIfPresent(Int.self, forKey: .awayRed) ?? 0
        shown = try c.decodeIfPresent(Bool.self, forKey: .shown) ?? true
    }
}

public enum Scoreboard {
    /// Rendered score bug (premultiplied RGBA) for a 1080p frame; nil when hidden. Place it at (margin, margin) from the top left.
    public static let margin = 32
    public static func render(_ s: ScoreState, clock: String?) -> CGImage? {
        guard s.shown else { return nil }
        let h = 56.0, pad = 16.0, bar = 10.0
        let nameFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 28, nil)
        let scoreFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 32, nil)
        let clockFont = CTFontCreateWithName("Helvetica" as CFString, 26, nil)
        func line(_ t: String, _ f: CTFont, _ c: CGColor) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: t, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): f, NSAttributedString.Key(kCTForegroundColorAttributeName as String): c]))
        }
        func width(_ l: CTLine) -> Double { Double(CTLineGetTypographicBounds(l, nil, nil, nil)) }
        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1), dark = CGColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1)
        let hn = line(short(s.home.name), nameFont, white), an = line(short(s.away.name), nameFont, white)
        let sc = line("\(s.homeGoals) – \(s.awayGoals)", scoreFont, dark)
        let cl = clock.map { line($0, clockFont, white) }
        let nameW = max(width(hn), width(an), 60)                    // both names in equal boxes: the bug does not jump
        let scoreW = width(sc) + 2 * pad
        let clockW = cl.map { width($0) + 2 * pad } ?? 0
        let W = bar + pad + nameW + pad + scoreW + pad + nameW + pad + bar + clockW
        let wi = Int(W.rounded(.up)), hi = Int(h)
        guard let ctx = CGContext(data: nil, width: wi, height: hi, bitsPerComponent: 8, bytesPerRow: wi * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 0.78)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: h))
        ctx.setFillColor(CGColor(red: s.home.r, green: s.home.g, blue: s.home.b, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: bar, height: h))
        let awayBarX = bar + pad + nameW + pad + scoreW + pad + nameW + pad
        ctx.setFillColor(CGColor(red: s.away.r, green: s.away.g, blue: s.away.b, alpha: 1)); ctx.fill(CGRect(x: awayBarX, y: 0, width: bar, height: h))
        let scoreX = bar + pad + nameW + pad
        ctx.setFillColor(white); ctx.fill(CGRect(x: scoreX, y: 6, width: scoreW, height: h - 12))
        func draw(_ l: CTLine, x: Double, f: CTFont) {
            let base = (h - Double(CTFontGetAscent(f) - CTFontGetDescent(f))) / 2
            ctx.textPosition = CGPoint(x: x, y: base); CTLineDraw(l, ctx)
        }
        draw(hn, x: bar + pad + (nameW - width(hn)) / 2, f: nameFont)
        draw(sc, x: scoreX + pad, f: scoreFont)
        draw(an, x: scoreX + scoreW + pad + (nameW - width(an)) / 2, f: nameFont)
        if let cl { draw(cl, x: awayBarX + bar + pad, f: clockFont) }
        return ctx.makeImage()
    }

    /// Names longer than 12 characters are cut: the bug must stay small on a phone screen.
    static func short(_ n: String) -> String {
        let t = n.trimmingCharacters(in: .whitespaces).uppercased()
        return t.count <= 12 ? (t.isEmpty ? "—" : t) : String(t.prefix(11)) + "."
    }

    /// Match clock "mm:ss" (minutes keep counting past 59: 92:15).
    public static func clock(_ seconds: Double) -> String { let s = max(0, Int(seconds)); return String(format: "%d:%02d", s / 60, s % 60) }
}
