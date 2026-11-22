# AlbumArtwork-Screensaver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein macOS-Screensaver (`AlbumArtwork.saver`), der die in MP3s eingebetteten Cover eines lokalen Musikordners als bewegte Wand zeigt — Gitter und sieben Animationen wie lingkuma/AlbumArtwork.

**Architecture:** Alles ohne Apple-Frameworks — Gitter, Bewegungsformeln, Animationsplanung, Wand-Zustand, ID3-Leser, Index-Abgleich, Statustexte — liegt als reines Swift in `AlbumArtworkCore` und wird auf Linux mit `swift test` getestet. Der macOS-Teil ist dünn: `ScreenSaverView`, ein `CALayer` pro Cover, der jedes Frame die Pose aus dem Core übernimmt, Bild-Cache, Scanner-Rahmen, Optionen-Blatt. `build-saver.sh` kompiliert beides mit `swiftc` als ein Modul zu einem `.saver`; CI baut und testet auf `macos-latest`.

**Tech Stack:** Swift im Sprachmodus 5 (lokal Compiler 6.0.3 auf Linux), XCTest, ScreenSaver.framework, AppKit, QuartzCore, ImageIO, GitHub Actions, Python 3 (nur Standardbibliothek) für Test-Fixtures.

**Spec:** `docs/superpowers/specs/2026-11-22-albumartwork-screensaver-design.md`

## Global Constraints

- Ort `AlbumArtworkSaver/` im BeamerPresenter-Repo, eigenes `Package.swift`, README, `CHANGELOG.md`, Saver-Version 1.0.
- Bundle-ID `app.beamerpresenter.AlbumArtworkSaver`, Produkt `AlbumArtwork.saver`, Prinzipalklasse `@objc(AlbumArtworkView)`.
- Nur `.mp3` (Endung ohne Groß/Klein). Musikordner strikt nur lesend.
- Keine WebView, kein SceneKit; Core Animation.
- Bauen ohne Xcode: Command Line Tools + `build-saver.sh`, ad-hoc `codesign --sign -`. `MACOS_MIN` Standard `14.0` bis Task 1 die Version des Mac mini liefert; `ARCHS` Standard `$(uname -m)`.
- `AlbumArtworkCore` importiert nur `Foundation`. macOS-Dateien schreiben **kein** `import AlbumArtworkCore`: `build-saver.sh` kompiliert Core + Saver als ein Modul (wie BeamerPresenters `Shared/`), Typen bleiben `internal`; Tests nutzen `@testable import AlbumArtworkCore`.
- Welt-Einheiten: Bildschirmhöhe = 20; Kameraabstand d = 10 / tan(22,5°) ≈ 24,1421; Punkte pro Einheit = Bildhöhe in Punkten / 20; `m34 = −1 / (d × Punkte pro Einheit)`.
- Werte: 6 Reihen (3–12), kein Abstand, Intervall 3 s (1–10 s) + Zufall 0–1 s, einmal pro Start gewürfelt; Gewichte Flip 15, Fallen 15, Rollen 15, Abrollen 15, Nadel 15, Reihe rollt ab 12,5, Reihe fällt 12,5; 3–6 Cover je Takt, 200 ms versetzt.
- Cache `Caches/app.beamerpresenter.AlbumArtworkSaver/` (im Sandbox-Container aufgelöst): `index.json`, `covers/<AlbumID>.jpg` (quadratisch, Kante 640 px, JPEG-Qualität 0,85, nie hochskaliert), `scan.lock`.
- UI-Texte deutsch; wörtlich aus der Spec: „Musikordner in den Screensaver-Optionen wählen“, „Jetzt neu einlesen“, Statusformat „1.234 Alben · zuletzt eingelesen vor 2 Std.“.
- Logging per `os_log`, Subsystem = Bundle-ID, Kategorien `scan` und `wall`.
- Referenz-Quelltext: `git clone https://github.com/lingkuma/AlbumArtwork && git -C AlbumArtwork checkout e1b421c`, Datei `index.html`. Zeilenangaben unten beziehen sich darauf. Formeln 1:1 übernehmen, Zeiten in Sekunden.

## Review Focus

1. **Musikordner nicht erreichbar** (Platte nicht eingehängt, NAS schläft, Freigabe abgelaufen): Cache und Wand bleiben, Status sagt es. → Task 4 `testFinishIncompleteRemovesNothing`, Task 11 Scan-Test Schritt 6, Task 12 `testStatusUnavailable`.
2. **Kaputte oder ungewöhnliche Tags** (abgeschnitten, Größenangabe jenseits des Dateiendes, Link-MIME `-->`, mehrere Bilder, UTF-16 ohne BOM, gar kein Tag): kein Absturz, Datei wird übersprungen und nicht bei jedem Start neu gelesen. → Task 3 Randfall- und Zufallstests, Task 4 `testRecordWithoutPictureIsRemembered`, Task 11 Fixture `broken.mp3`.
3. **Winzige Sammlung** (1–10 Alben, weniger als Felder): Wand ist trotzdem voll, keine Endlosschleife beim Meiden sichtbarer Alben. → Task 7 `testSingleAlbumPool`, Task 8 `testLongRunSingleAlbum`.
4. **Ungewöhnliche Bildschirmformate** (Vorschau 296×184, Hochformat, 32:9, Reihen außerhalb 3–12): Gitter füllt, keine Division durch null. → Task 2 `testOddScreens`.
5. **Mehrere Instanzen gleichzeitig** (zwei Bildschirme + Vorschau): höchstens ein Scan schreibt, `index.json` bleibt gültig. → Task 11 Scan-Test Schritt 7.

## Reihenfolge

Task 1 braucht den Mac mini und den Nutzer. Tasks 2–8 laufen nur auf Linux und hängen nicht vom Spike ab; sie dürfen zuerst laufen, solange der Mac mini nicht verbunden ist. **Tasks 9–13 erst nach Task 1.** Scheitert der Spike, gilt Weg B (Abschnitt am Ende): dann vor Task 9 einen Plan-Nachtrag schreiben.

## Dateistruktur

```
AlbumArtworkSaver/
  Package.swift                   Core-Bibliothek + Tests
  build-saver.sh                  → build/AlbumArtwork.saver, build/TestHost
  README.md, CHANGELOG.md
  Resources/Info.plist
  Scripts/load-saver.swift        CI: Bundle laden, Prinzipalklasse prüfen
  Scripts/make-fixtures.py        Testbilder (images) und Test-MP3s (mp3)
  Scripts/scan-test.sh            CI: Scanner Ende-zu-Ende
  Sources/AlbumArtworkCore/
    GridLayout.swift  SplitMix64.swift  ID3Reader.swift  Fingerprint.swift
    AlbumKey.swift  LibraryIndex.swift  ScanPlanner.swift  Easing.swift
    CoverPose.swift  Motions.swift  GridTargets.swift  AnimationPlanner.swift
    AlbumPicker.swift  WallEngine.swift  StatusText.swift
  Sources/AlbumArtworkSaver/      (nur macOS)
    AlbumArtworkView.swift  CoverWall.swift  CoverImageStore.swift
    TagFileReader.swift  CoverImageProcessor.swift  CoverCache.swift
    LibraryScanner.swift  LibraryService.swift
    SaverSettings.swift  FolderAccess.swift  OptionsSheet.swift
  Sources/TestHost/main.swift     Fenster-App + Kommandozeilen-Modi
  Tests/AlbumArtworkCoreTests/    eine Testdatei je Core-Datei + ID3Builder.swift
.github/workflows/build-saver.yml
```

---

### Task 1: Spike — Ordnerzugriff im echten Screensaver (Prüfpunkt 1)

**Files:**
- Wegwerf, nur im Checkout auf dem Mac mini, nicht committen: `AlbumArtworkSaver/Spike/SpikeView.swift`, `Spike/Info.plist`, `Spike/build-spike.sh`
- Modify: `docs/superpowers/specs/2026-11-22-albumartwork-screensaver-design.md` (neuer Abschnitt „Spike-Ergebnis“)

**Interfaces:**
- Produces: Abschnitt „Spike-Ergebnis“ in der Spec mit macOS-Version, Chip, Lage des Musikordners (intern/extern/Netz), Prüfungen 1–6 je ja/nein, funktionierendes Link-Flag für Bundles, Mechanismus `panel+bookmark` | `path` | `B`. Tasks 9–13 lesen `MACOS_MIN`, Link-Flag und Mechanismus daraus.

