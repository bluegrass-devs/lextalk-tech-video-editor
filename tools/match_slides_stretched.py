"""Like match_slides.py, for light slides that blow out to white on camera.

usage: match_slides_stretched.py video.gray video_s.gray deck.gray deck_s.gray W H fps [bright=235]

video_s / deck_s are the same samples with a contrast stretch applied (see docs/PLAYBOOK.md).
For samples whose mean brightness is above `bright`, the stretched features are compared;
otherwise the plain ones are. Prints segments plus the top-3 candidate pages for each.
"""
import sys, math

V_p, Vs_p, D_p, Ds_p = sys.argv[1:5]
W, H, fps = int(sys.argv[5]), int(sys.argv[6]), float(sys.argv[7])
BRIGHT = float(sys.argv[8]) if len(sys.argv) > 8 else 235
N = W * H

def raw(p):
    b = open(p, "rb").read()
    return [list(b[i:i + N]) for i in range(0, len(b) - N + 1, N)]

def nz(v):
    m = sum(v) / N; d = [x - m for x in v]; s = math.sqrt(sum(x * x for x in d))
    return [x / s for x in d] if s > 1e-6 else [0.0] * N

V, Vs, D, Ds = raw(V_p), raw(Vs_p), raw(D_p), raw(Ds_p)
Vn = [nz(v) for v in V]; Vsn = [nz(v) for v in Vs]; Dn = [nz(d) for d in D]; Dsn = [nz(d) for d in Ds]
T, K = len(V), len(D)
bright = [sum(v) / N for v in V]
score = []
for t in range(T):
    f, P = (Vsn[t], Dsn) if bright[t] > BRIGHT else (Vn[t], Dn)
    score.append([sum(a * b for a, b in zip(f, p)) for p in P])

STEP, JUMP = 0.35, 0.9   # Viterbi transition costs: next slide, any other slide
best = score[0][:]; back = []
for t in range(1, T):
    m_all = max(range(K), key=lambda k: best[k]); nb = []; bk = []
    for k in range(K):
        c = [(best[k], k)]
        if k > 0: c.append((best[k - 1] - STEP, k - 1))
        c.append((best[m_all] - JUMP, m_all))
        v, s = max(c); nb.append(v + score[t][k]); bk.append(s)
    best = nb; back.append(bk)
k = max(range(K), key=lambda k: best[k]); path = [k]
for t in range(T - 2, -1, -1):
    k = back[t][k]; path.append(k)
path.reverse()
start = 0
for t in range(1, T + 1):
    if t == T or path[t] != path[start]:
        k = path[start]; avg = sum(score[i][k] for i in range(start, t)) / (t - start)
        top = sorted(range(K), key=lambda j: -sum(score[i][j] for i in range(start, t)))[:3]
        print(f"{start/fps:7.1f}-{t/fps:7.1f}  page {k+1:2d}  corr {avg:.2f}  "
              f"bright {sum(bright[start:t])/(t-start):5.1f}  top " + ",".join(str(j + 1) for j in top))
        start = t
