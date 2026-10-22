import SwiftUI
import CoreMotion
import Combine
import FolloCore

/// Нахил і рух телефона (датчики iPhone, системний CoreMotion): лінія горизонту на прев'ю, «телефон рівно»,
/// і повторна перевірка позиції, коли телефон повернули і він знову стоїть нерухомо (власник, 2026-10-19).
@MainActor final class TiltMonitor: ObservableObject {
    /// Кут горизонту в кадрі, градуси (0 — рівно). nil — датчиків немає (симулятор).
    @Published var tilt: Double?
    @Published var portrait = false
    @Published var moving = false
    /// Телефон рухали, і він стоїть нерухомо вже 1,5 с.
    var onSettled: (() -> Void)?
    private let mm = CMMotionManager()
    private var stillSince: Date?, wasMoving = false

    func start() {
        guard mm.isDeviceMotionAvailable, !mm.isDeviceMotionActive else { return }
        mm.deviceMotionUpdateInterval = 0.1
        mm.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let m else { return }
            MainActor.assumeIsolated { self?.update(m) }
        }
    }
    func stop() { mm.stopDeviceMotionUpdates() }

    private func update(_ m: CMDeviceMotion) {
        let g = m.gravity
        // Кадр камери — рідна орієнтація сенсора (videoRotationAngle 0): телефон лежить горизонтально, верх ліворуч,
        // сила тяжіння ≈ (−1, 0, 0). У координатах кадру (y донизу) вона (−g.y, −g.x): кут від «прямо вниз» = нахил.
        let por = abs(g.y) > abs(g.x) + 0.2
        if por != portrait { portrait = por }
        let t = (atan2(-g.y, -g.x) * 180 / .pi * 2).rounded() / 2      // крок 0,5°: екран не перемальовується 10 разів на секунду
        if t != tilt { tilt = t }
        let r = m.rotationRate, spin = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
        if spin > 0.25 { moving = true; wasMoving = true; stillSince = nil; return }
        if stillSince == nil { stillSince = Date() }
        if moving, Date().timeIntervalSince(stillSince!) > 1.5 {
            moving = false
            if wasMoving { wasMoving = false; onSettled?() }
        }
    }
}

/// Що показати перед матчем: один висновок (чекай / виправ / готово), рядки чекліста і що малювати на прев'ю.
/// Слова «ворота» — лише коли застосунок справді знає ворота (знайоме поле); інакше «кінець поля» (власник, 2026-10-19).
struct PositionCheck {
    enum Verdict { case checking, problem, ready }
    struct Row: Identifiable { let id = UUID(); let ok: Bool?; let text: String; var icon: String? = nil }
    var verdict: Verdict
    var title: String
    var detail: String
    var arrow = 0                     // −1: поверни ліворуч, +1: праворуч
    var rows: [Row] = []
    var knownGoals: [Pt]?

    static let levelDeg = 1.5         // до стількох градусів — «рівно»

