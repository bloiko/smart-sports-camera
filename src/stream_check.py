"""Compare every frame produced (SENT.flv from `follosim stream`) with everything the server received over all
connections (RECV_*.flv from `ffmpeg -copyts -listen 1 … -c copy`): missing, duplicated, order, timestamps.

Usage: python src/stream_check.py SENT.flv RECV_1.flv [RECV_2.flv …]
"""
import sys

KIND = 9   # 9 video (AVC NALU packets), 8 audio (AAC raw packets); `--audio` checks audio
def video(p):
    b = open(p, 'rb').read(); o = 13; out = []
    while o + 11 <= len(b):
        t = b[o]; n = int.from_bytes(b[o + 1:o + 4], 'big'); ts = int.from_bytes(b[o + 4:o + 7], 'big') | (b[o + 7] << 24)
        body = b[o + 11:o + 11 + n]
        if t == KIND and len(body) > 1 and body[1] == 1: out.append((ts, body))   # media packets only (no headers, no end of sequence)
        o += 15 + n
    return out
if '--audio' in sys.argv: KIND = 8; sys.argv.remove('--audio')

sent = video(sys.argv[1]); index = {body: i for i, (_, body) in enumerate(sent)}
got = []; files = []
for p in sys.argv[2:]:
    v = video(p); idx = [index.get(body, -1) for _, body in v]
    unknown = idx.count(-1); idx = [i for i in idx if i >= 0]
    ts_ok = sum(1 for (ts, body) in v if body in index and sent[index[body]][0] == ts)
    order = all(b > a for a, b in zip(idx, idx[1:]))
    first_key = bool(v) and (KIND == 8 or (v[0][1][0] >> 4) == 1)
    files.append((p.split('/')[-1], len(v), idx[0] if idx else None, idx[-1] if idx else None, unknown, order, ts_ok == len(v), first_key))
    got += idx
missing = sorted(set(range(len(sent))) - set(got)); dup = len(got) - len(set(got))
print(f'{"audio" if KIND == 8 else "video"}: produced {len(sent)} packets; received {len(got)} over {len(files)} connection(s); unique {len(set(got))}; missing {len(missing)}; duplicates {dup}')
for name, n, a, b, unk, order, ts, key in files:
    print(f'  {name}: {n} frames, items {a}..{b}, starts with keyframe {key}, in order {order}, timestamps equal to sent {ts}, unknown {unk}')
if missing:
    runs = []; s = missing[0]; p = s
    for m in missing[1:] + [None]:
        if m != p + 1: runs.append((s, p)); s = m
        p = m if m is not None else p
    print('  missing runs (items):', runs[:10], '…' if len(runs) > 10 else '')
print('ALL FRAMES DELIVERED' if not missing else 'FRAMES LOST')
