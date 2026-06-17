# BeamerPresenter for iPadOS

A native iPad presenter for compiled PDFs (Beamer or any PDF). This is the
**minimal app** — see `CHECKLIST.md` for the feature roadmap.

> The macOS app stays where it is (repo root / `Sources/`). This folder is a
> standalone SwiftUI iOS app. It is **not** part of the SwiftPM package, so
> `swift build` on macOS is unaffected.

## Requirements
- Xcode 15+, iPadOS 16+ deployment target
- An iPad (works in the Simulator too, minus the external display)

## Build it (Xcode)
1. **File ▸ New ▸ Project… ▸ iOS ▸ App.**
   - Interface: **SwiftUI**, Language: **Swift**, name: `BeamerPresenter`.
2. Delete the generated `ContentView.swift` / `…App.swift`, then **drag the
   files from `iOS/BeamerPresenter/` into the project** (check “Copy items if
   needed” or reference in place).
3. Set the **deployment target to iPadOS 16.0** and the device family to iPad.
4. In **Signing & Capabilities**, pick your team.
5. (Optional) In Info, add the **document type** “PDF” / `com.adobe.pdf` and set
   *Supports opening documents in place* + iCloud/Files access so PDFs open from
   the Files app.
6. Select your iPad (or an iPad Simulator) and **Run**.

## What works now
Open a PDF, present it full-screen, navigate by tapping the left/right edges,
swiping, or the on-screen arrows; jump via the thumbnail strip; draw with the
pen (undo / clear). Recently opened files are listed on the start screen.

Everything else is on the roadmap in `CHECKLIST.md`.
