# BeamerPresenter — project notes for Claude

## Versioning

Every change that lands in `main` bumps the app version:

- **Smaller changes** (bugfixes, behaviour tweaks, UI polish): bump the minor
  version — `3.1` → `3.2`.
- **Larger changes** (new features, redesigns, breaking changes): bump the major
  version — `3.x` → `4.0`.

The version lives in all of these places — keep them in sync:

- `Resources/Info.plist` — `CFBundleShortVersionString` (version) and
  `CFBundleVersion` (build number, increment by 1 on every bump)
- `iOS/project.yml` — `MARKETING_VERSION` / `CFBundleShortVersionString` and
  `CURRENT_PROJECT_VERSION` / `CFBundleVersion`
- Code fallbacks: `Sources/BeamerPresenter/Favorites.swift` (`AppInfo.version`)
  and `iOS/BeamerPresenter/ContentView.swift`

Add a matching entry at the top of `CHANGELOG.md` (`## vX.Y — YYYY-MM-DD`)
describing the change.
