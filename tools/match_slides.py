"""Match small grayscale video samples of a projected slide to deck pages.

usage: match_slides.py video.gray deck.gray W H fps out.tsv
Each sample/page is W*H bytes. Scores are Pearson correlation; a Viterbi pass
picks the most likely slide sequence (staying put is free, advancing one slide
is cheap, jumping elsewhere costs more), which suppresses one-off mismatches.
"""
import sys, math

vid_path, deck_path, W, H, fps, out_path = sys.argv[1:7]
W, H, fps = int(W), int(H), float(fps)
N = W * H

def load(p):
    b = open(p, "rb").read()
    frames = []
    for i in range(0, len(b) - N + 1, N):
        v = list(b[i:i + N])
        m = sum(v) / N
        d = [x - m for x in v]
        s = math.sqrt(sum(x * x for x in d)) or 1.0
        frames.append([x / s for x in d])
    return frames

video, deck = load(vid_path), load(deck_path)
T, K = len(video), len(deck)
score = [[sum(a * b for a, b in zip(f, p)) for p in deck] for f in video]

STEP, JUMP = 0.35, 0.9   # transition costs: next slide, any other slide
best = score[0][:]
back = []
for t in range(1, T):
    m_all = max(range(K), key=lambda k: best[k])
    nb, bk = [], []
    for k in range(K):
        cands = [(best[k], k)]
        if k > 0:
            cands.append((best[k - 1] - STEP, k - 1))
        cands.append((best[m_all] - JUMP, m_all))
        v, src = max(cands)
        nb.append(v + score[t][k]); bk.append(src)
    best = nb; back.append(bk)
k = max(range(K), key=lambda k: best[k])
path = [k]
for t in range(T - 2, -1, -1):
    k = back[t][k]; path.append(k)
path.reverse()

# collapse into segments
segs, start = [], 0
for t in range(1, T + 1):
    if t == T or path[t] != path[start]:
        k = path[start]
        avg = sum(score[i][k] for i in range(start, t)) / (t - start)
        raw_best = sum(1 for i in range(start, t) if max(range(K), key=lambda j: score[i][j]) == k) / (t - start)
        segs.append((start / fps, t / fps, k + 1, avg, raw_best))
        start = t
with open(out_path, "w") as f:
    f.write("start\tend\tpage\tavg_corr\tframes_agreeing\n")
    for s, e, p, a, r in segs:
        f.write(f"{s:.1f}\t{e:.1f}\t{p}\t{a:.3f}\t{r:.2f}\n")
for s, e, p, a, r in segs:
    print(f"{int(s//60):2d}:{s%60:04.1f}-{int(e//60):2d}:{e%60:04.1f}  page {p:2d}  corr {a:.2f}  agree {r:.0%}")
