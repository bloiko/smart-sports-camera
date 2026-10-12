"""Compare Swift highlights (follosim highlights → DIR/highlights/live_highlights.json written by Swift as swift_highlights/…)
with Python's (live_highlights.py → DIR/highlights/live_highlights.json): kick-offs, clips, jersey samples.
Usage: python src/compare_highlights.py DIR"""
import json, sys, numpy as np
d = sys.argv[1]
p, s = json.load(open(f'{d}/highlights/live_highlights.json')), json.load(open(f'{d}/swift_highlights/live_highlights.json'))
print('kickoffs python', p['kickoffs'], 'swift', s['kickoffs'])
pj, sj = np.array(p['jerseys']), np.array(s['jerseys'])
print(f'jersey samples python {len(pj)} swift {len(sj)}', end='')
if len(pj) == len(sj): print(f'; max |Δa| {np.abs(pj[:, 2] - sj[:, 2]).max():.1f} max |Δb| {np.abs(pj[:, 3] - sj[:, 3]).max():.1f}')
else: print()
ps, ss = np.array(p['separation']), np.array(s['separation'])
if len(ps) == len(ss): print(f'separation: max |diff| {np.abs(ps[:, 1] - ss[:, 1]).max():.3f}, python max {ps[:, 1].max():.3f} swift max {ss[:, 1].max():.3f}')
print(f'clips python {len(p["clips"])} swift {len(s["clips"])}')
for a, b in zip(p['clips'], s['clips']):
    same = a['start'] == b['start'] and a['end'] == b['end'] and a['kind'] == b['kind'] and a['goal'] == b['goal']
    print(f"  {a['start']:6.1f}-{a['end']:6.1f} {a['kind']:6} {a['goal']:5} | {b['start']:6.1f}-{b['end']:6.1f} {b['kind']:6} {b['goal']:5}  {'same' if same else 'DIFFERENT'}")
