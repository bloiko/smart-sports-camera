import Foundation
import CoreML
import CoreImage
import CoreVideo

/// YOLO Core ML model with NMS inside (src/export_coreml.py): one tile of the source frame → boxes in source pixels.
/// Letterbox like Ultralytics (scale to fit, grey 114 padding, centred).
public final class Detector {
    public let model: MLModel
    public let inW: Int, inH: Int
    let ctx = CIContext(options: [.cacheIntermediates: false])
    /// Resample like Python: no colour management (pixel values, not linear light) and, when enlarging (the ball ROI 2×),
    /// bicubic a = −0.75 as `cv2.resize(..., INTER_CUBIC)`. With aligned frames the ball model then finds 100% of
    /// Python's balls ≥ 0.4 and 99% of its own are Python's (match 2, `follosim ballroi`); bilinear in linear light: 99% / 95%.
    public var cvLike = true
    let rawCtx = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    var pool: CVPixelBufferPool?
    public var iou = 0.7

    /// `url`: a compiled .mlmodelc (Xcode compiles .mlpackage into the app bundle) or an .mlpackage (compiled here).
    public init(url: URL, computeUnits: MLComputeUnits = .all) throws {
        let cfg = MLModelConfiguration(); cfg.computeUnits = computeUnits
        let u = url.pathExtension == "mlpackage" ? try MLModel.compileModel(at: url) : url
        model = try MLModel(contentsOf: u, configuration: cfg)
        let c = model.modelDescription.inputDescriptionsByName["image"]!.imageConstraint!
        inW = c.pixelsWide; inH = c.pixelsHigh
        let attrs: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: inW, kCVPixelBufferHeightKey as String: inH,
                                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
    }

    public struct Det { public var box: Box; public var cls: Int }

    /// Run on `rect` (source pixels, top-left origin) of `frame`, scaled by `scale` before letterboxing (ball ROI: 2×).
    public func run(_ frame: CIImage, rect: CGRect, scale: Double = 1, conf: Double) -> [Det] {
        autoreleasepool { runInner(frame, rect: rect, scale: scale, conf: conf) }
    }

    func runInner(_ frame: CIImage, rect: CGRect, scale: Double, conf: Double) -> [Det] {
        let H = frame.extent.height
        let tw = rect.width * scale, th = rect.height * scale
        let s = min(Double(inW) / tw, Double(inH) / th); let nw = (tw * s).rounded(), nh = (th * s).rounded()
        let dx = ((Double(inW) - nw) / 2).rounded(.down), dy = ((Double(inH) - nh) / 2).rounded(.down)
        // CoreImage: origin bottom-left. Crop, move to the origin, scale, pad.
        let ciRect = CGRect(x: rect.minX, y: H - rect.maxY, width: rect.width, height: rect.height)
        var img = frame.cropped(to: ciRect).transformed(by: CGAffineTransform(translationX: -ciRect.minX, y: -ciRect.minY))
        if cvLike, scale * s > 1, let f = CIFilter(name: "CIBicubicScaleTransform") {
            f.setValue(img, forKey: kCIInputImageKey); f.setValue(scale * s, forKey: kCIInputScaleKey); f.setValue(1.0, forKey: kCIInputAspectRatioKey)
            f.setValue(0.0, forKey: "inputB"); f.setValue(0.75, forKey: "inputC"); img = f.outputImage ?? img
        } else { img = img.transformed(by: CGAffineTransform(scaleX: scale * s, y: scale * s)) }
        img = img.transformed(by: CGAffineTransform(translationX: dx, y: Double(inH) - nh - dy))
        let bg = CIImage(color: CIColor(red: 114 / 255, green: 114 / 255, blue: 114 / 255)).cropped(to: CGRect(x: 0, y: 0, width: inW, height: inH))
        img = img.composited(over: bg)
        var pb: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, pool!, &pb)
        guard let out = pb else { return [] }
        if cvLike { rawCtx.render(img, to: out, bounds: CGRect(x: 0, y: 0, width: inW, height: inH), colorSpace: nil) }
        else { ctx.render(img, to: out, bounds: CGRect(x: 0, y: 0, width: inW, height: inH), colorSpace: CGColorSpaceCreateDeviceRGB()) }
        let input = try! MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: out), "iouThreshold": MLFeatureValue(double: iou), "confidenceThreshold": MLFeatureValue(double: conf)])
        guard let res = try? model.prediction(from: input), let confs = res.featureValue(for: "confidence")?.multiArrayValue, let coords = res.featureValue(for: "coordinates")?.multiArrayValue else { return [] }
        let n = confs.shape[0].intValue, nc = confs.shape[1].intValue; var dets: [Det] = []
        for i in 0..<n {
            var best = 0, bc = 0.0
            for c in 0..<nc { let v = confs[i * nc + c].doubleValue; if v > bc { bc = v; best = c } }
            let cx = coords[i * 4].doubleValue * Double(inW), cy = coords[i * 4 + 1].doubleValue * Double(inH)
            let w = coords[i * 4 + 2].doubleValue * Double(inW), h = coords[i * 4 + 3].doubleValue * Double(inH)
            // back to source pixels: remove padding, undo scale, add the tile origin
            let k = scale * s
            let x0 = (cx - w / 2 - dx) / k + rect.minX, y0 = (cy - h / 2 - dy) / k + rect.minY
            dets.append(Det(box: Box(x0, y0, x0 + w / k, y0 + h / k, bc), cls: best))
        }
        return dets
    }
}
