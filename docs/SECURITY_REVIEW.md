# BeamerPresenter — Sicherheitsreview

> **Methode:** manuelles Code-Review aller drei Plattformen (macOS-App in
> `Sources/BeamerPresenter`, iPad/iPhone-App in `iOS/BeamerPresenter`,
> Linux-Port in `Linux/` mit Tauri v2), ergänzt um Angriffssimulationen als
> Unit-Tests (`Tests/BeamerCoreTests`, Rust-Tests in `Linux/src-tauri/src/lib.rs`,
> Node-Tests in `Linux/ui/test`) und einen lokalen Parcours (`Tools/pentest.sh`,
> siehe [PENTEST.md](PENTEST.md)). Bewertet wird der Code-Stand v7.0
> (Commit `f37aec6`, Korrekturen gegenüber v6.3 = `57bbc61`). Die AppKit-,
> UIKit- und MultipeerConnectivity-Teile konnten in der Prüfumgebung (Linux)
> nicht kompiliert werden; sie sind gelesen, nicht ausgeführt.
>
> Stand: 2026-11-04

## Gesamtbewertung

BeamerPresenter ist ein lokales Präsentationswerkzeug ohne Server, ohne Konten
und ohne eingebettete Geheimnisse. Die Angriffsfläche entsteht fast vollständig
dadurch, dass die App **fremde Dateien an externe Werkzeuge weitergibt**
(LaTeX, LibreOffice, `unzip`) und dass das iPad über MultipeerConnectivity
**von einem Nachbargerät gesteuert** werden kann.

Vor dem Audit war der schwerste Punkt (H1): Das Öffnen einer `.tex`-Datei ohne
daneben liegendes PDF startete ungefragt `latexmk`, das eine `latexmkrc` des
Projekts (Perl, also beliebiger Code) ausführt; außerdem durfte TeX beliebige
Dateien des Benutzers lesen und ins PDF setzen. Das ist auf macOS und Linux
behoben: Die App fragt vor jedem Build, `latexmk` läuft mit `-norc`, alle
Engines mit `-no-shell-escape` und TeX im Paranoid-Modus
(`openin_any=p`, `openout_any=p`). Alle externen Werkzeuge haben jetzt
Zeitlimits, die iPad-Kopplung ist deutlich härter, die Linux-WebViews haben
eine echte Content-Security-Policy.

Offen bleiben vor allem **Linux-Restpunkte** (der `.tex`-Notizparser im
Frontend ist noch quadratisch, Builds blockieren das Fenster ohne
Abbrechen-Knopf, keine Symlink-Prüfung, `lualatex` noch in der Engine-Liste)
und auf macOS das synchrone Entpacken einer `.pptx` auf dem Hauptthread.
Keiner dieser Punkte erlaubt Codeausführung; es sind Verfügbarkeits- bzw.
Restrisiken nach einer ausdrücklichen Benutzerbestätigung.

| Schweregrad | gefunden | behoben | teilweise | offen / akzeptiert |
|---|---|---|---|---|
| Hoch | 1 | 1 | – | – |
| Mittel | 4 + 1 (Linux) | 4 | 1 | – |
| Niedrig | 10 + 11 (Linux) | 13 | 2 | 6 |
| Info | 7 + 2 (Linux) | – | – | 9 |

## Befunde macOS / iPad

