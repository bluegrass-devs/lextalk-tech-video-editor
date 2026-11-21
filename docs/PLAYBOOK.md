# Playbook: from raw event footage to finished talk videos

This is written for an AI coding agent (e.g. Claude Code) working in a folder of event footage.
A person can follow it too. `REPO` below means the path to this repository.

## Ground rules

- **Never modify, move or delete the source recordings.** Write only new files.
- **Don't install** numpy, OpenCV, ImageMagick or poppler. The tools here don't need them, and
  the user's machine may be kept minimal on purpose.
- The scripts are **zsh**. Inside ffmpeg filter strings, always write `${VAR}`: in zsh,
  `$VAR[label]` is read as an array subscript.
- Renders of whole talks take 10–40 minutes. **Run them in the background**, and render a 60–90 s
  test first whenever something is new: a new layout, a new track, a new camera.
- **Never stop a render partway and leave its output**: a half-written mp4 won't play. After
  killing ffmpeg, check `pgrep -l ffmpeg`, because a plain `pkill` doesn't always stop it, and
  two renders writing the same file corrupt it.
- Renders that run about 4x slower than usual usually mean a laptop on battery with Low Power
  Mode on (`pmset -g | grep lowpower`). Tell the user; don't change the setting yourself.
- The user should be able to check your work quickly. Always report final-video timestamps
  for the joins and anything doubtful.
- **Ask the user**, rather than guess, about talk titles, presenter names and spelling, which
  talk is in which file, and whether a talk was a false start that should be dropped.

## Output naming

For each talk, in the event folder:

- `NN - Title - Presenter (with slides).mp4`: the layout, without intro/outro (intermediate)
- `NN - Title - Presenter (final).mp4`: the deliverable
- `decks/NN-presenter/`: the data needed to re-render: `pages/`, `timeline.tsv`,
  `screen.tsv` or `track.tsv`. Put the sync offset and cut points in `#` comments at the top.

## 1. Inventory the footage

For every file: `ffprobe` the duration, resolution, fps and audio. Then pull a contact sheet
(one frame every 60 s, tiled) to see which talk is where and which camera is which:

```bash
ffmpeg -i in.mp4 -vf "fps=1/60,scale=320:-1,tile=8x6" -frames:v 1 sheet.png
```

Typical sources:

- **Wide shot** (a phone on a tripod or held by hand): shows the screen and the stage. Often
  split into several files, with gaps between them.
- **Close-up camera** (DSLR/mirrorless): the presenter, usually with the best audio. It often
  doesn't cover every talk.
- **Voice memo or other audio recorder**: may run the whole evening. Check it; it can beat the
  camera audio (see step 8).
- **A produced recording** in which the screen is a small inset: see `layout_inset.sh`.

File creation times (`ffprobe -show_entries format_tags=creation_time`) give a rough starting
point for syncing. Sync itself always comes from audio.

## 2. Sync the cameras

```bash
python3 REPO/tools/audio_offset.py <wide> <t_in_wide> <other> [guess] [search] [window]
# → OFFSET x  corr c     (other_time = wide_time + x)
```

- Pick a `t` in the middle of speech. Without a good guess, use a large search (e.g. `0 3600`);
  this takes a few seconds.
- A correlation above ~0.6 is solid. If it's low, try another `t`.
- **Check for drift:** measure at the start and the end of each talk. Different devices' clocks
  drift by tens of ppm. Up to ~40 ms of drift across a talk is fine (use the midpoint offset);
  beyond that, sync per section.
- Each camera file has its own offset. Cameras split recordings into several files, so work out
  which file covers which talk.

## 3. Find each talk's start and end

- **Start:** the first moment the presenter is on their own: the MC has walked off, and ideally
  there's a pause in speech (`silencedetect`). Check the next 30 s too, because MCs sometimes
  come back to help with a laptop. A presenter's false start (a broken demo or a failed laptop
  setup) may need dropping, or may appear in another file; ask the user.
- **End:** the final applause. Run `tools/find_applause.py <file> <t> 60` over the last minute.
  Applause is continuous >3 kHz noise with no gaps between words. **Confirm with camera frames**:
  the presenter says thanks and steps back, and the MC walks up. Laughter or a clap mid-Q&A looks
  identical in the audio.
- **The fade starts ~0.75–1 s after the applause begins.** A fade exactly on the first clap feels
  abrupt, and one that waits for the MC to take the mic is several seconds too late. Then
  `talk_end = fade_start + 1.5`.

## 4. Choose the main panel

Aim for the real slides wherever possible; they are far sharper than any shot of a projector.

### 4a. A slide deck is available (PDF)

```bash
swiftc -O REPO/tools/pdf2png.swift -o /tmp/pdf2png
mkdir -p decks/NN-name/pages && /tmp/pdf2png deck.pdf decks/NN-name/pages 1920
```

**PPTX only** (no LibreOffice or Keynote export): unzip a copy and read `ppt/slides/slideN.xml`.
If the slides are just pictures (`ppt/media/*`), rebuild each page with ffmpeg from the picture's
offset and size (EMU / 12192000 × 1920).

Make a contact sheet of the pages and confirm the deck belongs to this talk.

**Match the video to the pages.** Sample the screen at 2 fps, down to 48x27:

```bash
ffmpeg -ss <talk_start> -t <dur> -i wide.mp4 -vf "crop=<screen box>,fps=2,scale=48:27:flags=area,format=gray" -f rawvideo v.gray
ffmpeg -pattern_type glob -i 'decks/NN-name/pages/page_*.png' -vf "scale=48:27:flags=area,format=gray" -f rawvideo d.gray
python3 REPO/tools/match_slides.py v.gray d.gray 48 27 2 raw.tsv
```

