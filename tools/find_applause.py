"""Find where the final applause starts, to place the outro fade.

usage: find_applause.py <file> <start_sec> [dur_sec=90] [gap_db=-55] [min_run=3]

Measures >3 kHz RMS in 1/8 s steps. Speech has short near-silent gaps between words; applause
is continuous broadband noise with no gaps. Candidates are runs of at least `min_run` seconds
with no step below `gap_db`. Prints a compact level strip (one char per 1/8 s) and the
candidates, latest last; the final applause is usually the last long run.

Always confirm with camera frames: laughter or a mid-Q&A clap looks the same in the audio.
Start the fade ~0.75-1 s after the applause begins (starting right on it feels abrupt), and
pass fade_start + fade (1.5) to bin/add_intro_outro.sh as talk_end.
"""
import sys, subprocess, re

f, start = sys.argv[1], float(sys.argv[2])
dur = float(sys.argv[3]) if len(sys.argv) > 3 else 90.0
gap = float(sys.argv[4]) if len(sys.argv) > 4 else -55.0
min_run = float(sys.argv[5]) if len(sys.argv) > 5 else 3.0

af = ("aresample=48000,highpass=f=3000,highpass=f=3000,asetnsamples=6000,"
      "astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-")
out = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(start), "-t", str(dur), "-i", f, "-vn", "-ac", "1",
                      "-af", af, "-f", "null", "-"], capture_output=True, text=True).stdout
lv = []
for m in re.finditer(r"RMS_level=(-?[\d.]+|-inf)", out):
    v = m.group(1); lv.append(-120.0 if v == "-inf" else float(v))
if not lv:
    sys.exit("no audio levels read")
step = 0.125
chars = " .:-=+*#"
strip = "".join(chars[min(7, max(0, int((v + 80) / 8)))] for v in lv)
for i in range(0, len(strip), 80):
    print(f"{start + i*step:8.1f}  |{strip[i:i+80]}|")
runs, i = [], 0
while i < len(lv):
    if lv[i] < gap:
        i += 1; continue
    j = i
    while j < len(lv) and lv[j] >= gap: j += 1
    if (j - i) * step >= min_run:
        seg = lv[i:j]
        runs.append((start + i * step, (j - i) * step, sum(seg) / len(seg)))
    i = j
print(f"\nruns with no gap below {gap} dB for >= {min_run} s:")
for s, d, m in runs:
    print(f"  {s:8.2f}  for {d:5.1f} s  mean {m:6.1f} dB   -> fade start ~{s + 0.75:.2f}, talk_end ~{s + 2.25:.2f}")
if not runs:
    print("  none; try a later/longer window or a higher gap_db")