| ID | Schweregrad | Bereich | Befund | Status |
|---|---|---|---|---|
| H1 | Hoch | macOS · LaTeX | Öffnen einer `.tex` ohne PDF kompilierte ungefragt mit `latexmk`; eine `latexmkrc` im Projekt (Perl) lief als Code, `\openin`/`\read` konnte beliebige Benutzerdateien (z. B. Dotfiles) ins PDF übernehmen, `\openout` beliebige Dateien schreiben. | **behoben** — Rückfrage „Compile this LaTeX project?“ (`AppDelegate.confirmBuild`), `-norc`, `-no-shell-escape`, `openin_any=p`/`openout_any=p`/`shell_escape=f` (`SafeProcess.latexArguments`/`latexEnvironment`), Warnung bei Symlinks, die aus dem Projekt führen (`confirmProjectLinks`, `SafeProcess.linksLeavingFolder`), `lualatex` aus der Engine-Liste entfernt. Restrisiko siehe „Offene akzeptierte Punkte“. |
| M1 | Mittel | macOS · LaTeX | Dateiname als Option: eine Datei `-pdflatex=touch PWNED #.tex` wurde von `latexmk` als Option gelesen (Befehlsausführung). | **behoben** — Übergabe als `./<name>` (`SafeProcess.latexArguments`); Test `testOptionLookingFileNameStaysAPath`. |
| M2 | Mittel | macOS · Prozesse | Keine Zeitlimits für LaTeX, LibreOffice und `unzip`; eine Endlosschleife im Dokument hing ewig, Ausgabe wurde unbegrenzt gepuffert; `unzip` lief auf dem Hauptthread. | **teilweise** — `SafeProcess.run`: LaTeX 180 s, LibreOffice 120 s, `unzip` je 30 s, SIGTERM → SIGKILL an die ganze Prozessgruppe, Ausgabe auf 64 KB begrenzt, Abbrechen-Knopf im Build-HUD. **Offen:** `PptxNotes.load` läuft weiter synchron in `PresentationState.load` auf dem Hauptthread (bis zu 2 × 30 s Hänger möglich). |
| M3 | Mittel | iPad · Fernbedienung | Kopplungscode nur 4 Ziffern, keine Rotation, keine Fehlversuchsgrenze, Advertiser blieb nach der Kopplung offen. | **behoben** — 6 Ziffern (`PairingCode.make`), Vergleich in konstanter Zeit, neuer Code nach jeder Kopplung, nach 5 Fehlversuchen neuer Code + 30 s Sperre, kein Advertising während eine Fernbedienung verbunden ist (`RemoteLink.shouldAccept`/`registerFailure`). Nicht auf Geräten getestet. |
| M4 | Mittel | iPhone · Fernbedienung | Die Fernbedienung schickte den Code automatisch an **jeden** gefundenen Presenter — ein fremdes Gerät konnte ihn abgreifen. | **behoben** — Liste gefundener Presenter, Code geht nur an den gewählten (`RemoteLink.connect(to:code:)`), immer nur eine Einladung gleichzeitig. |
| L1 | Niedrig | iPhone · Protokoll | Unvalidierter `PresenterState` (z. B. `index = Int.max`, `elapsed = Int.max`, Riesen-Notiz) brachte die Fernbedienung zum Absturz. | **behoben** — Pakete > 64 KB werden verworfen, `PresenterState.sanitized()` begrenzt alle Felder, jede Seite nimmt nur die Paketart der Gegenseite an; Streams/Ressourcen werden abgelehnt. Tests in `RemoteProtocolTests`. |
| L2 | Niedrig | macOS · `.pptx` | `.pptx` wurde ungeprüft entpackt (Zip-Bombe), Symlinks im Archiv wurden gelesen, Regex über unbegrenzt große XML-Teile. | **behoben** — `unzip -l` vorab, > 100 MB entpackt wird abgelehnt; Symlinks, Pfade außerhalb des Temp-Ordners und Teile > 5 MB werden nicht gelesen; Temp-Ordner wird auch im Fehlerfall gelöscht (`PptxNotes`). Rest: die Prüfung nutzt die im Archiv *angegebenen* Größen; ein Archiv mit gefälschten Angaben bremst nur das 30-s-Limit. |
| L3 | Niedrig | macOS/iPad · `.tex`-Notizen | Notizparser O(n²) bei offenem `\note{`, keine Größenbegrenzung. | **behoben** (macOS, iPad) — `TexNotes` liegt jetzt einmal in `BeamerCore`: `.tex`/`.nav` > 5 MB werden übersprungen, offene Gruppen beenden den Scan, keine Symlinks/FIFOs. Test `testUnclosedNoteFinishesQuickly`. Linux siehe **LX12**. |
| L4 | Niedrig | macOS · Notizen | `<deck>.notes.txt` in anderer Kodierung als UTF-8 wurde als leer gelesen und beim Schließen **gelöscht** (Datenverlust). | **behoben** — Latin-1-Fallback, Speichern in der Originalkodierung, eine vorhandene Datei wird nie gelöscht, eine unlesbare nie geschrieben (`PresentationState.loadScratch`/`saveScratch`). |
| L5 | Niedrig | macOS · Mentimeter | Seiten konnten ungefragt Downloads auslösen; jede besuchte URL landete in den Recents. | **behoben** — Rückfrage vor jedem Download; Recents nur für `https://*.mentimeter.com`/`menti.com` (`MentiBrowser.isMentimeterURL`). Navigation bleibt unbeschränkt (**akzeptiert**, SSO-Anmeldungen laufen über fremde Hosts). |
| L6 | Niedrig | macOS · Export | „Save Presentation As“, „Save Whiteboard“, „Insert into PDF“ und „Save Notes“ konnten das geöffnete Deck überschreiben; Schreiben direkt ins Ziel. | **behoben** — `BoardExporter.allowsDestination`/`isSameFile` (inkl. Groß-/Kleinschreibung und Hardlinks), Schreiben über Temp-Datei + `replaceItemAt`; `writePDF` schützt zusätzlich `PresentationState.openDeckURL`. |
| L7 | Niedrig | macOS · LibreOffice | `soffice` lief mit dem Profil des Benutzers (Makro-Einstellungen, vertrauenswürdige Orte) und ohne Zeitlimit. | **teilweise** — Rückfrage vor der Konvertierung, Wegwerf-Profil (`-env:UserInstallation`), 120 s Limit. Kein Sandboxing von LibreOffice selbst (außerhalb der App nicht machbar). |
| L8 | Niedrig | macOS · Build | Die Codesign-Rückfallebene in `build-app.sh` verlor die Hardened Runtime. | **behoben** — Rückfall nur ohne `--timestamp`, `--options runtime` bleibt. Ad-hoc-Signatur (ohne Identität) hat weiterhin keine Hardened Runtime, siehe I-Punkte. |
| L9 | Niedrig | macOS · Weitergabe | Bei Build-Fehlern bietet die App an, die Datei im Editor / in der Standard-App zu öffnen. | **akzeptiert** — nur auf ausdrücklichen Klick. |
| L10 | Niedrig | macOS · Vertrauen | „Always trust this folder“ ist dauerhaft und lässt sich in der Oberfläche nicht zurücknehmen; `AppDelegate.forgetTrustedBuildFolders()` existiert, wird aber nirgends aufgerufen. | **offen** — Schalter in `SettingsView.swift` fehlt. Gemildert: für Home, `/`, Downloads, Desktop und Temp-Ordner wird Vertrauen nie angeboten oder beachtet. |
| I1 | Info | macOS | Zuletzt geöffnete Dateien, Favoriten und Security-Scoped-Bookmarks enthalten Klartextpfade (`UserDefaults`). | akzeptiert — lokal, für die Funktion nötig. |
| I2 | Info | macOS | Beim Start werden bis zu 40 Bookmarks wiederhergestellt (`AccessBookmarks.maxEntries`), d. h. breiter Dateizugriff ab Start. | akzeptiert — Komfortfunktion; Liste ist begrenzt und wird bereinigt. |
| I3 | Info | Tools | `Tools/make-signing-cert.sh` nutzt ein fest kodiertes PKCS#12-Passwort (`beamer`) für eine temporäre Datei. | akzeptiert — Datei liegt nur kurz in einem `mktemp`-Ordner, Zertifikat ist selbstsigniert und lokal. |
| I4 | Info | iPad | Das Advertising verrät Gerätename und Deck-Titel (je max. 60 Zeichen) an Geräte in der Nähe. | akzeptiert — für die Auswahl in der Fernbedienung nötig; nur solange die Fernbedienung aktiv ist. |
| I5 | Info | alle | Kein Logging von Inhalten. | positiv. |
| I6 | Info | iPad | Bildimport für den Schwarzbild-Hintergrund ohne Größenlimit. | akzeptiert — vom Benutzer gewählte Datei, schlimmstenfalls Speicherdruck. |
| I7 | Info | macOS · Build | Ohne Signatur-Identität signiert `build-app.sh` ad hoc und ohne Hardened Runtime; `Tools/pentest.sh check` meldet das als INFO. | akzeptiert — lokale Entwickler-Builds; mit `Tools/make-signing-cert.sh` gibt es eine Identität und damit `--options runtime`. |

