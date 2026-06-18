# Night Console — redesign checklist (iPadOS)

Applying the **"Night Console" SwiftUI spec** (v1, 2026): one fixed dark theme,
tactile keys, mono labels, a single electric-lime signal. Reference mock:
`Night Console — BeamerPresenter`.

## Foundation
- [x] **Theme tokens** — `Theme.swift` (surfaces, text ladder, hairlines, accent,
      status, `Color(hex:)`).
- [x] **Typography** — `Font.display/ui/mono` (Space Grotesk · IBM Plex Sans ·
      JetBrains Mono) with system fallback + `.microLabel()`.
- [x] **Signature components** — `KeyButton`, `PrimaryButtonStyle`,
      `GhostButtonStyle`, `LivePill`, `.nightCard()`.
- [x] **Accent** switched app-wide to lime `#C7F24E`; pen inks set to the spec
      hues (red/yellow/green/blue).

## Screens (iPad + macOS)
- [x] **Launcher** — dark identity column, solid-lime primary, ghost secondaries,
      recent card, mono version footer. (macOS: identity rail + library + dashboard.)
- [x] **Presenter console** — toolbar (raised) · body · thumbnail rail (raised).
      Current/next slides on a `stage` mat, notes/scratch on Night surfaces with
      hairline borders, lime resize handles.
- [x] **Toolbar / control bar** — tactile keys (lime when active + glow), mono
      uppercase captions, inset slide-counter well, the solid-lime running-timer
      chip; macOS adds the `LivePill` + hairline group dividers.
- [x] **Thumbnail rail** — `key`-surface thumbs, current = lime 2.5px ring + glow.
- [x] **Overview grid** — Night base, lime ring + glow on the current slide,
      mono numbers, key-surface thumbs (both platforms).
- [x] **Whiteboard** — a shared `BoardStyle` drives the palette: `.dark` (Night
      `stage` + faint dot-grid, light text, dark tables) or `.light` (ink-on-white,
      no grid, light tables). A black/white toggle in the board chrome flips the
      on-screen board (presenter + audience), persisted across launches; the PDF /
      board export always uses `.light` so printed pages stay readable. QR codes
      always sit on a white chip with a quiet zone so they scan on either
      background. Chrome (macOS BoardBar / iPad insert bar) is on Night surfaces.
- [x] **Black-out / audience** — `blackout` fill, blinking "● Audience paused"
      pill, centred Space Grotesk message + mono clock (both platforms).
- [x] **Settings** — system dark form on the Night base with the lime accent.

## Notes
- **Fonts:** the three typefaces (Space Grotesk, IBM Plex Sans, JetBrains Mono,
  SIL OFL) are bundled in `iOS/BeamerPresenter/Fonts/` and `Resources/Fonts/`,
  registered via `UIAppFonts` (iOS) and `ATSApplicationFontsPath = Fonts`
  (macOS, copied by `build-app.sh`). Regenerate the exact static weights with
  `python3 tools/make_fonts.py`. (`swift run` dev builds without the .app bundle
  fall back to system fonts.)
- The chrome never recolours slide content — the deck stays as authored. The
  whiteboard is dark while presenting (presenter + audience) but exports light
  (ink-on-white) so printed/handed-out PDFs stay readable — see `BoardStyle`.
- macOS port of the same spec is a separate effort (shared tokens, AppKit shell).
