"""Compare Swift Core ML detections (follosim detect → swift_det.jsonl) with the Python ones (live_det.jsonl):
players per frame and how many match (IoU ≥ 0.5), ball found rate, agreement of accepted balls.
Usage: python src/compare_det.py DIR [PYTHON_DIR]   (PYTHON_DIR defaults to DIR)"""
import json, sys, numpy as np
d = sys.argv[1]; pd = sys.argv[2] if len(sys.argv) > 2 else d
P = {r['frame']: r for r in map(json.loads, open(f'{pd}/live_det.jsonl'))}
S = {r['frame']: r for r in map(json.loads, open(f'{d}/swift_det.jsonl'))}

def iou(a, b):
    x0, y0, x1, y1 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
    i = max(0, x1 - x0) * max(0, y1 - y0); return i / ((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - i + 1e-9)

np_, ns, matched = 0, 0, 0
for f in sorted(set(P) & set(S)):
    if 'persons' not in P[f] or 'persons' not in S[f]: continue
    a = [b for b in P[f]['persons'] if b[4] >= 0.25]; b_ = [b for b in S[f]['persons'] if b[4] >= 0.25]
    np_ += len(a); ns += len(b_)
    matched += sum(any(iou(x, y) >= 0.5 for y in b_) for x in a)
print(f'players (conf ≥ 0.25): python {np_}, swift {ns}, python boxes matched by swift {matched / max(np_, 1):.1%}')
bp = {f for f, r in P.items() if 'ball' in r}; bs = {f for f, r in S.items() if 'ball' in r}
passes = sum('roi' in r for r in P.values())
both = bp & bs; close = sum(np.hypot(*(np.array(P[f]['ball']) - np.array(S[f]['ball']))) < 20 for f in both)
print(f'ball found: python {len(bp) / passes:.1%} of passes, swift {len(bs) / passes:.1%}; both {len(both)}, within 20 px {close / max(len(both), 1):.1%}')
print(f'blacklisted static balls: python {sum("black" in r for r in P.values())}, swift {sum("black" in r for r in S.values())}')
