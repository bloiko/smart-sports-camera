import SwiftUI
import Combine
import AVFoundation

/// Пункт 11: екран темніє через 60 с без дотику; будь-який дотик повертає. Стрім і запис тривають.
struct DimOverlay: View {
    @Binding var lastTouch: Date
    @State private var now = Date()
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        let dim = now.timeIntervalSince(lastTouch) > 60          // власник: 10 с — замало, хвилина
        Color.black.opacity(dim ? 0.97 : 0).ignoresSafeArea().allowsHitTesting(dim)
            .accessibilityElement().accessibilityIdentifier(dim ? "dimmed" : "notDimmed")
            .onTapGesture { lastTouch = Date() }
            .onReceive(ticker) { now = $0 }
            .animation(.easeInOut(duration: 0.5), value: dim)
    }
}

/// Any touch on the screen (tap or scroll) counts as activity for `DimOverlay`. A window-level recognizer that never takes
/// touches away from the buttons or the scroll view (a SwiftUI DragGesture on the screen can block scrolling).
struct TouchWatcher: UIViewRepresentable {
    let onTouch: () -> Void
    func makeUIView(context: Context) -> WatcherView { let v = WatcherView(); v.onTouch = onTouch; v.isUserInteractionEnabled = false; return v }
    func updateUIView(_ v: WatcherView, context: Context) { v.onTouch = onTouch }

    final class WatcherView: UIView, UIGestureRecognizerDelegate {
        var onTouch: (() -> Void)?
        private var rec: UILongPressGestureRecognizer?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let r = rec { r.view?.removeGestureRecognizer(r); rec = nil }
            guard let w = window else { return }
            let r = UILongPressGestureRecognizer(target: self, action: #selector(touched)); r.minimumPressDuration = 0
            r.cancelsTouchesInView = false; r.delaysTouchesBegan = false; r.delaysTouchesEnded = false; r.delegate = self
            w.addGestureRecognizer(r); rec = r
        }
        @objc private func touched() { onTouch?() }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// Пункт 10: «погляд глядача» — кадр 1920×1080 після віртуальної камери, те, що бачить YouTube (без його затримки).
final class PixelBufferView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
    func show(_ pb: CVPixelBuffer, at t: CMTime) {
        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(CMSampleBuffer.from(pb, time: t))
    }
}

struct ViewerView: UIViewRepresentable {
    let runner: LiveCameraRunner
    func makeUIView(context: Context) -> PixelBufferView {
        let v = PixelBufferView(); v.displayLayer.videoGravity = .resizeAspect; v.backgroundColor = .black
        runner.onPreview = { [weak v] pb, t in DispatchQueue.main.async { v?.show(pb, at: t) } }
        return v
    }
    func updateUIView(_ v: PixelBufferView, context: Context) {}
    static func dismantleUIView(_ v: PixelBufferView, coordinator: ()) {}
}
