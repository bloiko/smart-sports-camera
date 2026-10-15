import Foundation
import CoreGraphics
import CoreText

/// Score bug designs in the spirit of top-league broadcasts (own drawings, no league branding):
/// a separate clock block, three-letter team codes, an added-time tab, half-time and a GOAL banner.
public enum ScoreStyle: String, Codable, CaseIterable { case classic, pill, stacked }

/// What the bug shows besides the score: clock text ("67:30"), half (1, 2), added minutes (+3), a phase label
/// instead of the clock ("ПЕРЕРВА"), and a banner under the bug ("ГОЛ!" + team) for a few seconds after a goal.
public struct ScoreExtras {
    public var clock: String?, half: Int, added: Int?, phase: String?, goalFor: Int?   // goalFor: 0 home, 1 away
    public init(clock: String?, half: Int = 1, added: Int? = nil, phase: String? = nil, goalFor: Int? = nil) {
        self.clock = clock; self.half = half; self.added = added; self.phase = phase; self.goalFor = goalFor
    }
}

public extension Scoreboard {
    /// Three-letter code from the name: skips club prefixes (ФК, FC, СК, ФШ, ДЮСШ), first letters of the main word.
    static func code(_ name: String) -> String {
        let skip: Set<String> = ["ФК", "FC", "СК", "SC", "ФШ", "ДЮСШ", "CF", "AFC", "ФСК"]
        let words = name.uppercased().split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "." }).map(String.init).filter { !skip.contains($0) && !$0.isEmpty }
        guard let w = words.first else { return "—" }
        return String(w.prefix(3))
    }

    static func renderStyled(_ s: ScoreState, style: ScoreStyle, extras e: ScoreExtras) -> CGImage? {
        guard s.shown else { return nil }
        let d = Drawer()
        switch style {
        case .classic: return classic(s, e, d)
        case .pill: return pill(s, e, d)
        case .stacked: return stacked(s, e, d)
        }
    }

    // ---------------------------------------------------------------- A. Classic: clock block | teams and score
    private static func classic(_ s: ScoreState, _ e: ScoreExtras, _ d: Drawer) -> CGImage? {
        let h = 54.0, pad = 14.0, chip = 8.0
        let clockT = e.phase ?? e.clock ?? "", halfT = e.phase == nil ? "\(e.half)Т" : ""
        let cw = max(110, d.width(clockT, d.bold(26)) + d.width(halfT, d.reg(16)) + 3 * pad)
        let hc = code(s.home.name), ac = code(s.away.name)
        let nameW = max(d.width(hc, d.bold(26)), d.width(ac, d.bold(26)), 56)
        let sc = "\(s.homeGoals) – \(s.awayGoals)", scW = d.width(sc, d.bold(28)) + 2 * pad
        let teamsW = chip + pad + nameW + pad + scW + pad + nameW + pad + chip
        let W = cw + teamsW, addH = e.added != nil ? 30.0 : 0, banH = e.goalFor != nil ? 46.0 : 0
        let H = h + max(addH, banH > 0 ? banH + 4 : 0)
        return d.image(W, H) { c in
            let top = H - h
            c.fill(CGRect(x: 0, y: top, width: cw, height: h), Drawer.accent)                       // clock block
            if !halfT.isEmpty { d.text(c, halfT, d.reg(16), Drawer.white.copy(alpha: 0.8)!, x: pad, y: top, h: h) }
            d.text(c, clockT, d.bold(26), Drawer.white, x: cw - pad - d.width(clockT, d.bold(26)), y: top, h: h)
            c.fill(CGRect(x: cw, y: top, width: teamsW, height: h), Drawer.panel)
            var x = cw
            c.fill(CGRect(x: x, y: top, width: chip, height: h), Drawer.col(s.home)); x += chip + pad
            d.text(c, hc, d.bold(26), Drawer.white, x: x + (nameW - d.width(hc, d.bold(26))) / 2, y: top, h: h); x += nameW + pad
            c.fill(CGRect(x: x, y: top + 7, width: scW, height: h - 14), Drawer.white)
            d.text(c, sc, d.bold(28), Drawer.ink, x: x + pad, y: top, h: h); x += scW + pad
            d.text(c, ac, d.bold(26), Drawer.white, x: x + (nameW - d.width(ac, d.bold(26))) / 2, y: top, h: h); x += nameW + pad
            c.fill(CGRect(x: x, y: top, width: chip, height: h), Drawer.col(s.away))
            if let a = e.added {                                                                     // added-time tab under the clock
                c.fill(CGRect(x: 0, y: top - addH, width: cw * 0.6, height: addH), Drawer.white)
                d.text(c, "+\(a)", d.bold(20), Drawer.accent, x: pad, y: top - addH, h: addH)
            }
            if let g = e.goalFor { goalBanner(c, d, s, g, x: e.added != nil ? cw * 0.6 + 6 : 0, y: 0, w: teamsW + cw - (e.added != nil ? cw * 0.6 + 6 : 0), h: banH) }
        }
    }

    // ---------------------------------------------------------------- B. Pill: light rounded capsule, clock in an accent capsule
    private static func pill(_ s: ScoreState, _ e: ScoreExtras, _ d: Drawer) -> CGImage? {
        let h = 50.0, pad = 16.0
        let hc = code(s.home.name), ac = code(s.away.name)
        let nameW = max(d.width(hc, d.bold(24)), d.width(ac, d.bold(24)), 52)
        let sc = "\(s.homeGoals)  \(s.awayGoals)", scW = d.width(sc, d.bold(28)) + 2 * pad
        let mainW = pad + 14 + 8 + nameW + pad + scW + pad + nameW + 8 + 14 + pad
        var clockT = e.phase ?? e.clock ?? ""; if e.phase == nil, let a = e.added { clockT += "  +\(a)" }
        let halfT = e.phase == nil ? "\(e.half)Т" : ""
        let cW = d.width(clockT, d.bold(22)) + d.width(halfT, d.reg(15)) + 3 * pad
        let W = mainW + 8 + cW, banH = e.goalFor != nil ? 44.0 : 0, H = h + (banH > 0 ? banH + 6 : 0)
        return d.image(W, H) { c in
            let top = H - h
            c.round(CGRect(x: 0, y: top, width: mainW, height: h), h / 2, Drawer.paper)
            var x = pad
            c.circle(CGPoint(x: x + 7, y: top + h / 2), 8, Drawer.ink.copy(alpha: 0.35)!); c.circle(CGPoint(x: x + 7, y: top + h / 2), 6.5, Drawer.col(s.home)); x += 14 + 8
            d.text(c, hc, d.bold(24), Drawer.ink, x: x, y: top, h: h); x += nameW + pad
            c.round(CGRect(x: x, y: top + 6, width: scW, height: h - 12), (h - 12) / 2, Drawer.ink)
            d.text(c, sc, d.bold(28), Drawer.white, x: x + pad, y: top, h: h); x += scW + pad
            d.text(c, ac, d.bold(24), Drawer.ink, x: x + nameW - d.width(ac, d.bold(24)), y: top, h: h); x += nameW + 8
            c.circle(CGPoint(x: x + 7, y: top + h / 2), 8, Drawer.ink.copy(alpha: 0.35)!); c.circle(CGPoint(x: x + 7, y: top + h / 2), 6.5, Drawer.col(s.away))
            let cx = mainW + 8
            c.round(CGRect(x: cx, y: top + 4, width: cW, height: h - 8), (h - 8) / 2, Drawer.accent)
            if !halfT.isEmpty { d.text(c, halfT, d.reg(15), Drawer.white.copy(alpha: 0.85)!, x: cx + pad, y: top, h: h) }
            d.text(c, clockT, d.bold(22), Drawer.white, x: cx + cW - pad - d.width(clockT, d.bold(22)), y: top, h: h)
            if let g = e.goalFor { goalBanner(c, d, s, g, x: 0, y: 0, w: mainW, h: banH, rounded: true) }
        }
    }

    // ---------------------------------------------------------------- C. Stacked: two team rows, clock column, half strip on top
    private static func stacked(_ s: ScoreState, _ e: ScoreExtras, _ d: Drawer) -> CGImage? {
        let row = 40.0, strip = 24.0, pad = 12.0, bar = 7.0
        let hn = short(s.home.name), an = short(s.away.name)
        let nameW = max(d.width(hn, d.bold(22)), d.width(an, d.bold(22)), 90)
        let scW = 44.0
        var clockT = e.clock ?? ""; if e.phase == nil, let a = e.added { clockT += " +\(a)" }   // the strip says ПЕРЕРВА
        let cW = max(96, d.width(clockT, d.bold(22)) + 2 * pad)
        let W = bar + pad + nameW + pad + scW + cW, mainH = strip + 2 * row
        let banH = e.goalFor != nil ? 40.0 : 0, H = mainH + (banH > 0 ? banH + 4 : 0)
        return d.image(W, H) { c in
            let top = H - mainH
            c.fill(CGRect(x: 0, y: top + 2 * row, width: W, height: strip), Drawer.accent)            // half strip
            let halfT = e.phase ?? (e.half == 1 ? "1-Й ТАЙМ" : "2-Й ТАЙМ")
            d.text(c, halfT, d.bold(14), Drawer.white, x: pad, y: top + 2 * row, h: strip)
            for (i, t) in [(s.home, hn, s.homeGoals), (s.away, an, s.awayGoals)].enumerated() {
                let y = top + row * Double(1 - i)
                c.fill(CGRect(x: 0, y: y, width: W - cW, height: row), i == 0 ? Drawer.panel : Drawer.panel2)
                c.fill(CGRect(x: 0, y: y, width: bar, height: row), Drawer.col(t.0))
                d.text(c, t.1, d.bold(22), Drawer.white, x: bar + pad, y: y, h: row)
                c.fill(CGRect(x: bar + pad + nameW + pad, y: y, width: scW, height: row), Drawer.white.copy(alpha: i == 0 ? 1 : 0.92)!)
                d.text(c, "\(t.2)", d.bold(24), Drawer.ink, x: bar + pad + nameW + pad + (scW - d.width("\(t.2)", d.bold(24))) / 2, y: y, h: row)
            }
            c.fill(CGRect(x: W - cW, y: top, width: cW, height: 2 * row), Drawer.ink)
            d.text(c, clockT, d.bold(22), Drawer.white, x: W - cW + (cW - d.width(clockT, d.bold(22))) / 2, y: top, h: 2 * row)
            if let g = e.goalFor { goalBanner(c, d, s, g, x: 0, y: 0, w: W, h: banH) }
        }
    }

    private static func goalBanner(_ c: CGContext, _ d: Drawer, _ s: ScoreState, _ g: Int, x: Double, y: Double, w: Double, h: Double, rounded: Bool = false) {
        let t = g == 0 ? s.home : s.away
        let r = CGRect(x: x, y: y, width: w, height: h)
        if rounded { c.round(r, h / 2, Drawer.col(t)) } else { c.fill(r, Drawer.col(t)) }
        let light = 0.299 * t.r + 0.587 * t.g + 0.114 * t.b > 0.6
        let ink = light ? Drawer.ink : Drawer.white
        d.text(c, "ГОЛ!", d.bold(26), ink, x: x + 16, y: y, h: h)
        d.text(c, short(t.name), d.bold(22), ink, x: x + 16 + d.width("ГОЛ!", d.bold(26)) + 14, y: y, h: h)
    }
}

