# Turns raw per-sample screen corners (from corners.py) into a smooth corner track.
# usage: smooth_corners.py raw.tsv out.tsv [margin=0.012] [keep=0.93] [win_s=8]
# raw.tsv rows: t area x0 y0 x1 y1 x2 y2 x3 y3 (TL TR BL BR), or "t 0" when nothing was found.
# Dark content (menu bars, docks, dark slides) makes the bright blob smaller than the screen, so a
# sample is trusted only when its area is within `keep` of the largest area seen within +-win_s
# (i.e. the whole screen is lit). Untrusted samples are linearly interpolated from trusted ones,
# then a +-1 s moving average is applied and the quad is grown by `margin`.
# out.tsv rows: t x0 y0 x1 y1 x2 y2 x3 y3, one per second.
import sys
raw, out = sys.argv[1], sys.argv[2]
margin = float(sys.argv[3]) if len(sys.argv) > 3 else 0.012
keep = float(sys.argv[4]) if len(sys.argv) > 4 else 0.93
win = float(sys.argv[5]) if len(sys.argv) > 5 else 8.0
rows = []
for line in open(raw):
    p = line.split()
    rows.append((float(p[0]), int(p[1]), [float(v) for v in p[2:10]] if len(p) >= 10 else None))
ts = [r[0] for r in rows]; dt = ts[1] - ts[0]; w = int(win / dt)
areas = [r[1] for r in rows]
# 1) area near the local max (whole screen lit) and not far below the long-run typical area
W60 = int(60 / dt)
def p90(v):
    v = sorted(x for x in v if x > 0); return v[int(0.9 * (len(v) - 1))] if v else 0
cand = [i for i, r in enumerate(rows)
        if r[2] is not None and r[1] >= keep * max(areas[max(0, i - w):i + w + 1])
        and r[1] >= 0.8 * p90(areas[max(0, i - W60):i + W60 + 1])]
# 2) shape check: corners relative to the centroid, scaled by size, must match the median shape
import math
def shape(c):
    cx = sum(c[0::2]) / 4; cy = sum(c[1::2]) / 4
    s = math.sqrt(abs((c[2] - c[0]) * (c[5] - c[1]))) or 1
    return [(c[k] - (cx if k % 2 == 0 else cy)) / s for k in range(8)]
shapes = {i: shape(rows[i][2]) for i in cand}
med = [sorted(shapes[i][k] for i in cand)[len(cand) // 2] for k in range(8)]
good = [i for i in cand if max(abs(shapes[i][k] - med[k]) for k in range(8)) < 0.06]
sys.stderr.write(f"trusted {len(good)}/{len(rows)} samples\n")
vals = [None] * len(rows)
for i in good: vals[i] = rows[i][2]
gi = 0
for i in range(len(rows)):
    if vals[i] is not None: continue
    while gi + 1 < len(good) and good[gi + 1] < i: gi += 1
    a = good[gi] if good[gi] < i else None
    b = next((g for g in good[gi:] if g > i), None)
    if a is None: vals[i] = rows[b][2]
    elif b is None: vals[i] = rows[a][2]
    else:
        f = (i - a) / (b - a)
        vals[i] = [rows[a][2][k] + (rows[b][2][k] - rows[a][2][k]) * f for k in range(8)]
m = max(1, int(1.0 / dt))
with open(out, 'w') as fo:
    step = max(1, int(round(1.0 / dt)))
    for i in range(0, len(vals), step):
        blk = vals[max(0, i - m):i + m + 1]
        c = [sum(b[k] for b in blk) / len(blk) for k in range(8)]
        cx = sum(c[0::2]) / 4; cy = sum(c[1::2]) / 4
        c = [cx + (c[k] - cx) * (1 + margin) if k % 2 == 0 else cy + (c[k] - cy) * (1 + margin) for k in range(8)]
        fo.write(f"{ts[i]:.2f}\t" + "\t".join(f"{v:.1f}" for v in c) + "\n")
