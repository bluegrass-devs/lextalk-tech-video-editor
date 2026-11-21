#!/bin/zsh
# Layout with the presenter's real slides, a close-up camera and a wide shot (two separate
# recordings, synced with tools/audio_offset.py).
#
# usage: layout_twocam.sh <wide.mp4> <close.mp4> <close_offset> <output.mp4> <deck_dir> \
#          <title> <subtitle> <presenter> <start_sec> <dur_sec> [audio=close|wide]
#
# All times (start_sec, timeline.tsv) are in the wide file's timeline.
# close_offset: close-up time = wide time + close_offset.
# <deck_dir>: pages/page_NNN.png + timeline.tsv ("start_seconds<TAB>page"). Page "-" shows
# the wide shot cropped to WIDE_SCREEN_CROP (w:h:x:y, default: the whole frame).
set -euo pipefail
source ${0:A:h:h}/lib/common.zsh
WIDE=$1 CLOSE=$2 OFF=$3 OUT=$4 DECK=${5:A} TITLE=$6 SUBTITLE=$7 PRESENTER=$8 START=$9 DUR=${10} AUD=${11:-close}
: ${WIDE_SCREEN_CROP:=iw:ih:0:0}
text_overlay "$TITLE" "$SUBTITLE" "$PRESENTER"
BLANK="$TMP/blank.png"
ffmpeg -v error -f lavfi -i "color=c=black@0.0:s=1920x1080,format=rgba" -frames:v 1 -y "$BLANK"
python3 -I $TOOLS/timeline_to_concat.py "$DECK/timeline.tsv" "$DECK/pages" "$BLANK" "$DUR" "$START" > "$TMP/slides.txt"

compose "$DUR"
FILTER="
[0:v]fps=30000/1001,split=2[a][c];
[a]crop=${WIDE_SCREEN_CROP},scale=${PANEL_W}:${PANEL_H}:flags=lanczos[foot];
[2:v]fps=30000/1001,scale=${PANEL_W}:${PANEL_H}:flags=lanczos,format=rgba[deck];
[foot][deck]overlay=0:0:eof_action=pass,${BORDER}[slide];
[1:v]fps=30000/1001,${SMALL}[cam];
[c]${SMALL}[wide];
${COMPOSE}"

[[ $AUD == wide ]] && AMAP=0:a || AMAP=1:a
ffmpeg -hide_banner -v error -stats -y \
  -ss "$START" -t "$DUR" -i "$WIDE" \
  -ss $(( START + OFF )) -t "$DUR" -i "$CLOSE" \
  -f concat -safe 0 -i "$TMP/slides.txt" \
  -filter_complex "$FILTER" -map "[out]" -map $AMAP $ENCODE -c:a aac -b:a 192k -ar 48000 "$OUT"