- [ ] **Step 1: Mac mini verbinden.** `list_computer_folders`, dann `request_computer_folder` für den BeamerPresenter-Checkout. Auf dem Mac mini (`_host`): `sw_vers; uname -m; xcode-select -p`, Branch `claude/determined-mayer-ap4ix8` holen. Nutzer nach dem Pfad des Musikordners fragen; `df -h "<pfad>"` zeigt die Lage.
- [ ] **Step 2: Spike schreiben** (per `_host` direkt in den Checkout). `@objc(AlbumArtworkSpikeView) final class SpikeView: ScreenSaverView`, Bundle-ID `app.beamerpresenter.AlbumArtworkSpike`.
  - `configureSheet`: „Ordner wählen…“ (`NSOpenPanel`, nur Ordner), Pfadfeld + „Pfad übernehmen“, „Fertig“. Bei Wahl: Bookmark mit `.withSecurityScope` anlegen (scheitert das: ohne Option, Fehler loggen); Bookmark und Pfad in `ScreenSaverDefaults(forModuleWithName:)`.
  - `startAnimation` führt aus, schreibt jede Zeile groß auf den Bildschirm und per `os_log` (Subsystem `app.beamerpresenter.AlbumArtworkSpike`): Kopf = `operatingSystemVersionString` + `NSHomeDirectory()`; **B** = Bookmark auflösen, `startAccessingSecurityScopedResource()`, rekursiv `.mp3` zählen, erste 64 KB der ersten MP3 lesen, beginnt mit `ID3`?; **P** = gespeicherten Pfad ohne Bookmark rekursiv lesen, `.mp3` zählen; **C** = Datei in `Caches/app.beamerpresenter.AlbumArtworkSpike/` schreiben und zurücklesen.
  - `build-spike.sh`: `swiftc -swift-version 5 -O -target <arch>-apple-macos<version> -emit-executable -Xclang-linker -bundle … -framework ScreenSaver -framework AppKit`, Bundle zusammensetzen, `codesign --force --sign -`.
- [ ] **Step 3: Bauen.** Run: `./build-spike.sh && file build/AlbumArtworkSpike.saver/Contents/MacOS/AlbumArtworkSpike`. Expected: `Mach-O 64-bit bundle`. Sonst nacheinander `-Xlinker -bundle`, dann `-emit-library` probieren; das erste funktionierende Flag notieren.
- [ ] **Step 4: Prüfpunkt 1a (Nutzer).** Dem Nutzer schreiben: `.saver` doppelklicken, in den Systemeinstellungen „AlbumArtworkSpike“ wählen, Optionen → „Ordner wählen…“ → Musikordner → „Fertig“; melden, ob das Auswahlfenster aufging.
- [ ] **Step 5: Ausführen.** Run: `open -a ScreenSaverEngine; sleep 8; log show --last 2m --predicate 'subsystem == "app.beamerpresenter.AlbumArtworkSpike"'`, dann `killall legacyScreenSaver` und dasselbe nochmal. Expected: Ergebniszeilen B, P, C; Nutzer bestätigt den Bildschirmtext.
- [ ] **Step 6: Prüfpunkt 1b (Nutzer).** Nutzer startet den Mac mini neu; neu verbinden, Step 5 wiederholen (Prüfung 6).
- [ ] **Step 7: Entscheiden.** Regel aus Spec §7: Weg A, wenn der echte Ordner nach dem Neustart lesbar ist — `panel+bookmark`, wenn B ja; sonst `path`, wenn P nach dem Neustart ja; sonst `B`. Abschnitt „Spike-Ergebnis“ schreiben, Spike-Ordner auf dem Mac mini löschen.
- [ ] **Step 8: Commit**

```bash
git add docs/superpowers/specs/2026-11-22-albumartwork-screensaver-design.md
git commit -m "Record the screensaver folder-access spike result"
```

### Task 2: Core-Paket, Gitter, Zufall, CI

**Files:**
- Create: `AlbumArtworkSaver/Package.swift`, `Sources/AlbumArtworkCore/GridLayout.swift`, `Sources/AlbumArtworkCore/SplitMix64.swift`, `Tests/AlbumArtworkCoreTests/GridLayoutTests.swift`, `Tests/AlbumArtworkCoreTests/SplitMix64Tests.swift`, `.github/workflows/build-saver.yml`

**Interfaces:**
- Produces:
  - `struct GridCell: Hashable, Codable { var row: Int; var col: Int }`
  - `struct Point2: Equatable { var x: Double; var y: Double }`
  - `struct GridLayout: Equatable` — `static let worldHeight = 20.0`, `static let cameraDistance: Double`, `init(rows: Int, aspect: Double)` (rows auf 3…12, aspect auf ≥ 0,1 geklemmt), `let rows: Int`, `let aspect: Double`, `var coverSize: Double`, `var columns: Int`, `var cellCount: Int`, `var allCells: [GridCell]` (zeilenweise), `func center(of: GridCell) -> Point2`, `func contains(_: GridCell) -> Bool`, `var bottomEdge: Double` (= −10)
  - `struct SplitMix64: RandomNumberGenerator { init(seed: UInt64) }`

- [ ] **Step 1: Failing tests**

```swift
func testSixRowsSixteenByNine() {
    let g = GridLayout(rows: 6, aspect: 16.0 / 9.0)
    XCTAssertEqual(g.coverSize, 20.0 / 6, accuracy: 1e-9)
    XCTAssertEqual(g.columns, 11); XCTAssertEqual(g.cellCount, 66)
    XCTAssertEqual(g.center(of: GridCell(row: 0, col: 0)).x, -16.666667, accuracy: 1e-5)
    XCTAssertEqual(g.center(of: GridCell(row: 0, col: 0)).y, 8.333333, accuracy: 1e-5)
    XCTAssertEqual(g.center(of: GridCell(row: 5, col: 10)).x, 16.666667, accuracy: 1e-5)
    XCTAssertEqual(g.center(of: GridCell(row: 5, col: 10)).y, -8.333333, accuracy: 1e-5)
}
func testCameraDistance() { XCTAssertEqual(GridLayout.cameraDistance, 24.142136, accuracy: 1e-5) }
func testOddScreens() {   // Review Focus 4
    XCTAssertEqual(GridLayout(rows: 6, aspect: 296.0 / 184.0).columns, 10)
    XCTAssertEqual(GridLayout(rows: 6, aspect: 9.0 / 16.0).columns, 4)
    XCTAssertEqual(GridLayout(rows: 6, aspect: 32.0 / 9.0).columns, 22)
    XCTAssertEqual(GridLayout(rows: 1, aspect: 1.5).rows, 3)
    XCTAssertEqual(GridLayout(rows: 40, aspect: 1.5).rows, 12)
    XCTAssertEqual(GridLayout(rows: 6, aspect: 0).columns, 1)
}
func testSplitMixSeedZero() { var r = SplitMix64(seed: 0); XCTAssertEqual(r.next(), 0xE220A8397B1DCDAF) }
```

