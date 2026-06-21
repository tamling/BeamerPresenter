# Changelog

## v2.0 — 2026-06-17

BeamerPresenter for **macOS** and **iPadOS**: present LaTeX Beamer / PDF decks
with a private presenter console and a clean audience screen.

### Highlights

**Night Console redesign**
- A single fixed dark theme with tactile keys, mono labels and one electric-lime
  signal colour, applied across every screen on both platforms.
- Bundled typefaces (Space Grotesk · IBM Plex Sans · JetBrains Mono) and a new
  glowing app icon + brand mark.

**Presenter console**
- Current slide, next slide, speaker notes and your own scratch notes, with
  draggable, persisted split sizes.
- Thumbnail strip and a full-deck overview grid (current slide highlighted).
- Slide counter, wall clock and a start/stop/reset elapsed timer.

**Lecture timer**
- Optional lecture-length target — presets (30 / 45 / 60 / 90 = 2 × 45 / 120)
  plus a custom value — with a countdown "Left" chip that warns amber in the last
  five minutes and turns red on overrun.

**Annotation & laser**
- Freehand pen (colours, line weights, Apple Pencil palm rejection on iPad),
  a laser pointer, undo/clear — on slides and on the whiteboard.

**Whiteboard**
- A free-form scratch board with movable text, tables and QR codes.
- Dark on screen (presenter + audience), and a black/white toggle.
- Exports light (ink-on-white) so printed / handed-out PDFs stay readable; QR
  codes sit on a white chip so they always scan.

**Black-out / audience screen**
- One-key audience black-out with an optional centred message, clock or image.

**iPhone remote (iPad)**
- Use a second iPhone/iPad as a remote over MultipeerConnectivity
  (Wi-Fi/Bluetooth, encrypted): prev/next, black-out and timer, with the current
  slide number and speaker note.
- **Pairing code:** the presenting iPad shows a random 4-digit code that the
  remote must enter — no unknown device on the same network can connect.

**macOS**
- Universal build (Apple Silicon + Intel), menu-bar commands and keyboard
  shortcuts, external-display support, and optional on-the-fly compilation of
  `.tex` / `.pptx` sources when the tools are installed.

**Export**
- Render the whole deck to a new PDF with the freehand ink burned in and the
  whiteboards inserted after the slide on which they were drawn.

### Notes
- Licensed under the GNU GPL.
