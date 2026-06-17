# BeamerPresenter

A native macOS (Apple Silicon) presenter app for LaTeX **Beamer** decks,
modelled on [magicPresenter](https://www.magicpresenter.app). The audience
screen shows the slide; your laptop shows a full presenter console: current
slide, next slide, speaker notes, a thumbnail strip, a slide overview, and a
timer.

It works directly off a compiled PDF; if a matching `.tex` is alongside it, the
app can also pull `\note{}` speaker notes straight from the source.

**Version 1.0** (2026-06-17) — by Timo Amling.

## GUI

- **Launch splash** — a brief startup screen with the app icon, name, and version.
- **Menu bar** — every command lives here: *File* (Open, Add Folder to Favorites,
  Close), *Presentation* (next/previous/first/last, overview, blackout, reset
  timer), *Tools* (pen, laser, pen colours, undo/clear ink), *Whiteboard* (toggle,
  boards, add text/table/QR, save/insert). *App* holds About + Settings (⌘,).
- **Welcome screen** — open button, drag-and-drop a PDF/`.tex`, a **browsable
  folder** (Documents by default, set in Settings), **favorite folders** (expand
  to the PDFs inside; add with the `+`), and a recent-files list.
- **Settings (⌘,)** — choose the start-screen folder, toggle the default black
  audience screen, and set the black-screen message.
- **Presenter console** — a control bar with every live tool, each a captioned
  symbol (exit, prev/next + slide counter, overview, blackout, whiteboard, pen,
  laser, the pen-colour swatches, undo/clear ink, reset timer, elapsed + clock),
  large current slide, next slide, notes pane. **Exit** returns to the home
  screen. The slide/sidebar split and the next/notes split are **draggable**, and
  the sizes persist. The same commands are also in the menu bar.
- **Thumbnail strip** — click any slide to jump; auto-scrolls to the current one.
- **Overview grid** — press `G` for a full grid of every slide; click to jump.
- **Ink & laser** — draw freehand on a slide (pen, 4 colours, undo/clear) or use
  a laser pointer; both mirror live onto the audience screen.
- **Whiteboard** — press `W` for a blank white scratch slide to work through a
  calculation live. Draw on it, drop in text boxes, a clean Safari-style table,
  or a QR code, move and **resize** items with handles, keep several boards,
  export any of them to its own PDF, or **insert** one after the current slide
  into a *copy* of the deck PDF (the original is untouched). The board toolbar is
  a compact, Safari-like rounded bar.
- **Audience window** — full-bleed slide, fullscreen on the external display.
  Starts **blacked out** by default; the black screen shows an optional centered
  message (*Presentation ▸ Set Black-Screen Message…*) or, when empty, the clock.

## How notes work

Compile your Beamer deck so each PDF page carries the slide on the left half and
your `\note{}` text on the right half:

```latex
\documentclass{beamer}
\setbeameroption{show notes on second screen=right}

\begin{document}
\begin{frame}{Title}
  Slide content here.
  \note{These are my speaker notes for this slide.}
\end{frame}
\end{document}
```

The app detects the double-width layout automatically and splits each page:
left half → audience, right half → your notes pane.

### Notes straight from the `.tex`

You don't have to recompile with the second-screen option. If you open a plain
PDF and a `.tex` file with the **same base name** sits next to it, the app reads
your `\note{…}` text directly from the source and shows it in the notes pane.
You can also do it the other way round — **open (or drop) the `.tex` itself** and
the app opens the matching `<name>.pdf` beside it:

```latex
\begin{frame}{Title}
  Slide content here.
  \note{These are my speaker notes for this slide.}
\end{frame}
```

If there's no `.tex` with the same base name (or it has no notes), the app falls
back to any other `.tex` in the same folder. Page mapping is exact when the
matching Beamer `.nav` file is also present (it encodes each frame's page range,
so overlays line up); otherwise each frame is treated as one page. A plain PDF
with neither notes layout nor a `.tex` still presents fine — the notes pane just
shows a hint instead.

## Run it (development)

Requires Xcode / the Swift toolchain on macOS 13+.

```bash
cd BeamerPresenter
swift run
```

An open panel appears — pick your compiled PDF. The audience window goes
fullscreen on your external display (or the only display if there's just one).

## Keyboard / remote controls

| Key | Action |
| --- | --- |
| → / Space / Page Down | Next slide |
| ← / Page Up | Previous slide |
| Home / End | First / last slide |
| `G` | Toggle the slide overview |
| `B` | Black out the audience screen |
| `W` | Toggle the whiteboard scratch slide |
| `R` | Reset the elapsed timer |
| `P` | Pen tool |
| `L` | Laser pointer |
| `Z` | Undo last stroke |
| `C` | Clear ink on this slide |
| Esc | Drop the tool → close overview |

Bluetooth presenter remotes emit Page Up / Page Down, so they work out of the box.

## Project layout

| File | Responsibility |
| --- | --- |
| `main.swift` | AppKit bootstrap |
| `AppDelegate.swift` | Windows, screen placement, menu, keyboard |
| `PresentationState.swift` | Shared state (index, timer, blackout, overview, thumbnails) |
| `PDFModel.swift` | Loads the PDF and crops each page into halves |
| `TexNotes.swift` | Parses `\note{}` from a sibling `.tex` (+ `.nav` page ranges) |
| `PDFPageView.swift` | Renders one non-interactive page (SwiftUI ↔ PDFKit) |
| `SlideView.swift` | Aspect-correct slide + ink/laser annotation layer |
| `Whiteboard.swift` | Whiteboard model, items, and QR-code generation |
| `WhiteboardView.swift` | Board rendering, item editing, toolbar, and PDF export |
| `RecentFiles.swift` | Recently-opened list persisted in UserDefaults |
| `Favorites.swift` | Favorite folders + app version info, persisted in UserDefaults |
| `WelcomeView.swift` | Home screen: open, drag-and-drop, browse folder, favorites, recents |
| `SettingsView.swift` | Settings window (start-screen folder, black-screen options) |
| `SplashView.swift` | Brief launch splash with icon + version |
| `PresenterView.swift` | Root switch + presenter console + control bar |
| `ThumbnailStrip.swift` | Clickable thumbnail navigation row |
| `OverviewGrid.swift` | Full-window slide overview overlay |
| `AudienceView.swift` | Full-bleed slide for the projector |

## Build a real `.app`

`swift run` is for iterating. To get a double-clickable bundle, run the included
script — it builds a release `arm64` binary, generates the app icon, and wraps
everything with `Info.plist`:

```bash
./build-app.sh
open build/BeamerPresenter.app
```

To codesign for distribution, pass your Developer ID:

```bash
./build-app.sh "Developer ID Application: Your Name (TEAMID)"
```

Then notarize with `xcrun notarytool submit build/BeamerPresenter.app --wait …`
and `xcrun stapler staple`. (You can also drop these sources into a regular
Xcode macOS App target if you prefer the Xcode toolchain.)

## App icon

The icon is drawn programmatically — no design tools or binaries needed. Edit the
shapes/colours in `Tools/make_icon.py` and run:

```bash
./make-icon.sh
```

It renders `Resources/AppIcon.iconset` (and a 1024px `Resources/AppIcon.png`
preview), then, on macOS, compiles `Resources/BeamerPresenter.icns` with the
built-in `iconutil`. `build-app.sh` does this automatically when assembling the
bundle.

## Roadmap ideas

- Embedded links and videos in the PDF
- Persisting ink between sessions / exporting an annotated PDF
- Larger / scrollable / markdown notes via the `pdfpc` embedded-notes format
- Per-slide timing and a rehearsal mode
- Notarized release build
