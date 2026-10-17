import SwiftUI
import Combine
import FolloCore

/// Рахунок на трансляції: назви і кольори форм задає власник перед грою, рахунок змінює кнопками +/− під час гри.
/// Стан переживає крах (UserDefaults), як і сам ефір.
@MainActor
final class ScoreModel: ObservableObject {
    @Published var state: ScoreState { didSet { save() } }
    // Годинник матчу: іде від clockStart; на паузі показує pausedAt (с). Тайм і його тривалість задає власник.
    @Published var clockStart: Date? { didSet { UserDefaults.standard.set(clockStart, forKey: "score.clockStart") } }
    @Published var pausedAt: Double? { didSet { UserDefaults.standard.set(pausedAt, forKey: "score.pausedAt") } }
    @Published var half: Int { didSet { UserDefaults.standard.set(half, forKey: "score.half") } }
    @Published var halfMinutes: Int { didSet { UserDefaults.standard.set(halfMinutes, forKey: "score.halfMinutes") } }
    @Published var added: Int { didSet { UserDefaults.standard.set(added, forKey: "score.added") } }      // доданий час, хв (0 — не показувати)
    private var goalFor: Int?, goalUntil = Date.distantPast                                                   // банер «ГОЛ!» 6 с після +
    private var redFor: Int?, redUntil = Date.distantPast                                                     // банер «ЧЕРВОНА КАРТКА» 6 с
    private var lastKey = ""

    init() {
        state = UserDefaults.standard.data(forKey: "score.state").flatMap { try? JSONDecoder().decode(ScoreState.self, from: $0) } ?? ScoreState()
        clockStart = UserDefaults.standard.object(forKey: "score.clockStart") as? Date
        pausedAt = UserDefaults.standard.object(forKey: "score.pausedAt") as? Double
        half = max(1, UserDefaults.standard.integer(forKey: "score.half"))
        halfMinutes = UserDefaults.standard.object(forKey: "score.halfMinutes") as? Int ?? 45
        added = UserDefaults.standard.integer(forKey: "score.added")
    }

    /// Секунди на годиннику зараз (nil — годинник не запущено).
    var seconds: Double? { pausedAt ?? clockStart.map { Date().timeIntervalSince($0) } }
    var clockText: String? { seconds.map { "\(half)Т " + Scoreboard.clock($0) } }
    /// Поставити час вручну (запізнився на гру, перерва): пауза зберігається.
    func setClock(_ s: Double) {
        if pausedAt != nil { pausedAt = max(0, s) } else { clockStart = Date().addingTimeInterval(-max(0, s)) }
        DebugLog.log("clock set \(Scoreboard.clock(s)) half \(half)")
    }
    func togglePause() {
        if let p = pausedAt { pausedAt = nil; clockStart = Date().addingTimeInterval(-p) }
        else { pausedAt = seconds ?? 0 }
    }
    /// Інший тайм: годинник ставиться на його початок (2-й — з тривалості тайму, 45:00); пауза зберігається.
    func setHalf(_ h: Int) { half = h; added = 0; setClock(Double((h - 1) * halfMinutes * 60)) }
    private func save() { UserDefaults.standard.set(try? JSONEncoder().encode(state), forKey: "score.state") }

    /// Новий матч: 0:0, годинник з нуля. Назви і кольори лишаються з минулого разу.
    func newMatch() { state.homeGoals = 0; state.awayGoals = 0; state.homeRed = 0; state.awayRed = 0; half = 1; added = 0; pausedAt = nil; clockStart = Date() }
    func add(home: Bool, _ d: Int) {
        if home { state.homeGoals = max(0, state.homeGoals + d) } else { state.awayGoals = max(0, state.awayGoals + d) }
        if d > 0 { goalFor = home ? 0 : 1; goalUntil = Date().addingTimeInterval(6); redUntil = .distantPast } else { goalUntil = .distantPast }
    }
    /// Червона картка: маленька картка біля назви клубу на табло (до 5), банер на 6 с; − знімає помилкову.
    func addRed(home: Bool, _ d: Int) {
        if home { state.homeRed = max(0, min(5, state.homeRed + d)) } else { state.awayRed = max(0, min(5, state.awayRed + d)) }
        if d > 0 { redFor = home ? 0 : 1; redUntil = Date().addingTimeInterval(6); goalUntil = .distantPast } else { redUntil = .distantPast }
        DebugLog.log("red cards \(state.homeRed):\(state.awayRed)")
        DebugLog.log("score \(state.homeGoals):\(state.awayGoals)")
    }

