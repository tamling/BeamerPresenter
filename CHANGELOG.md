# Changelog

## v3.3 — 2026-08-19

- Removed the reference/link to the magicPresenter project from the README
  (and a code comment).

## v3.2 — 2026-08-19

- Drop a PDF, .tex, or .pptx anywhere on the home screen to open it (and a
  folder anywhere to pin it as a favourite) — the drop zone stays as the
  visual anchor and still lights up while dragging.

## v3.1 — 2026-08-19

Window-behaviour polish on macOS.

- The audience window now opens as a normal, resizable window by default; the
  borderless edge-to-edge fill on the external display is opt-in via
  Presentation ▸ Enter Audience Full Screen or the settings toggle — and then
  covers the menu bar completely.
- The green traffic-light button enters real macOS full screen on both the
  presenter and the audience window (it previously only zoomed).
- Fixed: unplugging the projector while the borderless audience window was up
  stranded it — uncloseable — on the main screen. It now converts to a normal
  window; replugging restores the fill mode.
- The blacked-out audience screen keeps its pulsing green dot but no longer
  shows the "Audience paused" label (macOS and iPadOS).

## v3.0 — 2026-06-21

BeamerPresenter for **macOS** and **iPadOS**: present LaTeX Beamer / PDF decks
with a private presenter console and a clean audience screen.

New since the first cut: a fully dark whiteboard with a black/white toggle (and
a light, printable export), a lecture-length countdown with a custom value, a
pairing code for the iPhone remote, a save prompt for unsaved annotations, the
new "two screens" app logo, and a build date + commit stamp shown in About.

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
