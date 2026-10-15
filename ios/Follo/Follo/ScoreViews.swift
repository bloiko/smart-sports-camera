import SwiftUI
import Combine
import FolloCore

/// Рахунок на трансляції: назви і кольори форм задає власник перед грою, рахунок змінює кнопками +/− під час гри.
/// Стан переживає крах (UserDefaults), як і сам ефір.
@MainActor
final class ScoreModel: ObservableObject {
    @Published var state: ScoreState { didSet { save() } }
    @Published var clockStart: Date? { didSet { UserDefaults.standard.set(clockStart, forKey: "score.clockStart") } }
    private var lastKey = ""

    init() {
        state = UserDefaults.standard.data(forKey: "score.state").flatMap { try? JSONDecoder().decode(ScoreState.self, from: $0) } ?? ScoreState()
        clockStart = UserDefaults.standard.object(forKey: "score.clockStart") as? Date
    }
    private func save() { UserDefaults.standard.set(try? JSONEncoder().encode(state), forKey: "score.state") }

    /// Новий матч: 0:0, годинник з нуля. Назви і кольори лишаються з минулого разу.
    func newMatch() { state.homeGoals = 0; state.awayGoals = 0; clockStart = Date() }
    func add(home: Bool, _ d: Int) {
        if home { state.homeGoals = max(0, state.homeGoals + d) } else { state.awayGoals = max(0, state.awayGoals + d) }
        DebugLog.log("score \(state.homeGoals):\(state.awayGoals)")
    }

    /// Раз на секунду і після кожної зміни: перемальовує табло, лише якщо текст змінився.
    func push(to runner: LiveCameraRunner) {
        let clock = clockStart.map { Scoreboard.clock(Date().timeIntervalSince($0)) }
        let key = "\(state)\(clock ?? "")"
        guard key != lastKey else { return }
        lastKey = key; runner.setScoreboard(Scoreboard.render(state, clock: clock))
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
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                side(home: true)
                Text(":").font(.system(size: 28, weight: .heavy, design: .rounded))
                side(home: false)
            }
            HStack {
                Text(score.clockStart.map { Scoreboard.clock(Date().timeIntervalSince($0)) } ?? "—").monospacedDigit()
                Text("утримуй — годинник з нуля").font(.caption2).foregroundStyle(.secondary)
            }.font(.footnote)
            .onLongPressGesture(minimumDuration: 1) { score.clockStart = Date(); DebugLog.log("clock reset") }
        }
        .padding(10).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    func side(home: Bool) -> some View {
        let t = home ? score.state.home : score.state.away, n = home ? score.state.homeGoals : score.state.awayGoals
        return VStack(spacing: 4) {
            HStack(spacing: 6) { Circle().fill(Color(red: t.r, green: t.g, blue: t.b)).frame(width: 12, height: 12); Text(t.name).font(.caption).lineLimit(1) }
            HStack(spacing: 8) {
                Button { score.add(home: home, -1) } label: { Image(systemName: "minus").frame(width: 36, height: 36) }.buttonStyle(.bordered)
                Text("\(n)").font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit().frame(minWidth: 34)
                Button { score.add(home: home, 1) } label: { Image(systemName: "plus").frame(width: 36, height: 36) }.buttonStyle(.borderedProminent)
            }
        }.frame(maxWidth: .infinity)
    }
}
