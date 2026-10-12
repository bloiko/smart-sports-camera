import SwiftUI
import AVFoundation

/// Екрани 1–3: вхід Google (поки що заглушка до підключення SDK), 3 картки онбордингу, дозволи.
struct OnboardingView: View {
    var onDone: () -> Void
    @State var page = 0
    let cards: [(String, String, String)] = [
        ("iphone.landscape", "Телефон горизонтально, ширококутна камера", "Став на штатив, перила чи паркан на висоті 2–3 м біля центральної лінії за бровкою. Обидва ворота мають бути в кадрі — застосунок сам перевірить."),
        ("record.circle", "Одна кнопка", "Натисни Go live — Follo сам знайде поле, ворота і м'яч, стежитиме за грою і стрімитиме 1080p на YouTube. Широкий 4K-запис лишається на телефоні."),
        ("lock.rectangle", "Щоб ефір не перервався", "Увімкни «Не турбувати» і Guided Access (тричі бічна кнопка), підключи павербанк на 90 хвилин, не виходь із застосунку — камера зупиниться."),
    ]
    var body: some View {
        VStack(spacing: 20) {
            if page < 0 {
                Spacer()
                Text("Follo").font(.system(size: 44, weight: .heavy, design: .rounded)); Text("Follo the match.").foregroundStyle(.secondary)
                Spacer()
                Text("Вхід через Google потрібен лише для YouTube Live (Google Sign-In SDK: див. docs/youtube-live.md)").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Увійти через Google") { page = 0 }.buttonStyle(.borderedProminent)
                Button("Поки без YouTube (лише запис)") { page = 0 }.font(.footnote)
            } else {
                TabView(selection: $page) {
                    ForEach(cards.indices, id: \.self) { i in
                        VStack(spacing: 16) {
                            Image(systemName: cards[i].0).font(.system(size: 64)).foregroundStyle(.red)
                            Text(cards[i].1).font(.system(size: 24, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
                            Text(cards[i].2).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.padding(24).tag(i)
                    }
                }.tabViewStyle(.page)
                Button(page < cards.count - 1 ? "Далі" : "Дозволи камери й мікрофона") {
                    if page < cards.count - 1 { withAnimation { page += 1 } } else { requestPermissions() }
                }
                .font(.system(size: 20, weight: .heavy, design: .rounded)).frame(maxWidth: .infinity).padding(14)
                .background(Color.red).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 24)
        .onAppear { page = -1 }
    }

    /// Екран 3: дозволи. Камера і мікрофон — обов'язкові; після відповіді йдемо далі в будь-якому разі (на екрані гри буде підказка).
    func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { _ in
            AVCaptureDevice.requestAccess(for: .audio) { _ in DispatchQueue.main.async { UserDefaults.standard.set(true, forKey: "onboarding.done"); onDone() } }
        }
    }
}
