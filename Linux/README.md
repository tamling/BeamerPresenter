# BeamerPresenter for Linux

The Linux port of the presenter console: open a LaTeX **Beamer** PDF (or the
`.tex` itself), get the **console** on your laptop — current slide, next slide,
speaker notes, clock, elapsed timer, overview grid — and a clean **audience
window** for the projector.

Built with [Tauri 2](https://tauri.app) (Rust + WebKitGTK) and
[pdf.js](https://mozilla.github.io/pdf.js/) (vendored, no network needed).

## Features (core console)

- **Two windows** — presenter console + audience. With a second monitor the
  audience window opens there full screen automatically; `F` toggles it.
- **Speaker notes**, both Beamer flavours:
  - `\setbeameroption{show notes on second screen=right}` double-width PDFs:
    the audience sees the left half, the console shows the right half.
  - Plain PDFs: `\note{…}` text is read from the `.tex` next to the PDF
    (exact page mapping via the sibling `.nav` file when present).
- **.tex opening** — uses the sibling PDF, or compiles via
  `latexmk`/`pdflatex`/`xelatex`/`lualatex`.
- **Blackout** (`B`) — audience shows a quiet pulsing dot and the clock.
- **Overview grid** (`G`), slide counter, wall clock, start/stop/reset timer.
- Drop a PDF or `.tex` **anywhere** on the home screen to open it; recents list.

### Keys

`←`/`→`/`Space` slides · `Home`/`End` first/last · `B` blackout · `G` overview ·
`F` audience full screen · `T` timer start/stop · `R` timer reset

## Building

Prerequisites (once):

```sh
# Debian / Ubuntu
sudo apt install libwebkit2gtk-4.1-dev build-essential curl wget file \
  libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev
# Fedora
sudo dnf install webkit2gtk4.1-devel openssl-devel curl wget file \
  libappindicator-gtk3-devel librsvg2-devel
# Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

Then:

```sh
cd Linux/src-tauri
cargo run            # development
cargo build --release   # → target/release/beamerpresenter
```

No Node/npm needed — the frontend is plain HTML/CSS/JS served from `ui/`,
with pdf.js vendored under `ui/vendor/pdfjs/`.

Optional: `latexmk`/TeX Live for compiling `.tex` files
(`sudo apt install latexmk texlive-latex-extra`).

## Layout

```
Linux/
  ui/                  # frontend (no build step)
    index.html         #   presenter: home screen + console
    audience.html      #   audience window
    css/night.css      #   Night Console theme (mirrors Theme.swift)
    js/slides.js       #   pdf.js wrapper: load, split detection, half rendering
    js/texnotes.js     #   \note{} + .nav parser (port of TexNotes.swift)
    js/presenter.js    #   console logic
    js/audience.js     #   audience logic
    vendor/pdfjs/      #   vendored pdf.js (legacy build)
  src-tauri/           # Rust backend
    src/lib.rs         #   commands: file dialog, read files, compile .tex,
                       #   audience window control (second monitor, fullscreen)
```