- [ ] **Step 2: Run** `cd AlbumArtworkSaver && swift test` — Expected: FAIL (Typen fehlen).
- [ ] **Step 3: Implementieren.** `Package.swift`: tools 5.9, `platforms: [.macOS(.v13)]`, Library-Target `AlbumArtworkCore`, Test-Target. Gitter wie Original Z. 3764–3789 mit Abstand 0: `coverSize = 20 / rows`, `columns = ceil(20·aspect / coverSize)`, Mitte x = −columns·size/2 + (col + 0,5)·size, y = 10 − (row + 0,5)·size. SplitMix64: Standardalgorithmus (Inkrement `0x9E3779B97F4A7C15`, Mischer `0xBF58476D1CE4E5B9` / `0x94D049BB133111EB`, Shifts 30/27/31).
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: CI-Workflow.** `build-saver.yml`: Trigger `push` auf `main` und `claude/**` mit `paths: [AlbumArtworkSaver/**, .github/workflows/build-saver.yml]`, dazu `workflow_dispatch`; `permissions: contents: read`; Job `macos` auf `macos-latest`: `actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0`, `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, `swift --version`, `cd AlbumArtworkSaver && swift test`. (Linux-Tests laufen lokal in der Claude-Sitzung.)
- [ ] **Step 6: Commit, push, CI prüfen.**

```bash
git add AlbumArtworkSaver .github/workflows/build-saver.yml
git commit -m "AlbumArtworkSaver: core package, grid layout, seeded random, CI"
git push
```
Expected (GitHub-MCP `actions_list` für `build-saver.yml`): Lauf grün.

### Task 3: ID3-Leser

**Files:**
- Create: `Sources/AlbumArtworkCore/ID3Reader.swift`, `Tests/AlbumArtworkCoreTests/ID3Builder.swift`, `Tests/AlbumArtworkCoreTests/ID3ReaderTests.swift`

**Interfaces:**
- Produces: `struct TrackTags: Equatable { var album: String?; var albumArtist: String?; var artist: String?; var picture: Data?; var pictureMIME: String? }`; `enum ID3Reader { static let headerLength = 10; static func tagLength(header: Data) -> Int?; static func parse(_ tag: Data) -> TrackTags? }`
- Test-Helfer (nur Tests): `struct ID3Builder { init(version: UInt8); var unsynchronised: Bool; var extendedHeader: Bool; mutating func text(_ id: String, _ value: String, encoding: UInt8); mutating func picture(type: UInt8, mime: String, description: String, data: Data, encoding: UInt8); mutating func rawFrame(id: String, flags: [UInt8], body: Data, sizeOverride: UInt32?); func build() -> Data }` — schreibt Größen je Version (2.2: 3 Byte, 2.3: 4 Byte normal, 2.4: sync-safe), bei `unsynchronised` fügt es nach jedem `FF` ein `00` ein.

Regeln (Entscheidungen für die Implementierung):
- Nur Versionen 2, 3, 4; sonst `nil`. `tagLength` = sync-safe Größe + 10, +10 bei 2.4-Footer-Flag `0x10`; Größenbyte ≥ `0x80` → `nil`.
- Header-Flag `0x80`: bei 2.2/2.3 ganzen Rumpf ent-synchronisieren (`FF 00` → `FF`), bei 2.4 jeden Frame-Inhalt. Erweiterter Header (`0x40`): 2.3 überspringe 4 + Größe, 2.4 überspringe sync-safe Größe; bei 2.2 bedeutet `0x40` Kompression → `nil`.
- Frames: Ende bei ID-Byte `0x00` oder Größe > Rest. 2.3: überspringen bei Flags[1] & `0x80` oder `0x40`; 2.4: bei `0x08` oder `0x04`; 2.4 `0x02` → Frame ent-synchronisieren, `0x01` → erste 4 Byte weg.
- Texte: `TALB`/`TAL` → album, `TPE2`/`TP2` → albumArtist, `TPE1`/`TP1` → artist. Kodierung 0 = ISO-8859-1, 1 = UTF-16 mit BOM (ohne BOM: little-endian), 2 = UTF-16BE, 3 = UTF-8. Erster Wert bis zum Terminator, getrimmt, leer → `nil`.
- `APIC`: Kodierung, MIME (Latin-1, null-terminiert), Bildtyp, Beschreibung (Terminator `00` bzw. `00 00` an gerader Position bei Kodierung 1/2), Rest = Bild. `PIC`: Kodierung, 3 Zeichen Format (`JPG` → `image/jpeg`, `PNG` → `image/png`), Typ, Beschreibung, Bild.
- Erstes Bild mit Typ 3, sonst das erste; MIME `-->` und leere Bilder auslassen. `parse` gibt nur bei ungültigem Header `nil`, sonst `TrackTags` (Felder evtl. leer).

- [ ] **Step 1: Failing tests** (`ID3ReaderTests`):
  - `testV23TextAndFrontCover` — album `"Blue Train"`, artist `"John Coltrane"`, picture == eingebettete Bytes, MIME `"image/jpeg"`
  - `testV24UTF8AndSyncSafeSizes` — album `"Ångström"`, Bild 300 Byte
  - `testV22Frames` — `TAL`/`TP1`/`TP2`/`PIC "PNG"` → MIME `"image/png"`
  - `testUTF16Variants` — Kodierung 1 mit `FF FE` und `FE FF`, Kodierung 1 ohne BOM (LE), Kodierung 2 → jeweils `"Kind of Blue"`
  - `testFrontCoverPreferred` — Typ 0 zuerst, Typ 3 danach → Daten des zweiten
  - `testLinkPictureIgnored` — MIME `"-->"` → `picture == nil`
  - `testTagUnsynchronisation` — 2.3, Flag `0x80`, Bild enthält `FF E0` → gelesenes Bild == Original
  - `testV24DataLengthIndicator`, `testExtendedHeaders` (2.3 und 2.4), `testCompressedFrameSkipped` (übrige Frames gelesen)
  - `testTruncatedTag` — gebauten Tag halbieren → kein Absturz, vollständig enthaltene Frames gelesen
  - `testFrameSizeBeyondEnd` — `rawFrame` mit `sizeOverride: 0x7FFFFFFF` hinter `TALB` → album gelesen, kein Absturz
  - `testNotID3` — `"RIFF…"` → beide `nil`; Version 5 → `nil`
  - `testTagLength` — `[0x49,0x44,0x33,4,0,0, 0,0,0x02,0x01]` → 267; mit Flag `0x10` → 277
  - `testRandomGarbageNeverCrashes` — `SplitMix64(seed: 7)`, 2000 × `"ID3"` + `[3,0,0]` + zufällige 4 Größenbytes < `0x80` + 0–2000 Zufallsbytes → `parse` läuft durch
- [ ] **Step 2: Run** `swift test --filter ID3ReaderTests` — Expected: FAIL.
- [ ] **Step 3: Implementieren** nach den Regeln oben.
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "AlbumArtworkSaver: ID3v2.2–2.4 reader for album tags and cover art"`

### Task 4: Album-Schlüssel, Index, Abgleich

**Files:**
- Create: `Sources/AlbumArtworkCore/{Fingerprint,AlbumKey,LibraryIndex,ScanPlanner}.swift`, `Tests/AlbumArtworkCoreTests/{AlbumKeyTests,ScanPlannerTests}.swift`

**Interfaces:**
- Produces:
  - `enum Fingerprint { static func fnv1a64(_ data: Data) -> UInt64 }`
  - `typealias AlbumID = String`; `enum AlbumKey { static func normalize(_ s: String) -> String; static func make(album: String?, albumArtist: String?, artist: String?, pictureFingerprint: UInt64) -> AlbumID }`
  - `struct FileStamp: Codable, Equatable { var size: Int64; var modified: Double }`
  - `struct IndexedFile: Codable, Equatable { var stamp: FileStamp; var album: AlbumID? }` (`nil` = kein brauchbares Bild)
  - `struct IndexedAlbum: Codable, Equatable { var fingerprint: UInt64; var title: String; var artist: String }`
  - `struct LibraryIndex: Codable, Equatable { static let currentVersion = 1; var version: Int; var files: [String: IndexedFile]; var albums: [AlbumID: IndexedAlbum]; var lastCompleteScan: Date?; init(); var albumIDs: [AlbumID] }` (`albumIDs` sortiert; Schlüssel von `files` = Pfad relativ zum Musikordner)
  - `struct ScanPlan: Equatable { var toRead: [String]; var vanished: [String] }` (beide sortiert)
  - `enum ScanPlanner`: `static func plan(index: LibraryIndex, listing: [String: FileStamp]) -> ScanPlan`; `static func existingAlbum(id: AlbumID, fingerprint: UInt64, in: LibraryIndex) -> AlbumID?` (id falls vorhanden, sonst Album mit gleichem Fingerabdruck, sonst `nil`); `static func record(path: String, stamp: FileStamp, album: AlbumID?, info: IndexedAlbum?, into: inout LibraryIndex) -> (album: AlbumID?, isNew: Bool)` (kanonisiert über `existingAlbum`, legt Album-Info nur neu an); `static func finish(vanished: [String], listingComplete: Bool, at: Date, into: inout LibraryIndex) -> [AlbumID]` (vollständig: verschwundene Dateien und unreferenzierte Alben entfernen, `lastCompleteScan` setzen, entfernte IDs sortiert zurück; unvollständig: nichts ändern, `[]`)

Regeln: `normalize` = klein, Leerraum-Folgen → ein Leerzeichen, getrimmt. `make`: ist `normalize(album)` nicht leer → `"a-"` + 16 Hex-Ziffern von `fnv1a64(utf8(normalize(albumArtist, sonst artist, sonst "") + "\u{1F}" + normalize(album)))`; sonst `"i-"` + 16 Hex-Ziffern des Fingerabdrucks. Hex klein, mit Nullen aufgefüllt.

- [ ] **Step 1: Failing tests**

```swift
func testFNVVectors() {
    XCTAssertEqual(Fingerprint.fnv1a64(Data()), 0xcbf29ce484222325)
    XCTAssertEqual(Fingerprint.fnv1a64(Data("a".utf8)), 0xaf63dc4c8601ec8c)
}
func testAlbumKeyNormalisation() {
    XCTAssertEqual(AlbumKey.make(album: "Blue Train", albumArtist: nil, artist: "John Coltrane", pictureFingerprint: 1),
                   AlbumKey.make(album: "  blue   TRAIN ", albumArtist: nil, artist: "JOHN COLTRANE", pictureFingerprint: 2))
}
func testAlbumArtistBeatsArtist()   // ("Hits","VA","A") == ("Hits","VA","B")
func testNoAlbumUsesFingerprint() { XCTAssertEqual(AlbumKey.make(album: nil, albumArtist: nil, artist: "x", pictureFingerprint: 0xABC), "i-0000000000000abc") }
func testIDsAreFileSafe()           // jede erzeugte ID passt auf ^[ai]-[0-9a-f]{16}$
func testPlanNewChangedVanished()   // Index {a,b,c}; Listing {a gleich, b Größe geändert, d neu} → toRead ["b.mp3","d.mp3"], vanished ["c.mp3"]
func testRecordGroupsTracksOfOneAlbum()   // zwei Pfade, gleiche ID → albums.count 1, zweites isNew == false
func testRecordDedupesIdenticalPictures() // ("a-1", fp 5), dann ("a-2", fp 5) → zweites ergibt "a-1"
func testRecordWithoutPictureIsRemembered() // album nil → files[p].album == nil; plan mit gleichem Stempel → p nicht in toRead
func testFinishCompleteRemovesOrphans()     // Album ohne Dateien entfernt und zurückgegeben; referenziertes bleibt
func testFinishIncompleteRemovesNothing()   // Review Focus 1: Index vorher == nachher, Rückgabe []
func testIndexCodableRoundTrip()
func testPlanFiftyThousandFilesIsFast()     // 50 000 Einträge in Index und Listing: plan < 2 s
```

