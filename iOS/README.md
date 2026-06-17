# BeamerPresenter for iPadOS

A native iPad presenter for compiled PDFs (Beamer or any PDF). This is the
**minimal app** — see `CHECKLIST.md` for the feature roadmap.

> The macOS app stays where it is (repo root / `Sources/`). This folder is a
> standalone SwiftUI iOS app. It is **not** part of the SwiftPM package, so
> `swift build` on macOS is unaffected.

> **Yes, an iOS app needs an Xcode project.** Rather than hand-create one, this
> folder ships an [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec
> (`project.yml`) that generates a ready-to-run `.xcodeproj`.

## Requirements
- Xcode 15+, iPadOS 16+ deployment target
- An iPad (works in the Simulator too, minus the external display)

## Build it — recommended (XcodeGen)
```bash
brew install xcodegen        # once
cd iOS
xcodegen generate            # creates BeamerPresenter.xcodeproj from project.yml
open BeamerPresenter.xcodeproj
```
Then in Xcode: select the **BeamerPresenter** target ▸ **Signing & Capabilities**
▸ pick your **Team**, choose your iPad (or an iPad Simulator), and **Run**.
The Info.plist (PDF document type, Files access, orientations) is generated from
`project.yml`, so re-run `xcodegen generate` whenever files are added.

## Build it — manual (no XcodeGen)
1. **File ▸ New ▸ Project… ▸ iOS ▸ App** — Interface **SwiftUI**, name
   `BeamerPresenter`.
2. Delete the generated `ContentView.swift` / `…App.swift`, then **drag the files
   from `iOS/BeamerPresenter/` into the project**.
3. Deployment target **iPadOS 16.0**, device family **iPad**.
4. **Signing & Capabilities** ▸ pick your team.
5. (Optional) Add the **PDF** document type (`com.adobe.pdf`) and enable
   *Supports opening documents in place* + Files/iCloud access.
6. Select your iPad and **Run**.

## What works now
Tap **Try a sample deck** to present the bundled 6-slide sample immediately, or
open your own PDF (AirDrop/Files/iCloud). The full feature checklist in
`CHECKLIST.md` is now implemented:

- **Navigate** by tapping edges, swiping, the on-screen arrows, the thumbnail
  strip, or an **overview grid**.
- **External display:** plug in USB-C/AirPlay and the audience sees just the
  slide (with ink); the iPad stays the presenter console.
- **Ink** with six colours, three weights, and a **laser pointer** — all
  mirrored to the audience. **Apple Pencil** pressure + palm rejection.
- **Speaker notes:** auto-detected split PDFs *or* `\note{}` from a sibling
  `.tex` (or one you attach).
- **Timer + clock**, **black-out** (message / clock / image), **whiteboard**
  scratch boards (ink, text, table, QR), and **export** to an annotated PDF.
- **Settings** for defaults, and **Bluetooth remote** / keyboard control.
