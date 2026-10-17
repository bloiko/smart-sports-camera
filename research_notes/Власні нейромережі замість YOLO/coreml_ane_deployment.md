# Deploying small own detection networks on iPhone 15 (A16) with Core ML and the Neural Engine, and switching between two models at runtime

Context for the report writer: iPhone 15 has the **A16 Bionic**, the same chip as the **iPhone 14 Pro**. Apple's coremltools benchmark tables that say "iPhone 14 Pro (A16)" therefore apply directly to the iPhone 15. The project's own Mac numbers (not phone numbers): Core ML on the M1 Mac runs players 43–55 ms per pair of 1280×672 tiles and ball 8–14 ms per ROI (`specs/results.md`, `specs/backlog.md`); the phone budget is ≤ 33 ms per frame (`docs/requirements.md`). The app's `ios/FolloCore/Sources/FolloCore/Detector.swift` already takes a model URL and `computeUnits` (default `.all`) and compiles `.mlpackage` at runtime when given one.

## Which layer types and shapes run on the ANE, and which fall back to GPU/CPU

### Takeaway
Plain 2D convolutions (including depthwise, grouped, dilated and transposed), ReLU, max/avg pooling, nearest upsampling ×2, concat, slice and element-wise ops on 4D NCHW tensors with static shapes run on the ANE; top-k/sort, gather/scatter, RNNs, 3D conv, dynamic shapes and data-dependent control flow do not, and each fallback adds an ANE↔CPU/GPU hand-off. There is no official per-op table; the authoritative check is Xcode's Core ML performance report or `MLComputePlan` on the real device.

