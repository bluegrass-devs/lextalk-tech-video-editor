#!/bin/zsh
# Layout for a single produced recording (one 1920x1080 file, e.g. a livestream program feed)
# where the projector screen is only visible as a small region of the frame. The real slides
# replace that region; the camera and wide shot are cropped out of the same frame.
#
# usage: layout_inset.sh <input.mp4> <output.mp4> <deck_dir> <title> <subtitle> <presenter> [start_sec=0] [dur_sec]
#
# <deck_dir> holds pages/page_NNN.png (1920x1080) and timeline.tsv ("start_seconds<TAB>page",
# page "-" = show the enlarged screen crop instead). timeline.tsv stays in the input's own
# timeline; [start_sec] skips e.g. an MC intro without touching the input.
#
# Crops (w:h:x:y in the input frame; defaults are from the 2026-11-05 recording):
#   SCREEN_CROP  the projector screen      (default 112:63:183:944)
#   CAM_CROP     the presenter camera      (default 1450:820:470:0)
#   WIDE_CROP    the wide stage view       (default 432:243:16:827)
set -euo pipefail
source ${0:A:h:h}/lib/common.zsh
IN=$1 OUT=$2 DECK=${3:A} TITLE=$4 SUBTITLE=$5 PRESENTER=$6 START=${7:-0} DUR=${8:-}
: ${SCREEN_CROP:=112:63:183:944} ${CAM_CROP:=1450:820:470:0} ${WIDE_CROP:=432:243:16:827}
text_overlay "$TITLE" "$SUBTITLE" "$PRESENTER"

FULL=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$IN")
[[ -z $DUR ]] && DUR=$(( FULL - START ))
BLANK="$TMP/blank.png"
ffmpeg -v error -f lavfi -i "color=c=black@0.0:s=1920x1080,format=rgba" -frames:v 1 -y "$BLANK"
python3 -I $TOOLS/timeline_to_concat.py "$DECK/timeline.tsv" "$DECK/pages" "$BLANK" "$DUR" "$START" > "$TMP/slides.txt"

compose "$DUR"
FILTER="
[0:v]fps=30000/1001,split=3[a][b][c];
[a]crop=${SCREEN_CROP},atadenoise=s=31,scale=${PANEL_W}:${PANEL_H}:flags=lanczos,unsharp=7:7:0.9,eq=contrast=1.12[foot];
[1:v]fps=30000/1001,scale=${PANEL_W}:${PANEL_H}:flags=lanczos,format=rgba[deck];
[foot][deck]overlay=0:0:eof_action=pass,${BORDER}[slide];
[b]crop=${CAM_CROP},${SMALL}[cam];
[c]crop=${WIDE_CROP},${SMALL}[wide];
${COMPOSE}"

ffmpeg -hide_banner -v error -stats -y -ss "$START" -t "$DUR" -i "$IN" -f concat -safe 0 -i "$TMP/slides.txt" \
  -filter_complex "$FILTER" -map "[out]" -map 0:a $ENCODE -c:a aac -b:a 192k -ar 48000 "$OUT"
