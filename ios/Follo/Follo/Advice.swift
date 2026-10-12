import SwiftUI
import CallKit

/// Пункти 9 і 14: перед першим ефіром — «Не турбувати» (iOS не дає ввімкнути Focus з коду) і Guided Access.
struct BeforeGameSheet: View {
    var onDone: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Перед ефіром").font(.system(size: 26, weight: .heavy, design: .rounded))
            advice("moon.fill", "Увімкни «Не турбувати»", "Дзвінок на весь екран зупиняє камеру. Центр керування → Фокусування → Не турбувати. Якщо дзвінок усе ж прийде, після нього ефір сам підключиться до тієї ж трансляції.")
            advice("lock.rectangle", "Увімкни Guided Access", "Щоб випадковий свайп не закрив застосунок: Параметри → Універсальний доступ → Guided Access → увімкнути; потім у Follo тричі натисни бічну кнопку.")
            advice("battery.100.bolt", "Павербанк і тінь", "90 хвилин 4K + ефір: телефон на павербанку, не на сонці.")
            Spacer()
            Button("Зрозуміло") { onDone() }.font(.system(size: 20, weight: .heavy, design: .rounded)).frame(maxWidth: .infinity).padding(14)
                .background(Color.red).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 14))
        }.padding(20)
    }
    func advice(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(text).font(.footnote).foregroundStyle(.secondary) }
        }
    }
}

/// Пункт 9 (друга частина): фіксуємо дзвінки — після дзвінка камера зупинялась, стрімер перепідключається сам (пункт 1).
final class CallWatcher: NSObject, CXCallObserverDelegate {
    private let observer = CXCallObserver()
    var onCall: ((Bool) -> Void)?
    override init() { super.init(); observer.setDelegate(self, queue: nil) }
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) { onCall?(!call.hasEnded) }
}
