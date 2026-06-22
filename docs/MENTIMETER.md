# Mentimeter integration — design (approved plan)

A way to run a Mentimeter poll (typically at the start of a lecture) from inside
BeamerPresenter: log in, present the poll on the audience screen, then pull the
results back into the app as a file. **Not built yet — this is the agreed plan.**

## Decisions
- **Audience = Variant A (integrated):** Mentimeter's *Present* view runs on the
  real audience/projector screen, not a separate window the user drags around.
- **Results download = next to the deck, with a prompt:** captured exports open a
  save panel pre-pointed at the current deck's folder.
- **Cross-platform:** macOS first, then iPadOS with the same approach.

## Why a web view (no API)
Mentimeter has no open public API for normal accounts (only a PowerPoint add-in
and enterprise integrations). So the integration uses the **official web UI**
inside an embedded `WKWebView` — no scraping or private-endpoint automation.

- **Login (username/password):** the user signs in on the real Mentimeter page
  *inside* the web view. The app never sees the password. The session persists
  via a shared `WKWebsiteDataStore.default()` (cookies survive relaunch).
- **Network:** the app is not sandboxed (it already spawns `Process` for LaTeX),
  so `WKWebView` needs no extra entitlements. (If ever sandboxed: add
  `com.apple.security.network.client`.)

## Architecture

### Shared
- `MentiSession` — owns the shared `WKWebsiteDataStore`/`WKProcessPool` so the
  presenter view and the audience view are the *same* logged-in session.
- `MentiResultsStore` — saves captured downloads and lists recent ones.
- State (PresentationState / iOS PresentationModel): `mentiActive: Bool`,
  `mentiPresentURL: URL?`, plus recent-menti URLs persisted in UserDefaults.

### macOS
- `Mentimeter/WebView.swift` — `NSViewRepresentable` over `WKWebView`, plus a
  `WKDownloadDelegate` for result exports.
- `Mentimeter/MentimeterWindow.swift` — presenter-side window: address/title bar,
  back/forward/reload, a "Present on audience" button, and a "Stop" button.
- `AudienceView.swift` — new branch: when `mentiActive`, show a `WKWebView` at
  `mentiPresentURL` full-bleed (shares the session, so it's logged in).
- `AppDelegate.swift` — menu item **Tools → Mentimeter…**, window management,
  and routing presenter controls (next/prev question) to the audience web view
  via Mentimeter's keyboard navigation.

### iPadOS
- `Mentimeter/WebView.swift` — `UIViewRepresentable` over `WKWebView` (+ download
  delegate).
- A full-screen sheet/cover from the launcher and the presenter toolbar.
- Audience output (external display / mirrored) shows the present view; controls
  stay on the iPad.

## Audience flow (Variant A)
1. Presenter opens the Mentimeter window, logs in, picks a menti, hits *Present*.
2. We capture the *present* URL and set `mentiPresentURL` + `mentiActive`.
3. The audience window swaps from the slide/board to a `WKWebView` on that URL
   (same data store → already authenticated, shows question + join code + live
   results).
4. The presenter advances questions from a small control strip; key events are
   forwarded to the audience web view (Mentimeter supports arrow-key nav).
5. "Stop" returns the audience to the deck.

## Results download (next to the deck, with prompt)
- `WKDownloadDelegate` intercepts the export the user triggers in Menti.
- On finish: an `NSSavePanel` (macOS) / share-or-save sheet (iPad) pre-pointed at
  the current deck's folder; default filename from the download.
- Saved files are also recorded in `MentiResultsStore` for a small
  "Menti results" list (open / reveal in Finder).
- ⚠️ Export availability depends on the user's Mentimeter plan; show a clear
  hint if it isn't offered.

## UI entry points
- macOS menu **Tools → Mentimeter…**; optional "Start with a poll" on the
  welcome screen; recent menti links for quick relaunch.
- iPad: launcher action + presenter-toolbar button.

## Edge cases
- Not logged in / session expired → the web view simply shows the login page.
- Offline → clear error state.
- Plan without export → hint instead of a silent failure.
- Leaving Menti must always restore the normal audience output and black-out.

## Phases
- **P1 — done (macOS):** File → Mentimeter… opens an embedded browser window
  (`Mentimeter/MentiBrowser.swift`, `MentimeterView.swift`) with a persistent,
  shared login session; back/forward/reload/home toolbar; sign in and present
  manually. Audience integration + downloads follow below.
- **P2 — done (macOS):** "Present on audience" pushes the browser's current page
  to the audience screen (`MentiAudienceView`, shared session) and a control strip
  drives it — Previous/Next send arrow-key events into the page (Mentimeter present
  mode listens for them; best-effort, since synthetic keys may need adjusting),
  plus Reload and Stop. The audience window is brought up even before a deck is
  open and restored to the slides on Stop.
- **P3** — download capture (save next to deck) + results list.
- **P4** — quick-launch links, join-code overlay, black-out integration.
- **P5** — iPadOS port.
