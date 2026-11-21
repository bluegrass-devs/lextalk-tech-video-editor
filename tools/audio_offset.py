"""Find the time offset between two recordings of the same event by audio cross-correlation.

usage: audio_offset.py <ref_file> <ref_time> <other_file> [guess_offset=0] [search=120] [window=60]

Prints OFFSET such that  other_time = ref_time + OFFSET.

A `window`-second stretch of <ref_file> starting at <ref_time> is compared with <other_file>
around ref_time + guess_offset (+- search seconds). Matching uses log-energy envelopes, so it
works across very different microphones (camera, phone, voice memo, mixer feed): first a coarse
pass, then a 5 ms refinement. Pick a ref_time with plenty of speech; avoid long silences.

With no idea of the offset, use a large search (e.g. 3600). Recordings started on different
devices often drift by tens of ppm, so check the offset at the start and end of a talk and
use the midpoint (or re-sync per talk) if it moves by more than ~40 ms.
Pure Python + ffmpeg; no numpy needed.
"""
import sys, math, array, subprocess

def pcm(path, start, dur, rate=8000):
    start = max(0.0, start)
    out = subprocess.run(["ffmpeg", "-v", "error", "-ss", f"{start:.3f}", "-t", f"{dur:.3f}", "-i", path,
                          "-vn", "-ac", "1", "-ar", str(rate), "-f", "s16le", "-"],
                         capture_output=True, check=True).stdout
    a = array.array("h"); a.frombytes(out[: len(out) // 2 * 2]); return a, start

def envelope(a, hop):
    e = []
    for i in range(0, len(a) - hop, hop):
        s = 0
        for x in a[i:i + hop]: s += x * x
        e.append(math.log(s + 1))
    m = sum(e) / max(1, len(e)); return [x - m for x in e]

def best_lag(ref, oth, lags, step=1):
    best = None
    for lag in lags:
        if lag < 0 or lag + len(ref) > len(oth): continue
        s = 0.0; n1 = 0.0; n2 = 0.0
        for i in range(0, len(ref), step):
            a, b = ref[i], oth[i + lag]; s += a * b; n1 += a * a; n2 += b * b
        c = s / math.sqrt(n1 * n2 or 1)
        if best is None or c > best[0]: best = (c, lag)
    return best

ref_f, ref_t, oth_f = sys.argv[1], float(sys.argv[2]), sys.argv[3]
guess = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0
search = float(sys.argv[5]) if len(sys.argv) > 5 else 120.0
win = float(sys.argv[6]) if len(sys.argv) > 6 else 60.0

ref, _ = pcm(ref_f, ref_t, win)
oth, o0 = pcm(oth_f, ref_t + guess - search, win + 2 * search)

# coarse: 10 Hz envelope (4 Hz for very long searches to keep it quick)
crate = 4 if search > 600 else 10
hop = 8000 // crate
r, o = envelope(ref, hop), envelope(oth, hop)
c, lag = best_lag(r, o, range(len(o) - len(r) + 1))
coarse = o0 + lag / crate - ref_t

# fine: 200 Hz envelope within +-1 coarse step
oth2, o2 = pcm(oth_f, ref_t + coarse - 1.5, win + 3.0)
r, o = envelope(ref, 40), envelope(oth2, 40)
centre = int(round((ref_t + coarse - o2) * 200))
c, lag = best_lag(r, o, range(centre - 2 * 200 // crate, centre + 2 * 200 // crate + 1), step=2)
offset = o2 + lag / 200 - ref_t
print(f"OFFSET {offset:.3f}  corr {c:.3f}  (other_time = ref_time + OFFSET)")
if c < 0.4:
    print("warning: weak match; try another ref_time with more speech, or a larger search", file=sys.stderr)