    /// `extra`: готовність телефона до матчу (місце, батарея, нагрів, команди) — додається в кінець чекліста, ефір не блокує.
    static func make(runner: LiveCameraRunner, halfPitch: Bool, tilt: TiltMonitor, lowLight: String?, extra: [Row] = []) -> PositionCheck {
        var rows: [Row] = []
        let tiltRow: Row? = {
            if tilt.portrait { return Row(ok: false, text: "Поверни телефон горизонтально", icon: "rectangle.landscape.rotate") }
            guard let a = tilt.tilt else { return nil }
            return abs(a) <= levelDeg ? Row(ok: true, text: "Телефон рівно") : Row(ok: false, text: String(format: "Нахил %.0f°: вирівняй телефон", abs(a)), icon: "level")
        }()
        let lightRow = lowLight == nil ? Row(ok: true, text: "Світла досить") : Row(ok: false, text: "Мало світла", icon: "sun.min")
        guard let env = runner.env else {
            let left = max(0, Int(Double(7 - runner.prerollCount) * 1.4 + 4))
            rows = [Row(ok: nil, text: "Поле"), Row(ok: nil, text: "Кінці поля")]
            if let t = tiltRow { rows.append(t) }
            rows.append(lightRow); rows += extra
            let d = tilt.moving ? "Телефон рухається: тримай його нерухомо"
                : runner.building ? "Рахую поле…" : "Тримай телефон нерухомо ще \(left) с"
            return PositionCheck(verdict: .checking, title: "Дивлюсь на поле", detail: d, rows: rows)
        }
        let goals = runner.knownGoals
        let ov = runner.positionOverlay
        let p = env.positionProblem
        let name = goals == nil ? ("Лівий кінець поля", "Правий кінець поля") : ("Ліві ворота", "Праві ворота")
        if p?.hasPrefix("No pitch") == true {
            rows = [Row(ok: false, text: "Поле не знайдено", icon: "xmark")]
        } else {
            rows.append(Row(ok: true, text: "Поле знайдено"))
            let lOK = ov?.leftOK ?? true, rOK = ov?.rightOK ?? true
            if halfPitch, !(lOK && rOK) {
                rows.append(Row(ok: true, text: "Один кінець поля поза кадром: так і треба для пів поля"))
            } else {
                rows.append(lOK ? Row(ok: true, text: "\(name.0) в кадрі") : Row(ok: false, text: "\(name.0) за краєм кадру", icon: "arrow.left"))
                rows.append(rOK ? Row(ok: true, text: "\(name.1) в кадрі") : Row(ok: false, text: "\(name.1) за краєм кадру", icon: "arrow.right"))
            }
            if p?.contains("too small") == true { rows.append(Row(ok: false, text: "Поле замале в кадрі", icon: "arrow.up.left.and.arrow.down.right")) }
        }
        if let t = tiltRow { rows.append(t) }
        rows.append(lightRow); rows += extra

        let okForMode = p == nil || (halfPitch && p!.contains("goal"))
        if okForMode {
            if halfPitch { return PositionCheck(verdict: .ready, title: "Пів поля (1×)", detail: "Видно частину поля. Можна починати, не рухай телефон", rows: rows, knownGoals: goals) }
            return PositionCheck(verdict: .ready, title: "Все поле в кадрі",
                                 detail: goals != nil ? "Знайоме поле: ворота з минулого матчу. Не рухай телефон"
                                                      : "Обидва кінці поля видно. Ворота знайду сам за перші хвилини гри",
                                 rows: rows, knownGoals: goals)
        }
        let p2 = p ?? ""
        if p2.hasPrefix("No pitch") { return PositionCheck(verdict: .problem, title: "Поле не знайдено", detail: "Наведи камеру на поле", rows: rows) }
        if p2.contains("too small") { return PositionCheck(verdict: .problem, title: "Поле замале в кадрі", detail: "Постав телефон ближче або вище", rows: rows) }
        let left = p2.contains("left")
        let what = goals == nil ? (left ? "Лівий кінець поля" : "Правий кінець поля") : (left ? "Ліві ворота" : "Праві ворота")
        return PositionCheck(verdict: .problem, title: left ? "Поверни трохи ліворуч" : "Поверни трохи праворуч",
                             detail: "\(what) за краєм кадру. Повернеш — перевірю сам", arrow: left ? -1 : 1, rows: rows, knownGoals: goals)
    }

    var color: Color { verdict == .ready ? Color(red: 0.36, green: 0.79, blue: 0.65) : verdict == .problem ? Color(red: 0.94, green: 0.6, blue: 0.48) : .secondary }
}

/// Поверх прев'ю: сітка третин і лінія горизонту (завжди до ефіру), а після перевірки — контур поля, мітки кінців поля
/// (або ворота знайомого поля) і стрілка, куди повернути.
struct PositionCanvas: View {
    var overlay: PositionOverlay?
    var check: PositionCheck
    var tilt: Double?
    /// Розмір кадру камери: сітка і горизонт лише на картинці, не на чорних смугах навколо.
    var imageSize: CGSize?

