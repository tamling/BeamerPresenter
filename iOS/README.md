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
Open a PDF, present it full-screen, navigate by tapping the left/right edges,
swiping, or the on-screen arrows; jump via the thumbnail strip; draw with the
pen (undo / clear). Recently opened files are listed on the start screen.

Everything else is on the roadmap in `CHECKLIST.md`.
