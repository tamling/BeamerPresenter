# Changelog

## v8.0 — 2026-11-22

**New: AlbumArtworkSaver, a macOS screensaver that turns the covers in your
MP3s into a moving wall.** BeamerPresenter itself is unchanged; this release
adds the screensaver in its own folder, `AlbumArtworkSaver/`.

- It reads the album covers embedded in the MP3s of a music folder you choose
  and shows them as a wall with the same grid, seven animations and timings as
  [lingkuma/AlbumArtwork](https://github.com/lingkuma/AlbumArtwork) (MIT).
- Options: the music folder ("Ordner wählen…" or a typed path), rows (3–12),
  interval (1–10 s) and "Jetzt neu einlesen".
- New MP3s are picked up on the next start; only changed files are re-read
  (a re-tagged cover replaces the old one), and nothing is forgotten after an
  incomplete pass, for instance when the disk is unplugged.
- Built with `./build-saver.sh` (Command Line Tools are enough) or downloaded
  as the `AlbumArtwork-saver` artifact of the "Build Saver" workflow, which
  tests the core, builds a universal bundle and runs it in a test host.
- `AlbumArtworkSaver/README.md` explains installing, Gatekeeper, the first run,
  uninstalling and what to do when the folder cannot be read.

## v7.9 — 2026-11-22

**Design and plan for a companion macOS screensaver, AlbumArtworkSaver.**
BeamerPresenter itself is unchanged; this release only adds the two documents.

- `docs/superpowers/specs/2026-11-22-albumartwork-screensaver-design.md`
  describes a native `.saver` that reads the album covers embedded in the MP3s
  of a local music folder and shows them as a moving wall, modelled on
  [lingkuma/AlbumArtwork](https://github.com/lingkuma/AlbumArtwork) (MIT) — the
  same grid, the same seven animations, the same timings and weights, read
  from its source rather than guessed from its GIF.
- New music is picked up on every start without rescanning everything, and the
  cover cache is never cleared just because the music drive is not mounted.
- It will live in its own folder, `AlbumArtworkSaver/`, with its own package,
  version and changelog, and its own macOS CI workflow.
- Before anything is built, a throwaway spike checks on the real Mac whether
  Apple's sandboxed screen-saver host can read a user-chosen folder at all. If
  it cannot, a small helper app does the reading instead.
- `docs/superpowers/plans/2026-11-22-albumartwork-screensaver.md` breaks the
  build into 13 tasks: the spike, then everything that needs no Apple framework
  — grid, motions, wall engine, ID3 reader, incremental index — as plain Swift
  tested on Linux, then the thin macOS layer, built and checked in CI.

## v7.8 — 2026-11-16

**The control bar no longer breaks apart when the window is made narrow.**

- **Captions were wrapping.** The labels under each tool — `CURSOR`, `TARGET`,
  `RESET`, `ELAPSED` — had no line limit, so the moment the window got too
  narrow to lay the bar out at its natural width, SwiftUI's first move was to
  squeeze them and break them mid-word: `CURSO` over `R`. They now carry
  `lineLimit(1)` and refuse to be compressed horizontally, so they stay one
  line whatever the window does.
- **The bar scrolls instead of clipping.** With the captions held at their full
  width the bar is simply wider than a small window, so it is now a horizontal
  scroll view with `minWidth` pinned to the window — identical at full size,
  scrollable below it. Before, the overflow was taken out of whichever end
  lost: `Exit` disappeared off the left while the right-hand captions wrapped.
- **The Linux bar had the same bug**, in CSS rather than SwiftUI: at 700&nbsp;px
  the page counter `1 / 6` broke into three lines and the deck title was pushed
  out of the bar. Its children now refuse to shrink or wrap, the title
  ellipsises rather than collapsing, and the bar scrolls.

Found on macOS from a screenshot, then reproduced on Linux by driving the real
app at 700×620 — not by reading the stylesheet.

## v7.7 — 2026-11-16

- **The iPad text colours were still the pre-7.0 ones.** macOS had its contrast
  ladder corrected to clear WCAG AA in 7.0; the iPad target kept its own copy of
  `Theme.swift` and never got the fix. Secondary, muted and faint text on iPad
  were all darker than they should have been. Fixed by removing the second copy.
- **Six files no longer exist twice.** `Theme.swift`, `NotesMarkup.swift`,
  `TexNotes.swift`, `NightComponents.swift`, `MentiLinks.swift` and the
  UserDefaults keys now live once, in `Sources/Shared/`, compiled by the macOS
  target through `Package.swift` and by the iPad target through `project.yml`.
  They stay one module rather than a separate library, so nothing had to become
  `public` for the sake of a boundary that buys nothing here.
- The UserDefaults key list is shared too. Those are strings: a key that drifts
  between copies does not fail to build, it silently reads a setting nobody
  wrote.

Files that genuinely differ per platform — the views, the whiteboard, the
Mentimeter browser — are untouched and stay per-target.

## v7.6 — 2026-11-16

The interface now matches the icon.

- **The accent is no longer lime.** Fills — the primary button, the LIVE badge,
  the active tool, the ring on the current thumbnail — take the icon's orange.
- **Text keeps a gold, not the orange.** Against the dark ground the orange only
  reaches about 5:1, which would have undone part of the contrast work in 7.0;
  the gold reaches about 11:1. It is also deliberately lighter than the
  "dependency missing" amber, so a tagline cannot be read as a warning.
- **The home screen leads with the app icon**, centred above the name, tagline
  and pitch. On macOS the icon comes from the running app, so it follows the
  Night/Paper swap rather than pinning one variant into the window.
- Screenshots and the README banner retaken in the new palette.

## v7.5 — 2026-11-16

Presentation only — the app is byte-for-byte 7.4.

- **Rewritten README.** The old one still announced "Version 5.7" and described
  the app as macOS-only, which stopped being true several releases ago. It now
  leads with what the app is for, puts the download first, and names the two
  things it does that other presenter apps do not: the translated twin deck and
  the whiteboard on the projector.
- **New banner** (`docs/banner.png`) built from the app icon and the app's own
  typefaces, so the repository page and the home screen look like the same
  product.
- **All five screenshots retaken** from the current build. The old ones predated
  7.0 and 7.1 and showed neither the lazy thumbnail strip, nor the Paper toggle,
  nor the fixed overview — and still carried the old icon.

## v7.4 — 2026-11-16

- **New app icon: Mina.** Flat and friendly, drawn from a photo — black fur, the
  white bib, her white fleck set off to one side under the nose, amber eyes and
  big ears. Orange ground, with a cream variant for the light appearance.
- `Tools/make_icon.py` now renders every platform from one description: the
  macOS `.iconset`, the Linux bundle icons and the iOS app icon. They had been
  three separate sets, free to drift apart.
- The iOS icon is rendered full-bleed and opaque. It previously had transparent
  corners, which iOS treats as a defect — the system supplies its own mask.

## v7.3 — 2026-11-16

- **The release now carries a macOS app, not just a Linux `.deb`.** A macOS
  runner builds `BeamerPresenter.app` universal (Apple Silicon and Intel) from
  `build-app.sh` and attaches it as `BeamerPresenter-<version>-macOS.zip`.
- That runner is also the first thing ever to type-check the macOS target.
  AppKit, SwiftUI and PDFKit exist nowhere else, so until now every macOS change
  shipped compiled only on whatever machine happened to build it. It now
  compiles on every push that touches `Sources/`, `Package.swift`, `Resources/`
  or `build-app.sh`.
- The app is **ad-hoc signed**: the runner holds no Developer ID. macOS will
  refuse the first launch from Finder — right-click the app and choose *Open*,
  or run `xattr -dr com.apple.quarantine BeamerPresenter.app` once. Build it
  yourself with `./build-app.sh` for a locally signed copy.

## v7.2 — 2026-11-16

Documentation only — the app is byte-for-byte 7.1.

- `docs/AUDIT-2026-11.md` publishes the November audit in full: all 117 confirmed
  findings with evidence and fixes, the 9 that verification refuted, the blind
  spots the completeness critic named, and what each dimension actually read.
  Every finding in it is closed (110 in 7.0, 7 in 7.1); builds up to and
  including 6.3 remain affected and are not patched.

## v7.1 — 2026-11-15

Closes the findings 7.0 left open, so the audit is fully worked through.

### Security

- **The Tauri asset protocol no longer has the run of the disk.** Its configured
  scope was `**`, which meant any file was fetchable from the page. The scope is
  now empty and `slides.js` asks Rust to grant exactly the deck it is about to
  load — the one place both the presenter and the audience window pass through.
  The grant takes the canonical path and only an existing `.pdf`, so a symlink
  cannot widen it. Checked in the running app: a file that was never opened
  answers 403, as does `/etc/hostname`, while the open deck answers 200 and
  renders.
- **Vendored pdf.js moves from 4.10.38 to 6.5.438.** It is the component that
  parses untrusted PDFs, so a two-major-version lag is worth closing. pdf.js 6
  removed `PDFDocumentProxy.destroy()`; the document is now torn down through
  its loading task, which works on both. Verified before the swap: every pdf.js
  call the app makes works on 6.5.438, and all six pages of a test deck render
  to identical pixel checksums on both versions.
- The page count is taken from the pages that actually resolve rather than the
  `/Count` a file declares — one probe for an honest deck, a short binary search
  for a dishonest one. Note that the reported attack did not reproduce: with
  hand-crafted files declaring five million pages, flat and nested, both pdf.js
  versions already reported the real count. The check is kept as cheap
  defence-in-depth that does not depend on pdf.js's behaviour here.

### iPad

- Speaker notes picked by hand landed on the wrong slides in a deck built with
  overlays. The file picker grants access one file at a time, so the `.nav`
  beside the chosen `.tex` could not be read and every frame collapsed onto a
  single page. The picker now takes both files at once, each scoped separately,
  and the pane says which file the notes came from — with a warning when they
  were placed without a `.nav`. Notes can also be replaced or cleared without
  reopening the deck, and picking a `.tex` that holds no `\note{…}` now says so
  instead of appearing to do nothing.

### Build and CI

- `.github/dependabot.yml` keeps the action SHA pins and the Cargo dependencies
  under monthly review, so pinning does not turn into rot.
- `Linux/ui/vendor/pdfjs/VERSION` records the package, version, build flavour,
  tarball URL and both SHA-256 sums machine-readably, and
  `Tools/update-pdfjs.sh` either verifies the working tree against it or fetches
  another release and rewrites it.

## v7.0 — 2026-11-15

A security and robustness release. An audit of all three platforms produced 117
confirmed findings — each one checked by three independent reviewers before it
was accepted — and this release closes 110 of them. Major version because
several changes are deliberately breaking: see **Breaking** below.

### Security

- **Opening an untrusted `.tex` could run arbitrary code.** `latexmk` was
  started with the deck's own folder as its working directory and without
  `-norc`, and it evaluates a `latexmkrc` found there as Perl. A downloaded talk
  that shipped `talk.tex` alongside a `latexmkrc` therefore ran that file's code
  on open, with no prompt. latexmk now starts in an empty scratch folder, takes
  `-norc` as its first argument and `-cd`s into the deck only for the compile.
  Your own `~/.latexmkrc` is restored explicitly, so your setup keeps working.
  Fixed on macOS and in the Linux port.
- `shell_escape`, `openin_any` and `openout_any` are pinned in the child
  environment, which also binds the engines latexmk spawns — a
  `-no-shell-escape` argument never reaches those. A crafted deck can no longer
  read dot files or write outside its own folder.
- Deck paths are anchored, so a file named like a command-line option cannot
  pose as one, and latexmk refuses paths containing `$` or `` ` ``.
- The `.pptx` reader no longer extracts an untrusted archive without limits,
  leaves its temp tree behind when extraction fails, or deadlocks the main
  thread on pipes it never drained. Its XML scans no longer backtrack
  quadratically over unclosed tags.
- `.tex` and `.nav` sources are size-capped, and a crafted `.nav` frame range no
  longer spins the main thread.
- Linux: both WebViews get a real Content-Security-Policy instead of none, and
  `read_text` is restricted to `.tex`/`.nav` instead of being a
  whole-filesystem read reachable from the page.
- Compile and conversion children now have a deadline and a bounded log, and on
  Linux they lead their own process group so a timeout reaches what they spawned.

### Breaking

- **A deck's own `latexmkrc` is no longer run.** Decks that relied on one (for
  `$pdf_mode`, a custom `$bibtex`, extra dependencies) now build without it; the
  failure log says so. Compile such a deck in a terminal and open the PDF.
- **⌘Z now undoes typing, not ink.** There is a proper Edit menu at last, so
  Undo/Redo/Cut/Copy/Paste/Select All work in every text field. Undoing a pen
  stroke moves to ⌥⌘Z, and Clear Ink gains ⇧⌘K.
- **← and → move the caret in text fields** instead of changing the slide. Page
  Up/Page Down still drive the deck, so clickers are unaffected, and esc leaves
  the field.
- **The iPhone remote's pairing protocol changed and is not compatible with
  older builds.** The code is no longer sent over the network: the presenter
  advertises a nonce, both sides prove they know the code, only one remote is
  admitted at a time, the code is re-rolled after a disconnect and after five
  rejected attempts, and the deck filename is no longer broadcast in discovery.
  State from a peer is validated instead of trusted.
- "Start with a black audience screen" now also applies to a resumed deck.
- **Keep screen awake now defaults to on** on iPad.

### macOS

- The projector is identified as the external (non-built-in) display instead of
  being assumed to be `screens[1]`, which inverted console and projector on many
  arrangements. Screen changes no longer re-centre a window you moved.
- Presenter keys act only while the console or the projector is frontmost, so
  typing in Settings, the Mentimeter browser or a save panel no longer drives
  the projector.
- "Save Presentation As…" and "Insert into PDF (Copy)…" refused nothing and
  would happily write over the deck PDFKit was still reading from, corrupting it
  while reporting success. Both now refuse by file identity (symlinks and hard
  links included).
- A failed rebuild no longer passes a stale sibling PDF off as its own output,
  and opening a `.tex`/`.pptx` whose PDF is older now asks instead of silently
  presenting the old build.
- A notes file the app cannot read is never deleted; clearing moves it to the
  Trash, and an existing file is backed up before being written over.
- A manually chosen translated deck is page-count checked, as the auto-detected
  one already was, so the console cannot sit on a stale slide.
- New Window menu; the audience window can be brought back instead of being lost
  for the session, and no longer projects window buttons over the slide.
- Text colours re-spaced for WCAG AA, thumbnails are keyboard-reachable, and
  VoiceOver reports on/off state for the control-bar toggles.
- Mentimeter exports download beside the target and replace it only once
  complete, so an interrupted export cannot destroy the previous file.

### iPad

- **The external display never worked at all**: the audience window was a
  scene-less `UIWindow` in a `WindowGroup` app. It is now hosted in the
  `UIWindowScene` iOS creates for the external screen.
- Decks reopen at the slide you left off, per deck.
- The slide strip builds only visible thumbnails, so long decks open without a
  multi-second freeze; the overview grid renders at its own size instead of
  upscaling the strip's bitmaps.
- Export & Share writes into Documents (visible in Files) instead of the temp
  directory, never overwrites an existing file, and no longer marks annotations
  saved before the share sheet has answered.
- The Mentimeter browser shows the page's real host, with a warning when it is
  not mentimeter.com.

### Linux

- The Content-Security-Policy added here forbids inline script, so the three
  inline blocks the pages carried moved into their own files — including the one
  that loads pdf.js. Verified end to end: a deck parses and renders under the
  shipped CSP with no violations.
- Thumbnails and the overview grid render on scroll and release off-screen
  bitmaps instead of rendering every page up front; the overview no longer stays
  blank for every deck after the first.
- Closing or switching a deck frees the previous pdf.js document and its worker
  instead of leaking one per deck.
- Rapid navigation, toggling the twin deck and toggling blackout no longer leave
  the projector blank or the console out of step.

### Build and CI

- Every third-party GitHub Action is pinned to a full commit SHA.
- `.deb` builds use `--locked`, and a pushed `v*` tag that disagrees with the
  version in `Cargo.toml` fails the workflow instead of publishing over the
  matching release.
- `build-app.sh` no longer hides a codesign failure or silently drops the
  hardened runtime, and `Tools/make-signing-cert.sh` imports the key as
  non-extractable.

### Known gaps

- The Tauri asset-protocol scope is still `**`. Narrowing it needs per-deck
  runtime grants on the load path; with the new CSP in place this is
  defence-in-depth, and it is tracked for the next release.
- Five further findings are deferred, each with its reason recorded: a
  page-count DoS in the Linux strip and overview build loops (both available
  fixes would have regressed working behaviour); notes picked by hand for an
  overlay deck on iOS, which needs changes spread across files this pass did not
  own; a pdf.js version bump, declined as scope creep since the vendored 4.10.38
  post-dates the CVE it was raised for; and two new files — a Dependabot config
  for the action pins and a declarative pdf.js VERSION file, whose content is
  recorded in Linux/README.md in the meantime.

## v6.3 — 2026-10-31

- **Fixed a macOS-hostile case collision**: the repo carried both `Tools/` and
  `tools/`, which merge into one folder on case-insensitive filesystems (the
  default on macOS) and can break checkouts and ZIP extraction.
  `make_fonts.py` moved into `Tools/`; a stale `__pycache__` is gone and
  Python caches are now ignored.
- `build-app.sh` checks that `Package.swift`, `Sources/` and `Info.plist` are
  present and explains how to get a clean copy, instead of failing with
  SwiftPM's "package manifest cannot be accessed".

## v6.2 — 2026-10-31

- **Unified window look** (macOS): the grey system title bar is gone — the
  console, home screen and audience window run all the way to the window's
  top edge, with the traffic lights floating over the content the way Safari,
  Vivaldi and the Claude app do. Views keep that corner clear (and reclaim
  the room in full screen, where macOS hides the lights); the window
  background matches the Night Console base so resizing never flashes grey.

## v6.1 — 2026-10-21

- **Thumbnail-strip zoom as smooth as a window resize** (macOS + Linux):
  - the drag handles now track the pointer in window coordinates — the
    handle moves with the pane it resizes, so the old local measurement fed
    back on itself and made the drag stutter (all console dividers, iOS too);
  - mid-drag the strip height lives in view state and is saved once on
    release (no preference write per pixel), with no implicit animation and
    no blur filter on every thumbnail; only visible thumbnails are laid out;
  - the slide views no longer force a re-scale pass on every update (macOS);
  - Linux: at most one update per frame, one CSS variable drives all
    thumbnails, and the current slide is scaled live to its shrinking pane
    (also while resizing the window) and re-rendered crisp on release.
- **Home screen** (macOS): the logo tile above the app name is gone — the
  name leads the sidebar now — and the LaTeX / LibreOffice status moved from
  the sidebar into the bottom bar, between the stats and the version.
  While favourites or recents are still empty, the free space shows a
  keyboard-shortcuts card for the presenter console.

## v6.0 — 2026-10-21

- **Paper — a light appearance** (macOS, iOS, Linux): Settings → Appearance
  on macOS and iOS (on iOS it applies when Settings closes), the Paper/Night
  button on the Linux home screen and console bar.
  Silver-grey surfaces, the same lime signal (as fills; lime text becomes a
  dark olive so it stays readable), and darker status colours. Night stays
  the default. The audience screen, the slides and the Night whiteboard are
  unchanged.
- **Dock icon follows the appearance** (macOS): with Paper the running app
  shows a silver icon (`Resources/AppIconLight.png`, rendered by
  `Tools/make_icon.py`). Finder keeps the bundled Night icon.
- **Markdown-style speaker notes** (macOS, iOS, Linux): `# heading`, `- item`,
  `**bold**`, `*italic*`, `` `code` ``, `> question` and `[text](url)` in
  `\note{…}` are highlighted like a code editor does: the markup characters
  stay visible in red-orange, the content gets its weight. Notes use
  JetBrains Mono.
- The app icon on iOS stays the Night icon (alternate icons not set up).

## v5.7 — 2026-10-21

- **Home-screen cards scale with the window** (macOS): when fewer
  favourites/recents exist than would fit, the cards grow (up to 118 pt per
  row) so large windows no longer leave dead space below the lists.

## v5.6 — 2026-10-21

- **Dynamic home-screen lists** (macOS): favourites and recents show as many
  entries as the window height allows (split between the two sections, spare
  slots handed to the fuller one) — no scroll bar; enlarging the window
  reveals more.

## v5.5 — 2026-10-21

- **No scroll bar on the home screen** (macOS): instead of scrolling, the
  right column shows at most 3 favourite folders and 3 recent files (with a
  "+ N more" hint), so everything always fits the window.

## v5.4 — 2026-10-21

- **New, modern app icon** (macOS + Linux, one shared renderer): a dark
  squircle with a glowing lime-gradient play mark over a progress bar with a
  lit playhead — "presenting, live".
- **Home screen layout fixed** (macOS): with many favourites/recents the
  right column overflowed and cut everything off. The drop zone now sits in
  the left column between the Open button and the tip (drops still land
  anywhere on the window), and favourites + recents scroll.

## v5.3 — 2026-10-20

macOS file-opening fixes.

- **Dock & Finder opening works**: dropping a PDF on the Dock icon (or
  "Open With" in Finder) no longer errors — the missing
  `application(_:open:)` handler is implemented, with buffering for files
  handed over before launch finishes. PowerPoint/ODP document types are now
  declared too.
- **Drop truly anywhere**: an AppKit-level drop catcher wraps the presenter
  window, so files land no matter where on the window they're dropped (even
  over buttons and lists — and now also while a presentation is open, with
  the usual save check).

## v5.2 — 2026-10-19

- Fix the macOS build of v5.0/v5.1: `SlideView.swift` references
  `PDFDocument` since the twin-deck feature but was missing
  `import PDFKit`.

## v5.1 — 2026-10-19

- **Screenshots refreshed** to show the translated twin deck in action: the
  console screenshot now presents the Norwegian sample deck with its English
  twin in the current/next panes (captured from a real headless run of the
  Linux UI, which also exercises the twin-deck detection end to end).

## v5.0 — 2026-10-19

**Translated twin deck** (macOS + Linux): present localized slides while
reading the translation.

- A language-suffixed sibling with the same page count (`talk-no.pdf` ↔
  `talk-en.pdf`, also `_en`/`.en`, or `talk.pdf` + `talk-en.pdf`) is detected
  automatically on open; "en" is preferred.
- The audience always sees the primary deck; the console's current + next
  slide switch to the translation. Toggle with `E`, the Transl key in the
  control bar, or the Presentation menu; a twin can also be picked manually
  (macOS: Presentation ▸ Open Translated Deck…).
- Ink, laser, notes, thumbnails and the overview keep working on the primary
  deck as before.

## v4.15 — 2026-10-05

- **Smooth pulsing dot again**: the blackout screen's status dot is now driven
  by a time-based `TimelineView` animation (macOS + iPadOS) — the old
  `repeatForever` animation stuttered whenever the clock re-rendered the view.
- **Natural thumbnail zoom**: while dragging the strip handle the bitmaps are
  only scaled, with a slight blur as a cue; the crisp PDF re-render happens
  once, on release (macOS; Linux already worked this way and gains the same
  blur cue). The strip now owns its zoom handle.
- **No clock screen on resume**: the "start blacked out" default now applies
  only when a deck starts fresh — resuming mid-presentation jumps straight to
  the slide.

## v4.14 — 2026-10-04

- Build warnings fixed: `import Combine` added where `Timer.publish` is used
  (AudienceView, PresenterView); `build-app.sh` defaults to Apple Silicon
  (arm64) only — newer SDKs deprecate x86_64, which stays available via
  `ARCHS="arm64 x86_64"`.

## v4.13 — 2026-10-04

- **Fix for the recurring folder-access prompts on macOS**: TCC remembers the
  "Allow" per code signature, and unsigned/ad-hoc builds change identity on
  every rebuild. `Tools/make-signing-cert.sh` creates a stable self-signed
  identity once; `build-app.sh` now auto-detects it (or a real Developer
  ID/Apple Development identity), always signs the bundle, and explains the
  fix when only ad-hoc signing is available.

## v4.12 — 2026-10-04

- **Screenshots in the README** (`docs/screenshots/`): presenter console,
  home screen, whiteboard, audience window and black-out — captured from the
  Linux build (same Night Console design as macOS).

## v4.11 — 2026-10-04

Peer-review fixes (macOS) and Linux feature parity.

- **macOS fixes** from the code review: the thumbnail strip now scrolls to the
  resumed slide on open; a failed load of a second deck no longer leaves
  half-mutated state (and can no longer mis-key saved slide positions); the
  access-bookmark store is capped at 40 most-recently-used entries with proper
  stale/moved-file handling; the thumbnail cache is bounded (NSCache); slide
  positions save only on actual changes and dead entries are pruned at launch;
  strip/overview cells are accessible again (VoiceOver/keyboard); shared
  Prefs key for the strip height.
- **Linux parity**: per-deck resume, the exit dialog (home screen / quit /
  cancel), and a zoomable thumbnail strip at the bottom of the console —
  single-click to jump, drag the handle to zoom, bucketed rendering for a
  fluid drag (same approach as macOS).

## v4.10 — 2026-10-04

- **Fluid thumbnail zoom** (macOS): while dragging the strip handle the
  thumbnails scale smoothly — PDF pages are re-rendered only at 64 pt size
  buckets instead of on every drag pixel, which caused the stutter.
- **Single click opens a slide** (macOS): thumbnail strip and overview grid
  now jump on a single click by default; Settings ▸ Presenter console offers
  a double-click mode instead.

## v4.9 — 2026-10-04

- README refreshed to match the app: v4.1–v4.8 features documented (PowerPoint
  speaker notes, audience-window behaviour, exit choice, resume, zoomable
  thumbnail strip, remembered folder access, Linux `.deb` releases), stale
  defaults corrected, project layout table extended.

## v4.8 — 2026-10-04

Quality-of-life fixes on macOS.

- **Fewer folder-access prompts**: opened files and favourite folders are
  remembered as bookmarks in a config folder
  (`~/Library/Application Support/BeamerPresenter/`) and access is restored at
  launch, so drag & drop or an app restart no longer re-asks for the same
  folders.
- **Resume per deck**: reopening a presentation continues on the slide you
  left, instead of starting from the first one.
- **Exit choice**: leaving a presentation (Exit key, Close Presentation, ⌘W)
  now asks: back to the home screen, quit the app, or cancel.
- **Zoomable slide strip**: the thumbnail strip at the bottom has a drag
  handle — pull it up for larger, readable thumbnails (size persists).

## v4.7 — 2026-08-23

- CI now publishes a GitHub **Release** (`v<version>`) with the built `.deb`
  attached on every push to `main` — the package is always downloadable from
  the repo's Releases page.

## v4.6 — 2026-08-22

- `build-deb.sh` checks its prerequisites up front (Rust, dpkg-deb, WebKitGTK
  dev) and prints install instructions instead of failing mid-build.
- **CI**: a GitHub Actions workflow builds the Linux .deb on every push to
  `main` (downloadable under Actions → artifacts) and attaches it to releases
  on `v*` tags — no local toolchain needed to get a package.

## v4.5 — 2026-08-22

- `Linux/build-deb.sh` no longer needs Node: without a Tauri CLI it packages
  the .deb itself via `cargo build --release` + `dpkg-deb` (same contents and
  dependency metadata).

## v4.4 — 2026-08-22

- **Linux home screen**: with more than 3 recent presentations the recents
  switch from rich cards to a compact, scrollable single-line list; up to 10
  recents are kept (was 5).

## v4.3 — 2026-08-22

- **Linux .deb package**: `Linux/build-deb.sh` builds an installable Debian
  package (desktop entry, icons, WebKitGTK/GTK dependencies declared) via the
  Tauri bundler; proper icon sizes generated by `make-icon.py`.

## v4.2 — 2026-08-22

**Whiteboard for Linux** (`W`): free-form scratch boards during a talk, live on
the projector.

- Freehand ink with the four pen colours, smoothed strokes, undo (`Z`) and
  clear (`C`); drawing streams to the audience window in real time.
- Multiple boards (new / previous / next / delete) with a board counter.
- Dark Night-look board with the dot grid, plus a light ink-on-white toggle
  for bright projectors — same styles as the macOS app.
- Blackout still covers the board; `Esc` returns to the slides.

## v4.1 — 2026-08-22

PowerPoint support with speaker notes, on macOS and Linux.

- **Linux**: opens `.pptx`/`.ppt`/`.odp` via headless LibreOffice conversion
  (sibling PDF is reused when present), with a LibreOffice status light on the
  home screen — matching the macOS flow.
- **Both platforms**: PowerPoint **speaker notes now show in the presenter
  console** — read directly from the `.pptx` next to the converted PDF
  (slide order, per-slide notes pages, XML entities all handled; covered by a
  unit test on the Linux side). LibreOffice's PDF only carries the slides, so
  this fills the gap; `.tex` notes take precedence when both exist.

## v4.0 — 2026-08-22

**Linux port** (`Linux/`): the core presenter console as a native Linux app,
built with Tauri 2 (Rust + WebKitGTK) and a vendored pdf.js — no Node needed.

- Two windows: presenter console (current + next slide, notes, clock,
  start/stop/reset timer, overview grid) and a clean audience window that
  moves to a second monitor full screen automatically (`F` toggles).
- Speaker notes in both Beamer flavours: split double-width PDFs
  (`show notes on second screen=right`) and `\note{…}` read from the `.tex`
  (with exact `.nav` page mapping) — same logic as the macOS app.
- Opens `.pdf` and `.tex` (sibling PDF or on-the-fly LaTeX compile), drop
  anywhere on the home screen, recents, blackout (`B`) with the pulsing dot
  and clock, Night Console theme throughout.

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