## Befunde Linux (Tauri v2)

| ID | Schweregrad | Bereich | Befund | Status |
|---|---|---|---|---|
| LX1 | Mittel | WebView · CSP | `"csp": null` — keine Content-Security-Policy in beiden Fenstern. | **behoben** — `default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; …` in `tauri.conf.json`; `pdf.js` mit `isEvalSupported: false`. `'unsafe-inline'` nur für Styles (`dangerousDisableAssetCspModification: ["style-src"]`). |
| LX2 | Niedrig | Asset-Protokoll | Asset-Scope `"**"`: die WebViews durften jede Datei des Benutzers laden. | **behoben** — Scope startet leer, `grant_deck` gibt nur den Ordner des geöffneten Decks frei (nicht rekursiv). |
| LX3 | Niedrig | `compile_tex` | Wie H1/M1/M2: `latexmkrc` ausgeführt, keine Paranoid-Variablen, kein Zeitlimit, Ausgabe unbegrenzt. | **behoben** — Rückfrage im Frontend (`confirmTrust`), `engine_args`/`tex_env`/`latex_input`, `TEXMFOUTPUT` entfernt, `run_capped` mit 180 s, eigener Prozessgruppe und 64 KB Log; Hinweistext bei Paranoid-Ablehnungen (`PARANOID_HINT`). |
| LX4 | Niedrig | `convert_office` | Kein Zeitlimit, Benutzerprofil, Überschreiben eines PDFs, das zwischen Prüfung und Konvertierung entsteht (TOCTOU). | **teilweise** — Rückfrage, Wegwerf-Profil, 120 s Limit. TOCTOU **akzeptiert** (lokaler Wettlauf, Ziel ist ohnehin das Geschwister-PDF). |
| LX5 | Niedrig | `read_text` | Liest beliebig große Dateien und auch FIFOs/Geräte. | **behoben** — nur reguläre Dateien ≤ 5 MB. |
| LX6 | Niedrig | `pptx_notes` | `zip_text` entpackte Einträge unbegrenzt (Zip-Bombe im Speicher). | **behoben** — Einträge > 5 MB abgelehnt, Lesen über `take(5 MB)`. |
| LX7 | Niedrig | localStorage | `JSON.parse` ohne `try` (kaputter Eintrag = leerer Startbildschirm), `lastSlideByPath` wuchs unbegrenzt. | **behoben** — `loadJSON` mit Formprüfung, Positionen werden auf die Recents beschnitten. Klartextpfade bleiben (Info, wie I1). |
| LX8 | Niedrig | CI | `contents: write` für den ganzen Job, Actions per Tag, Tauri-CLI über `npx` ohne Version. | **behoben** — Build-Job `contents: read`, Release als eigener Job mit `contents: write`, alle Actions auf Commit-SHA, Tauri-CLI 2.12.4, `cargo --locked`. Release bei jedem Push auf `main`: **akzeptiert** (gewollt). |
| LX9 | Niedrig | IPC | Alle Commands sind aus beiden Fenstern aufrufbar (keine Capabilities pro Fenster), `withGlobalTauri: true`; `grant_deck` nimmt jeden absoluten Dateipfad. | **akzeptiert** — beide Fenster laden nur eigene, gebündelte Seiten; mit der CSP (LX1) und den escapenden DOM-Senken gibt es keinen bekannten Weg, fremdes Skript einzuschleusen. |
| LX10 | Info | IPC | `file_exists` / `tex_candidates` beantworten Existenzfragen zu beliebigen Pfaden. | akzeptiert — nur für eigenes Frontend erreichbar (siehe LX9). |
| LX11 | Niedrig | `compile_tex` | Restabweichungen zu macOS: keine Symlink-Prüfung vor dem Build (ein Link `s.tex -> ../geheim` umgeht `openin_any=p`), `lualatex` steht noch in `LATEX_ENGINES` (`\directlua` → `os.remove`), „Always trust this folder“ auch für `/tmp`, Downloads usw. | **offen** — alles erst nach Bestätigung des Benutzers ausnutzbar; Vorlage ist `SafeProcess.linksLeavingFolder` bzw. `AppDelegate.isSharedFolder`. |
| LX12 | Niedrig | `texnotes.js` | Der Frontend-Notizparser ist noch die alte, quadratische Fassung: ein offenes `\note{` gefolgt von vielen weiteren `\note{` lässt `bracedGroup` jedes Mal bis zum Dateiende laufen. Gemessen: 2 000 / 4 000 / 8 000 Zeilen → 0,14 / 0,47 / 1,9 s; eine 3,7-MB-Datei (unter dem 5-MB-Limit) blockiert die Konsole hochgerechnet ~10 min. | **offen** — Swift-Fix (`TexNotes.skipOptional`/Abbruch bei offener Gruppe) nach `Linux/ui/js/texnotes.js` portieren. |
| LX13 | Niedrig | Verfügbarkeit | `compile_tex`, `convert_office` und `pptx_notes` sind synchrone Tauri-Commands; Tauri führt diese im IPC-Handler auf dem Hauptthread aus (`tauri-macros` 2.6.3, `body_blocking`). Ein Build friert das Fenster bis zu 180 s ein; es gibt keinen Abbrechen-Knopf. | **offen** — als `async fn` bzw. `#[tauri::command(async)]` deklarieren und ein Abbrechen-Command ergänzen. |
| LX14 | Info | Build | `compile_tex` schreibt Hilfsdateien und PDF neben die Quelle. | akzeptiert — gewolltes Verhalten wie auf macOS. |

