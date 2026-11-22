# Changelog

## v1.0 — 2026-11-22

First release.

- Shows the album covers embedded in the MP3s of a music folder as an animated
  wall: the grid, seven animations and timings of
  [lingkuma/AlbumArtwork](https://github.com/lingkuma/AlbumArtwork).
- Options: music folder, rows (3–12), interval (1–10 s), "Jetzt neu einlesen".
- Incremental scanning with a cover cache: only new and changed files are
  read, a track re-tagged with another picture renews its album's cover, and
  nothing is removed after an incomplete pass.
- Universal bundle (Apple Silicon and Intel), macOS 13 or later.
