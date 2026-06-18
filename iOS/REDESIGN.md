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
- [ ] **Overview grid** — LazyVGrid 5 cols, gap 13, current ringed lime.
- [ ] **Whiteboard** — `stage` canvas with faint dot-grid, lime ink, dark mono
      tables, mini toolbar reusing KeyButton.
- [ ] **Black-out / audience** — `blackout` fill, centred Space Grotesk message +
      mono clock; audience stays chrome-free.
- [ ] **Settings / Remote** — Night surfaces, cards, mono labels.

## Notes
- **Fonts:** `.custom(...)` falls back to system until the three Google fonts
  (`SpaceGrotesk-Bold`, `IBMPlexSans-*`, `JetBrainsMono-*`) `.ttf` are added to
  the target and `UIAppFonts` in Info.plist. Drop the `.ttf`s into
  `iOS/BeamerPresenter/Fonts/` and list them in `project.yml`.
- The chrome never recolours slide content — the deck stays as authored.
- macOS port of the same spec is a separate effort (shared tokens, AppKit shell).