- [ ] **Step 2: Run** `swift test --filter "AlbumKeyTests|ScanPlannerTests"` — Expected: FAIL.
- [ ] **Step 3: Implementieren** nach den Signaturen und Regeln.
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "AlbumArtworkSaver: album keys, library index and incremental scan planning"`

### Task 5: Easing, Pose, Bewegungen

**Files:**
- Create: `Sources/AlbumArtworkCore/{Easing,CoverPose,Motions}.swift`, `Tests/AlbumArtworkCoreTests/MotionsTests.swift`

**Interfaces:**
- Consumes: `Point2`, `SplitMix64` (Task 2)
- Produces:
  - `enum Easing { static func inOutSine(_:) ; outQuart(_:) ; inQuart(_:) ; inOutCubic(_:) ; inOutQuad(_:) }` — alle `(Double) -> Double`, Formeln wie Original Z. 4084, 4212–4214, 4537–4539
  - `struct CoverPose: Equatable { var x, y, z, rotX, rotY, rotZ, scale, opacity: Double; static func resting(at: Point2, z: Double = 0) -> CoverPose }`
  - `struct FlipMotion { static let duration = 0.9; let center: Point2; func frame(at t: Double) -> (pose: CoverPose, showsNewAlbum: Bool) }`
  - `struct DropMotion { static let duration = 2.2; init(origin: Point2, coverSize: Double, yawTarget: Double, rollWobble: Double, spin: Double); static func random(origin: Point2, coverSize: Double, using: inout SplitMix64) -> DropMotion; func pose(at t: Double) -> CoverPose }`
  - `struct RollStepMotion { static let duration = 0.3; init(from: Point2, to: Point2, startRotZ: Double, increment: Double, coverSize: Double); func pose(at: Double) -> CoverPose }`
  - `struct TumbleStepMotion { static let duration = 0.35; static let pause = 0.08; init(from: Point2, coverSize: Double, startRotX: Double); var to: Point2; func pose(at: Double) -> CoverPose }`
  - `struct PinSwingMotion { static let duration = 0.8; static let swapProgress = 0.4; init(pin: Point2, from: Point2); func pose(at: Double) -> CoverPose; func hasSwapped(at: Double) -> Bool }`
  - `t` in Sekunden ab Start, auf `[0, duration]` geklemmt.

Formeln:
- Flip: Winkel = `inOutSine(t/0,9)·π`; ist er > π/2, dann `rotY = Winkel − π` und `showsNewAlbum = true` (ein Layer statt zwei Flächen, gleiches Bild), sonst `rotY = Winkel`.
- Fallen: Original Z. 4223–4290 mit `originalZ = 0`, `finalPivotY = −10 − coverSize`; `random` zieht `yawTarget ∈ [−0,4; 0,4)`, `rollWobble ∈ [−0,15; 0,15)`, `spin ∈ {−1, 1}`.
- Rollschritt: Original Z. 4522–4572. Abrollschritt: Z. 4733–4770, `to = (from.x, from.y − coverSize)`.
- Nadel: Z. 5128–5196, linear; Drehrichtung immer +π; Radius und Startwinkel aus `pin`/`from`; `z = 0,001` außerhalb 30–70 %, sonst −0,001; `rotZ = π·p − (p > 0,4 ? π : 0)`; `scale = 1 + sin(2πp)·0,03`. (Das Original tauscht beim ersten Frame mit p > 0,4 — hier fest bei 0,4.)

- [ ] **Step 1: Failing tests** (Werte aus einer Nachrechnung der Original-Formeln, Genauigkeit 1e-5; `s = 20/6`):
  - `testEasing` — alle f(0) = 0, f(1) = 1; `inOutQuad(0.25) == 0.125`, `inOutCubic(0.25) == 0.0625`, `outQuart(0.5) == 0.9375`
  - `testFlip` — t 0 → rotY 0, false; t 0,45 → π/2, false; t 0,6 → −π/4, true; t 0,9 → 0, true
  - `testDropTopRow` — Ursprung (−16,666667 | 8,333333), yaw 0,3, wobble 0,1, spin 1: t 0 → y 8,333333, z 0,08, rotX 0 · t 0,22 → y 8,433333, z 0,287791, rotX 0,117187, rotY 0,045, rotZ 0,02 · t 0,44 → z 0,492340, rotX 0,25, rotY 0,09 · t 1,32 → y 0,256486, z 1,740334, rotX 1,658, rotY 0,286875, rotZ −0,006020, scale 1,009375 · t 2,2 → y −23,395260, z 1,866667, rotX 5,002, scale 1,15, opacity 0
  - `testDropBottomRowLeavesScreen` — Ursprung (16,666667 | −8,333333), t 2,2 → y −15,655316
  - `testDropRandomRanges` — 1000 Ziehungen innerhalb der Bereiche
  - `testRollStep` — von (0|0) nach (s|0), Inkrement −π/2: t 0,15 → x 1,666667, y 0,333333, z 0,266667, rotZ −0,785398, scale 1,05 · t 0,3 → x 3,333333, y 0, z 0,1, rotZ −π/2, scale 1
  - `testTumbleStep` — von (0|0): t 0,175 → y −1,666667, z 1,866667, rotX π/2, scale 1,05 · t 0,35 → y −3,333333, z 0,2, rotX π
  - `testPinSwing` — pin (0|0), von (−s/2 | s/2): t 0,2 → x −2,357023, y 0, z 0,001, rotZ π/4, scale 1,03 · t 0,3 → `hasSwapped == false` · t 0,4 → (−1,666667 | −1,666667), z −0,001, rotZ −π/2, `hasSwapped == true` · t 0,8 → (1,666667 | −1,666667), z 0,001, cos(rotZ) ≈ 1, scale 1
- [ ] **Step 2: Run** `swift test --filter MotionsTests` — Expected: FAIL.
- [ ] **Step 3: Implementieren** nach Formeln und Signaturen.
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "AlbumArtworkSaver: easing and the five cover motions, ported from the original"`

### Task 6: Ziele und Wege im Gitter

**Files:**
- Create: `Sources/AlbumArtworkCore/GridTargets.swift`, `Tests/AlbumArtworkCoreTests/GridTargetsTests.swift`

**Interfaces:**
- Consumes: `GridLayout`, `GridCell`, `Point2`
- Produces:
  - `enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }`
  - `struct PinBlock: Equatable { var source: GridCell; var target: GridCell; var middle: [GridCell]; var targetCorner: Corner; func pinPoint(in: GridLayout) -> Point2 }` (`middle` zeilenweise sortiert; `pinPoint` = Mittel der vier Zellmitten)
  - `enum ChainKind: CaseIterable { case sequential, downward, fall }`
  - `enum GridTargets`: `static func linkedDropCandidates(from: GridCell, in: GridLayout) -> [GridCell]` (Zeile > Start, Manhattan-Abstand ∈ {4, 8, 12}, sortiert nach Abstand, Zeile, Spalte); `static func rollPath(from: GridCell, to: GridCell) -> [GridCell]` (erst waagerecht, dann senkrecht; ohne Start, mit Ziel); `static func rollIncrement(from: GridCell, to: GridCell) -> Double` (+π/2 wenn `to.col < from.col`, sonst −π/2, für **jeden** Schritt gleich); `static func tumbleSteps(from: GridCell, rows: Int) -> Int` (`rows − row + 2`); `static func pinBlocks(for: GridCell, in: GridLayout) -> [PinBlock]` (alle im Gitter liegenden der vier Diagonal-Konfigurationen aus Z. 4896–5006, Reihenfolge: Start links oben, rechts oben, links unten, rechts unten); `static func chainCell(_: ChainKind, arrivedAt: GridCell, corner: Corner) -> GridCell`

Regeln für `chainCell` (Z. 5368–5506), Ankunft (r, c): sequential — unten rechts → (r, c−1), unten links → (r, c+1), oben → (r+1, c); downward → (r+1, c); fall — unten → (r−1, c), oben rechts → (r, c−1), oben links → (r, c+1).

