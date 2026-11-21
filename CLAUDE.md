# CLAUDE.md

This repo is a toolkit for editing meetup talk recordings into finished videos. The footage
lives elsewhere, in a per-event folder the user points you to. Don't copy footage into this repo.

- **Process:** follow `docs/PLAYBOOK.md` step by step. It includes the ground rules (never
  modify source recordings, no new dependencies, zsh `${VAR}` in filters, background renders,
  test renders first).
- **Scripts:** `bin/` (each header documents usage). Shared look and geometry: `lib/common.zsh`.
  Helpers: `tools/`.
- **Changing the scripts:** keep them dependency-free (zsh + ffmpeg + python3 stdlib). Render a
  short test with real footage before committing. Keep each script's header comment in sync with
  its arguments.
- Don't commit media files or per-event data; `.gitignore` excludes them.
