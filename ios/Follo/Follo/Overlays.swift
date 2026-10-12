import SwiftUI
import AVFoundation

/// Пункт 11: екран темніє через 10 с без дотику; будь-який дотик повертає. Стрім і запис тривають.
struct DimOverlay: View {
    @Binding var lastTouch: Date
    @State private var now = Date()
    var body: some View {
        let dim = now.timeIntervalSince(lastTouch) > 10
        Color.black.opacity(dim ? 0.97 : 0).ignoresSafeArea().allowsHitTesting(dim)
            .onTapGesture { lastTouch = Date() }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
            .animation(.easeInOut(duration: 0.5), value: dim)
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
