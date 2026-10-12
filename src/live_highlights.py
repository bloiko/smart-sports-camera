"""Highlights from a live recording, as the phone will do after Stop (port: ios/FolloCore Highlights*.swift).

Inputs: the live camera path (live_sim.py → OUT/live_B{B}.npz with GON, GI, BX, BY, GOALS, S_FRAMES, ZN, ZONE_BASE),
the detections (OUT/live_det.jsonl: persons) and the video. Jersey colours are sampled on every 2nd player frame
(f % 8 == 0): the phone does this during the live from the frame in memory, here they are read from the video.
Steps: moments (highlights.py) → kickoffs by team separation (kickoff.py) → goals → clips 16:9 and 9:16 with the
close-up camera (closeup.py) rendered from the original video.
Usage: python src/live_highlights.py OUT_DIR VIDEO [--buffer 2] [--checklist C.json] [--no-render] [--clips DIR]
  → OUT_DIR/highlights/live_highlights.json (+ clips in OUT_DIR/highlights/ and OUT_DIR/highlights/vertical/)
"""
import json, os, sys, numpy as np, cv2
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from highlights import moments, mark_goals, arg, tsec, MIN_SCORE
from kickoff import jersey_colours, separation, find_kickoffs
from closeup import close_path, content_bounds, render

JERSEY_EVERY = 8   # every 2nd player frame; 20 missed the match 3 kickoff (0.75), 4 misses both (0.76-0.77): the 0.77 threshold has no margin


def main():
    out, video = sys.argv[1], sys.argv[2]; B = float(arg('--buffer', '2'))
    p = dict(np.load(os.path.join(out, f'live_B{B:g}.npz')))
    det = [json.loads(l) for l in open(os.path.join(out, 'live_det.jsonl'))]
    rows = [r for r in det if 'persons' in r and r['frame'] % JERSEY_EVERY == 0]
    fmd = cv2.imread(os.path.join(out, 'fmd.png'), 0) > 127
    F = jersey_colours(video, rows, fmd.astype(np.uint8))
    T, S = separation(F, (p['GOALS'][0][0] + p['GOALS'][1][0]) / 2, float(p['FPS']))
    kicks = find_kickoffs(T, S)
    print('separation median', round(float(np.median(S)), 2), 'max', round(float(S.max()), 2), 'at', round(float(T[np.argmax(S)]), 1), 's; kickoffs', kicks)
    ms = moments(p); mark_goals(ms, kicks); ms = [m for m in ms if m['score'] >= MIN_SCORE]
    hd = arg('--clips', os.path.join(out, 'highlights')); os.makedirs(os.path.join(hd, 'vertical'), exist_ok=True)
    med = cv2.imread(os.path.join(out, 'med.png')); Hs, Ws = med.shape[:2]; top, bot = content_bounds(med)
    paths = {False: close_path(p, Ws, Hs, top, bot), True: close_path(p, Ws, Hs, top, bot, vertical=True)}
    for k, m in enumerate(ms, 1):
        name = f"clip_{k:02d}_{int(m['peak'] // 60)}m{int(m['peak'] % 60):02d}s.mp4"; m['file'] = name
        t = m['peak']; label = f"{int(t // 60)}:{int(t % 60):02d}  " + (f"GOAL  {m['goal']} goal" if m['kind'] == 'goal' else f"chance  {m['goal']} goal")
        if '--no-render' not in sys.argv:
            render(video, paths[False], os.path.join(hd, name), m['start'], m['end'], (1920, 1080), label)
            render(video, paths[True], os.path.join(hd, 'vertical', name), m['start'], m['end'], (1080, 1920), label)
        print(f"{m['start']:6.1f}-{m['end']:6.1f}s  {m['goal']:5} {m['kind']:6} danger {m['score']:.2f}  {name}")
    report = dict(kickoffs=kicks, separation=[[round(float(t), 2), round(float(s), 3)] for t, s in zip(T, S)], clips=ms,
                  jerseys=[[int(f), round(float(x), 1), round(float(a), 1), round(float(b), 1)] for f, x, a, b in F])
    if arg('--checklist'):
        ev = json.load(open(arg('--checklist')))['events']; miss = 0
        for e in ev:
            hit = [m['file'] for m in ms if m['start'] <= tsec(e['time']) <= m['end']]
            miss += not hit; print(f"checklist {e['time']} {e['goal']} {e['type']}: {'in ' + hit[0] if hit else 'MISSING'}")
        report['checklist_missing'] = miss
    json.dump(report, open(os.path.join(hd, 'live_highlights.json'), 'w'), indent=1)
    print(f'{len(ms)} clips, {sum(m["end"] - m["start"] for m in ms):.0f} s')


if __name__ == '__main__':
    main()