/// Small CoreGraphics/CoreText helper for the score bug.
final class Drawer {
    static let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let ink = CGColor(red: 0.07, green: 0.07, blue: 0.1, alpha: 1)
    static let panel = CGColor(red: 0.07, green: 0.08, blue: 0.12, alpha: 0.86)
    static let panel2 = CGColor(red: 0.11, green: 0.12, blue: 0.17, alpha: 0.86)
    static let paper = CGColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 0.94)
    static let accent = CGColor(red: 0.86, green: 0.1, blue: 0.24, alpha: 1)     // Follo red
    static func col(_ t: ScoreTeam) -> CGColor { CGColor(red: t.r, green: t.g, blue: t.b, alpha: 1) }
    func bold(_ s: Double) -> CTFont { CTFontCreateWithName("Helvetica-Bold" as CFString, s, nil) }
    func reg(_ s: Double) -> CTFont { CTFontCreateWithName("Helvetica" as CFString, s, nil) }
    func line(_ t: String, _ f: CTFont, _ c: CGColor) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: t, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): f, NSAttributedString.Key(kCTForegroundColorAttributeName as String): c]))
    }
    func width(_ t: String, _ f: CTFont) -> Double { Double(CTLineGetTypographicBounds(line(t, f, Drawer.white), nil, nil, nil)) }
    func text(_ c: CGContext, _ t: String, _ f: CTFont, _ col: CGColor, x: Double, y: Double, h: Double) {
        c.textPosition = CGPoint(x: x, y: y + (h - Double(CTFontGetAscent(f) - CTFontGetDescent(f))) / 2); CTLineDraw(line(t, f, col), c)
    }
    func image(_ w: Double, _ h: Double, _ draw: (CGContext) -> Void) -> CGImage? {
        let wi = Int(w.rounded(.up)), hi = Int(h.rounded(.up))
        guard let c = CGContext(data: nil, width: wi, height: hi, bitsPerComponent: 8, bytesPerRow: wi * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(c); return c.makeImage()
    }
}

extension CGContext {
    func fill(_ r: CGRect, _ c: CGColor) { setFillColor(c); fill(r) }
    func round(_ r: CGRect, _ rad: Double, _ c: CGColor) { setFillColor(c); addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)); fillPath() }
    func circle(_ p: CGPoint, _ rad: Double, _ c: CGColor) { setFillColor(c); fillEllipse(in: CGRect(x: p.x - rad, y: p.y - rad, width: 2 * rad, height: 2 * rad)) }
}
