"""Turn a slide timeline into an ffmpeg concat list of slide images.

usage: timeline_to_concat.py timeline.tsv pages_dir blank.png dur_sec start_sec > slides.txt

timeline.tsv: one line per slide change, "start_seconds<TAB>page" in the source file's own
timeline. page "-" means "no slide": the blank (transparent) frame is used so the footage
underneath shows through. Lines starting with # are comments.

The list is shifted so start_sec becomes 0, and only [start_sec, start_sec + dur_sec) is kept.
Long holds are emitted as <=1 s chunks: one image with a long duration makes ffmpeg's fps filter
wait for the next image while the camera frames pile up in memory.
"""
import sys

tl, pages, blank, dur, start = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), float(sys.argv[5])
rows = []
for line in open(tl):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    s, p = line.split("\t")[:2]
    rows.append((float(s), p.strip()))
rows.sort()
before = [r for r in rows if r[0] <= start]
rows = ([(0.0, before[-1][1])] if before else []) + [(s - start, p) for s, p in rows if start < s < start + dur]
if not rows:
    sys.exit("timeline has no rows covering the requested range")
q = lambda path: "'" + path.replace("'", "'\\''") + "'"
print("ffconcat version 1.0")
img = blank
for i, (s, p) in enumerate(rows):
    e = rows[i + 1][0] if i + 1 < len(rows) else dur
    if e <= s:
        continue
    img = blank if p == "-" else f"{pages}/page_{int(p):03d}.png"
    left = e - s
    while left > 1e-6:
        d = min(1.0, left)
        print(f"file {q(img)}\nduration {d:.3f}")
        left -= d
print(f"file {q(img)}")