The output times are relative to `-ss`; add `talk_start` back before writing the timeline. Then
review the output critically:

- **Build steps** (near-identical consecutive pages) get skipped. Time those by eye, from zoomed
  frames at 4 fps or from the per-sample score jumps.
- **Light slides that blow out to white**: use stretched samples and
  `match_slides_stretched.py`. For the video, add `lutyuv=y='clip((val-215)*6,0,255)'`; for the
  deck, `lut=y='clip((val-150)*3,0,255)'`.
- **Similar-looking pages** (the same layout, or the same photo) get confused even at high
  scores. Compare zoomed crops side by side.
- **Low correlation** (below ~0.5) means the stretch isn't a deck slide: a demo, a web page or
  the desktop. Mark it `-`, which shows the footage instead. At the very end of the talk, keep
  the last real slide ("Questions?") up instead.
- A quicker route when the matcher struggles: sample a frame every 5 s, identify each page by
  eye, then time each change precisely from 4 fps frame differences.

Write `decks/NN-name/timeline.tsv`: `start_seconds<TAB>page` in the **wide file's** timeline.

```bash
bin/layout_twocam.sh wide.mp4 close.mp4 <offset> "NN ... (with slides).mp4" decks/NN-name \
  "Title" "Subtitle" "Presenter" <start> <dur> [close|wide]
```

Set `WIDE_SCREEN_CROP=w:h:x:y` so `-` stretches show the screen region, not the whole frame.

### 4b. No deck, and the camera didn't move

Measure the four screen corners on a still frame. Zoom in with a `drawgrid` overlay to read the
coordinates. Write `screen.tsv` (`t<TAB>x0:y0:x1:y1:x2:y2:x3:y3`, in the order TL TR BL BR), and
add a row each time the camera got bumped (compare frames every few minutes).
Then run `bin/layout_screen.sh`.

**Remote speaker** on a video call: pass `-` as the close-up and set `CAM_CROP` to their webcam
tile in the wide shot. The audio then comes from the wide shot (the room PA).

### 4c. No deck, and the camera was handheld or drifting

```bash
bin/track_screen.sh wide.mp4 <start> <dur> decks/NN-name/track.tsv [thr=170]
```

- Run it over the **whole talk**. Its trust filter compares each sample with the ±60 s around
  it, so very short windows give poor tracks.
- It trusts only samples where the whole screen is lit. Dark slides and dark menu bars shrink the
  bright blob, so those samples are interpolated over.
- If the blob leaks into a bright banner or wall, raise `thr`; if the screen is dim, lower it.
- **Always render a 60–90 s test** at a camera move and on a dark slide, and look at it before
  the full render.
- If the projector goes off for Q&A, set `CAM_RANGES=a-b` (wide-file times) so the main panel
  shows the close-up camera.

```bash
CAM_RANGES=2399-2600 bin/layout_tracked.sh wide.mp4 close.mp4 <offset> "NN ... (with slides).mp4" \
  decks/NN-name/track.tsv "Title" "" "Presenter" <start> <dur>
```

## 5. Audio

By default the close-up camera's audio is used. Compare the candidate sources over the same
30 s, matched in loudness. Check the speech-to-pause contrast (the 90th minus the 10th percentile
of 100 ms energy) and the >4 kHz energy (muffled or clear), and give the user short A/B clips to
listen to. A phone voice memo near the speaker often has 3–5 dB better contrast than a camera at
the back, despite its low bitrate.

To use another source without re-rendering:

```bash
bin/swap_audio.sh "NN ... (with slides).mp4" memo.m4a <talk_start + memo_offset> out.mp4 ["highshelf=f=4000:g=3"]
```

It brings the speech to `TARGET_LUFS` (default −14, which roughly matches typical intro music)
with a fixed gain and a limiter. Re-check sync on the result: run `audio_offset.py` with the wide
file as the reference at a few times `t` and the new file as the other. The offset should stay
at `-talk_start` (or `8.5 - talk_start` once the intro has been added), within ~40 ms.

## 6. Intro and outro

```bash
bin/add_intro_outro.sh "NN ... (with slides).mp4" intro.mp4 "NN ... (final).mp4" <talk_end> [1.5] [outro.mp4]
```

- `talk_end` is in the (with slides) timeline: `fade_start - talk_start + 1.5`.
- With a 10 s intro and 1.5 s fades, **final time = talk time + 8.5 s**.

## 7. Verify before reporting

- Check durations with `ffprobe`.
- Grab frames: in the intro join (8.5–10 s), at several points in the talk (slides vs the
  projector, the tracked screen at camera moves, Q&A switching), in the outro join, and at the end.
- Measure loudness per section with `ebur128` (intro, talk, outro). The talk should be within a
  few LU of the intro, with no gaps or jumps across the joins.
- Check sync at the start, middle and end.
- Report the outro fade and any doubtful spots as **final-video timestamps**.

## Lessons from past events

- A tracker that followed the screen's outward extremes failed on long dark content. Trusting
  only fully lit samples, plus a long-window area check and a shape check, fixed it.
- A glow on the projector that looked like a tracking bug was real content (a Windows Hello
  prompt). Look at the source before "fixing" anything.
- The first sync guess from file timestamps was off by ~30 s; audio cross-correlation fixed it.
- Mid-talk camera bumps show up as sudden corner jumps. Add a `screen.tsv` row or let the
  tracker handle it.
- A speaker's first attempt failed (their laptop wouldn't connect) and the real talk was in the
  next file. Ask the user which attempt to use.
- When a talk has no close-up coverage, use the wide shot's audio and check its level against
  the other talks; it's usually a few dB quieter.