    var body: some View {
        Canvas { ctx, size in
            let full = CGRect(origin: .zero, size: size)
            let img = imageSize.map { fit(w: $0.width, h: $0.height, in: full) } ?? full
            // сітка третин
            var grid = Path()
            for i in 1...2 {
                let x = img.minX + img.width * CGFloat(i) / 3, y = img.minY + img.height * CGFloat(i) / 3
                grid.move(to: CGPoint(x: x, y: img.minY)); grid.addLine(to: CGPoint(x: x, y: img.maxY))
                grid.move(to: CGPoint(x: img.minX, y: y)); grid.addLine(to: CGPoint(x: img.maxX, y: y))
            }
            ctx.stroke(grid, with: .color(.white.opacity(0.22)), lineWidth: 0.7)
            // лінія горизонту: справжня горизонталь у кадрі; зелена, коли телефон рівно
            if let a = tilt {
                let level = abs(a) <= PositionCheck.levelDeg
                var h = Path(); let L = img.width * 0.3
                h.move(to: CGPoint(x: -L, y: 0)); h.addLine(to: CGPoint(x: L, y: 0))
                let tr = CGAffineTransform(translationX: img.midX, y: img.midY).rotated(by: CGFloat(-a * .pi / 180))
                ctx.stroke(h.applying(tr), with: .color(level ? Color(red: 0.36, green: 0.79, blue: 0.65) : .orange), lineWidth: 2)
            }
            guard let ov = overlay, check.verdict != .checking else { return }
            let r = fit(w: CGFloat(ov.w), h: CGFloat(ov.h), in: full)
            let sx = r.width / CGFloat(ov.maskW), sy = r.height / CGFloat(ov.maskH)
            // поза полем трохи темніше, по краю поля — контур
            var dim = Path(), edge = Path()
            for y in 0..<ov.maskH {
                var x = 0
                while x < ov.maskW {                                     // поза полем: один прямокутник на відрізок рядка
                    guard ov.mask[y * ov.maskW + x] == 0 else { x += 1; continue }
                    let x0 = x; while x < ov.maskW, ov.mask[y * ov.maskW + x] == 0 { x += 1 }
                    dim.addRect(CGRect(x: r.minX + CGFloat(x0) * sx, y: r.minY + CGFloat(y) * sy, width: CGFloat(x - x0) * sx, height: sy + 0.5))
                }
                for x in 0..<ov.maskW where ov.mask[y * ov.maskW + x] != 0 {
                    let cell = CGRect(x: r.minX + CGFloat(x) * sx, y: r.minY + CGFloat(y) * sy, width: sx + 0.5, height: sy + 0.5)
                    let border = x == 0 || y == 0 || x == ov.maskW - 1 || y == ov.maskH - 1
                        || ov.mask[y * ov.maskW + x - 1] == 0 || ov.mask[y * ov.maskW + x + 1] == 0
                        || ov.mask[(y - 1) * ov.maskW + x] == 0 || ov.mask[(y + 1) * ov.maskW + x] == 0
                    if border, !(x == 0 || x == ov.maskW - 1 || y == ov.maskH - 1) { edge.addRect(cell.insetBy(dx: -0.4, dy: -0.4)) }
                }
            }
            ctx.fill(dim, with: .color(.black.opacity(0.35)))
            ctx.fill(edge, with: .color(check.verdict == .ready ? check.color : .white.opacity(0.9)))
            let px = r.width / CGFloat(ov.w), py = r.height / CGFloat(ov.h)
            let ok = Color(red: 0.11, green: 0.62, blue: 0.46), bad = Color(red: 0.85, green: 0.35, blue: 0.19)
            // смуга біля краю кадру, де кінець поля бути не може
            for (x0, good) in [(0.0, ov.leftOK), (Double(ov.w) - ov.margin, ov.rightOK)] where !good {
                ctx.fill(Path(CGRect(x: r.minX + CGFloat(x0) * px, y: r.minY, width: CGFloat(ov.margin) * px, height: r.height)), with: .color(bad.opacity(0.35)))
            }
            if let goals = check.knownGoals {
                for g in goals {                                         // ворота знайомого поля
                    let c = CGPoint(x: r.minX + CGFloat(g.x) * px, y: r.minY + CGFloat(g.y) * py), s = max(10, r.width / 28)
                    ctx.stroke(Path(CGRect(x: c.x - s / 2, y: c.y - s * 0.6, width: s, height: s * 0.6)), with: .color(.white), lineWidth: 2)
                    let gp = CGPoint(x: min(max(c.x, r.minX + 26), r.maxX - 26), y: max(c.y - s * 0.6 - 9, r.minY + 8))
                    ctx.fill(Path(roundedRect: CGRect(x: gp.x - 25, y: gp.y - 8, width: 50, height: 16), cornerRadius: 8), with: .color(.black.opacity(0.6)))
                    ctx.draw(Text("ворота").font(.caption2.weight(.semibold)).foregroundStyle(.white), at: gp)
                }
            } else {
                let y = r.minY + CGFloat((ov.farTop + ov.farBottom) / 2) * py, rad = max(5, r.width / 70)
                for (x, good) in [(ov.farLeft, ov.leftOK), (ov.farRight, ov.rightOK)] {
                    let c = CGPoint(x: min(max(r.minX + CGFloat(x) * px, r.minX + rad), r.maxX - rad), y: y)
                    let e = Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: 2 * rad, height: 2 * rad))
                    ctx.fill(e, with: .color(good ? ok : bad)); ctx.stroke(e, with: .color(.white), lineWidth: 1.5)
                    let lx = min(max(c.x, r.minX + 34), r.maxX - 34)
                    let ly = c.y - rad - 9 < r.minY + 7 ? c.y + rad + 9 : c.y - rad - 9   // біля верхнього краю — під міткою
                    ctx.fill(Path(roundedRect: CGRect(x: lx - 36, y: ly - 8, width: 72, height: 16), cornerRadius: 8), with: .color(.black.opacity(0.6)))
                    ctx.draw(Text("кінець поля").font(.caption2.weight(.semibold)).foregroundStyle(.white), at: CGPoint(x: lx, y: ly))
                }
            }
            if check.arrow != 0 {                                        // куди повернути телефон
                let s = min(r.width, r.height) * 0.12, cx = check.arrow < 0 ? r.minX + r.width * 0.16 : r.maxX - r.width * 0.16, cy = r.midY
                let d = CGFloat(check.arrow)
                var a = Path()                                           // вістря з боку, куди повертати
                let tip = CGPoint(x: cx + d * s, y: cy)
                a.move(to: CGPoint(x: cx - d * s, y: cy)); a.addLine(to: tip)
                a.move(to: tip); a.addLine(to: CGPoint(x: tip.x - d * s * 0.6, y: cy - s * 0.6))
                a.move(to: tip); a.addLine(to: CGPoint(x: tip.x - d * s * 0.6, y: cy + s * 0.6))
                ctx.stroke(a, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false).accessibilityIdentifier("positionOverlay")
    }

    private func fit(w W: CGFloat, h H: CGFloat, in rect: CGRect) -> CGRect {
        let k = min(rect.width / W, rect.height / H)
        let w = W * k, h = H * k
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}

/// Висновок і чекліст під прев'ю.
struct PositionCard: View {
    var check: PositionCheck
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(check.title).font(.headline).foregroundStyle(check.verdict == .checking ? Color.primary : check.color)
                .accessibilityIdentifier("status").accessibilityLabel("\(check.title). \(check.detail)")
            Text(check.detail).font(.footnote).foregroundStyle(.secondary).padding(.bottom, 4)
            ForEach(check.rows) { r in
                HStack(spacing: 6) {
                    Image(systemName: r.ok == nil ? "circle.dotted" : r.ok! ? "checkmark" : (r.icon ?? "exclamationmark.triangle"))
                        .frame(width: 18)
                    Text(r.text)
                }
                .font(.footnote)
                .foregroundStyle(r.ok == nil ? Color.secondary : r.ok! ? Color(red: 0.36, green: 0.79, blue: 0.65) : Color(red: 0.94, green: 0.6, blue: 0.48))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain).accessibilityIdentifier("positionCard")
    }
}