    /// Раз на секунду і після кожної зміни: перемальовує табло, лише якщо текст змінився.
    func push(to runner: LiveCameraRunner) {
        // червоний блок годинника з таймом, повні назви клубів, +N доданого часу, ПЕРЕРВА на паузі, ГОЛ! 6 с
        let ex = ScoreExtras(clock: seconds.map { Scoreboard.clock($0) }, half: half, added: added > 0 ? added : nil,
                             phase: pausedAt != nil ? "ПЕРЕРВА" : nil, goalFor: Date() < goalUntil ? goalFor : nil, fullNames: true,
                             redFor: Date() < redUntil ? redFor : nil)
        let key = "\(state)\(ex.clock ?? "")\(half)\(added)\(ex.phase ?? "")\(ex.goalFor ?? -1)\(ex.redFor ?? -1)"
        guard key != lastKey else { return }
        lastKey = key; runner.setScoreboard(Scoreboard.renderStyled(state, style: .classic, extras: ex))
    }
}

/// Кольори форм: великі кружки, щоб попасти пальцем на полі.
let jerseyColours: [(String, Double, Double, Double)] = [
    ("Білий", 0.95, 0.95, 0.95), ("Чорний", 0.1, 0.1, 0.1), ("Червоний", 0.85, 0.12, 0.15), ("Синій", 0.1, 0.3, 0.85),
    ("Блакитний", 0.4, 0.7, 0.95), ("Зелений", 0.1, 0.6, 0.25), ("Жовтий", 0.98, 0.85, 0.1), ("Помаранчевий", 0.98, 0.5, 0.1),
    ("Фіолетовий", 0.5, 0.25, 0.7), ("Сірий", 0.55, 0.55, 0.58)]

struct TeamsSheet: View {
    @ObservedObject var score: ScoreModel
    var done: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                team("Господарі", $score.state.home)
                team("Гості", $score.state.away)
                Toggle("Показувати рахунок на трансляції", isOn: $score.state.shown)
            }
            .navigationTitle("Команди").toolbar { Button("Готово") { done() } }
        }
    }
    func team(_ title: String, _ t: Binding<ScoreTeam>) -> some View {
        Section(title) {
            TextField("Назва команди", text: t.name).textInputAutocapitalization(.words)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                ForEach(jerseyColours, id: \.0) { c in
                    let on = abs(t.wrappedValue.r - c.1) + abs(t.wrappedValue.g - c.2) + abs(t.wrappedValue.b - c.3) < 0.01
                    Circle().fill(Color(red: c.1, green: c.2, blue: c.3)).frame(width: 40, height: 40)
                        .overlay(Circle().stroke(on ? Color.accentColor : Color.gray.opacity(0.5), lineWidth: on ? 4 : 1))
                        .onTapGesture { t.wrappedValue.r = c.1; t.wrappedValue.g = c.2; t.wrappedValue.b = c.3 }
                        .accessibilityLabel(c.0)
                }
            }.padding(.vertical, 4)
        }
    }
}

