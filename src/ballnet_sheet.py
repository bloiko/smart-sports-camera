"""Contact sheet of FolloNet-B samples (look at the labels before training, project rule).

Each tile is frame t of a sample. Green circle: ball from the track; yellow: interpolated ball; red cross: decoy of a
negative (YOLO false positive, spare ball, player's feet). Caption: kind, frame, split.
Usage: python src/ballnet_sheet.py OUT.jpg DIR [DIR ...] [--kind pos|fp|player|spare] [--interp] [--n 48] [--seed 1]
"""
import cv2, glob, numpy as np, random, sys

out = sys.argv[1]
dirs = [a for a in sys.argv[2:] if not a.startswith('--') and not a.isdigit()]
opt = lambda k, d: sys.argv[sys.argv.index(k) + 1] if k in sys.argv else d
kind, n, seed = opt('--kind', None), int(opt('--n', 48)), int(opt('--seed', 1))
files = [f for d in dirs for f in glob.glob(f'{d}/*.npz') if kind is None or f.endswith(f'_{kind}.npz')]
random.Random(seed).shuffle(files)
tiles = []
for f in files:
    z = np.load(f)
    if '--interp' in sys.argv and not int(z['interp']): continue
    img = cv2.imdecode(z['f2'], cv2.IMREAD_COLOR)
    b, d = z['ball'], z['decoy']
    if b[0] >= 0:
        cv2.circle(img, (int(b[0]), int(b[1])), 12, (0, 255, 255) if int(z['interp']) else (0, 255, 0), 2)
    if str(z['kind']) != 'pos':
        x, y = int(d[0]), int(d[1]); cv2.line(img, (x - 9, y - 9), (x + 9, y + 9), (0, 0, 255), 2); cv2.line(img, (x - 9, y + 9), (x + 9, y - 9), (0, 0, 255), 2)
    cv2.putText(img, f"{z['kind']} {int(z['frame'])} {z['split']}", (4, 16), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
    tiles.append(img)
    if len(tiles) == n: break
cols = 8
rows = [np.hstack(tiles[i:i + cols] + [np.zeros_like(tiles[0])] * (cols - len(tiles[i:i + cols]))) for i in range(0, len(tiles), cols)]
cv2.imwrite(out, cv2.resize(np.vstack(rows), None, fx=0.75, fy=0.75, interpolation=cv2.INTER_AREA), [cv2.IMWRITE_JPEG_QUALITY, 85])
print(out, len(tiles), 'tiles of', len(files))