**Bewusste Abweichung:** Im Original dreht ein Rollschritt nach links +90°, nach unten −90°. Bei Wegen mit Linksanteil summiert sich das nicht auf volle Umdrehungen, und das Cover springt am Ziel sichtbar zurück. Hier dreht jeder Schritt eines Weges in dieselbe Richtung; weil der Abstand 4, 8 oder 12 ist, ergibt das immer volle Umdrehungen.

- [ ] **Step 1: Failing tests** (Gitter 6 Reihen, 16:9):
  - `testLinkedDropCandidatesFromTopLeft` — erste drei == [(1,3), (2,2), (3,1)]; alle Abstände ∈ {4, 8, 12}, alle Zeilen > 0
  - `testNoCandidatesFromBottomRow` — von (5,4) → []
  - `testRollPath` — (0,0)→(2,2) == [(0,1),(0,2),(1,2),(2,2)]; (0,3)→(1,0) == [(0,2),(0,1),(0,0),(1,0)]
  - `testRollIncrementGivesFullTurns` — für jeden Kandidaten von (0,5): `increment · path.count` ist ein Vielfaches von 2π
  - `testTumbleSteps` — Zeile 0 → 8, Zeile 5 → 3
  - `testPinBlockAtCorner` — (0,0) → genau ein Block: target (1,1), middle [(0,1),(1,0)], corner `.bottomRight`, pinPoint (−15 | 6,666667)
  - `testPinBlocksInterior` — (2,3) → 4 Blöcke; (5,10) → ein Block mit target (4,9), corner `.topLeft`
  - `testChainCells` — sequential/unten rechts von (3,3) → (3,2); fall/oben links → (3,4); downward → (4,3)
- [ ] **Step 2: Run** `swift test --filter GridTargetsTests` — Expected: FAIL.
- [ ] **Step 3: Implementieren.**
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "AlbumArtworkSaver: roll paths, pin-rotation blocks and chain targets"`

### Task 7: Animationsplanung und Albumwahl

**Files:**
- Create: `Sources/AlbumArtworkCore/{AnimationPlanner,AlbumPicker}.swift`, `Tests/AlbumArtworkCoreTests/{AnimationPlannerTests,AlbumPickerTests}.swift`

**Interfaces:**
- Consumes: `SplitMix64`, `GridCell`, `AlbumID`
- Produces:
  - `enum AnimationKind: CaseIterable { case flip, drop, linkedDrop, rollDrop, pinRotation, rowRollDrop, rowDrop; var weight: Double; var isRow: Bool }`
  - `enum AnimationPlanner`: `static let stagger: TimeInterval = 0.2`; `static func pickKind(using: inout SplitMix64) -> AnimationKind`; `static func coverCount(using:) -> Int` (3…6); `static func pickCells(_ count: Int, from: [GridCell], using:) -> [GridCell]` (verschieden); `static func row(rows: Int, using:) -> Int` (0 ..< max(1, rows/2)); `static func rowDelays(count: Int, using:) -> [TimeInterval]` (Eintrag i = i × eigener Zufall 0,2…0,4); `static func tickInterval(base: TimeInterval, using:) -> TimeInterval` (base + [0, 1))
  - `enum AlbumPicker`: `static func initialFill(count: Int, pool: [AlbumID], using:) -> [AlbumID]` (gemischter Pool, zyklisch wiederholt wenn zu klein, `[]` bei leerem Pool); `static func replacement(pool: [AlbumID], isReady: (AlbumID) -> Bool, visible: Set<AlbumID>, avoiding: AlbumID?, using:) -> AlbumID?` (Vorrang: bereit und unsichtbar → bereit und ≠ avoiding → irgendein bereites → `nil`); `static func prefetchCandidates(pool: [AlbumID], visible: Set<AlbumID>, count: Int, using:) -> [AlbumID]` (bis zu `count` verschiedene unsichtbare, sonst mit sichtbaren aufgefüllt)

- [ ] **Step 1: Failing tests**
  - `testKindFrequencies` — Seed 42, 100 000 Ziehungen: jede Art innerhalb ±0,01 von Gewicht/100
  - `testCoverCountRange` — 10 000 Ziehungen ⊆ 3…6, alle vier kommen vor
  - `testRowInUpperHalf` — rows 6 → 0…2; rows 3 → 0; rows 12 → 0…5
  - `testRowDelays` — count 4: `[0] == 0`, `delays[i] / i ∈ [0,2; 0,4]`
  - `testTickInterval` — base 3 → [3, 4)
  - `testInitialFillUnique` — Pool 100, count 66 → 66 verschiedene
  - `testInitialFillRepeats` — Pool 7, count 66 → jedes Album 9- oder 10-mal
  - `testReplacementPrefersInvisible` — Pool 100, 66 sichtbar, 1000 Ziehungen nie sichtbar
  - `testSingleAlbumPool` — Review Focus 3: Pool `["a"]`, sichtbar `["a"]`, avoiding `"a"` → `"a"`
  - `testNothingReady` → `nil`
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implementieren.**
- [ ] **Step 4: Run** `swift test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "AlbumArtworkSaver: weighted animation planning and album picking"`

### Task 8: Wand-Engine

**Files:**
- Create: `Sources/AlbumArtworkCore/WallEngine.swift`, `Tests/AlbumArtworkCoreTests/WallEngineTests.swift` (mit `FakeSource`)

**Interfaces:**
- Consumes: alles aus Tasks 2, 5, 6, 7
- Produces:
```swift
struct SpriteID: Hashable { let raw: Int }
struct Sprite: Equatable { let id: SpriteID; var album: AlbumID; var pose: CoverPose }
enum WallChange: Equatable { case added(SpriteID), removed(SpriteID), albumChanged(SpriteID) }
struct WallSettings: Equatable { var rows: Int; var interval: TimeInterval
    init(rows: Int = 6, interval: TimeInterval = 3) }            // klemmt 3…12 bzw. 1…10
protocol ArtworkSource: AnyObject {
    var pool: [AlbumID] { get }
    func isReady(_ album: AlbumID) -> Bool
    func prefetch(_ albums: [AlbumID]) }
final class WallEngine {
    init(layout: GridLayout, settings: WallSettings, source: ArtworkSource, seed: UInt64)
    let layout: GridLayout
    private(set) var sprites: [SpriteID: Sprite]
    func owner(of cell: GridCell) -> SpriteID?
    func isBusy(_ cell: GridCell) -> Bool
    func start(at time: TimeInterval, initialAlbums: [AlbumID])   // count == layout.cellCount
    func advance(to time: TimeInterval) -> [WallChange]
    func trigger(_ kind: AnimationKind, cells: [GridCell], at time: TimeInterval) }  // Reihen-Arten ignorieren cells