## Umgesetzte Korrekturen

- **Neue Bibliothek `BeamerCore`** (Foundation only, `Sources/BeamerCore`):
  `SafeProcess` (Argument-/Umgebungsbau, Lauf mit Zeitlimit, Abbruch und
  begrenzter Ausgabe, Symlink-Scan), `TexNotes` (gehärteter Parser, jetzt auch
  für das iPad statt der alten Kopie), `RemoteProtocol` (Paketgrenze,
  `sanitized()`, `PairingCode`). Unter Linux testbar (`swift test`).
- **LaTeX** (macOS/Linux): Rückfrage vor jedem Build, `-norc`,
  `-no-shell-escape`, Paranoid-Modus, `./<name>` statt Dateiname, Zeitlimit
  180 s, Abbrechen (macOS), Symlink-Warnung (macOS), kein `lualatex` (macOS).
- **LibreOffice**: Rückfrage, Wegwerf-Profil, Zeitlimit 120 s.
- **`.pptx`**: Größenprüfung vor dem Entpacken, keine Symlinks, Teile ≤ 5 MB.
- **iPad-Fernbedienung**: 6-stelliger rotierender Code, Sperre nach 5
  Fehlversuchen, gezielte Kopplung, Paket- und Zustandsvalidierung.
- **Dateischutz**: Exporte überschreiben nie das offene Deck, Schreiben über
  Temp-Dateien; `notes.txt` wird nie mehr gelöscht.
