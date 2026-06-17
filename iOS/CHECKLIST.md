# BeamerPresenter for iPadOS — feature checklist

A focused iPad app, grown one feature at a time. The **minimal app** (this first
commit) presents a PDF; everything below is implemented in order afterwards.

Target device: **iPad Pro 2021** (USB‑C, external display capable), iPadOS 16+.

> **Status: all checklist items complete.** ✅ The minimal app plus features
> 1–11 below are implemented. Future polish (e.g. scene-based external displays)
> is noted inline.

## ✅ Minimal app (done)
- [x] Open a PDF from Files / iCloud (document picker, security‑scoped access)
- [x] Present a slide full‑screen
- [x] Navigate: tap left/right halves, swipe, on‑screen prev/next
- [x] Slide counter
- [x] Thumbnail strip to jump to any slide
- [x] Pen annotation (one colour) with undo / clear, per slide
- [x] Recent files

## ⏭️ Next, in order
1. [x] **External display (audience)** — the slide (with ink) mirrors onto a
       connected screen (USB‑C / AirPlay) while the iPad keeps the presenter
       console; a green `tv` badge appears when a display is attached.
       *Implemented with the `UIScreen` connect/disconnect API* — deprecated on
       iOS 16 but the most contained, reliable option. A future modernisation
       to scene-based external displays (`UIWindowScene` / `requestGeometryUpdate`)
       is noted here for when we adopt the multi-scene lifecycle.
2. [x] **Pen colours + laser pointer** — six pen colours, three line weights,
       and a laser pointer (glowing red dot) that, like the ink, is mirrored
       live onto the external/audience display. Pen and laser are mutually
       exclusive tools.
3. [x] **Overview grid** — a full-screen grid of every slide (`square.grid.2x2`
       in the toolbar); tap a thumbnail to jump to it. The current slide is
       highlighted and scrolled into view.
4. [x] **Speaker notes** — a presenter-only notes pane (`note.text` toolbar
       button). Two sources: (a) a "show notes on second screen" **split PDF**
       is auto-detected from its double-wide pages — the slide half goes to the
       iPad/audience, the notes half into the pane; (b) `\note{}` parsed from a
       sibling `.tex` via the ported, pure-Foundation `TexNotes` (`.nav`-aware).
       When the sibling `.tex` isn't reachable in the sandbox, the pane offers
       **Load notes (.tex)…** to attach one explicitly.
5. [x] **Timer + clock** — a centred stopwatch (play / pause / reset) and the
       wall clock in the toolbar, ticking once a second via `TimelineView`.
6. [x] **Black‑out** the audience — `eye.slash` toolbar button (tap to toggle,
       long-press for options) blacks the external/audience screen with an
       optional centred message (presets) and a clock. The presenter keeps the
       slide, dimmed, with a "blacked out" badge.
7. [x] **Whiteboard** scratch boards — ported the macOS `Whiteboard` model &
       rendering (`NSImage`→`UIImage`, `CIFilter`→`CIFilterBuiltins`). A boards
       menu adds/switches/deletes blank white boards shown instead of the deck
       (and on the audience screen). Draw ink, and insert movable/resizable
       **text**, **table** (`a | b` rows), and **QR** items with a delete ✕.
8. [x] **Export** — `square.and.arrow.up` bakes the freehand ink onto each
       slide and inserts each whiteboard after the slide it was made on, into a
       new vector PDF (Core Graphics), then opens the share sheet (Files /
       AirDrop / Mail). Ported from the macOS `BoardExporter`.
9. [x] **Apple Pencil** — a UIKit inking overlay (active while the pen tool is
       on) tells Pencil from finger, samples coalesced touches for smooth lines,
       and reads pressure to vary the stroke width (per-point, rendered & exported
       as variable-width). An **Apple Pencil only** toggle (pen menu) gives palm
       rejection by ignoring finger touches.
10. [x] **Settings** — a `gearshape` screen (start screen + presenter toolbar)
        with persisted (`@AppStorage`) defaults: Apple-Pencil-only, default pen
        colour & line weight, and black-out options (start blacked out, clock,
        preset/custom message, and a background image copied into app support).
11. [x] **Bluetooth presenter remote** — a `UIKeyCommand` responder maps the keys
        clickers emit: Page Down / → / ↓ / space = next, Page Up / ← / ↑ =
        previous, `b` / `.` = black-out, Esc = close board. Works with any paired
        keyboard too (iPadOS 16-compatible, unlike SwiftUI `onKeyPress`).

## Notes / platform limits
- **No on‑device LaTeX / PowerPoint compilation** — iOS can't spawn subprocesses.
  On iPad you open already‑compiled **PDFs**. (`.tex` notes parsing still works.)
  A future option: a small companion/server endpoint to compile remotely.
- **Code sharing:** the model/whiteboard logic is largely portable; the macOS app
  keeps the AppKit‑only parts (windows, menu bar, status item, `Process`).
  As features land, factor the shared bits into a common folder/Swift package.
