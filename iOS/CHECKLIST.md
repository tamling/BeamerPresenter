# BeamerPresenter for iPadOS — feature checklist

A focused iPad app, grown one feature at a time. The **minimal app** (this first
commit) presents a PDF; everything below is implemented in order afterwards.

Target device: **iPad Pro 2021** (USB‑C, external display capable), iPadOS 16+.

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
2. [ ] **Pen colours + laser pointer** (mirrored to the audience)
3. [ ] **Overview grid** — tap a slide to jump
4. [ ] **Speaker notes** — split (notes‑on‑second‑screen) PDFs *and* `\note{}`
       parsed from a sibling `.tex` (reuse the macOS `TexNotes` logic — it is
       pure Foundation and portable)
5. [ ] **Timer + clock** with start/stop/reset
6. [ ] **Black‑out** the audience (+ optional message / clock)
7. [ ] **Whiteboard** scratch slides (ink, text, table, QR) — port the macOS
       `Whiteboard` model & rendering (mostly portable; swap `NSImage`→`UIImage`)
8. [ ] **Export** the annotated deck (ink + boards) to a new PDF (share sheet)
9. [ ] **Apple Pencil** pressure / palm rejection (PencilKit option)
10. [ ] **Settings** (black‑screen message/image, defaults)
11. [ ] **Bluetooth presenter remote** support (page up/down)

## Notes / platform limits
- **No on‑device LaTeX / PowerPoint compilation** — iOS can't spawn subprocesses.
  On iPad you open already‑compiled **PDFs**. (`.tex` notes parsing still works.)
  A future option: a small companion/server endpoint to compile remotely.
- **Code sharing:** the model/whiteboard logic is largely portable; the macOS app
  keeps the AppKit‑only parts (windows, menu bar, status item, `Process`).
  As features land, factor the shared bits into a common folder/Swift package.