- **Linux**: CSP, leerer Asset-Scope mit `grant_deck`, Lese-Limits, robuster
  localStorage.
- **Build/CI**: Hardened Runtime im Signatur-Rückfall, minimale
  Workflow-Rechte, SHA-gepinnte Actions, gepinnte Tauri-CLI, neuer
  `tests`-Workflow.

## Bestätigt sicher

- **Keine Geheimnisse** im Repository oder in den Apps (keine API-Schlüssel,
  Tokens, Passwörter außer I3).
- **Keine Shell**: alle externen Werkzeuge werden mit Argument-Arrays
  gestartet (`Process`, `std::process::Command`), nie über `sh -c`.
- **Mentimeter**: keine JS-Brücke ins Native; `evaluateJavaScript` wird nur
  mit konstanten Skripten aufgerufen (`MentiAudience`).
- **Notizen**: Links in Notizen sind nicht klickbar; unter Linux erzeugt
  `NotesMarkup.html` nur eigene `<span>`s um escapten Text (27 Node-Tests,
  u. a. `javascript:`-Links und verschachteltes Markup).
- **DOM-Senken (Linux)**: alle Stellen, die Dateinamen, Pfade oder Logs
  anzeigen, nutzen `textContent` bzw. escapen.
- **pdf.js 4.10.38**: nicht von CVE-2024-4367 betroffen (behoben ab 4.2.67);
  zusätzlich `isEvalSupported: false` und CSP ohne `unsafe-eval`.
