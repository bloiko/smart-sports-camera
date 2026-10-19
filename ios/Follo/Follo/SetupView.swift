import SwiftUI
import Combine
import FolloCore
import AVFoundation

/// Прев'ю до ефіру: кадр з камери → UIImage (5 fps). AVCaptureVideoPreviewLayer і AVSampleBufferDisplayLayer
/// на цій сесії (ручний 4K-формат, NV12) на iPhone 15 нічого не показували.
struct CameraPreview: View {
    @ObservedObject var cam: CameraSession
    /// «Що бачить застосунок»: поза полем темно, дальні кути з воротами зелені (в кадрі) або червоні (поверни телефон).
    var overlay: PositionOverlay? = nil
    /// Новий вигляд перевірки (2026-10-19): сітка, горизонт, контур поля, мітки кінців поля. nil — старий вигляд.
    var check: PositionCheck? = nil
    var tilt: Double? = nil
    var body: some View {
        ZStack {
            Color.black
            if let img = cam.previewImage {
                Image(uiImage: img).resizable().scaledToFit()
                if let check {
                    PositionCanvas(overlay: overlay, check: check, tilt: tilt, imageSize: img.size)
                } else if let ov = overlay {
                    Canvas { ctx, size in
                        let r = AVMakeRect(aspectRatio: CGSize(width: ov.w, height: ov.h), insideRect: CGRect(origin: .zero, size: size))
                        ctx.withCGContext { ov.draw(in: $0, rect: r) }
                    }.allowsHitTesting(false).accessibilityIdentifier("positionOverlay")
                }
            }
            else { Text("Камера…").foregroundStyle(.secondary) }
        }
    }
}

/// Перерва (власник, 2026-10-17): в ефірі заставка з рахунком, камера, нейромережі й запис вимкнені — телефон
/// охолоджується. Тримає час останнього кадру в ефірі, щоб мітки часу йшли лише вперед (заставка, потім знову камера).
@MainActor final class BreakFeed {
    var active = false
    var lastPTS: CMTime?
    var shift = CMTime.zero, needShift = false
    var timer: Timer?
    var card: CVPixelBuffer?
    var frames = 0
    /// Кадр віртуальної камери → ефір. Після перерви тестове відео продовжує свій годинник з місця паузи: зсунути вперед.
    func adjust(_ t: CMTime) -> CMTime {
        if needShift, let l = lastPTS {
            needShift = false
            let d = CMTimeSubtract(CMTimeAdd(l, CMTime(value: 1, timescale: 30)), CMTimeAdd(t, shift))
            if d > .zero { shift = CMTimeAdd(shift, d); DebugLog.log("break: stream clock shifted by \(String(format: "%.1f", CMTimeGetSeconds(d))) s") }
        }
        let o = CMTimeAdd(t, shift); lastPTS = o; return o
    }
    static func pixelBuffer(_ img: CGImage) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, img.width, img.height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &pb)
        guard let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, []); defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        let c = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        c?.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return pb
    }
}

