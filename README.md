# LexTalk Tech video editor

Scripts for turning raw meetup recordings into finished, YouTube-ready talk videos. They were
built for the LexTalk Tech meetup and are meant to be driven by an AI coding agent
such as [Claude Code](https://claude.com/claude-code). A person can run them too: they are plain
zsh, ffmpeg and Python.

Each finished talk looks like this:

```
┌───────────────────────────────────────────┬──────────────┐
│                                           │  close-up    │
│   main panel: the real slides, or the     │  camera      │
│   projector screen squared up from the    ├──────────────┤
│   wide shot, or the camera during Q&A     │  wide shot   │
│                                           │              │
│                                           │ event · date │
├───────────────────────────────────────────┴──────────────┤
│ Talk title                                               │
│ Subtitle                                                 │
│ Presenter                                                │
└──────────────────────────────────────────────────────────┘
```

The video then gets an intro and an outro, joined with 1.5 s crossfades. The outro fade starts
on the applause.

## What it handles

| Situation | Script |
|---|---|
| One produced recording (a program feed) where the screen is a small inset | `bin/layout_inset.sh` |
| A wide shot plus a close-up camera, with the speaker's slide deck (PDF) available | `bin/layout_twocam.sh` |
| No deck, a tripod wide shot: show the projector screen squared up | `bin/layout_screen.sh` |
| No deck, a handheld or drifting wide shot: track the screen and warp it every frame | `bin/track_screen.sh` + `bin/layout_tracked.sh` |
| A remote speaker on a video call: use their webcam tile as the camera | `bin/layout_screen.sh` with `-` and `CAM_CROP` |
| Projector off for Q&A: switch the main panel to the close-up camera | `CAM_RANGES` in `bin/layout_tracked.sh` |
| Separate recorders (camera, phone, voice memo) that need syncing | `tools/audio_offset.py` |
| A cleaner audio recording than the camera's | `bin/swap_audio.sh` |
| Finding where the final applause starts | `tools/find_applause.py` |
| Matching video to slide pages | `tools/pdf2png.swift`, `tools/match_slides.py` |
| Intro and outro | `bin/add_intro_outro.sh` |

## Requirements

- macOS. Fonts default to system Arial, and `pdf2png.swift` uses PDFKit. On Linux, set
  `FONT_BOLD` and `FONT_REG`, and render PDFs with another tool.
- zsh (the macOS default shell)
- ffmpeg 6 or newer. It is tested with ffmpeg 8; install it with `brew install ffmpeg`.
- python3. Only the standard library is used: no numpy or OpenCV.
- swiftc, from the Xcode command-line tools, to build `pdf2png`.

## Using it with Claude Code

1. Clone this repo somewhere, e.g. `~/projects/lextalk-tech-video-editor`.
2. Put an event's footage in its own folder and start Claude Code there.
3. Tell it which talks are in which files, then say something like:

   > Follow ~/projects/lextalk-tech-video-editor/docs/PLAYBOOK.md to cut these into finished
   > talk videos. Intro/outro clip: ~/path/intro.mp4. Event text: "LexTalk Tech · November 6, 2025".

The playbook covers the full process: syncing cameras, finding each talk's start and end,
matching slides, tracking the screen, checking the results, and the mistakes made before. It also
has rules the agent must follow; the most important is to never modify the source recordings.

## Quick reference

```bash
# Branding (optional; these are the defaults apart from EVENT_TEXT)
export EVENT_TEXT="LexTalk Tech  ·  November 6, 2025" BG=0x0b1d3f ACCENT=0x2fd4c4

# Sync: close-up time = wide time + OFFSET
python3 tools/audio_offset.py wide.mp4 1500 closeup.mp4 0 1200

# Deck → pages → layout
swiftc -O tools/pdf2png.swift -o /tmp/pdf2png && /tmp/pdf2png deck.pdf decks/03-name/pages 1920
bin/layout_twocam.sh wide.mp4 closeup.mp4 -1558.05 "03 - Title - Name (with slides).mp4" \
  decks/03-name "Title" "Subtitle" "Name" 1718.0 1130

# No deck, handheld camera
bin/track_screen.sh wide.mp4 1012 1503 decks/04-name/track.tsv
CAM_RANGES=2399-2600 bin/layout_tracked.sh wide.mp4 closeup.mp4 -918.175 "04 ... (with slides).mp4" \
  decks/04-name/track.tsv "Title" "" "Name" 1012 1503

# Applause → intro/outro (talk_end = fade start + 1.5)
python3 tools/find_applause.py wide.mp4 2470 60
bin/add_intro_outro.sh "04 ... (with slides).mp4" intro.mp4 "04 ... (final).mp4" 1499.5
```

Each script's header comment documents its arguments and file formats in full. `examples/`
has sample `timeline.tsv`, `screen.tsv` and `track.tsv` files.

## Layout

```
bin/      runnable scripts (layouts, tracking, audio swap, intro/outro)
lib/      common.zsh: shared branding, panel geometry, text overlay
tools/    Python/Swift helpers called by the scripts or used during analysis
docs/     PLAYBOOK.md: the step-by-step process for an agent (or a person)
examples/ sample data files
```

## License

MIT; see [LICENSE](LICENSE).
