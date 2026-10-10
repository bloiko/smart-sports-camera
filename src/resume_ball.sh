#!/bin/bash
# Продовжити ball_window.py з місця зупинки. Використання: VIDEO=game.mp4 PATH_NPZ=out/camera_path.npz ./src/resume_ball.sh
OUT=${OUT:-ball_window.jsonl}
START=0
if [ -s "$OUT" ]; then
  START=$(python3 - <<'P'
import json
ok=[]
for l in open(__import__('os').environ.get('OUT','ball_window.jsonl')).read().splitlines():
    try: ok.append(json.loads(l))
    except: pass
open(__import__('os').environ.get('OUT','ball_window.jsonl'),'w').write(''.join(json.dumps(r)+'\n' for r in ok))
print(ok[-1]['frame']+5 if ok else 0)
P
)
fi
timeout 540 python3 "$(dirname "$0")/ball_window.py" "$VIDEO" "${PATH_NPZ:-out/camera_path.npz}" $OUT 5 $START > ball_window.log 2>&1
tail -1 $OUT | cut -c1-25; wc -l < $OUT; tail -1 ball_window.log
