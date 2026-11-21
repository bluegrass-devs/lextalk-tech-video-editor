#!/bin/zsh
# Build a smoothed projector-screen corner track for bin/layout_tracked.sh.
#
# usage: track_screen.sh <wide.mp4> <start_sec> <dur_sec> <track.tsv> [thr=170] [margin=0.012]
#
# Samples the wide shot at 2 fps (384x216 gray), finds the largest bright blob in each sample
# (tools/corners.py), then keeps only samples where the whole screen is lit and interpolates /
# smooths the rest (tools/smooth_corners.py). Times in the output are wide-file times.
#
# thr: brightness threshold (0-255) for "screen". Raise it if the blob leaks into a bright wall
#   or banner; lower it if the screen is dim. Check the result by rendering a 60-90 s test with
#   layout_tracked.sh at a few points (especially dark slides and camera moves).
set -euo pipefail
WIDE=$1 START=$2 DUR=$3 OUT=$4 THR=${5:-170} MARGIN=${6:-0.012}
TOOLS=${0:A:h:h}/tools
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ffmpeg -v error -ss "$START" -t "$DUR" -i "$WIDE" -vf "fps=2,scale=384:216:flags=area,format=gray" \
  -f rawvideo "$TMP/frames.gray"
python3 -I $TOOLS/corners.py "$TMP/frames.gray" 384 216 "$START" 2 "$THR" > "$TMP/raw.tsv"
python3 -I $TOOLS/smooth_corners.py "$TMP/raw.tsv" "$TMP/track.tsv" "$MARGIN"
{ print -r -- "# screen corner track (t TL TR BL BR) for $WIDE:t, thr=$THR margin=$MARGIN"; cat "$TMP/track.tsv"; } > "$OUT"
print -r -- "wrote $OUT ($(grep -vc '^#' $OUT) rows)"
