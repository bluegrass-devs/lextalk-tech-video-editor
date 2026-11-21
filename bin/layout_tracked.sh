#!/bin/zsh
# Layout for a handheld or drifting wide shot: the main panel is the projector screen, squared
# up with a per-frame perspective warp that follows a smoothed corner track (bin/track_screen.sh).
# The panel is rendered in ~60 s chunks in parallel, then composited.
#
# usage: layout_tracked.sh <wide.mp4> <close.mp4> <close_offset> <output.mp4> <track.tsv> \
#          <title> <subtitle> <presenter> <start_sec> <dur_sec> [audio=close|wide]
#
# track.tsv: "t x0 y0 x1 y1 x2 y2 x3 y3" (TL TR BL BR in 1920x1080 coords, wide-file times).
# close-up time = wide time + close_offset.
# CAM_RANGES="a-b,c-d": wide-file time ranges where the main panel shows the close-up camera
#   instead (e.g. Q&A after the projector is switched off).
# JOBS: parallel chunk renders (default 4).
set -euo pipefail
source ${0:A:h:h}/lib/common.zsh
WIDE=${1:A} CLOSE=${2:A} OFF=$3 OUT=$4 TRACK=${5:A} TITLE=$6 SUBTITLE=$7 PRESENTER=$8 START=$9 DUR=${10} AUD=${11:-close}
JOBS=${JOBS:-4}
text_overlay "$TITLE" "$SUBTITLE" "$PRESENTER"

# 1. Per-chunk filter scripts: piecewise-linear corner expressions in the chunk's frame number.
python3 -I - "$TRACK" "$START" "$DUR" "$TMP" <<'PY'
import sys
track, start, dur, tmp = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
rows = [list(map(float, l.split())) for l in open(track) if l.strip() and not l.startswith('#')]
FR = 30000 / 1001; CH = 1798                      # frames per chunk (~60 s)
nframes = int(dur * FR + 0.5)
def val(t, k):
    if t <= rows[0][0]: return rows[0][k + 1]
    if t >= rows[-1][0]: return rows[-1][k + 1]
    lo, hi = 0, len(rows) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if rows[mid][0] <= t: lo = mid
        else: hi = mid
    a, b = rows[lo], rows[hi]; f = (t - a[0]) / (b[0] - a[0])
    return a[k + 1] + (b[k + 1] - a[k + 1]) * f
jobs = []
names = ["x0", "y0", "x1", "y1", "x2", "y2", "x3", "y3"]
for c, f0 in enumerate(range(0, nframes, CH)):
    n = min(CH, nframes - f0)
    t0 = start + f0 / FR
    knots = list(range(0, n, 30)) + [n]           # a knot every 30 frames (~1 s)
    parts = []
    for k in range(8):
        v = [val(t0 + q / FR, k) for q in knots]
        terms = [f"gte(in,{a})*lt(in,{b})*({v[i]:.2f}+{(v[i+1]-v[i])/(b-a):.5f}*(in-{a}))"
                 for i, (a, b) in enumerate(zip(knots, knots[1:]))]
        terms.append(f"gte(in,{knots[-1]})*{v[-1]:.2f}")
        parts.append(f"{names[k]}='" + "+".join(terms) + "'")
    flt = ("fps=30000/1001,perspective=" + ":".join(parts) +
           ":interpolation=cubic:eval=frame,scale=1408:792:flags=lanczos,unsharp=5:5:0.5,setsar=1")
    open(f"{tmp}/c{c:03d}.vf", "w").write(flt)
    jobs.append(f"{c:03d} {t0:.6f} {n}")
open(f"{tmp}/jobs.txt", "w").write("\n".join(jobs) + "\n")
with open(f"{tmp}/panel.txt", "w") as f:
    for j in jobs: f.write(f"file '{tmp}/c{j.split()[0]}.mp4'\n")
PY

# 2. Render the chunks, JOBS at a time.
print -r -- "rendering $(wc -l < $TMP/jobs.txt | tr -d ' ') panel chunks, $JOBS at a time"
while read -r c t0 n; do
  while (( $(jobs -r | wc -l) >= JOBS )); do sleep 1; done
  ffmpeg -hide_banner -v error -y -ss "$t0" -i "$WIDE" -/vf "$TMP/c$c.vf" -frames:v "$n" -an \
    -c:v libx264 -preset fast -crf 14 -pix_fmt yuv420p "$TMP/c$c.mp4" &
done < "$TMP/jobs.txt"
wait
ffmpeg -hide_banner -v error -y -f concat -safe 0 -i "$TMP/panel.txt" -c copy "$TMP/panel.mp4"

# 3. Composite. CAM_RANGES (wide-file times) -> enable expression in output time.
CAMEN=$(python3 -I -c '
import sys
start = float(sys.argv[1]); r = sys.argv[2].strip()
terms = []
for part in filter(None, r.split(",")):
    a, b = (float(x) - start for x in part.split("-"))
    terms.append(f"between(t,{a:.3f},{b:.3f})")
print("+".join(terms) or "0")' "$START" "${CAM_RANGES:-}")

compose "$DUR"
FILTER="
[0:v]fps=30000/1001,${SMALL}[wide];
[1:v]fps=30000/1001,split=2[k1][k2];
[k1]${SMALL}[cam];
[k2]scale=${PANEL_W}:${PANEL_H}:flags=lanczos[bigcam];
[2:v]setpts=PTS-STARTPTS[pan];
[pan][bigcam]overlay=0:0:enable='${CAMEN}',${BORDER}[slide];
${COMPOSE}"

[[ $AUD == wide ]] && AMAP=0:a || AMAP=1:a
ffmpeg -hide_banner -v error -stats -y \
  -ss "$START" -t "$DUR" -i "$WIDE" \
  -ss $(( START + OFF )) -t "$DUR" -i "$CLOSE" \
  -i "$TMP/panel.mp4" \
  -filter_complex "$FILTER" -map "[out]" -map $AMAP $ENCODE -c:a aac -b:a 192k -ar 48000 "$OUT"