struct SetupView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject var cam = CameraSession()
    @StateObject var ls = LiveSession()
    @StateObject var score = ScoreModel()                            // рахунок на трансляції
    @State var showTeams = false
    @State var autoWentLive = false                                  // debug --golive: only once per launch
    @State var match: MatchRecord?                                   // поточний матч: своя папка, запис у списку з першої секунди
    @State var live: LiveTarget?
    @State var status = "Все поле в кадрі? Ворота з обох боків?"
    @State var error: String?
    @State var startedAt: Date?
    @State var thermal = ProcessInfo.processInfo.thermalState
    @State var lastTouch = Date()                                   // пункт 11
    @State var viewer = false
    @State var stoppedAt: Date?                                      // GO LIVE не спрацьовує 3 с після СТОП
    @State var holdingStop = false
    @State var muted = false
    @ObservedObject var yt = YouTubeAccount.shared                    // власний вхід Google → ефір «Не для всіх»
    @State var privacy: YouTubeAPI.Privacy = .unlisted               // з чим стартує ефір (debug: приватне або не для всіх)
    @State var livePrivacy: String?                                  // видимість ефіру зараз (з YouTube)
    @State var confirmPublic = false
    @State var viewers: Int?
    @State var breakFeed = BreakFeed()
    @State var bgTask: UIBackgroundTaskIdentifier = .invalid
    /// Тест якості (власник, 2026-10-17): об'єктив 1× і лише частина поля. Пікселів на гравця ~1,7× більше, ніж з 0.5×.
    /// Другі ворота поза кадром, тож лише в цьому режимі перевірка позиції не вимагає обох кутів з воротами.
    @State var halfPitch = UserDefaults.standard.bool(forKey: "mode.halfPitch")
    @State var onBreak = false
    @State var breakMinutes = 15
    @State var secondHalfAt: Date?                                         // скільки людей дивляться зараз (YouTube, раз на 30 с)
    @State var streamTask: Task<Void, Never>?                         // підключення ефіру з повторами (запис від нього не залежить)
    @State var lastDbg = ""
    /// Старий вигляд перевірки позиції (до 2026-10-19), для порівняння: --old-position-ui.
    static let oldPositionUI = CommandLine.arguments.contains("--old-position-ui")
    @StateObject var tilt = TiltMonitor()
    @State var checkTick = 0                                          // щосекунди: перемалювати висновок перевірки
    @State var recordOnly = false                                     // «Тільки запис, без ефіру»
    // таймер один на весь екран: Timer.publish у body перестворювався з кожним кадром прев'ю і не встигав спрацювати
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @Environment(\.scenePhase) var scenePhase                                       // пункт 10
    @State var showAdvice = !UserDefaults.standard.bool(forKey: "advice.shown")   // пункти 9, 14
    @State var result: Bool = false                                 // екран результату після Стоп
    @State var clips: [HighlightsRunner.Clip] = []
    @State var hlProgress: String?

    var body: some View {
        ZStack {
        // На штативі телефон стоїть горизонтально: прев'ю ліворуч, керування справа з прокруткою, GO LIVE / СТОП під ним.
        // Вертикально: усе в одну колонку з прокруткою, GO LIVE / СТОП завжди внизу.
        GeometryReader { g in
            if g.size.width > g.size.height {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 8) { header; previewBlock; Spacer(minLength: 0) }.frame(maxWidth: .infinity)
                    VStack(spacing: 0) {
                        ScrollView { VStack(spacing: 12) { controls }.padding(.vertical, 8) }
                        goStopButton
                    }.frame(width: min(420, g.size.width * 0.45))
                }.padding(.horizontal, 8)
            } else {
                VStack(spacing: 0) {
                    ScrollView { VStack(spacing: 12) { header; previewBlock; controls }.frame(width: max(0, g.size.width - 32)).padding(16) }
                    goStopButton
                }
            }
        }
        if cam.isRecording { DimOverlay(lastTouch: $lastTouch) }
        }
        .background(TouchWatcher { if Date().timeIntervalSince(lastTouch) > 1 { lastTouch = Date() } })    // дотик і прокрутка
        .sheet(isPresented: $showAdvice) { BeforeGameSheet { UserDefaults.standard.set(true, forKey: "advice.shown"); showAdvice = false } }
        .confirmationDialog("Зробити ефір «Для всіх»? Його побачать на каналі, у пошуку і підписники отримають сповіщення.", isPresented: $confirmPublic, titleVisibility: .visible) {
            Button("Так, для всіх") { if let l = live { setPrivacy(l, .public) } }
        }
        .sheet(isPresented: $showTeams) { TeamsSheet(score: score) { showTeams = false } }
        .onChange(of: score.state) { _, _ in if startedAt != nil { score.push(to: ls.runner) } }
        .sheet(isPresented: $result) { ResultView(watchURL: live?.watchURL, clips: clips, progress: hlProgress, match: match) }
        .onAppear {
            DebugLog.reset(); UIDevice.current.isBatteryMonitoringEnabled = true
            if !Self.oldPositionUI {
                status = ""; tilt.start()
                // телефон повернули й він знову нерухомий: перевірити позицію ще раз, без кнопок
                tilt.onSettled = { [cam, ls] in
                    // лише з камерою: тестове відео від руху телефона не змінюється (18.10: перевірка двічі даремно)
                    guard !cam.isRecording, cam.testVideo == nil, ls.runner.env != nil else { return }
                    DebugLog.log("phone moved: checking the position again"); ls.runner.resetPosition()
                }
            }
            // debug: --video NAME з Mac або останній вибір у перемикачі
            if let i = CommandLine.arguments.firstIndex(of: "--video"), i + 1 < CommandLine.arguments.count { UserDefaults.standard.set(CommandLine.arguments[i + 1], forKey: "debug.testVideo") }
            if CommandLine.arguments.contains("--camera") { UserDefaults.standard.removeObject(forKey: "debug.testVideo") }
            if let i = CommandLine.arguments.firstIndex(of: "--streamer"), i + 1 < CommandLine.arguments.count { UserDefaults.standard.set(CommandLine.arguments[i + 1], forKey: "debug.streamer") }
            if let n = UserDefaults.standard.string(forKey: "debug.testVideo") { cam.testVideo = CameraSession.testVideos.first { $0.lastPathComponent == n } }
            if halfPitch { cam.useWide = true }                          // режим «пів поля»: одразу об'єктив 1×
            cam.configure(); UIApplication.shared.isIdleTimerDisabled = true
            ls.calls.onCall = { [ls] active in ls.warning = active ? "Дзвінок: камера на паузі, після дзвінка ефір відновиться сам" : nil }
            // до ефіру: кадри для перевірки позиції (маска поля); під час ефіру: віртуальна камера
            cam.frameHandler = { [ls] sb in
                if ls.runner.isLive { ls.runner.push(sb) }
                else if let pb = CMSampleBufferGetImageBuffer(sb) { ls.runner.addPrerollFrame(pb, time: CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))) }
            }
        }
        .onChange(of: scenePhase) { _, ph in
            // у фоні iOS і так зупиняє камеру; відпускаємо її явно, щоб вона не лишалась зайнятою
            DebugLog.log("scene \(ph == .active ? "active" : ph == .background ? "background" : "inactive")")
            if ph == .background { cam.pause() } else if ph == .active, !onBreak { cam.resume() }      // на перерві камера лишається вимкненою
            // Короткий вихід з застосунку (свайп, сповіщення): попросити в iOS час, щоб з'єднання з YouTube не обірвалось.
            // Без цього iOS призупиняла застосунок за секунду й закривала сокет → перепідключення і 3 с відставання.
            // Вимикач для порівняння до/після: --no-bg-task (debug).
            if ph == .background, startedAt != nil, bgTask == .invalid, !CommandLine.arguments.contains("--no-bg-task") {
                bgTask = UIApplication.shared.beginBackgroundTask(withName: "follo.stream") {
                    DebugLog.log("background time is over: iOS will suspend the app"); UIApplication.shared.endBackgroundTask(bgTask); bgTask = .invalid
                }
                // backgroundTimeRemaining is "infinite" until iOS decides: Int(...) of it crashed the app (UI test, 2026-10-17)
                let left = UIApplication.shared.backgroundTimeRemaining
                DebugLog.log("background: keeping the stream connection (\(left < 10_000 ? "\(Int(left)) s" : "time not set yet") allowed)")
            } else if ph == .active, bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask); bgTask = .invalid; DebugLog.log("foreground again: background time released")
            }
        }
        .onDisappear { cam.pause(); tilt.stop() }
        .onChange(of: cam.sourceFps, initial: true) { _, f in ls.runner.fps = f }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in thermal = ProcessInfo.processInfo.thermalState }
        .onReceive(ticker) { _ in
            // debug: --golive натискає GO LIVE сам, щойно перевірка позиції пройшла (тест з Mac без дотику)
            if startedAt == nil, !cam.isRecording, !autoWentLive, CommandLine.arguments.contains("--golive"), positionOK, error == nil { DebugLog.log("auto GO LIVE"); autoWentLive = true; go() }
            if let s = startedAt, Int(Date().timeIntervalSince(s)) % 10 == 0 {
                DebugLog.log("live \(Int(Date().timeIntervalSince(s))) s: frames in \(ls.runner.inFrames) out \(ls.runner.outFrames) ball \(Int(ls.runner.ballShare * 100))% goals \(ls.runner.goalsKnown) chunks \(cam.chunkCount) stream \(ls.streamer.state) \(ls.streamer.bitrateKbps) kbps thermal \(thermalText) mem \(DebugLog.memMB()) MB battery \(Int(UIDevice.current.batteryLevel * 100))% \(UIDevice.current.batteryState == .unplugged ? "unplugged" : "charging") delay \(Int(ls.streamer.delayS)) s")
                if !ls.streamer.diag.isEmpty { DebugLog.log("  " + ls.streamer.diag) }
            }
            if startedAt != nil { score.push(to: ls.runner) }
            if let s = startedAt, Int(Date().timeIntervalSince(s)) % 30 == 5, let l = live, !l.broadcastId.isEmpty, yt.signedIn {
                let api = yt.api(); Task { if let v = try? await api.viewers(l.broadcastId) { viewers = v } }
            }
            // debug: --stop-after N натискає «Стоп» через N секунд ефіру (перевірка запису з Mac)
            if let s = startedAt, let i = CommandLine.arguments.firstIndex(of: "--stop-after"), i + 1 < CommandLine.arguments.count,
               let n = Double(CommandLine.arguments[i + 1]), Date().timeIntervalSince(s) >= n { DebugLog.log("auto STOP after \(Int(n)) s"); stop() }
            if startedAt != nil { startedAt = startedAt; ls.tick(onFrameRate: { ls.streamer.setFrameRate($0) }, onDetectEvery: { ls.runner.setDetectEvery($0) }, onLowStorage: { cam.stopRecording() }, onEnd: { stop() }) }
            else if error == nil { let st = ls.runner.env == nil ? "preroll \(ls.runner.prerollCount)/7 building \(ls.runner.building)" : (ls.runner.env?.positionProblem ?? "pitch ok"); if st != lastDbg { DebugLog.log(st); lastDbg = st }
                if Self.oldPositionUI { status = ls.runner.env == nil ? "Перевіряю позицію: кадр \(ls.runner.prerollCount)/7\(ls.runner.building ? ", рахую поле…" : "")" : (halfPitch && positionOK ? "Пів поля (1×): видно частину поля, другі ворота поза кадром. Можна в ефір" : ls.runner.env?.positionProblem.map(Self.ukr) ?? "Поле в кадрі. Можна в ефір") }
                else {
                    checkTick &+= 1
                    // debug: нахил раз на 10 с до ефіру — чи правильно лінія горизонту показує напрям (перевірка на телефоні)
                    if checkTick % 10 == 0, let a = tilt.tilt { DebugLog.log(String(format: "tilt %.1f° (horizon %@)%@", a, abs(a) <= PositionCheck.levelDeg ? "level" : "not level", tilt.portrait ? ", phone upright" : "")) }
                } }
        }
    }

    @ViewBuilder var header: some View {
        HStack {
            if !cam.isRecording { Button { dismiss() } label: { Image(systemName: "chevron.left") }.accessibilityIdentifier("back") }
            Spacer(); Text(cam.isRecording ? (recordOnly ? "ЗАПИС" : "LIVE") : "Готово до гри").font(.system(size: 28, weight: .heavy, design: .rounded)).accessibilityIdentifier("title"); Spacer()
        }
    }

    @ViewBuilder var previewBlock: some View {
        if viewer && cam.isRecording {
            ViewerView(runner: ls.runner).frame(maxWidth: .infinity).aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
            Text("Так бачить глядач (без затримки YouTube). Не виходь із застосунку: камера зупиниться — дивись трансляцію на іншому телефоні.").font(.caption2).foregroundStyle(.secondary)
        } else {
            CameraPreview(cam: cam, overlay: cam.isRecording ? nil : ls.runner.positionOverlay,
                          check: cam.isRecording || Self.oldPositionUI ? nil : positionCheck, tilt: tilt.tilt)
            if !cam.isRecording && !Self.oldPositionUI { PositionCard(check: positionCheck) }   // висновок одразу під прев'ю.frame(maxWidth: .infinity).aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
        }
        if cam.isRecording {
            HStack(spacing: 12) {
                Toggle("Погляд глядача", isOn: $viewer).font(.footnote)
                Button { muted.toggle(); ls.streamer.setMuted(muted) } label: {
                    Label(muted ? "Звук вимкнено" : "Звук", systemImage: muted ? "mic.slash.fill" : "mic.fill")
                }.accessibilityIdentifier("mute").font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                    .background(muted ? Color.red.opacity(0.4) : Color.white.opacity(0.08)).clipShape(Capsule())
            }
        }
    }

    @ViewBuilder var controls: some View {
        HStack {
            stat(cam.isRecording ? "\(cam.chunkCount)" : "—", "файлів 4K")
            stat(thermalText, "телефон")
            stat(startedAt.map { fmt(Date().timeIntervalSince($0)) } ?? "—", recordOnly && cam.isRecording ? "запис" : "у ефірі")
            stat(startedAt != nil ? "\(Int(ls.runner.ballShare * 100))%" : "—", "м'яч")
        }
        if cam.isRecording { ScoreBar(score: score); breakRow }
        else {
            Button { showTeams = true } label: {
                HStack { Text("Команди"); Spacer(); Text("\(score.state.home.name) – \(score.state.away.name)").foregroundStyle(.secondary).lineLimit(1) }
            }.font(.footnote).padding(10).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
        }
        if !cam.isRecording, yt.auth != nil { youTubeRow }
        if let l = live, cam.isRecording {
            HStack { Text(l.watchURL).font(.footnote).lineLimit(1).accessibilityIdentifier("watchURL"); Spacer()
                Button("Копіювати") { UIPasteboard.general.string = l.watchURL }
                if let u = URL(string: l.watchURL), u.host?.contains("youtu") == true { ShareLink(item: u) { Image(systemName: "square.and.arrow.up") } } }
                .padding(10).background(.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
            if !l.broadcastId.isEmpty { livePrivacyRow(l) }
        }
        if cam.isRecording || Self.oldPositionUI {
            Text(error ?? cam.cameraError ?? status).accessibilityIdentifier("status").font(.footnote).foregroundStyle(cam.cameraError == nil ? Color.secondary : Color.yellow).multilineTextAlignment(.center)
        } else {
            if let n = error ?? cam.cameraError ?? (status.isEmpty ? nil : status) {
                Text(n).accessibilityIdentifier("statusNote").font(.footnote).foregroundStyle(error != nil || cam.cameraError != nil ? Color.yellow : Color.secondary).multilineTextAlignment(.center)
            }
        }
        if !cam.isRecording, !CameraSession.testVideos.isEmpty {      // лише debug: тестове відео замість камери
            Picker("Джерело", selection: Binding(get: { cam.testVideo }, set: { cam.setSource($0); ls.runner.resetPosition() })) {
                Text("Камера").tag(URL?.none)
                ForEach(CameraSession.testVideos, id: \.self) { Text("Відео \($0.deletingPathExtension().lastPathComponent)").tag(URL?.some($0)) }
            }.pickerStyle(.segmented)
        }
        #if DEBUG
        if !cam.isRecording {                                             // debug: which stream path (rollback switch, stage 1f)
            Picker("Стрім", selection: Binding(get: { Streamer.engine.rawValue }, set: { UserDefaults.standard.set($0, forKey: "debug.streamer") })) {
                Text("Стрім: HaishinKit").tag("haishinkit"); Text("Стрім: Follo").tag("follo")
            }.pickerStyle(.segmented)
        }
        #endif
        #if DEBUG
        if cam.isRecording { Text("reconnects \(ls.streamer.reconnects)").font(.caption2).foregroundStyle(.tertiary).accessibilityIdentifier("reconnects") }
        #endif
        if cam.isRecording, let m = ls.streamer.limitedKbps {            // слабкий інтернет: бітрейт підлаштований
            Text(String(format: "Слабкий інтернет (≈%.1f Мбіт/с): ефір %.1f Мбіт/с, без відставання", Double(m) / 1000, Double(ls.streamer.bitrateKbps) / 1000))
                .font(.caption).foregroundStyle(.yellow).accessibilityIdentifier("slowLink")
        }
        if cam.isRecording, ls.streamer.delayS > 5 {                      // own engine after a network drop
            HStack { Text("Ефір відстає на \(Int(ls.streamer.delayS)) с").font(.footnote); Spacer(); Button("Наздогнати ефір") { ls.streamer.catchUp() }.font(.footnote) }
                .padding(8).background(Color.yellow.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 8))
        }
        if !cam.formatInfo.isEmpty { Text(cam.formatInfo).font(.caption2).foregroundStyle(.secondary) }
        if let l = cam.lowLight { Text(l).font(.caption2).foregroundStyle(Color.yellow).multilineTextAlignment(.center) }
        if !cam.isRecording {
            // звичайна кнопка: ні сегментний Picker, ні Toggle тут не перемикались (UI-тест 9, 2026-10-18)
            Button { halfPitch.toggle() } label: {
                Label(halfPitch ? "Пів поля (1×, тест): УВІМКНЕНО" : "Пів поля (1×, тест): вимкнено", systemImage: halfPitch ? "checkmark.square" : "square")
            }.font(.footnote).accessibilityIdentifier("halfPitch").accessibilityValue(halfPitch ? "1" : "0")
                .onChange(of: halfPitch) { _, v in
                    UserDefaults.standard.set(v, forKey: "mode.halfPitch")
                    if cam.testVideo == nil { cam.switchCamera(wide: v) }; ls.runner.resetPosition(); DebugLog.log("mode: \(v ? "half pitch, 1×" : "whole pitch, 0.5×")")
                }
        }
        if !cam.isRecording, !halfPitch, (ls.runner.env?.positionProblem ?? "").contains("too small") || cam.useWide {
            Button(cam.useWide ? "Назад до 0.5× (ультраширока)" : "Поле замале → спробувати камеру 1×") {
                cam.switchCamera(wide: !cam.useWide); ls.runner.resetPosition()
            }.font(.footnote)
        }
        if let w = ls.warning { Text(w).font(.footnote).foregroundStyle(.yellow) }
        if !cam.isRecording, yt.signedIn, let s = ls.saved, !s.broadcastId.isEmpty, Date().timeIntervalSince(s.startedAt) < 3 * 3600 {
            Text("GO LIVE продовжить ефір \(s.watchURL) (те саме посилання)").font(.footnote).foregroundStyle(.secondary)
        } else if !cam.isRecording, let s = ls.saved, Date().timeIntervalSince(s.startedAt) < 3 * 3600 {
            Button("Відновити ефір \(s.watchURL.suffix(11))…") { live = LiveTarget(broadcastId: s.broadcastId, rtmpsURL: s.rtmpsURL, streamKey: s.streamKey, watchURL: s.watchURL); go(resume: true) }
                .font(.footnote).disabled(!positionOK)
        }
    }

    var goStopButton: some View {
        // СТОП — окремий вигляд без дії на дотик: у Button з утриманням відпускання пальця після стопу натискало GO LIVE
        Group {
            if cam.isRecording {
                Text(holdingStop ? "■  Тримай…" : "■  СТОП (утримуй)").frame(maxWidth: .infinity).padding(16)
                    .background(holdingStop ? Color.red.opacity(0.7) : Color.gray.opacity(0.4))
                    .onLongPressGesture(minimumDuration: 1, perform: { holdingStop = false; stop() }, onPressingChanged: { holdingStop = $0 })
                    .accessibilityIdentifier("stop").accessibilityAddTraits(.isButton)
            } else {
                if !Self.oldPositionUI, ls.runner.env != nil, !positionOK {
                    // позиція не та: ефіру не буде (правило власника), але матч не має пропасти — лише запис 4K
                    Button("Тільки запис, без ефіру") { if stoppedAt.map({ Date().timeIntervalSince($0) > 3 }) ?? true { go(recordOnly: true) } }
                        .accessibilityIdentifier("recordOnly").font(.system(size: 18, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity).padding(16).background(Color.white.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.35)))
                } else {
                // сіра, поки позиція не перевірена (вимкнена кнопка з червоним тлом виглядала активною)
                Button(positionOK ? "●  GO LIVE" : "Перевіряю поле…") { if stoppedAt.map({ Date().timeIntervalSince($0) > 3 }) ?? true { go() } }
                    .disabled(!positionOK).accessibilityIdentifier("goLive")
                    .frame(maxWidth: .infinity).padding(16).background(positionOK ? Color.red : Color.gray.opacity(0.35))
                }
            }
        }
            .font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16).padding(.vertical, 8)
    }

    /// Правило власника: ефір ніколи не стартує, поки не знайдене поле і обидва дальні кути з воротами не в кадрі
    /// (перевірка позиції). Стоїть у самому go(), тож її не обходить ні GO LIVE, ні «Відновити ефір», ні --golive.
    var positionOK: Bool {
        guard let e = ls.runner.env else { return false }
        guard let p = e.positionProblem else { return true }
        return halfPitch && p.contains("goal")                       // пів поля: лише «ворота біля краю» не заважає
    }
    /// Висновок перевірки позиції для нового вигляду (checkTick перемальовує його щосекунди).
    var positionCheck: PositionCheck { _ = checkTick; return PositionCheck.make(runner: ls.runner, halfPitch: halfPitch, tilt: tilt, lowLight: cam.lowLight) }
    /// Тест: тестове відео замість камери або запуск з Mac. Правило власника: у тестах звук ефіру завжди вимкнений.
    var isTest: Bool { cam.testVideo != nil || CommandLine.arguments.contains("--autostart") }

    func go(resume resumeAsked: Bool = false, recordOnly only: Bool = false) {
        recordOnly = only
        if only { DebugLog.log("RECORD ONLY (no stream): \(ls.runner.env?.positionProblem ?? "no pitch yet")") }
        guard positionOK || only else { DebugLog.log("GO LIVE refused: position not checked (\(ls.runner.env?.positionProblem ?? "no pitch yet"))"); return }
        if isTest && !muted { muted = true; ls.streamer.setMuted(true) }
        error = nil
        let problems = ls.preflight()
        if !problems.isEmpty && !resumeAsked { status = problems.joined(separator: " · ") }
        // матч, що лишився після перезапуску застосунку (Стоп не натискали): та сама папка, годинник і ефір (те саме посилання)
        let saved = ls.saved.flatMap { Date().timeIntervalSince($0.startedAt) < 3 * 3600 ? $0 : nil }
        let resume = !only && (resumeAsked || (yt.signedIn && saved?.broadcastId.isEmpty == false))
        // старий ефір після збою (автостоп вимкнено, сам YouTube його не закриє): закрити, щоб не висів «в ефірі»
        if !only, yt.signedIn, let old = ls.saved, !old.broadcastId.isEmpty, saved == nil {
            let api = yt.api(); Task { try? await api.complete(old.broadcastId); DebugLog.log("YouTube: closed stale broadcast \(old.broadcastId)") }
        }

        // 1. Запис 4K і віртуальна камера — одразу: ні інтернет, ні YouTube, ні вхід Google їх не зупиняють
        if !resume { score.newMatch() }
        // debug: --clock H:MM:SS ставить тайм і час після старту (перевірка табло з Mac)
        if let i = CommandLine.arguments.firstIndex(of: "--clock"), i + 1 < CommandLine.arguments.count {
            let p = CommandLine.arguments[i + 1].split(separator: ":").compactMap { Int($0) }
            if p.count == 3 { score.half = p[0]; score.setClock(Double(p[1] * 60 + p[2])) }
        }
        score.push(to: ls.runner)
        let start = resume ? saved?.startedAt ?? Date() : Date()
        let folder = MatchStore.folderName(for: start)
        var m = MatchStore.load().first(where: { $0.folder == folder })
            ?? MatchRecord(date: start, watchURL: nil, durationS: 0, chunkFiles: [], clipFiles: [], goals: 0, knownPitch: false, folder: folder)
        m.recording = true; MatchStore.upsert(m); match = m
        cam.startRecording(dir: MatchStore.chunksDir(m)); startedAt = start
        DebugLog.log("recording into matches/\(folder)\(resume ? " (continuing)" : ""), mode \(halfPitch ? "half pitch 1×" : "whole pitch 0.5×"), lens \(cam.useWide ? "1×" : "0.5×")")
        // віртуальна камера: кроп 1920×1080 із затримкою 2 с → стрімер (і «погляд глядача», пункт 10)
        ls.runner.onOutput = only ? nil : { [ls, breakFeed] pb, t in Task { @MainActor in guard !breakFeed.active else { return }; ls.streamer.push(pb, at: breakFeed.adjust(t)) } }
        // лише запис без знайденого поля: віртуальна камера не потрібна (їй потрібна маска поля)
        if !only || ls.runner.env?.fm != nil {
            do { try ls.runner.start() } catch { self.error = "Камера: \(error.localizedDescription) (моделі players/ball.mlmodelc у проєкті?)" }
        }
        if only { live = nil; status = "Лише запис 4K, без ефіру: позиція не та"; return }

        // 2. Ефір — окремо, з повторами, поки не вийде або поки не натиснуть СТОП (посилання попереднього матчу не показуємо)
        live = nil
        streamTask = Task { await connectStream(saved: resume ? saved : nil, start: start) }
    }

    /// Підключає ефір, поки триває матч: YouTube не відповів — ще раз через 10 с; вхід Google скінчився — запис іде далі.
    func connectStream(saved: LiveSession.Saved?, start: Date) async {
        var attempt = 0
        while startedAt != nil, !Task.isCancelled {
            attempt += 1
            do {
                guard let l = try await streamTarget(resumeBroadcastId: saved?.broadcastId), startedAt != nil else {
                    if startedAt != nil { status = "Без YouTube: лише запис (увійди в YouTube)" }; return
                }
                live = l
                if var m = match { m.watchURL = l.watchURL; MatchStore.upsert(m); match = m }
                ls.save(.init(broadcastId: l.broadcastId, rtmpsURL: l.rtmpsURL, streamKey: l.streamKey, watchURL: l.watchURL, startedAt: start))
                await ls.streamer.start(url: l.rtmpsURL, key: l.streamKey)
                if attempt > 1 { status = "Ефір підключено"; DebugLog.log("stream connected on attempt \(attempt)") }
                return
            } catch GoogleAuth.AuthError.signedOut {
                status = "Запис іде. Вхід у YouTube скінчився: ефіру немає. Після матчу увійди знову"
                DebugLog.log("YouTube: signed out during GO LIVE — recording only"); return
            } catch {
                status = "Запис іде. YouTube не відповідає, пробую ще раз через 10 с (\(attempt))"
                DebugLog.log("YouTube: attempt \(attempt) failed: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    /// Куди стрімити: ефір YouTube через API (вхід Google), або debug-шляхи (свій RTMP-сервер, ключ зі Studio), або нікуди.
    func streamTarget(resumeBroadcastId: String?) async throws -> LiveTarget? {
        if yt.signedIn {
            let (b, st) = try await yt.api().prepare(streamId: yt.streamId, resumeBroadcastId: resumeBroadcastId, title: broadcastTitle, privacy: privacy)
            yt.streamId = st.id; livePrivacy = b.privacy
            DebugLog.log("YouTube: broadcast \(b.id) \(b.privacy) (asked \(privacy.rawValue))\(b.id == resumeBroadcastId ? " (same as before the restart)" : ""), engine \(Streamer.engine.rawValue)")
            return LiveTarget(broadcastId: b.id, rtmpsURL: st.ingestURL, streamKey: st.key, watchURL: b.watchURL)
        }
        if let t = YouTubeLive.debugTarget() {                                          // debug: свій RTMP-сервер (ffmpeg на Mac)
            DebugLog.log("stream target: \(t.url) (debug), engine \(Streamer.engine.rawValue)")
            return LiveTarget(broadcastId: "", rtmpsURL: t.url, streamKey: t.key, watchURL: t.url)
        }
        if let k = YouTubeLive.debugStreamKey() {                                        // debug: ключ з YouTube Studio
            DebugLog.log("YouTube: Studio stream key")
            return LiveTarget(broadcastId: "", rtmpsURL: YouTubeLive.studioIngest, streamKey: k, watchURL: "https://studio.youtube.com")
        }
        return nil
    }

    // ---------------------------------------------------------------- перерва

    func startBreak() {
        guard !onBreak, startedAt != nil else { return }
        onBreak = true; breakFeed.active = true; breakFeed.frames = 0
        if score.pausedAt == nil { score.togglePause() }
        secondHalfAt = Date().addingTimeInterval(Double(breakMinutes) * 60)
        cam.pauseRecording(); cam.pause()                     // без кадрів нейромережі віртуальної камери простоюють
        makeCard()
        breakFeed.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in Task { @MainActor in pushCard() } }
        DebugLog.log("break started: camera, recording and detection off; card in the stream, second half at \(secondHalfText)")
    }

    func endBreak() {
        guard onBreak else { return }
        breakFeed.timer?.invalidate(); breakFeed.timer = nil
        breakFeed.active = false; breakFeed.needShift = true; onBreak = false
        score.setHalf(2); if score.pausedAt != nil { score.togglePause() }
        cam.resume(); if let m = match { cam.resumeRecording(dir: MatchStore.chunksDir(m)) }
        DebugLog.log("break ended after \(breakFeed.frames) card frames: second half")
    }

    var secondHalfText: String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: secondHalfAt ?? Date()) }

    func makeCard() {
        if let img = Scoreboard.breakCard(score.state, line: "Другий тайм о \(secondHalfText)") { breakFeed.card = BreakFeed.pixelBuffer(img) }
    }

    /// 10 кадрів заставки на секунду; час кожного — на 0,1 с після попереднього кадру в ефірі.
    func pushCard() {
        guard onBreak, let pb = breakFeed.card else { return }
        let t = CMTimeAdd(breakFeed.lastPTS ?? CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600), CMTime(value: 1, timescale: 10))
        breakFeed.lastPTS = t; ls.streamer.push(pb, at: t); breakFeed.frames += 1
        if breakFeed.frames % 50 == 0 { makeCard() }                  // рахунок могли виправити під час перерви
        if breakFeed.frames % 600 == 0 { DebugLog.log("break: \(breakFeed.frames) card frames in the stream") }
    }

    var breakRow: some View {
        Group {
            if onBreak {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ПЕРЕРВА: глядачі бачать заставку з рахунком").font(.footnote.weight(.semibold)).accessibilityIdentifier("breakOn")
                    Text("Камера, запис і нейромережі вимкнені — телефон охолоджується. Другий тайм о \(secondHalfText).").font(.caption2).foregroundStyle(.secondary)
                    Stepper("Перерва \(breakMinutes) хв", value: $breakMinutes, in: 5...30, step: 5)
                        .onChange(of: breakMinutes) { _, m in secondHalfAt = Date().addingTimeInterval(Double(m) * 60); makeCard() }.font(.footnote)
                    Button { endBreak() } label: { Label("Другий тайм", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(.green).accessibilityIdentifier("breakEnd")
                }.padding(10).background(Color.yellow.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Button { startBreak() } label: { Label("Перерва (заставка в ефірі)", systemImage: "cup.and.saucer.fill") }
                    .font(.footnote).accessibilityIdentifier("breakStart")
            }
        }
    }

    /// «Динамо – Шахтар, 17.10» з назв команд табло; без назв — «Матч 17.10 11:00».
    var broadcastTitle: String {
        let h = score.state.home.name.trimmingCharacters(in: .whitespaces), a = score.state.away.name.trimmingCharacters(in: .whitespaces)
        let f = DateFormatter(); f.dateFormat = "dd.MM"
        if (h == "Home" && a == "Away") || h.isEmpty || a.isEmpty { f.dateFormat = "dd.MM HH:mm"; return "Матч \(f.string(from: Date()))" }
        return "\(h) – \(a), \(f.string(from: Date()))"
    }

    func stop() {
        let startedAtSaved = startedAt ?? Date()
        streamTask?.cancel(); streamTask = nil
        if onBreak { breakFeed.timer?.invalidate(); breakFeed.timer = nil; breakFeed.active = false; onBreak = false }
        stoppedAt = Date(); DebugLog.log("STOP")
        cam.stopRecording(); startedAt = nil; ls.streamer.stop(); ls.save(nil)
        let camOut = ls.runner.stop(); let env = ls.runner.env; let target = live
        result = true; clips = []; hlProgress = "Готую хайлайти…"
        // хайлайти з записаних файлів у фоні (≈ 1–2 хв): кікоф → гол, кліпи 16:9 і 9:16
        DispatchQueue.global(qos: .userInitiated).async {
            let rec = match ?? MatchRecord(date: startedAtSaved, durationS: 0, chunkFiles: [], clipFiles: [], goals: 0, knownPitch: false, folder: MatchStore.folderName(for: startedAtSaved))
            Thread.sleep(forTimeInterval: 1)                          // останній файл дописується після stopRecording
            let chunks = MatchStore.chunks(rec)
            var out: [HighlightsRunner.Clip] = []
            if let (c, j) = camOut, let e = env { out = (try? HighlightsRunner.make(chunks: chunks, cam: c, jerseys: j, env: e, outDir: MatchStore.highlightsDir(rec), progress: { p in DispatchQueue.main.async { hlProgress = p } })) ?? [] }
            DispatchQueue.main.async {
                clips = out; hlProgress = nil
                var m = rec
                m.watchURL = target?.watchURL ?? m.watchURL; m.durationS = Date().timeIntervalSince(startedAtSaved)
                m.chunkFiles = chunks.map { $0.lastPathComponent }; m.clipFiles = out.map { $0.file.lastPathComponent }
                m.goals = out.filter { $0.kind == "goal" }.count; m.knownPitch = ls.runner.knownPitch; m.recording = false
                MatchStore.upsert(m); match = m
            }
        }
        if let l = target, !l.broadcastId.isEmpty, yt.signedIn {
            Task { do { try await yt.api().complete(l.broadcastId); DebugLog.log("YouTube: broadcast \(l.broadcastId) ended") } catch { DebugLog.log("YouTube: end failed: \(error.localizedDescription)") } }
        }
        livePrivacy = nil; viewers = nil
        status = "Записано \(cam.chunkCount) файлів 4K — у «Моїх матчах»: переглянути і зберегти у Фото"
    }

    /// До ефіру: вхід у YouTube і з якою видимістю стартувати. «Для всіх» тут немає ніколи: лише під час ефіру, в релізі.
    var youTubeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "play.rectangle.fill").foregroundStyle(.red)
                if yt.signedIn { Text("YouTube: \(yt.channel ?? "вхід виконано")").lineLimit(1); Spacer(); Button("Вийти") { yt.signOut() }.foregroundStyle(.secondary) }
                else { Button(yt.busy ? "Вхід…" : "Увійти в YouTube (Google)") { Task { await yt.signIn() } }.disabled(yt.busy).accessibilityIdentifier("signIn"); Spacer() }
            }
            if yt.signedIn {
                #if DEBUG
                Picker("Видимість", selection: $privacy) { Text("Приватне").tag(YouTubeAPI.Privacy.private); Text("Не для всіх").tag(YouTubeAPI.Privacy.unlisted) }
                    .pickerStyle(.segmented).accessibilityIdentifier("privacyPicker")
                #else
                Text("Ефір стартує «Не для всіх»: бачать лише ті, кому ти дав посилання").font(.caption2).foregroundStyle(.secondary)
                #endif
            }
            if let e = yt.error { Text(e).font(.caption2).foregroundStyle(.yellow) }
        }.font(.footnote).padding(10).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Під час ефіру: видимість і перемикач. Тестова збірка: приватне ⇄ не для всіх. Реліз: «Для всіх» з підтвердженням.
    func livePrivacyRow(_ l: LiveTarget) -> some View {
        let p = livePrivacy ?? ""
        let name = ["private": "Приватне", "unlisted": "Не для всіх", "public": "Для всіх"][p] ?? "…"
        return HStack {
            Image(systemName: p == "public" ? "globe" : p == "unlisted" ? "link" : "lock.fill")
            Text(name).accessibilityIdentifier("privacy")
            if let v = viewers { Label("\(v)", systemImage: "eye").foregroundStyle(.secondary).accessibilityIdentifier("viewers") }
            Spacer()
            #if DEBUG
            Button(p == "private" ? "Зробити «Не для всіх»" : "Зробити приватним") { setPrivacy(l, p == "private" ? .unlisted : .private) }
            #else
            if p == "public" { Button("Зробити «Не для всіх»") { setPrivacy(l, .unlisted) } }
            else { Button("Зробити «Для всіх»…") { confirmPublic = true } }
            #endif
        }.font(.footnote).padding(10).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func setPrivacy(_ l: LiveTarget, _ p: YouTubeAPI.Privacy) {
        Task {
            do { livePrivacy = try await yt.api().setPrivacy(l.broadcastId, p).privacy; DebugLog.log("YouTube: privacy \(livePrivacy ?? "")") }
            catch { self.error = error.localizedDescription }
        }
    }

    /// Підказки перевірки позиції (FolloCore пише англійською) — для людини на полі.
    static func ukr(_ p: String) -> String {
        if p.hasPrefix("No pitch") { return "Поле не знайдене: наведи камеру на поле" }
        if p.contains("too small") { return "Поле замале в кадрі: постав ближче або спробуй іншу камеру" }
        if p.contains("left goal") { return "Лівий кут з воротами біля краю (червона точка): поверни телефон трохи вліво" }
        if p.contains("right goal") { return "Правий кут з воротами біля краю (червона точка): поверни телефон трохи вправо" }
        return p
    }

    var thermalText: String { ["ok", "ok", "гаряче", "критично"][min(thermal.rawValue, 3)] }
    func fmt(_ s: TimeInterval) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
    func stat(_ v: String, _ l: String) -> some View {
        VStack { Text(v).font(.system(size: 20, weight: .heavy, design: .rounded)); Text(l).font(.caption2).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity).padding(8).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