```

Verhalten (genau so umsetzen):
1. `start`: ein Sprite je Zelle, ruhend in der Mitte, z 0. Takt = `tickInterval(base: interval)`, einmal gewürfelt; erster Takt bei start + Takt.
2. Takt: `prefetch(prefetchCandidates(count: 12))`, Art ziehen. Reihen-Arten: Zeile per `row`, Zellen nach Spalte aufsteigend, Zelle i startet nach `rowDelays[i]` mit `rollDrop` bzw. `drop`. Sonst `coverCount` Zellen per `pickCells` aus allen Zellen, Zelle i nach i × 0,2 s.
3. Beim Start einer Einzelanimation: ist eine beteiligte Zelle belegt → überspringen. Braucht sie ein neues Album: `AlbumPicker.replacement(visible: Alben aller Sprites, avoiding: Album des abgehenden Sprites)`; `nil` → ganze Animation überspringen, keine Änderung. Beteiligte Zellen sind bis zum Ende belegt.
4. Je Art:
   - **flip:** gleicher Sprite, `FlipMotion`; beim ersten Frame mit `showsNewAlbum` Album setzen und `.albumChanged`.
   - **drop:** Nachfolger an der Zelle (ruhend, z −0,01, `.added`); abgehender Sprite mit `DropMotion.random`; am Ende `.removed`, Nachfolger z 0 und Besitzer.
   - **linkedDrop:** keine Kandidaten → wie drop. Ziel zufällig unter den ersten drei; Zielzelle belegt → überspringen. Belegt: Start + Ziel. Nachfolger am Start. Rollschritte ohne Pause entlang `rollPath`, `rollIncrement`, `startRotZ` aufsummiert. Am Ende: rotZ 0, z 0, Besitzer des Ziels; alter Ziel-Sprite `.removed`.
   - **rollDrop:** Nachfolger am Start; `tumbleSteps` Abrollschritte, je 0,35 s + 0,08 s Pause, `startRotX` +π je Schritt; am Ende `.removed`.
   - **pinRotation:** Blöcke, deren vier Zellen frei sind; keiner → flip auf der Zelle. Block zufällig; alle vier Zellen belegt; Nachfolger am Start; Besitzer der Mittelzellen auf z 0,002. Beim ersten Frame mit `hasSwapped` neues Album (bei `nil` altes behalten) und `.albumChanged`. Am Ende: Besitzer des Ziels; alter Ziel-Sprite `.removed`; Mittelzellen z 0. Dann Kette, wenn Stufe < 5 und Zufall < 0,8: unter den `ChainKind`, deren `chainCell` im Gitter und frei ist, zufällig eine — sequential/downward → pinRotation dort mit Stufe + 1; fall → drop oder rollDrop (50:50) dort. Kette startet sofort.
5. `advance`: erst fällige geplante Ereignisse in Zeitfolge, dann Posen aus den laufenden Bewegungen, dann Animationen mit Ende ≤ Zeit abschließen (in Startreihenfolge). Ruhende Sprites behalten ihre Ruhepose.

- [ ] **Step 1: Failing tests** (Gitter 6 Reihen 16:9, `FakeSource` mit Pool 200, alles bereit, außer wo genannt):
  - `testStartFillsEveryCell` — 66 Sprites, jede Zelle hat Besitzer, alle Posen ruhend in der Mitte
  - `testFlipChangesAlbumHalfway` — trigger flip (2,3) bei 0: `advance(0.4) == []`; `advance(0.5) == [.albumChanged(owner)]`, Album anders; `advance(0.95)`: rotY 0, Zelle frei
  - `testDropReplacesCover` — nach trigger `advance(0)` == `[.added(r)]`, r.z == −0,01; `advance(2.25)` enthält `.removed(alt)`, Besitzer == r, z 0
  - `testLinkedDropMovesToTarget` — Seed 1, trigger (0,0); `advance(1.25)`: Besitzer des Ziels ist der alte (0,0)-Sprite mit rotZ 0; Besitzer von (0,0) ist neu
  - `testLinkedDropFromBottomRowDrops` — (5,4) verhält sich wie drop
  - `testRollDropLeavesScreen` — (4,0): bei 4 × 0,43 − 0,02 s ist y des Sprites < bottomEdge − coverSize/2; bei 4 × 0,43 + 0,02 s `.removed`
  - `testPinRotationSwapsOnce` — (2,3): bis 0,85 s genau ein `.albumChanged`; der drehende Sprite besitzt das Blockziel
  - `testNothingReadySkips` — `ready = false`: jede Art auslösen, `advance(5) == []`, Sprites unverändert
  - `testLongRunInvariants` — Seeds 1…3, 600 s in 1/60-s-Schritten: jede Zelle hat einen existierenden Besitzer; Besitzer freier Zellen ruhen (Mitte, z 0, Rotation 0, scale 1, opacity 1); `sprites.count ≤ 3 × cellCount`; keine NaN; keine doppelten Alben unter den Besitzern
  - `testLongRunSingleAlbum` — Review Focus 3: Pool `["a"]`, 120 s: dieselben Invarianten außer „keine doppelten Alben“
- [ ] **Step 2: Run** `swift test --filter WallEngineTests` — Expected: FAIL.
- [ ] **Step 3: Implementieren.** Geplante Ereignisse als nach Zeit sortierte Liste; jede laufende Animation hält Startzeit, ihre Bewegung(en) und einen Abschluss, der Besitz und Ebenen umsetzt.
- [ ] **Step 4: Run** `swift test` — Expected: PASS, auch alle früheren Tests.
- [ ] **Step 5: Commit, push, CI grün** `git commit -m "AlbumArtworkSaver: wall engine with all seven animations and chains"`

### Task 9: `.saver`-Bundle, TestHost, CI-Build (nach Task 1)

**Files:**
- Create: `AlbumArtworkSaver/Resources/Info.plist`, `AlbumArtworkSaver/build-saver.sh`, `Sources/AlbumArtworkSaver/AlbumArtworkView.swift`, `Sources/TestHost/main.swift`, `Scripts/load-saver.swift`
- Modify: `.github/workflows/build-saver.yml`

**Interfaces:**
- Produces: `@objc(AlbumArtworkView) final class AlbumArtworkView: ScreenSaverView` mit `init?(frame: NSRect, isPreview: Bool)`, `animationTimeInterval = 1.0 / 60`, layer-gestützt, schwarzer Hintergrund; `enum HostOverride { case covers(URL); case music(URL, cache: URL) }` und `static var hostOverride: HostOverride?` (im echten Saver `nil`). `build-saver.sh` erzeugt `build/AlbumArtwork.saver` und `build/TestHost`.

- [ ] **Step 1: `Info.plist`** — `CFBundleIdentifier` `app.beamerpresenter.AlbumArtworkSaver`, `CFBundleExecutable` `AlbumArtwork`, `CFBundleName` `AlbumArtwork`, `CFBundlePackageType` `BNDL`, `CFBundleShortVersionString` `1.0`, `CFBundleVersion` `1`, `NSPrincipalClass` `AlbumArtworkView`, `LSMinimumSystemVersion` wird vom Skript auf `MACOS_MIN` gesetzt.
- [ ] **Step 2: `build-saver.sh`** — je Arch: `swiftc -swift-version 5 -O -module-name AlbumArtworkSaver -target <arch>-apple-macos$MACOS_MIN -emit-executable <Link-Flag aus Task 1> Sources/AlbumArtworkCore/*.swift Sources/AlbumArtworkSaver/*.swift -framework ScreenSaver -framework AppKit -framework QuartzCore -framework ImageIO -framework UniformTypeIdentifiers`; `lipo -create`; Bundle zusammensetzen; `codesign --force --sign - build/AlbumArtwork.saver`. TestHost: dieselben Quellen + `Sources/TestHost/main.swift` als normales Programm (`-module-name AlbumArtworkTestHost`).
- [ ] **Step 3: `AlbumArtworkView`-Gerüst und TestHost** — TestHost ohne Argumente: Fenster 1280×720 „AlbumArtwork TestHost“, Inhalt = `AlbumArtworkView(frame:isPreview: false)`, `startAnimation()`, App läuft.
- [ ] **Step 4: `Scripts/load-saver.swift`** — lädt das Bundle aus Argument 1, prüft dass `principalClass` eine Unterklasse von `ScreenSaverView` ist, instanziiert sie mit 400×225, gibt `OK AlbumArtworkView` aus; sonst Exit ≠ 0.
- [ ] **Step 5: CI erweitern** — nach `swift test`: `./build-saver.sh`; `file build/AlbumArtwork.saver/Contents/MacOS/AlbumArtwork | grep -q bundle`; `codesign --verify build/AlbumArtwork.saver`; `swift Scripts/load-saver.swift build/AlbumArtwork.saver | grep '^OK AlbumArtworkView'`; `ditto -c -k --sequesterRsrc --keepParent build/AlbumArtwork.saver AlbumArtwork-saver.zip`; `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2` mit Name `AlbumArtwork-saver`.
- [ ] **Step 6: Commit, push, prüfen.** Expected: CI grün mit Artefakt. Auf dem Mac mini: `./build-saver.sh && (./build/TestHost & sleep 3; kill $!)` läuft ohne Absturz.

```bash
git commit -m "AlbumArtworkSaver: .saver bundle, test host and macOS CI build"
```

### Task 10: Wand zeichnen

**Files:**
- Create: `Sources/AlbumArtworkSaver/CoverWall.swift`, `Sources/AlbumArtworkSaver/CoverImageStore.swift`, `Scripts/make-fixtures.py` (Unterbefehl `images`)
- Modify: `Sources/AlbumArtworkSaver/AlbumArtworkView.swift`, `Sources/TestHost/main.swift`

**Interfaces:**
- Consumes: `WallEngine`, `ArtworkSource`, `WallSettings`, `GridLayout`, `CoverPose`, `HostOverride`
- Produces:
  - `final class CoverImageStore: ArtworkSource { init(imageURL: @escaping (AlbumID) -> URL?); var pool: [AlbumID]; var pixelEdge: Int; func image(for: AlbumID) -> CGImage? }` — dekodiert auf einer seriellen Hintergrund-Queue (`.userInitiated`) per ImageIO-Thumbnail (kurze Seite ≥ `pixelEdge`), mittig quadratisch beschnitten; Ergebnis in einen `NSCache` auf dem Main-Thread.
  - `final class CoverWall { init(hostLayer: CALayer, layout: GridLayout, images: CoverImageStore); func apply(_ changes: [WallChange], engine: WallEngine) }` — hält `[SpriteID: CALayer]`.

Abbildung (Entscheidungen):
- Einheit = Bildhöhe / 20. Wand-Layer füllt die View, `sublayerTransform.m34 = −1 / (GridLayout.cameraDistance × Einheit)`, schwarz.
- Sprite-Layer: Kante = coverSize × Einheit; `position` = Mitte + (x, y) × Einheit (macOS-Layer: y nach oben, wie die Welt); `zPosition` = z × Einheit (positioniert **und** sortiert); `transform` = erst Z-, dann Y-, dann X-Rotation, dann Skalierung; `opacity`; `contents` = CGImage, `contentsGravity = .resizeAspectFill`, `masksToBounds`, `isDoubleSided = true`. Alles in `CATransaction` mit `setDisableActions(true)`.
- `.added` → neuer Layer, `.removed` → entfernen, `.albumChanged` → `contents` tauschen. `pixelEdge = ceil(coverSize × Einheit × backingScaleFactor)`.
- `AlbumArtworkView`: `startAnimation` baut Layout (Seitenverhältnis der View, `WallSettings()` bis Task 12), Store, Engine (Seed zufällig), Erstbefüllung, `prefetch`. `animateOneFrame`: schwarz, bis alle Erstbilder bereit sind; dann `engine.start`, danach jedes Frame `wall.apply(engine.advance(to: CACurrentMediaTime()), engine:)`. Alle 10 s die mittlere Dauer von `animateOneFrame` in Kategorie `wall` loggen.
- TestHost `--covers <dir>`: Pool = Dateinamen ohne Endung aller `*.jpg|*.jpeg|*.png`.
- `make-fixtures.py images <n> <dir>`: n einfarbige PNGs (verschiedene Farben, 64×48 — nicht quadratisch), nur Standardbibliothek (`zlib`, `struct`).

- [ ] **Step 1: Implementieren** nach den Schnittstellen.
- [ ] **Step 2: CI** — Expected: grün (kompiliert, bisherige Prüfungen bestehen).
- [ ] **Step 3: Auf dem Mac mini laufen lassen.** Run: `python3 Scripts/make-fixtures.py images 120 /tmp/aa-covers && ./build-saver.sh && (./build/TestHost --covers /tmp/aa-covers & sleep 25; kill $!); log show --last 1m --predicate 'subsystem == "app.beamerpresenter.AlbumArtworkSaver" && category == "wall"'`. Expected: kein Absturz, mittlere Frame-Dauer < 4 ms.
- [ ] **Step 4: Commit** `git commit -m "AlbumArtworkSaver: Core Animation cover wall driven by the engine"`

### Task 11: Einlesen auf macOS (Prüfpunkt 2)

**Files:**
- Create: `Sources/AlbumArtworkSaver/{TagFileReader,CoverImageProcessor,CoverCache,LibraryScanner,LibraryService}.swift`, `Scripts/scan-test.sh`
- Modify: `Scripts/make-fixtures.py` (Unterbefehl `mp3`), `Sources/TestHost/main.swift`, `Sources/AlbumArtworkSaver/AlbumArtworkView.swift`, `.github/workflows/build-saver.yml`

**Interfaces:**
- Consumes: `ID3Reader`, `Fingerprint`, `AlbumKey`, `ScanPlanner`, `LibraryIndex`, `CoverImageStore`
- Produces:
  - `enum TagFileReader { static let maxTagBytes = 16 << 20; static func readTag(at: URL) -> Data? }` — nur lesend; `nil` ohne Tag, bei zu großem Tag oder E/A-Fehler
  - `enum CoverImageProcessor { static let edge = 640; static let jpegQuality = 0.85; static func makeSquareJPEG(from: Data, edge: Int = edge) -> Data? }`
  - `final class CoverCache { init(directory: URL); func coverURL(for: AlbumID) -> URL; func loadIndex() -> LibraryIndex; func saveIndex(_: LibraryIndex) throws; func writeCover(_ jpeg: Data, for: AlbumID) throws; func removeCover(_: AlbumID); func removeOrphanCovers(keeping: Set<AlbumID>); func tryLock() -> Bool; func unlock() }` — fehlender/kaputter Index → `LibraryIndex()`; Schreiben atomar; Sperre per `flock(LOCK_EX | LOCK_NB)` auf `scan.lock`
  - `struct ScanSummary: Equatable { enum Outcome: String { case complete, incomplete, unavailable, busy, cancelled }; var outcome: Outcome; var albums: Int; var files: Int; var newAlbums: Int; var removedAlbums: Int }`
  - `final class LibraryScanner { init(root: URL, cache: CoverCache); func run(isCancelled: () -> Bool, onNewAlbums: ([AlbumID]) -> Void) -> ScanSummary }`
  - `final class LibraryService { static func shared(cacheDirectory: URL) -> LibraryService; private(set) var albums: [AlbumID]; private(set) var isScanning: Bool; var lastCompleteScan: Date?; func addObserver(_ owner: AnyObject, onChange: @escaping () -> Void); func scan(root: URL); func cancelScan() }` — ein Scan je Prozess (zweiter Aufruf während eines Laufs: nichts tun); läuft auf einer Queue mit `.utility`; meldet auf dem Main-Thread; Observer schwach gehalten

Ablauf `LibraryScanner.run`:
1. `root` kein vorhandener Ordner → `.unavailable`, Index unangetastet.
2. `tryLock()` scheitert → `.busy`.
3. Auflistung per `FileManager.enumerator` mit `.isRegularFileKey`, `.fileSizeKey`, `.contentModificationDateKey`, Optionen `.skipsHiddenFiles`, `.skipsPackageDescendants`; jeder Fehler im `errorHandler` → unvollständig (weiter auflisten). Nur `.mp3`.
4. `plan`; je `toRead`: abgebrochen → stoppen, unvollständig. Tag lesen und parsen; mit Bild: Fingerabdruck, ID, `existingAlbum` → vorhanden: ohne Bildarbeit `record`; sonst `makeSquareJPEG` (`nil` → `record` ohne Album) → `writeCover` → `record` mit `IndexedAlbum(fingerprint, album ?? "", albumArtist ?? artist ?? "")`. Ohne Bild → `record` ohne Album. Neue Alben gesammelt an `onNewAlbums` (alle 20 und beim Speichern); `saveIndex` alle 200 Dateien.
5. `finish`; entfernte Alben → `removeCover`; nur wenn vollständig: `removeOrphanCovers`.
6. `saveIndex`, `unlock`, Zusammenfassung; in Kategorie `scan` loggen.

- TestHost `--scan <music> --cache <dir>`: ohne Fenster, Scan synchron, gibt `outcome=<o> albums=<n> files=<m> new=<k>` aus, Exit 0. `--music <music> [--cache <dir>]`: Fenster mit echter Wand; `AlbumArtworkView` nutzt dann `LibraryService` (Pool aus `albums`, Observer aktualisiert `store.pool`, `scan(root:)` beim Start).
- `make-fixtures.py mp3 <dir>` erzeugt: `A/01–03.mp3` (ID3v2.3, `TALB` „Album A“, `TPE1` „Artist A“, gleiches rotes PNG), `B/01.mp3` (ID3v2.4, UTF-8 „Album B“, blaues PNG), `loose.mp3` (kein Album, grünes PNG), `nopic.mp3` (nur `TALB`), `broken.mp3` (Tag-Größe größer als die Datei), `.hidden/x.mp3` (gültig, muss ignoriert werden); hinter jedem Tag 1024 Nullbytes. Zusatzbefehl `mp3-one <file> <album> <rgb>` für eine einzelne Datei.

- [ ] **Step 1: Implementieren** nach Schnittstellen und Ablauf.
- [ ] **Step 2: `Scripts/scan-test.sh` schreiben** (bricht beim ersten Fehlschlag mit Exit 1 ab):
  1. Fixtures nach `$T/music`, Prüfsummen aller Dateien merken
  2. Scan → `outcome=complete albums=3 files=7 new=3`; `covers/` enthält 3 Dateien
  3. erneuter Scan → `new=0`
  4. `mp3-one $T/music/C/01.mp3 "Album C" …` → Scan `albums=4 new=1`
  5. `B/01.mp3` löschen → Scan `albums=3`; `covers/` enthält 3 Dateien
  6. Scan mit `$T/missing` → `outcome=unavailable`; `index.json` byteweise unverändert (Review Focus 1)
  7. zwei Scans gleichzeitig auf denselben Cache → danach `python3 -m json.tool index.json` gültig, Folge-Scan `albums=3` (Review Focus 5)
  8. Prüfsummen des Musikordners (ohne die in Schritt 4/5 geänderten Dateien) unverändert
- [ ] **Step 3: CI erweitern** — nach dem Build `Scripts/scan-test.sh build/TestHost`. Expected: grün.
- [ ] **Step 4: Prüfpunkt 2 (Nutzer).** Auf dem Mac mini `./build-saver.sh && ./build/TestHost --music "<musikordner>"`; Nutzer vergleicht mit dem GIF im Original-Repo. Ich lese Logs (`scan`, `wall`). Rückmeldungen als Liste festhalten und beheben, bevor Task 12 beginnt.
- [ ] **Step 5: Commit** `git commit -m "AlbumArtworkSaver: incremental scanner, cover cache and end-to-end scan test"`

### Task 12: Einstellungen, Ordnerzugriff, Optionen, Zustände, Lebenszyklus

**Files:**
- Create: `Sources/AlbumArtworkCore/StatusText.swift`, `Tests/AlbumArtworkCoreTests/StatusTextTests.swift`, `Sources/AlbumArtworkSaver/{SaverSettings,FolderAccess,OptionsSheet}.swift`
- Modify: `Sources/AlbumArtworkSaver/AlbumArtworkView.swift`

**Interfaces:**
- Consumes: `WallSettings`, `LibraryService`, `CoverImageStore`, Spike-Mechanismus aus Task 1
- Produces:
  - `enum FolderStatus: Equatable { case notChosen, available, unavailable }`
  - `enum StatusText { static func make(albumCount: Int, lastCompleteScan: Date?, now: Date, folder: FolderStatus, isScanning: Bool) -> String; static func hint(folder: FolderStatus, albumCount: Int, isScanning: Bool, needed: Int) -> String? }`
  - `struct SaverSettings { static let moduleName = "app.beamerpresenter.AlbumArtworkSaver"; var wall: WallSettings; var folderBookmark: Data?; var folderPath: String?; static func load() -> SaverSettings; func save() }` — Schlüssel `rows`, `interval`, `folderBookmark`, `folderPath` in `ScreenSaverDefaults`
  - `enum FolderAccess { static func remember(_ url: URL, in: inout SaverSettings); static func resolve(_ settings: SaverSettings) -> (status: FolderStatus, url: URL?); static func stopAccessing(_ url: URL) }` — erst Bookmark mit Security-Scope (veraltet → neu anlegen, wenn möglich), dann Pfad, wenn der Spike `path` zuließ; Ordner vorhanden → `available`, sonst `unavailable`
  - `final class OptionsSheet: NSWindowController { init(settings: SaverSettings, service: LibraryService?, onDone: @escaping (SaverSettings) -> Void) }`

Texte (`StatusText.make`): Zahlen mit Punkt gruppiert, ohne Locale (1234 → „1.234“). `notChosen` → „Kein Musikordner gewählt“; `unavailable` → „Musikordner nicht erreichbar · zeige N Alben aus dem Zwischenspeicher“; scannt → „N Alben · lese gerade ein …“; nie eingelesen → „N Alben · noch nicht eingelesen“; sonst „N Alben · zuletzt eingelesen “ + < 1 min „gerade eben“, < 60 min „vor X Min.“, < 24 h „vor X Std.“, sonst „vor 1 Tag“ / „vor X Tagen“. `hint`: `notChosen` → „Musikordner in den Screensaver-Optionen wählen“; scannt und `albumCount < needed` → „Lese Musik ein … N Alben“; fertig, verfügbar, 0 Alben → „Keine Cover gefunden“; sonst `nil`.

Verhalten `AlbumArtworkView` (echter Saver, `hostOverride == nil`):
- `startAnimation`: Einstellungen laden, Ordner auflösen, `LibraryService.shared` mit Standard-Cache, Store-Pool = `service.albums`, Hinweis als zentrierter `CATextLayer` (weiß, 60 % Deckkraft), bei verfügbarem Ordner `scan(root:)`.
- Wand startet, sobald `albums.count ≥ cellCount` oder der Scan fertig ist und mindestens 1 Album da ist; neue Alben fließen über den Pool ein.
- `stopAnimation` und verteilte Notification `com.apple.screensaver.willstop`: `cancelScan()`, Engine und Layer freigeben, `stopAccessing`.
- `hasConfigureSheet = true`; `configureSheet` liefert das Fenster von `OptionsSheet`: Musikordner-Pfad (Mitte gekürzt) + „Ordner wählen…“ (`NSOpenPanel`, nur Ordner), Pfadfeld editierbar falls Mechanismus `path`; Statuszeile (aktualisiert über Observer); „Jetzt neu einlesen“; Reihen-Regler 3…12 und Intervall-Regler 1…10 s mit Wertanzeige; „Fertig“ → `save()`, `sheetParent?.endSheet(window)`.

- [ ] **Step 1: Failing tests** (`StatusTextTests`, `now` fest):
  - `testStatusDefault` — 1234 Alben, vor 2 h → „1.234 Alben · zuletzt eingelesen vor 2 Std.“
  - `testStatusRelativeTimes` — 30 s „gerade eben“, 5 min „vor 5 Min.“, 1 Tag „vor 1 Tag“, 3 Tage „vor 3 Tagen“
  - `testStatusUnavailable` — Review Focus 1: 12 Alben → „Musikordner nicht erreichbar · zeige 12 Alben aus dem Zwischenspeicher“
  - `testStatusNotChosen`, `testStatusScanning`, `testStatusNeverScanned`
  - `testHints` — notChosen → „Musikordner in den Screensaver-Optionen wählen“; scannt 10 von 66 → „Lese Musik ein … 10 Alben“; 66 von 66 → `nil`; fertig mit 0 → „Keine Cover gefunden“
- [ ] **Step 2: Run** `swift test --filter StatusTextTests` — Expected: FAIL. **Step 3:** `StatusText` implementieren. **Step 4:** `swift test` — Expected: PASS.
- [ ] **Step 5: macOS-Teil implementieren** (Einstellungen, Ordnerzugriff, Optionen-Blatt, Lebenszyklus). CI — Expected: grün.
- [ ] **Step 6: Auf dem Mac mini installieren.** `./build-saver.sh && rm -rf ~/Library/Screen\ Savers/AlbumArtwork.saver && cp -R build/AlbumArtwork.saver ~/Library/Screen\ Savers/ && killall legacyScreenSaver 2>/dev/null; true`. Nutzer (Teil von Prüfpunkt 3): Systemeinstellungen → „AlbumArtwork“ wählen → Optionen → Ordner wählen; Statuszeile zeigt Alben. Dann `open -a ScreenSaverEngine`; Logs `scan` zeigen den Durchlauf.
- [ ] **Step 7: Commit** `git commit -m "AlbumArtworkSaver: settings, folder access, options sheet and lifecycle"`

### Task 13: Abschluss (Prüfpunkte 3 und 4)

**Files:**
- Create: `AlbumArtworkSaver/README.md`, `AlbumArtworkSaver/CHANGELOG.md`
- Modify: `CHANGELOG.md` und die Versionsstellen aus `CLAUDE.md` (dieselben acht Dateien wie bei v7.9)

- [ ] **Step 1: README** (englisch wie das Repo): was es ist; Original `lingkuma/AlbumArtwork` mit MIT-Hinweis; bauen (`./build-saver.sh`) oder CI-Artefakt; installieren (Doppelklick); Ordner in den Optionen wählen; wie Aktualisierung funktioniert; Fehlerhilfe (Ordner nicht erreichbar, `killall legacyScreenSaver`). `CHANGELOG.md`: `## v1.0 — <Datum>`.
- [ ] **Step 2: Prüfpunkt 3 (Nutzer).** Neue MP3 in den Musikordner legen, Screensaver starten → Album erscheint (Log `new=1`). Liegt die Musik extern: Platte abziehen, Screensaver starten → Wand aus dem Cache, Status „Musikordner nicht erreichbar …“.
- [ ] **Step 3: Prüfpunkt 4 (Nutzer + Terminal).** Alle Bildschirme zeigen eine Wand; nach dem Aufwachen zweimal im Abstand von 10 s `ps -Ao pid,%cpu,comm | grep -i legacyScreenSaver` → kein Prozess oder CPU < 1 %.
- [ ] **Step 4: Repo-Version** nach `CLAUDE.md`: neues Feature im Repo → `8.0`, Build `45`; Eintrag `## v8.0 — <Datum>` in `CHANGELOG.md`.
- [ ] **Step 5: Commit, push, CI grün.** `git commit -m "AlbumArtworkSaver 1.0: README and changelog; 8.0"`

---

## Weg B (nur wenn der Spike scheitert)

Vor Task 9 als Nachtrag ausformulieren. Skizze: `Sources/Helper/` — kleine App „AlbumArtwork-Einleser“ ohne Sandbox mit Ordnerwahl, Statuszeile und „Jetzt neu einlesen“; nutzt `LibraryScanner` und `CoverCache` unverändert mit Cache `/Users/Shared/AlbumArtwork`. LaunchAgent `~/Library/LaunchAgents/app.beamerpresenter.AlbumArtworkHelper.plist` mit `RunAtLoad` und `StartInterval 3600` ruft die App mit `--scan` auf. Der Screensaver liest nur Index und Cover aus dem gemeinsamen Ordner; kein `FolderAccess`; Optionen-Blatt nur Reihen, Intervall und ein Hinweis auf die Hilfs-App.
