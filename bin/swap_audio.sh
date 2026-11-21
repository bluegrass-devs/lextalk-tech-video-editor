#!/bin/zsh
# Replace a rendered video's audio with a better recording (voice memo, mixer feed, lapel mic...)
# without re-encoding the video.
#
# usage: swap_audio.sh <video.mp4> <audio_source> <audio_start_sec> <out.mp4> [extra_filters]
#
# <audio_start_sec>: the time in <audio_source> that lines up with t=0 of <video.mp4>
#   (= the video's source start time + the offset from tools/audio_offset.py).
# [extra_filters]: optional ffmpeg audio filters, e.g. "highshelf=f=4000:g=3" for a muffled source.
# TARGET_LUFS: integrated loudness to bring the speech to (default -14, YouTube's playback level).
#
# Mono sources are copied to both channels. Loudness is measured on the final stereo signal, then
# a fixed gain is applied (no dynamic compression) with a -1 dBTP-ish limiter as a safety net.
set -euo pipefail
IN=$1 SRC=$2 SS=$3 OUT=$4 EXTRA=${5:-}
TARGET=${TARGET_LUFS:--14}
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$IN")
CH=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 "$SRC")
(( CH == 1 )) && PAN="pan=stereo|c0=c0|c1=c0" || PAN="aformat=channel_layouts=stereo"
PRE="aresample=48000,highpass=f=80,lowpass=f=15000${EXTRA:+,$EXTRA},${PAN}"
I=$(ffmpeg -nostats -ss "$SS" -t "$DUR" -i "$SRC" -vn -af "$PRE,ebur128" -f null - 2>&1 | awk '/^ +I:/{v=$2} END{print v}')
G=$(python3 -c "print(round(${TARGET}-(${I}),2))")
print -r -- "source segment ${I} LUFS -> gain ${G} dB (target ${TARGET})"
ffmpeg -hide_banner -v error -stats -y -i "$IN" -ss "$SS" -t "$DUR" -i "$SRC" \
  -filter_complex "[1:a]${PRE},volume=${G}dB,alimiter=limit=0.89:level=false[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 192k -ar 48000 -shortest -movflags +faststart "$OUT"