### Cited Findings
- **No official list; the tools tell you.** Xcode 14+ Core ML performance report shows, per layer, the compute unit used (filled check), supported-but-not-chosen (unfilled check) or unsupported (empty diamond); example model: 54 layers on GPU, 32 on ANE; summary showed median prediction 22.19 ms, load ~400 ms, on-device compile ~940 ms on an iPhone — [WWDC22 "Optimize your Core ML usage"](https://developer.apple.com/videos/play/wwdc2022/10027/)
- WWDC24 update: the report can run on any connected device without code, shows **estimated time per op** and, on hover, **why an op is unsupported** on a device (demo: unsupported data type fixed by switching to Float16); reports can be exported and compared. `MLComputePlan` is the code API for the same information (supported/preferred devices, estimated relative cost per op) — [WWDC24 "Deploy machine learning and AI models on-device with Core ML"](https://developer.apple.com/videos/play/wwdc2024/10161/). (Availability of `MLComputePlan` is iOS 17.4+/macOS 14.4+ per my knowledge of the docs; the session transcript does not state it — verify.)
- There is no runtime API that reports which unit ran the model; ways to infer it: `H11ANEServicesThread` in the debugger, comparing `.all` vs `.cpuAndGPU` vs `.cpuOnly` speed, symbolic breakpoints on `-[_ANEModel program]`, Time Profiler, `powermetrics` on macOS — [hollance/neural-engine: Is my model using the ANE?](https://github.com/hollance/neural-engine/blob/master/docs/is-model-using-ane.md) (community, older; written for the NeuralNetwork model type era)
- Community list of problematic layers (explicitly "incomplete and possibly wrong", varies by ANE version): custom layers (CPU/GPU only), RNN/LSTM/GRU, gather, dilated convolutions, broadcasting ops (e.g. multiply `C×H×W` by `C×1×1`), pooling with kernel > 13 or stride > 2, **upsampling with scale factor > 2**, "Broadcastable" and "ND" layers of the old NeuralNetwork format; deconvolution and upsampling (×2) reported to work. When a model has unsupported layers, Core ML splits execution (ANE→GPU or ANE→CPU) and every switch adds overhead — [hollance/neural-engine: unsupported layers](https://github.com/hollance/neural-engine/blob/master/docs/unsupported-layers.md) (older, pre-ML-Program; mark as historical)
- 2026 reverse-engineering study (unofficial, undocumented interfaces; treat as a lead, not a spec), relevant points:
  - 2D conv is native, **including transposed, dilated, depthwise and grouped**; Winograd chosen automatically for eligible 3×3 stride-1 convs; conv pinned to 4D NCHW; max kernel width 32 (16 in FP16) from A14 on; an indivisible group count is rejected on device; 3D conv fails lowering on every device.
  - Reshape, flatten, squeeze, transpose, concat, split, stack, constant pad, slice are native (descriptor edits or DMA), no cost figures given.
  - Average, max and L2 pooling native; **max-pool native**.
  - **Top-k, sort and dynamic-slice are rejected at code generation**; whole-tensor argmax gated to A15+ on one route.
  - Unsupported on every family M1–M5: reduce_prod, scatter variants, mod, one_hot, non_zero, band_part, shape, sliding_windows, logical and/or/xor, GRU/LSTM/RNN, inverse/hyperbolic trig.
  - Control flow must be static (fixed-trip loops unroll; data-dependent loops not supported); symbolic (dynamic) shapes listed as a pitfall.
  - Texture-engine resize/crop-resize/resample present from A14 on.
  - Shape limits: width/height up to 16384 through A15, 65536 on A16/M5; matrix-multiply working set 2 MB on every family; kernels whose live tiles exceed a ~2 MB on-chip working set stall on off-chip streaming.
  - Datapath FP16 end to end (max 65504); ReLU is an exact max, while sigmoid/tanh/GELU use a 33-knot piecewise-linear table (worst abs. error sigmoid 0.0034, GELU 0.0059).
  - Per-call dispatch overhead on M1 ~190 µs for a tiny graph (~98 % software/firmware), floor ~0.23 ms per dispatch; one command in flight, so concurrent submissions serialise.
  — [ANE characterisation paper, arXiv 2606.22283](https://arxiv.org/html/2606.22283v1)
- Top-k in a Core ML model was routed to the CPU in the compute plan in a Gemma-4 conversion, and the round trip cost tens of ms per token — [Running Gemma4 on Apple Neural Engine (Medium)](https://rockyshikoku.medium.com/running-gemma4-on-apple-neural-engine-79fa0cb39dd2) (single anecdote)
- Apple's ANE guidance (transformers, 2022): the ANE prefers 4D channels-first `(B, C, 1, S)`; **the last axis is not packed and must be contiguous and 64-byte aligned**, so a singleton or small last axis is padded (32× memory at 16-bit for a size-1 last axis), hurting L2 residency; reshapes and transposes can trigger memory copies; replace `nn.Linear` with `nn.Conv2d`; smaller chunks improve L2 residency and multicore use. DistilBERT optimised this way: up to 10× faster, 14× less peak memory; 3.47 ms at 0.454 W on iPhone 13 ANE — [Apple ML Research: Deploying Transformers on the Apple Neural Engine](https://machinelearning.apple.com/research/neural-engine-transformers)
- Apple's own mobile backbone study (MobileOne, measured with Core ML on iPhone 12, 224×224, min latency of 1000 runs): in a 30-layer CNN, ReLU 1.53 ms, GELU 1.63 ms, SE-ReLU 2.10 ms, **SiLU 2.54 ms** (SiLU ≈ 66 % slower than ReLU), dynamic activations 57–273 ms; adding skip connections 1.53→2.62 ms; multi-branch blocks raise memory-access cost, so MobileOne re-parameterises to a single branch at inference. Latencies: MobileNetV2-1.0 0.98 ms, MobileNetV3-L 1.09 ms, EfficientNet-B0 1.72 ms, MobileOne-S0 0.79 ms, S1 0.89 ms, S2 1.18 ms — [MobileOne, arXiv 2206.04040](https://arxiv.org/html/2206.04040v2) (note: the paper's latency column labels are inconsistent for S4 between tables)
- Ultralytics advises `.cpuAndNeuralEngine` rather than `.all` in camera apps because GPU contention causes frame-time jitter; the iOS SDK defaults to `.cpuAndNeuralEngine` on iOS 16+ — [Ultralytics Core ML export docs](https://docs.ultralytics.com/integrations/coreml/)
- `.cpuAndNeuralEngine` (iOS 16+) excludes the GPU, useful when the app's GPU is busy (here: rendering/encoding the broadcast) — [WWDC22 "Optimize your Core ML usage"](https://developer.apple.com/videos/play/wwdc2022/10027/)

### Inferences
- **Design rules for an own ANE-only detector** (synthesis of the above, not an Apple checklist): static input shape; NCHW; only `Conv2d` (3×3/1×1, stride 1–2, depthwise allowed), BatchNorm folded into conv, **ReLU** (avoid SiLU/GELU: slower and approximated on the ANE), max-pool ≤ 3×3, nearest upsample ×2 (chain ×2 steps instead of ×4), concat/add of equal shapes (no broadcasting), sigmoid only at the very end (or leave logits and threshold in logit space). No top-k, gather, NMS, `nonzero`, or dynamic slicing inside the model.
- The current YOLO exports likely already run mostly on the ANE, but YOLO11 uses SiLU, and Ultralytics' optional `nms=True` NMS pipeline stage is not ANE work; a ReLU, single-branch (RepVGG/MobileOne-style) own network should be cheaper per FLOP.
- **Alignment:** with NCHW the last axis is W. By the 64-byte rule, FP16 widths that are multiples of 32 avoid padding. For a 1280-wide input: stride 4 → 320, stride 8 → 160 (both multiples of 32); stride 16 → 80 and stride 32 → 40 get padded (to 96 and 64). Small cost, but it argues against very deep downsampling on the width axis and for keeping input widths multiples of 128. For ball ROIs, 256/384/512/640 px are all fine at strides 4–8. Channel counts: no official rule found; the reverse-engineering paper says each ANE core emits 4 output channels per cycle (M1), so multiples of 8/16 are a safe convention, not a proven requirement.
- **High-resolution outputs are memory-bound:** a stride-4 head on 1280×672 is 320×168; at 64 channels in FP16 that is ~6.9 MB per feature map, above the ~2 MB on-chip working set, so the stride-4 neck/head layers stream through DRAM. Keep the stride-4 part thin (16–32 channels, 1–2 convs) and do the heavy work at stride 8–16 (inference from the paper's working-set figure).
- Verify every exported model with the Xcode performance report on an iPhone (or an A16 device) and require "all ops on Neural Engine" as an export gate; `MLComputePlan` lets a test in the app/`follosim` assert the same.

### Gaps
- No official Apple per-op ANE support matrix exists (Apple documents tools, not a list). The reverse-engineering data is mostly measured on M1/A14–A16 families via private interfaces and may not match the public Core ML compiler's choices.
- No sourced rule on channel multiples (8/16/32) for convs; the "multiple of 8/16" folklore could not be confirmed from a primary source.
- Bilinear upsampling on the ANE: not confirmed either way in found sources (texture-engine resize exists from A14 per the reverse-engineering paper, but whether Core ML's `upsample_bilinear` maps there was not found). Prefer nearest + conv.

## Measured latencies: YOLO family on A16/A17 and heatmap (CenterNet-style) models

### Takeaway
There is **no published, sourced YOLOv8n/YOLO11n Core ML latency for iPhone 15 (A16)**. The best references: YOLO26n 640 detect = 3.2 ms burst / 11.3 ms per frame live on iPhone 17 Pro (A19 Pro), and Apple's **CenterNet (ResNet34) = 6.85 ms on iPhone 14 Pro (A16)**, FP16, compute units "all" (input size not stated). Own measurement on the phone with the Xcode performance report is required.

### Cited Findings
- Ultralytics, iPhone 17 Pro (A19 Pro), iOS 26.5.2, mean of 15 runs after 3 warm-ups, totals incl. pre/post-processing: YOLO26n detect 640: CPU-only 9.2 ms, **CPU+ANE 3.2 ms**; YOLO26n-pose 3.9 ms; YOLO26n-seg 4.8 ms; YOLO26n-depth 5.3 ms. Live camera sweep (older): **11.3 ms/frame** detect, 16.5 ms/frame depth; sustained real-time runs higher than burst latency — [Ultralytics Core ML docs](https://docs.ultralytics.com/integrations/coreml/)
- Apple coremltools palettization benchmarks, **iPhone 14 Pro (A16)**, iOS 17, Xcode 15, compute units "all": **CenterNet (ResNet34) FP16 6.85 ms**; MobileNetV2-1.0 0.48 ms; MobileNetV3-small 0.13 ms; ResNet50 1.52 ms (all 224 for classifiers; CenterNet input size not given on the page) — [coremltools: palettization performance](https://apple.github.io/coremltools/docs-guides/source/opt-palettization-perf.html)
- Apple coremltools quantization benchmarks: ResNet50 FP16 1.52 ms (iPhone 14 Pro) / 1.38 ms (iPhone 15 Pro); MobileNetV2 0.48 / 0.49 ms — [coremltools: quantization performance](https://apple.github.io/coremltools/docs-guides/source/opt-quantization-perf.html)
- A YOLOv8n float16 TFLite model through the Core ML delegate on an A15 device: only 56 % of nodes delegated, 24–25 ms median; INT8 TFLite delegated 0 nodes — [nx_tflite_mob YOLOv8n walkthrough](https://hexdocs.pm/nx_tflite_mob/yolo_walkthrough.md) (different runtime; shows how a partial delegation hurts)
- Anecdotal: "yolov8n at 640 runs in roughly 50–80 ms on a modern iPhone" (no device, iOS version or compute unit given) — [DEV Community post](https://dev.to/toddsullivan/yolov8-coreml-on-ios-shipping-offline-computer-vision-that-actually-works-in-the-field-3e22); conflicts with the Ultralytics 3–11 ms figures on newer hardware and is probably a non-ANE or end-to-end figure. Low confidence.
- Marketing-level claims only (no device/model): quantized YOLO11 on the iPhone ANE "60+ FPS"; a case study 21 FPS (PyTorch) → 85 FPS (Core ML) — [Roboflow: best iOS object detection models](https://blog.roboflow.com/best-ios-object-detection-models/)
- Argmax burst tests: from iPhone 16 Pro to iPhone 17 Pro the GPU improved 2.5–3.1×, the Neural Engine only 1–1.15× — [Argmax iPhone 17 benchmarks](https://www.argmaxinc.com/blog/iphone-17-on-device-inference-benchmarks)
- Example of measured Xcode report output on an iPhone: a model with 54 GPU + 32 ANE layers ran 22.19 ms median — [WWDC22 session 10027](https://developer.apple.com/videos/play/wwdc2022/10027/)
- Project's own data (Mac M1, not phone): Core ML players 43–55 ms per 2 tiles at 1280×672 (YOLO11s), ball 8–14 ms per ROI (YOLO11n); Core ML ~3× faster than Ultralytics on MPS — `specs/results.md` and `specs/backlog.md` in this repository.

### Inferences
- The ANE barely changed between recent generations (Argmax: 1–1.15× from A18 Pro to A19 Pro), so A16 numbers are probably within ~1.5–2× of A19 Pro figures; YOLO26n at 640 on an iPhone 15 ANE would plausibly be ~5–8 ms burst (estimate, unverified; the repo's earlier research gave the same 1.5–2× estimate).
- Scaling the A16 CenterNet-ResNet34 figure by pixel count: if its input was 512×512 (CenterNet's common default; not stated on the page), a 1280×672 input has ~3.3× the pixels → ~20–25 ms for a ResNet34-sized network. A purpose-built small backbone (MobileOne-S0/S1-class, ~1/4 of ResNet34's FLOPs) at 1280×672 should plausibly land around 5–10 ms on the A16 ANE, and a 256–384 px ball ROI network around 1–2 ms plus ~0.2–0.5 ms dispatch overhead per call. These are estimates to confirm on the device.
- The YOLO11s player model's Mac figure (~22–27 ms per 1280×672 tile on M1 Core ML) is probably close to the iPhone 15 figure (M1 and A14/A15 ANEs are similar generations) — two tiles of YOLO11s would already eat the whole 33 ms budget, which is the main performance argument for an own smaller player network.
- Dispatch overhead (~0.2 ms per call) makes many tiny calls expensive; batch the ball ROIs into one call with a fixed batch dimension, or stitch them into one fixed-size input.

### Gaps
- No primary measurement of YOLOv8n/s or YOLO11n/s Core ML latency on A16/A17 found; Ultralytics publishes only YOLO26 numbers on iPhone 17 Pro.
- No measured latency found for a CenterNet-style model at 1280×672 or for stride-4 vs stride-8 heads on the ANE; CenterNet input size on Apple's page is unspecified.
- No public breakdown of the cost of high-resolution outputs on the ANE beyond the 2 MB working-set observation.

## FP16 vs INT8 (weight quantisation, activation quantisation, palettisation) on the ANE

### Takeaway
FP16 is the ANE's native format and the right default. **Weight-only** compression (8-bit linear or 2–8-bit palettisation) shrinks the file 2–8× but gives ~0–10 % speed on A16 for small CNNs (CenterNet 6.85 → 6.37–6.85 ms). **W8A8** (weights + activations INT8) is where speed comes from: 1.6–1.8× on A16 and up to 2.45× on A17 Pro, with ≤0.5 pt accuracy loss when trained with quantisation-aware training.

### Cited Findings
- A16 (iPhone 14 Pro), iOS 17, palettisation, latency ms: CenterNet-ResNet34 FP16 6.85; 2-bit 6.37; 4-bit 6.67; 6-bit 6.71; 8-bit 6.85. ResNet50 1.52 → 1.37–1.43. MobileNetV3-small 0.13 at every bit width. Palettisation's latency benefit mainly appears when weights are decompressed just in time, more often on the ANE from iOS 17/macOS 14 — [coremltools palettization perf](https://apple.github.io/coremltools/docs-guides/source/opt-palettization-perf.html)
- Quantisation, latency ms (FP16 → weight-only PTQ → W8A8 training-time): MobileNetV2 iPhone 14 Pro 0.48 → 0.45 → **0.27**; iPhone 15 Pro 0.49 → 0.44 → **0.20**. ResNet50 iPhone 14 Pro 1.52 → 1.49 → **0.94**; iPhone 15 Pro 1.38 → 1.50 → **0.77**. Accuracy top-1: MobileNetV2 71.86 → 71.78 → 71.66; ResNet50 76.14 → 76.10 → 76.80. Activation quantisation can slow CPU and sometimes GPU inference, so it is recommended mainly for ANE models — [coremltools quantization perf](https://apple.github.io/coremltools/docs-guides/source/opt-quantization-perf.html)
- Overview: palettisation (1–8 bit) works best on the ANE for memory and latency; weight-only INT8/INT4; **W8A8 gives "considerable latency benefits on the Neural Engine" via the int8-int8 compute path on A17 Pro and M4**; 6/8-bit palettisation or 8-bit weight-only usually loses little accuracy; gains depend on model and hardware, test on own device — [coremltools optimization overview](https://apple.github.io/coremltools/docs-guides/source/opt-overview.html)
- Reverse-engineering: on A16/M5 all compressed weight forms (int4 palette, int8 affine, sparse, blockwise) stream at 1.6–1.8× FP16 bandwidth; INT8 roughly doubles lanes; INT8 conv weights ~0.6 % relative error vs ~0.02 % for FP16 — [arXiv 2606.22283](https://arxiv.org/html/2606.22283v1)
- Ultralytics export: `quantize=16` (FP16), `8` (INT8), `"w8a16"` (INT8 weights, FP16 activations); `half`/`int8` flags deprecated — [Ultralytics Core ML docs](https://docs.ultralytics.com/integrations/coreml/)

### Inferences
- Apple's docs say the int8-int8 compute path is an A17 Pro/M4 feature, yet the same docs show W8A8 1.6–1.8× faster on iPhone 14 Pro (A16). A plausible reading: on A16 the gain comes from halved activation memory traffic rather than faster arithmetic. Either way, for memory-bound high-resolution heatmap layers, W8A8 is the lever most likely to help on iPhone 15. This is a contradiction in the sources worth flagging.
- For the ball heatmap (tiny objects, sub-pixel peaks), quantise only after an FP16 baseline passes the checklists; INT8 activations in the final heatmap layers could shift peaks. Keep the last 1–2 layers FP16 (coremltools allows per-op configuration) — inference, test needed.
- Weight compression barely matters for speed at these model sizes (a few MB); its value is app download size.

### Gaps
- No published accuracy numbers for quantised small detectors (mAP or heatmap peak precision) on the ANE; the CenterNet mAP values are named but not listed on Apple's page.
- The A16 int8 path behaviour (real int8 compute vs only bandwidth) is not documented officially.

## Decoding heatmaps on device: inside the model or afterwards

### Takeaway
Do the cheap, dense part inside the model on the ANE (sigmoid + 3×3 max-pool "peak mask", CenterNet style) and the sparse part (thresholding, top-k, sub-pixel offset read-out) in Swift on the CPU. Top-k/sort/nonzero inside Core ML are not ANE ops and force a CPU hand-off.

### Cited Findings
- CenterNet extracts peaks by keeping heatmap values equal to their 3×3 max-pooled value (max-pool as NMS), then takes the top 100 peaks — [Zhou et al., "Objects as Points", arXiv 1904.07850](https://arxiv.org/abs/1904.07850)
- Max-pool is native on the ANE; top-k and sort are rejected at code generation; non_zero unsupported on all families — [arXiv 2606.22283](https://arxiv.org/html/2606.22283v1)
- Top-k placed on CPU by the Core ML compute plan cost tens of ms per call in an LLM conversion — [Medium: Gemma4 on ANE](https://rockyshikoku.medium.com/running-gemma4-on-apple-neural-engine-79fa0cb39dd2)
- Since iOS 16 Core ML supports Float16 MultiArray and `OneComponent16Half` image outputs natively; preallocated **output backings** (`MLPredictionOptions.outputBackings`) with IOSurface-backed buffers avoid per-prediction allocation and copies between compute units — [WWDC22 session 10027](https://developer.apple.com/videos/play/wwdc2022/10027/)
- iOS 18 adds `MLTensor` (NumPy-like ops incl. top-k, asynchronous dispatch, must be materialised to `MLShapedArray` to read) for "glue" computation around models — [WWDC24 session 10161](https://developer.apple.com/videos/play/wwdc2024/10161/)

### Inferences
- Cost estimate: a stride-4 heatmap of 320×168 = 53,760 values (FP16, ~105 KB). A Swift loop or `vDSP` threshold scan over 54 k values is in the tens of microseconds on an A16 CPU; a ball ROI heatmap at 128×128 is ~16 k values. Post-processing on the CPU is therefore negligible compared with inference, provided the output is read directly from an FP16 output backing (no Float32 conversion, no MLMultiArray copies).
- Recommended output layout: model outputs (a) `peak = heatmap * (heatmap == maxpool3x3(heatmap))` or simply the sigmoid heatmap plus the max-pooled map, and (b) small offset/size maps; Swift scans for values above a threshold and reads offsets at those positions. For players, a box head (size map) at stride 4 or 8 is enough; NMS is not needed with peak extraction.
- `MLTensor` top-k is not needed at these sizes and would add a framework dependency on iOS 18+.
- Metal decoding is not worthwhile at this size and would compete with the GPU's video encoding work.

### Gaps
- No measured numbers found for heatmap decode time on iPhone (CPU or Metal); the estimates above are arithmetic, not measurements.
- Whether Core ML keeps an in-model `max_pool` + `equal` + `mul` chain fully on the ANE (the `equal` comparison op) was not confirmed; check in the performance report.

## Thermal and battery: sustained ANE use over 90 minutes vs GPU

### Takeaway
No published, measured 90-minute ANE-vs-GPU thermal or power data for iPhone exists in the found sources. Apple and vendors consistently state the ANE is the more energy-efficient unit; the only measured sustained-load data is for GPU (iPhone 16 Pro LLM throughput dropped ~35 % within minutes). Plan to measure in-app.

### Cited Findings
- Apple DistilBERT on iPhone 13 ANE: 3.47 ms at **0.454 W** — gives a sense of ANE power for a small model — [Apple ML Research](https://machinelearning.apple.com/research/neural-engine-transformers)
- Reverse-engineering on M1: a 3×3 conv at 256 channels ran ~3.8× faster than on the GPU and ~9× more energy-efficient — [arXiv 2606.22283](https://arxiv.org/html/2606.22283v1)
- Sustained GPU inference (LLM, MLX) on iPhone 16 Pro: throughput 36.8 tok/s average in the first two iterations → 25.0 in the warm state → 23.7 in the hot state (~35 % loss); battery −5 % over 20 iterations; iOS does not expose per-component power to third-party apps; the ANE was not used by MLX — [arXiv 2603.23640](https://arxiv.org/html/2603.23640v1)
- Argmax states the ANE "remains the clear choice" for on-device inference for energy efficiency, all-day battery and no contention with other workloads; their 30-minute sustained test is qualitative (video), no numbers — [Argmax](https://www.argmaxinc.com/blog/iphone-17-on-device-inference-benchmarks)
- Ultralytics: sustained real-time camera operation is slower than burst latency (11.3 vs 3.2 ms on iPhone 17 Pro) — [Ultralytics Core ML docs](https://docs.ultralytics.com/integrations/coreml/)
- The project's own requirement: 90 minutes live with a power bank; on overheating reduce fps or bitrate without dropping the stream — `docs/phases.md` in this repository.

### Inferences
- For Follo, the GPU and the media engine are already busy with camera capture, cropping/scaling and H.264/HEVC encoding for YouTube; keeping detection on the ANE (`.cpuAndNeuralEngine`) both avoids frame jitter and keeps the GPU's heat for the stream. The thermal risk over 90 minutes comes more from the camera + encoder + display + charging than from a small ANE detector.
- Measure on the phone: log `ProcessInfo.thermalState` changes, per-frame detection ms (already shown in the icon row) and battery level every minute over a 90-minute test run; MetricKit reports (already in the app) give daily CPU/GPU time but not ANE time.

### Gaps
- No sourced ANE thermal throttling curve or power figure for A16 over long runs.
- No data on whether the ANE itself is throttled under `thermalState == .serious/.critical`; only anecdotal low-quality blogs claim so (not used).

## Runtime switching between two Core ML models (rollback and A/B)

### Takeaway
Bundle both compiled models (`.mlmodelc`, built by Xcode) and load each once as its own `MLModel` with the same `MLModelConfiguration`; switch by a feature flag that picks which instance the detector calls. Loading is fast after the first (cached) specialisation; small detectors cost only a few tens of MB together. On iOS 27+ the new Core AI framework is the forward path, but Core ML remains required for iOS 17–26.

### Cited Findings
- Load mechanics: Xcode compiles `.mlmodel/.mlpackage` into `.mlmodelc`; the first load per model + path + configuration + device runs **device specialisation** (optimisation, segmentation across compute units, per-device compilation) and caches it on disk; later loads are "cached". The cache survives launches and reboots and is invalidated by low disk space, an OS update, or modifying/deleting the compiled model. Best practice: don't load on the UI thread at launch (use async loading or lazy), keep a model loaded while predicting, unload models not needed for a while; Instruments labels loads "prepare and cache" vs "cached" — [WWDC23 "Improve Core ML integration with async prediction"](https://developer.apple.com/videos/play/wwdc2023/10049/)
- Async prediction (iOS 17+) is thread-safe and lets several predictions run concurrently (2× throughput in the demo); for camera streams, cap in-flight predictions and **drop** stale frames rather than queueing; `MLModel.availableComputeDevices` / `MLComputeDevice` lets the app check for a Neural Engine — [WWDC23 session 10049](https://developer.apple.com/videos/play/wwdc2023/10049/)
- iOS 17 and iOS 18 each made many models faster with no recompilation — [WWDC23 10049](https://developer.apple.com/videos/play/wwdc2023/10049/); [WWDC24 10161](https://developer.apple.com/videos/play/wwdc2024/10161/)
- Example load numbers from Xcode performance reports: median load ~400 ms and on-device compile ~940 ms for one model; in Instruments, average load 17 ms vs average prediction 7.2 ms for another (cached) — [WWDC22 session 10027](https://developer.apple.com/videos/play/wwdc2022/10027/)
- A common bug is reloading the model on every access (computed property); fix with a `lazy var` so each model loads once — [WWDC22 session 10027](https://developer.apple.com/videos/play/wwdc2022/10027/)
- Models can be compiled from a source `.mlmodel/.mlpackage` on device with `MLModel.compileModel(at:)` (async variant iOS 16+); the result is in a temporary location and must be moved to a permanent location (e.g. Application Support) and reused — [Apple: Downloading and compiling a model on the user's device](https://developer.apple.com/documentation/coreml/downloading-and-compiling-a-model-on-the-user-s-device) (page body was not retrievable; summary from the API as I know it — verify against the doc)
- Multifunction models (iOS 18+): one model file exposes several named functions sharing weights, selected at load time by function name — [WWDC24 session 10161](https://developer.apple.com/videos/play/wwdc2024/10161/)
- **Core AI (iOS 27+)**: new framework to run AI models across CPU/GPU/ANE with `AIModel` (specialised), `AIModelAsset` (unspecialised source), `AIModelCache`, `SpecializationOptions`, `ComputeUnitKind`, ahead-of-time compilation with `xcrun coreai-build compile`, conversion via Core AI PyTorch Extensions (`.aimodel`), Core AI Instruments template and debugger app. Core ML remains for non-neural model types — [Apple Core AI documentation](https://developer.apple.com/tutorials/data/documentation/coreai.md); WWDC26 session recommends shipping per-architecture AOT-compiled assets and running specialisation in an opt-in first-run flow — [WWDC26 session 326](https://developer.apple.com/videos/play/wwdc2026/326)
- Ultralytics keeps Core ML as the default format; Core AI `.aimodel` targets iOS 27/macOS 27 and their SDKs load it only as an opt-in — [Ultralytics Core ML docs](https://docs.ultralytics.com/integrations/coreml/)
- Pre-WWDC reports (Bloomberg via 9to5Mac) said Core AI would replace Core ML — [9to5Mac](https://9to5mac.com/2026/03/01/apple-replacing-core-ml-with-modernized-core-ai-framework-for-ios-27-at-wwdc/); Apple's docs as found present Core AI alongside Core ML rather than deprecating it.

### Inferences
- **Recommended pattern for Follo (iOS 17–26, Core ML):**
  1. Bundle `players_yolo.mlmodelc`, `ball_yolo.mlmodelc`, `players_own.mlmodelc`, `ball_own.mlmodelc` (Xcode-compiled; no runtime compile needed, so `Detector`'s `compileModel` branch is only for `follosim`/development).
  2. A `DetectorSet` protocol with two implementations (YOLO decode vs heatmap decode); the camera logic (`live_cam` port) sees only boxes/points, so switching does not touch it.
  3. Feature flag stored in `UserDefaults`, chosen in a hidden settings screen (or by build config), read at match start; never switch mid-broadcast except as an automatic rollback (e.g., own model throws or exceeds the time budget for N frames → switch to YOLO and log it).
  4. Load the selected model set at app start asynchronously (or during the position check), and the other set lazily; keep both resident only during A/B runs. With small detectors (a few MB of FP16 weights each; YOLO11s ~19 MB), memory is dominated by activations and the 2 s 4K frame ring, not by weights.
  5. Use the same `MLModelConfiguration` (`computeUnits = .cpuAndNeuralEngine` — the current code defaults to `.all`) for both, so A/B timing is fair.
  6. **On-device A/B logging:** per match, write a compact log (model id + version hash, per-frame detection ms, number of player detections, ball found yes/no, ball confidence, chosen camera x/zoom, thermal state) to the app's container; compare offline with the same scripts as `live_sim.py`. For a true A/B on identical input, record the match video and replay it through the second model with `follosim` on the Mac or in an on-phone replay mode — running both models live on every frame doubles ANE load and distorts the timings being compared.
- Multifunction models are not useful here (the two networks do not share weights).
- Core AI is worth a later migration only if the minimum OS becomes iOS 27; the conversion path (PyTorch → `.aimodel`) is first-party Apple tooling, so it fits the "own code, no third-party runtime" rule.

### Gaps
- Exact memory footprint of loading two small Core ML models on an iPhone 15 (weights + ANE program + buffers) was not found; measure with the Allocations instrument.
- Load time of a cached small model on A16 was not found as a specific number (examples range 17–400 ms on unspecified devices/models).
- Whether iPhone 15 (A16) is supported by iOS 27, and Core AI's ANE behaviour vs Core ML for the same network, were not established from primary sources.
- The Apple doc page on on-device compilation returned only its title; the API description above is from general knowledge and should be checked.
