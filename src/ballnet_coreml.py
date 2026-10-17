"""FolloNet-B on the phone's budget: export to Core ML (FP16) and time it next to today's YOLO ball model on the Mac's
Neural Engine. The iPhone 15 (A16) already runs today's ball model; if ours is cheaper on the same Neural Engine, the
phone can carry it.

Usage (export venv: torch 2.7 + coremltools 9): .venv-export/bin/python src/ballnet_coreml.py NAME [--size 320]
→ work/ballnet/NAME/BallNet.mlpackage, MAC counts and timings printed.
"""
import os, sys, time
import numpy as np, torch, coremltools as ct
sys.path.insert(0, os.path.dirname(__file__))
from ballnet import BallNet, channels, opt

name, S = sys.argv[1], int(opt('--size', 320))
ck = torch.load(f'work/ballnet/{name}/best.pt', map_location='cpu')
cin = channels(ck['inputs'])
model = BallNet(cin); model.load_state_dict(ck['model']); model.eval()

# multiply-accumulates at the live ROI size
macs = 0
def hook(m, i, o):
    global macs
    if isinstance(m, torch.nn.Conv2d):
        macs += o.numel() * (m.in_channels // m.groups) * m.kernel_size[0] * m.kernel_size[1]
hs = [m.register_forward_hook(hook) for m in model.modules()]
with torch.no_grad(): model(torch.zeros(1, cin, S, S))
for h in hs: h.remove()
print(f'{name}: {cin} input channels, {sum(p.numel() for p in model.parameters()) / 1e6:.2f} M params, '
      f'{macs / 1e9:.2f} GMAC at {S}x{S} ({2 * macs / 1e9:.2f} GFLOPs)')

class Wrap(torch.nn.Module):                        # heatmap as probability; peaks are decoded in Swift (CPU)
    def __init__(self, m): super().__init__(); self.m = m
    def forward(self, x):
        h, o = self.m(x); return torch.sigmoid(h), o
traced = torch.jit.trace(Wrap(model), torch.zeros(1, cin, S, S))
ml = ct.convert(traced, inputs=[ct.TensorType(name='x', shape=(1, cin, S, S))], outputs=[ct.TensorType(name='heat'), ct.TensorType(name='offset')],
                compute_precision=ct.precision.FLOAT16, minimum_deployment_target=ct.target.iOS17, convert_to='mlprogram')
path = f'work/ballnet/{name}/BallNet.mlpackage'
ml.save(path); print('saved', path)

def bench(m, feed, n=200):
    for _ in range(10): m.predict(feed)
    t = time.perf_counter()
    for _ in range(n): m.predict(feed)
    return (time.perf_counter() - t) / n * 1000

for units in (ct.ComputeUnit.CPU_AND_NE, ct.ComputeUnit.CPU_ONLY):
    ours = ct.models.MLModel(path, compute_units=units)
    ms = bench(ours, {'x': np.random.rand(1, cin, S, S).astype(np.float32)})
    print(f'ours {units.name}: {ms:.2f} ms per ROI')
yolo_path = 'models/coreml/ball.mlpackage'
if os.path.exists(yolo_path):
    y = ct.models.MLModel(yolo_path, compute_units=ct.ComputeUnit.CPU_AND_NE)
    spec_in = y.get_spec().description.input[0]
    from PIL import Image
    w = spec_in.type.imageType.width or 640; hgt = spec_in.type.imageType.height or 640
    feed = {spec_in.name: Image.fromarray((np.random.rand(hgt, w, 3) * 255).astype(np.uint8))}
    extra = {i.name: 0.25 for i in y.get_spec().description.input[1:]}
    print(f'yolo ball CPU_AND_NE ({w}x{hgt}): {bench(y, {**feed, **extra}):.2f} ms per ROI')
