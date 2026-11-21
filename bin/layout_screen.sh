#!/bin/zsh
# Layout with no slide deck: the main panel is the projector screen cut out of a wide shot on
# a tripod and squared up with a perspective warp. For a handheld/moving camera use
# layout_tracked.sh instead.
#
# usage: layout_screen.sh <wide.mp4> <close.mp4|-> <close_offset> <output.mp4> <screen.tsv> \
#          <title> <subtitle> <presenter> <start_sec> <dur_sec> [audio=close|wide]
#
# screen.tsv: "start_seconds<TAB>x0:y0:x1:y1:x2:y2:x3:y3" (TL, TR, BL, BR screen corners in
# the wide frame, wide-file times). Add a row whenever the camera was bumped.
# close-up time = wide time + close_offset.
#
# Remote speaker (shown on the projector as a video call): pass "-" as <close.mp4> and set
# CAM_CROP=w:h:x:y to cut their webcam tile out of the wide shot. Audio is then the wide file's.
set -euo pipefail
source ${0:A:h:h}/lib/common.zsh
WIDE=$1 CLOSE=$2 OFF=$3 OUT=$4 SCR=$5 TITLE=$6 SUBTITLE=$7 PRESENTER=$8 START=$9 DUR=${10} AUD=${11:-close}
text_overlay "$TITLE" "$SUBTITLE" "$PRESENTER"
if [[ $CLOSE == - ]]; then
  SPLIT="[0:v]fps=30000/1001,split=3[s][c][k];"
  CAMSRC="[k]crop=${CAM_CROP:?set CAM_CROP=w:h:x:y},"
else
  SPLIT="[0:v]fps=30000/1001,split=2[s][c];"
  CAMSRC="[1:v]fps=30000/1001,"
fi

# One trim+perspective branch per screen.tsv segment, concatenated back together.
SEGS=$(python3 -I - "$SCR" "$START" "$DUR" <<'PY'
import sys
scr, start, dur = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
rows = []
for line in open(scr):
    line = line.strip()
    if not line or line.startswith("#"): continue
    s, c = line.split("\t")[:2]
    rows.append((float(s), c.strip()))
rows.sort()
before = [r for r in rows if r[0] <= start]
rows = ([(0.0, before[-1][1])] if before else []) + [(s - start, c) for s, c in rows if start < s < start + dur]
n = len(rows)
out = [f"[s]split={n}" + "".join(f"[s{i}]" for i in range(n)) + ";"] if n > 1 else ["[s]null[s0];"]
for i, (s, c) in enumerate(rows):
    e = rows[i + 1][0] if i + 1 < n else dur
    x0, y0, x1, y1, x2, y2, x3, y3 = c.split(":")
    out.append(f"[s{i}]trim=start={s:.3f}:end={e:.3f},setpts=PTS-STARTPTS,"
               f"perspective=x0={x0}:y0={y0}:x1={x1}:y1={y1}:x2={x2}:y2={y2}:x3={x3}:y3={y3}:interpolation=cubic[p{i}];")
out.append("".join(f"[p{i}]" for i in range(n)) + f"concat=n={n}:v=1:a=0[scr]")
print("\n".join(out))
PY
)

compose "$DUR"
FILTER="
${SPLIT}
${SEGS};
[scr]scale=${PANEL_W}:${PANEL_H}:flags=lanczos,unsharp=5:5:0.6,${BORDER}[slide];
${CAMSRC}${SMALL}[cam];
[c]${SMALL}[wide];
${COMPOSE}"

if [[ $CLOSE == - ]]; then
  CLOSEIN=(); AMAP=0:a
else
  CLOSEIN=(-ss $(( START + OFF )) -t "$DUR" -i "$CLOSE")
  [[ $AUD == wide ]] && AMAP=0:a || AMAP=1:a
fi
ffmpeg -hide_banner -v error -stats -y -ss "$START" -t "$DUR" -i "$WIDE" $CLOSEIN \
  -filter_complex "$FILTER" -map "[out]" -map $AMAP $ENCODE -c:a aac -b:a 192k -ar 48000 "$OUT"
