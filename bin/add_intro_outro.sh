#!/bin/zsh
# Wraps a talk in the LexTalk intro/outro with short video + audio crossfades.
#
# usage: add_intro_outro.sh <talk.mp4> <intro.mp4> <output.mp4> <talk_end_sec> [fade_sec=1.5] [outro.mp4=intro]
#
# The talk is used from 0 to <talk_end_sec> (set this to where the applause
# starts). The intro crossfades into the talk's start; the talk crossfades into
# the outro starting <fade_sec> before <talk_end_sec>.
set -euo pipefail
TALK=$1 INTRO=$2 OUT=$3 END=$4 FADE=${5:-1.5} OUTRO=${6:-$2}

ID=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$INTRO")
OFF1=$(( ID - FADE ))           # where the intro->talk crossfade starts
OFF2=$(( OFF1 + END - FADE ))   # where the talk->outro crossfade starts (output timeline)

NORM="fps=30000/1001,scale=1920:1080:flags=lanczos,setsar=1,format=yuv420p,settb=AVTB"
ANORM="aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo"
FILTER="
[1:v]${NORM},setpts=PTS-STARTPTS[iv]; [1:a]${ANORM},asetpts=PTS-STARTPTS[ia];
[0:v]trim=0:${END},${NORM},setpts=PTS-STARTPTS[tv]; [0:a]atrim=0:${END},${ANORM},asetpts=PTS-STARTPTS[ta];
[2:v]${NORM},setpts=PTS-STARTPTS[ov]; [2:a]${ANORM},asetpts=PTS-STARTPTS[oa];
[iv][tv]xfade=transition=fade:duration=${FADE}:offset=${OFF1}[v1];
[v1][ov]xfade=transition=fade:duration=${FADE}:offset=${OFF2}[v];
[ia][ta]acrossfade=d=${FADE}:c1=tri:c2=tri[a1];
[a1][oa]acrossfade=d=${FADE}:c1=tri:c2=tri[a]"

ffmpeg -hide_banner -v error -stats -y -i "$TALK" -i "$INTRO" -i "$OUTRO" \
  -filter_complex "$FILTER" -map "[v]" -map "[a]" \
  -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart "$OUT"