/// Під час ефіру: дві команди з великими + і −; утримання годинника — відлік з нуля (стартовий свисток).
struct ScoreBar: View {
    @ObservedObject var score: ScoreModel
    @State private var showClock = false
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                side(home: true)
                Text(":").font(.system(size: 28, weight: .heavy, design: .rounded))
                side(home: false)
            }
            HStack(spacing: 10) {
                Text(score.clockText ?? "—").monospacedDigit().font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
                Button { score.togglePause() } label: { Image(systemName: score.pausedAt != nil ? "play.fill" : "pause.fill").frame(width: 36, height: 30) }.buttonStyle(.bordered)
                Button { showClock = true } label: { Label("Час і тайм", systemImage: "clock").font(.footnote) }.buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $showClock) { ClockSheet(score: score) { showClock = false } }
        .padding(10).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    func side(home: Bool) -> some View {
        let t = home ? score.state.home : score.state.away, n = home ? score.state.homeGoals : score.state.awayGoals
        return VStack(spacing: 4) {
            HStack(spacing: 6) { Circle().fill(Color(red: t.r, green: t.g, blue: t.b)).frame(width: 12, height: 12); Text(t.name).font(.caption).lineLimit(1) }
            HStack(spacing: 6) {                                                // вужче: на iPhone панель виходила за край екрана
                Button { score.add(home: home, -1) } label: { Image(systemName: "minus").frame(width: 32, height: 36) }.buttonStyle(.bordered)
                Text("\(n)").font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit().frame(minWidth: 30)
                Button { score.add(home: home, 1) } label: { Image(systemName: "plus").frame(width: 32, height: 36) }.buttonStyle(.borderedProminent)
            }
            let red = home ? score.state.homeRed : score.state.awayRed
            HStack(spacing: 6) {                                               // червоні картки: + і − поруч, щоб виправити помилку
                Button { score.addRed(home: home, 1) } label: {
                    HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(width: 11, height: 16); Text(red > 0 ? "\(red)" : "+").font(.caption.bold()) }
                        .frame(height: 26).padding(.horizontal, 6)
                }.buttonStyle(.bordered)
                if red > 0 { Button { score.addRed(home: home, -1) } label: { Image(systemName: "minus").font(.caption).frame(height: 26) }.buttonStyle(.bordered) }
            }
        }.frame(maxWidth: .infinity)
    }
}

/// Поставити тайм і час вручну: запізнився на гру, перерва, другий тайм.
struct ClockSheet: View {
    @ObservedObject var score: ScoreModel
    var done: () -> Void
    @State private var minutes = 0
    @State private var secs = 0
    var body: some View {
        NavigationStack {
            Form {
                Section("Тайм") {
                    Picker("Тайм", selection: Binding(get: { score.half }, set: { score.setHalf($0); load() })) {
                        Text("1-й").tag(1); Text("2-й").tag(2)
                    }.pickerStyle(.segmented)
                    Stepper("Тайм триває \(score.halfMinutes) хв", value: $score.halfMinutes, in: 10...45, step: 5)
                }
                Section("Час на годиннику") {
                    HStack {
                        Picker("Хвилини", selection: $minutes) { ForEach(0..<131, id: \.self) { Text("\($0) хв").tag($0) } }.pickerStyle(.wheel)
                        Picker("Секунди", selection: $secs) { ForEach(0..<60, id: \.self) { Text("\($0) с").tag($0) } }.pickerStyle(.wheel)
                    }.frame(height: 140)
                    Button("Встановити \(minutes):\(String(format: "%02d", secs))") { score.setClock(Double(minutes * 60 + secs)); done() }
                    Button("Почати тайм з нуля") { score.setClock(Double((score.half - 1) * score.halfMinutes * 60)); done() }
                }
                Section("Доданий час") {
                    Stepper(score.added == 0 ? "Не показувати" : "+\(score.added) хв", value: $score.added, in: 0...15)
                }
                Section { Button(score.pausedAt != nil ? "Продовжити годинник" : "Пауза (перерва)") { score.togglePause() } }
            }
            .navigationTitle("Час і тайм").toolbar { Button("Готово") { done() } }
            .onAppear { load() }
        }
    }
    func load() { let s = Int(score.seconds ?? 0); minutes = min(130, s / 60); secs = s % 60 }
}