- **Drag & Drop** nimmt nur Datei-URLs an; **kein URL-Schema** registriert;
  **App Transport Security** im Standard (kein `NSAllowsArbitraryLoads`).
- **Temp-Ordner** mit zufälligen Namen (`UUID`), werden nach Gebrauch gelöscht.
- **ReferenceDeck** (übersetztes Deck) sucht nur Geschwisterdateien im selben
  Ordner, keine Pfad-Traversierung.
- **MultipeerConnectivity** mit `encryptionPreference: .required`.

## Offene akzeptierte Punkte

| Punkt | Begründung |
|---|---|
| LaTeX nach Bestätigung: `biber` ignoriert die kpathsea-Variablen (`\addbibresource{/abs/pfad}` wird gelesen); Symlinks nach „Compile Anyway“. | Die Rückfrage ist die Hauptschutzlinie; ein vollständiges Sandboxing von TeX ist ohne eigenen Container nicht machbar. |
| `PptxNotes` entpackt synchron auf dem Hauptthread (M2-Rest). | Begrenzt auf 2 × 30 s; Verschieben in eine Hintergrundaufgabe ist für die nächste Iteration vorgesehen. |
| Vertrauensliste nicht zurücksetzbar (L10). | Kleiner UI-Nachtrag in `SettingsView.swift`. |
| Mentimeter-Navigation ohne Allow-List (L5). | SSO-Anmeldungen führen über fremde Hosts. |
| Ad-hoc-signierte Builds ohne Hardened Runtime (I7). | Nur lokale Entwickler-Builds; `Tools/make-signing-cert.sh` erzeugt eine Identität, mit der `build-app.sh` die Hardened Runtime setzt. |
| `SafeProcess.linksLeavingFolder` ohne eigenen Unit-Test, keine Symlink-Fixture im Parcours. | Funktion wurde beim Implementieren in einem Wegwerf-Test geprüft; ein dauerhafter Test in `SafeProcessTests` steht aus. |
| Linux LX4 (TOCTOU), LX9, LX10, LX14. | Lokale, vom Benutzer ausgelöste Abläufe; kein Fremdinhalt im eigenen Frontend. |
| Linux LX11–LX13. | Offen, nicht akzeptiert — Verfügbarkeits- bzw. Restrisiken; als nächste Korrekturen eingeplant. |
