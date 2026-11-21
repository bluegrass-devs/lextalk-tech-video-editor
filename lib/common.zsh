# Shared settings and helpers for the layout scripts. Source it from a script in bin/.
#
# Everything here can be overridden with environment variables:
#   EVENT_TEXT   line under the right-hand panels, e.g. "LexTalk Tech  ·  November 6, 2025"
#   BG, ACCENT   background and border/presenter colours (ffmpeg colour syntax)
#   FONT_BOLD, FONT_REG   TrueType font files (defaults are macOS system Arial)

ROOT=${0:A:h:h}
TOOLS=$ROOT/tools

: ${EVENT_TEXT:="LexTalk Tech"}
: ${BG:=0x0b1d3f}
: ${ACCENT:=0x2fd4c4}
: ${FONT_BOLD:=/System/Library/Fonts/Supplemental/Arial Bold.ttf}
: ${FONT_REG:=/System/Library/Fonts/Supplemental/Arial.ttf}

# The 1920x1080 layout every script produces:
#   main panel  1408x792 at (32,40) with a 3 px ACCENT border
#   small cam    420x236 at (1466,39)   wide shot 420x236 at (1466,299)
#   title / subtitle / presenter under the main panel, EVENT_TEXT under the right column
PANEL_W=1408 PANEL_H=792

# Scratch dir for the script, removed when it exits. (Not in a function: in zsh an EXIT trap
# set inside a function fires when that function returns.)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# text_overlay <title> <subtitle> <presenter>: writes the text files and sets TEXT to the
# drawtext chain (text goes through files so quotes and colons in titles need no escaping).
text_overlay() {
  print -rn -- "$1" > "$TMP/title.txt"
  print -rn -- "$2" > "$TMP/subtitle.txt"
  print -rn -- "$3" > "$TMP/presenter.txt"
  print -rn -- "$EVENT_TEXT" > "$TMP/event.txt"
  TEXT="drawtext=fontfile='${FONT_BOLD}':textfile='$TMP/title.txt':fontsize=46:fontcolor=white:x=32:y=866,
drawtext=fontfile='${FONT_REG}':textfile='$TMP/subtitle.txt':fontsize=30:fontcolor=white@0.8:x=32:y=926,
drawtext=fontfile='${FONT_REG}':textfile='$TMP/presenter.txt':fontsize=34:fontcolor=${ACCENT}:x=32:y=978,
drawtext=fontfile='${FONT_REG}':textfile='$TMP/event.txt':fontsize=24:fontcolor=white@0.75:x=1464:y=560"
}

# compose <dur>: the shared background + panel placement. Expects labels [slide] (1414x798,
# border included), [cam] and [wide] (424x240 each), and emits [out]. Sets COMPOSE.
compose() {
  COMPOSE="color=c=${BG}:s=1920x1080:r=30000/1001${1:+,trim=duration=$1}[bg];
[bg][slide]overlay=29:37:shortest=1[l1];
[l1][cam]overlay=1464:37[l2];
[l2][wide]overlay=1464:297[l3];
[l3]${TEXT}[out]"
}

BORDER="pad=1414:798:3:3:color=${ACCENT}"
SMALL="scale=420:236,pad=424:240:2:2:color=${ACCENT}"
ENCODE=(-c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -movflags +faststart)
