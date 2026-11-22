# AlbumArtwork-Screensaver für macOS — Design

Stand: 2026-11-22

## 1. Worum es geht

Auf dem Mac mini des Nutzers soll ein echter macOS-Screensaver laufen, den er in
den Systemeinstellungen auswählt. Er zeigt die Album-Cover der eigenen
Musiksammlung als bewegte Wand, in Optik und Bewegung wie
[lingkuma/AlbumArtwork](https://github.com/lingkuma/AlbumArtwork) (Web-App,
three.js, MIT-Lizenz), das wiederum den alten iTunes-Screensaver nachahmt.

Quelle der Cover ist ein lokaler Musikordner mit MP3-Dateien; die Cover sind in
den Dateien eingebettet. Der Ordner wächst, neue Musik soll ohne Zutun auf der
Wand erscheinen.

Referenz für alle Animationswerte unten: `index.html` im Original, Commit
`e1b421c`. Zeilenangaben beziehen sich auf diesen Stand.

## 2. Ziele

1. Ein `.saver`-Bundle, per Doppelklick installierbar, in den Systemeinstellungen
   auswählbar.
2. Der Musikordner wird einmal in den Screensaver-Optionen gewählt; die Freigabe
   bleibt über Neustarts erhalten.
3. Eingebettete Cover aus MP3 werden ausgelesen, **ein Cover pro Album**.
4. Wand und alle sieben Animationen wie im Original (Abschnitt 8).
5. Neue, geänderte und gelöschte Dateien werden beim nächsten Start
   berücksichtigt, ohne alles neu zu lesen. Die Wand startet sofort aus dem Cache.
6. Läuft auf jedem angeschlossenen Bildschirm.

## 3. Nicht-Ziele

- Keine Online-Quellen (MusicBrainz, Spotify, YouTube) und kein Nachladen
  fehlender Cover aus dem Netz.
- Keine Interaktion: kein Klick auf Cover, kein 3D-Showcase, kein Player, keine
  Dialoge, keine Kirschblüten. Jede Eingabe beendet den Screensaver.
- Keine Cover aus losen Bilddateien (`cover.jpg`, `folder.jpg`). Später leicht
  ergänzbar.
- Keine Apple-Music-/iTunes-Bibliothek, kein FLAC/OGG.
- Keine Verteilung an Dritte: kein Notarisieren, keine Developer-ID nötig.
  Ad-hoc-signiert für den eigenen Mac.

## 4. Anti-Ziele (Fehlschlag, auch wenn es technisch läuft)

- Löcher oder schwarze Flächen in der Wand, Ruckeln.
- Dasselbe Album mehrfach, weil jeder Titel einzeln zählt.
- Schwarzer Bildschirm, während erst eingelesen wird (außer beim allerersten Mal).
- Cache wird geleert, weil die Musikplatte gerade nicht eingehängt ist.
- Der Screensaver-Prozess frisst nach dem Aufwachen weiter CPU/GPU.
- Irgendein Schreibzugriff auf den Musikordner. Strikt nur lesend.

## 5. Randbedingungen

- **Sandbox.** macOS lädt `.saver`-Bundles in Apples `legacyScreenSaver.appex`.
  Der Prozess ist sandboxed, kann keine Datenschutz-Abfragen zeigen, und eigene
  Daten landen im Container
  `~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/`.
  Eigene Entitlements kann ein `.saver` nicht mitbringen.
- **Keine WebView.** WKWebView ist in diesem Prozess seit Sonoma unzuverlässig
  (Zweitmonitor, Inhalt verschwindet).
- **Mehrere Instanzen.** Pro Bildschirm eine `ScreenSaverView`, dazu die kleine
  Vorschau in den Systemeinstellungen. Sie dürfen nie gleichzeitig denselben
  Cache beschreiben.
- **Bekannter Fehler:** der Host-Prozess läuft nach dem Beenden weiter. Der
  Screensaver muss auf `stopAnimation` und die verteilte Notification
  `com.apple.screensaver.willstop` hin alles anhalten.
- **Bauen ohne Xcode.** Command Line Tools und ein Skript, wie `build-app.sh` bei
  BeamerPresenter. Ad-hoc-`codesign`.
- **Entwicklung.** Claude arbeitet auf Linux (Swift 6.0.3 vorhanden). Kompiliert
  wird zusätzlich in GitHub Actions auf `macos-latest` — das Repo baut dort
  schon BeamerPresenter, auch bei Pushes auf `claude/**`. So fallen
  Compilerfehler ohne den Mac mini auf. Ausprobieren im echten Screensaver nur
  auf dem Mac mini über Remote Control.
- **Unbekannt bis zum ersten Verbinden:** macOS-Version und Chip des Mac mini,
  Lage des Musikordners (interne Platte, externe Platte, NAS). Das
  Deployment-Target richtet sich nach dem Mac mini; Annahme bis dahin macOS 14+,
  arm64.

## 6. Wege

### Zeichnen (Claudes Entscheidung)

| Weg | Bewertung |
|---|---|
| **Core Animation** — `CALayer` mit `CATransform3D`, Perspektive über `sublayerTransform.m34` | **Gewählt.** Flache Quadrate, die sich im Raum drehen und fallen, sind genau dafür gemacht. Teil von macOS, keine Abhängigkeit, GPU-komponiert. |
| SceneKit | Fast 1:1-Übersetzung des three.js-Codes, aber seit WWDC 2025 „soft-deprecated“. |
| WKWebView mit dem Original-HTML | Verworfen: im Screensaver-Prozess unzuverlässig, und der Lokal-Modus des Originals ist ohnehin defekt (README sagt `?local`, Code prüft `local=true`; der Scan trägt blind `1.jpg`–`8.jpg` ein). |

### Ordnerzugriff (Entscheidung des Nutzers)

| Weg | Bewertung |
|---|---|
| **A — alles im Screensaver.** Ordnerwahl im Optionen-Blatt (`NSOpenPanel`), Freigabe als Security-Scoped Bookmark; der Screensaver liest selbst ein. | **Gewählt.** Eine einzige Datei, Bedienung komplett in den Systemeinstellungen. Risiko: nicht dokumentiert, ob `NSOpenPanel` und Bookmarks im `legacyScreenSaver` funktionieren → Spike vorab. |
| B — Screensaver plus Hilfs-App. Eine normale App liest ein und legt die Cover in `/Users/Shared/AlbumArtwork` ab; der Screensaver liest nur dort. | **Rückfall**, falls der Spike scheitert. Funktioniert sicher. Damit neue Musik weiter ohne Zutun erscheint (Ziel 5), startet ein LaunchAgent die Hilfs-App bei der Anmeldung und danach regelmäßig (Vorschlag: stündlich) zum Einlesen. |

Das Design ist so geschnitten, dass Scanner, Cache und Wand bei A und B gleich
bleiben. Bei B wandert der Scanner in die Hilfs-App, und der Cache liegt in
`/Users/Shared/AlbumArtwork` statt im Container. Ordnerwahl, Status und „Jetzt
neu einlesen“ wandern ebenfalls in die Hilfs-App; das Optionen-Blatt des
Screensavers behält Reihen und Intervall und verweist auf die Hilfs-App
(Claudes Entscheidung).

## 7. Spike (vor dem eigentlichen Bau)

Ein Wegwerf-`.saver` auf dem Mac mini. Er prüft, jeweils im echten Screensaver
(nicht nur in der Vorschau):

1. Öffnet sich ein `NSOpenPanel` aus dem Optionen-Blatt (`configureSheet`)?
2. Lässt sich ein Security-Scoped Bookmark auf den gewählten Ordner anlegen, in
   `ScreenSaverDefaults` speichern, nach `killall legacyScreenSaver` wieder
   auflösen und der Ordner dann rekursiv lesen?
3. Lässt sich aus einer MP3 darin das Cover auslesen?
4. Lässt sich in den eigenen Cache-Ordner schreiben und von dort wieder lesen?
5. Ist der Musikordner auch **ohne** Bookmark lesbar, nur über den
   gespeicherten Pfad?
6. Punkte 2–5 nach einem **Neustart des Mac mini** wiederholen, mit dem echten
   Musikordner auf dem echten Laufwerk.

**Bewertung (Claudes Entscheidung).** Weg A gilt, wenn der Screensaver den
echten Musikordner nach einem Neustart zuverlässig lesen kann und die Einstellung
dafür in den Systemeinstellungen liegt. Wie der Ordner gewählt wird, ist
zweitrangig:

- Bevorzugt: `NSOpenPanel` plus Bookmark.
- Öffnet sich das Panel nicht: Ordner per Ziehen und Ablegen oder als Pfad im
  Optionen-Blatt eintragen.
- Hält das Bookmark nicht, ist der Ordner aber auch ohne lesbar: gespeicherter
  Pfad reicht — aber nur, wenn Punkt 6 das auf dem echten Laufwerk bestätigt.
  Externe und Netzlaufwerke sperrt macOS oft, wenn der Zugriff nicht über das
  Panel kam, und das kann sich mit macOS-Updates ändern.

Sonst gilt Weg B. Der Spike wird danach weggeworfen.

### Handarbeit am Mac mini (Entscheidung des Nutzers)

Der Nutzer erledigt alles, was nicht übers Terminal geht, selbst an festen
Prüfpunkten: Installieren per Doppelklick, Screensaver in den
Systemeinstellungen auswählen, Musikordner in den Optionen wählen, Neustart,
Hinschauen. Claude bereitet jeden Prüfpunkt so vor, dass er nur wenige Minuten
dauert, und sagt vorher genau, was zu klicken und worauf zu achten ist. Was
übers Terminal prüfbar ist, prüft Claude selbst: Logs (`log stream`), Inhalt des
Caches, CPU-Last von `legacyScreenSaver` nach dem Aufwachen.

Prüfpunkte:

1. **Spike** — Ordner wählen, Screensaver auslösen, Neustart, nochmal.
2. **Erste Wand** — Gitter und Animationen ansehen, mit dem Original-GIF
   vergleichen.
3. **Aktualisierung** — eine neue MP3 in den Ordner legen, Screensaver neu
   starten, das Album muss erscheinen. Musikplatte abziehen (falls extern), der
   Cache muss bleiben.
4. **Abnahme** — alle Bildschirme, Aufwachen ohne Restlast.

## 8. Wie es aussieht und sich bewegt (vom Original übernommen)

**Maßeinheit.** Das Original rechnet in Welt-Einheiten, bei denen die
Bildschirmhöhe genau 20 Einheiten ist (`frustumSize = 20`). Alle Längen unten
sind in diesen Einheiten; in Punkte umrechnen mit `Bildschirmhöhe / 20`.

**Szene.** Schwarzer Hintergrund. Perspektive wie eine Kamera mit 45° vertikalem
Blickwinkel, die so weit weg steht, dass die Ebene z = 0 genau die
Bildschirmhöhe füllt: Abstand d = 10 / tan(22,5°) ≈ 24,14 Einheiten ≈ 1,207 ×
Bildschirmhöhe. In Core Animation: `m34 = −1/d` mit d in Punkten. Cover sind
flach und unbeleuchtet, ohne Schatten.

**Gitter** (Z. 3734–3790). Standard 6 Reihen, kein Abstand. Kantenlänge =
Bildschirmhöhe / Reihen. Spalten = aufgerundet(Breite / Kantenlänge), das Gitter
ist horizontal zentriert, an beiden Rändern sind also angeschnittene Cover zu
sehen. Nicht-quadratische Bilder werden mittig quadratisch beschnitten.

**Erstbefüllung** (Z. 3863). Möglichst lauter verschiedene Alben; Wiederholungen
nur, wenn es weniger Alben als Felder gibt.

**Takt** (Z. 3937–3985). Alle `Intervall + Zufall(0–1000 ms)` (Standard-Intervall
3000 ms) wird ein Animationstyp nach Gewicht gezogen:

| Typ | Gewicht |
|---|---|
| Flip | 15 |
| Fallen | 15 |
| Rollen (linkedDrop) | 15 |
| Abrollen (rollDrop) | 15 |
| Nadel (pinRotation) | 15 |
| Reihe rollt ab (rowRollDrop) | 12,5 |
| Reihe fällt (rowDrop) | 12,5 |

Bei den fünf Einzeltypen werden **3–6 verschiedene** zufällige Cover gewählt und
im Abstand von 200 ms gestartet. Cover, die sich gerade bewegen, werden
übersprungen. Grundregel aller Animationen: Das Nachfolge-Cover liegt schon
bereit (bzw. wird vorher geladen), bevor das alte sich wegbewegt — es entsteht
nie ein Loch.

**Die sieben Animationen:**

1. **Flip** (Z. 4027–4128). Neues Cover erst fertig laden, dann um die eigene
   senkrechte Achse 0 → 180° drehen, 900 ms, Easing `0,5 − 0,5·cos(π·t)`. Die
   Rückseite zeigt das neue Cover, nicht gespiegelt.
2. **Fallen** (Z. 4130–4312). Nachfolger liegt sofort dahinter. Dauer 2200 ms.
   - 0–20 %: kippt um die waagerechte Mittelachse nach vorn bis 0,25 rad
     (easeOutQuart), hebt sich um sin·0,1 an, dreht leicht um die Hochachse (30 %
     des Zielwinkels), löst sich nach vorn von der Wand.
   - 20–100 %: fällt mit Schwerkraft (s = ½·g·t², g = 9,8, so skaliert, dass es
     unten aus dem Bild fällt), überschlägt sich beschleunigt um die waagerechte
     Achse (Start 0,5 rad/s, +2,5 rad/s², Richtung zufällig), dreht zur
     zufälligen Hochachsen-Neigung ±0,4 rad, wackelt um die Blickachse
     (Turbulenz), kommt nach vorn (easeInQuart bis max(0,8; Kante/2)), wird bis
     zu 15 % größer und blendet in den letzten 40 % aus (1 − easeInQuart).
3. **Rollen** (Z. 4314–4615). Ziel ist ein Cover weiter unten mit
   Manhattan-Abstand 4, 8 oder 12 (zufällig unter den drei nächsten). Weg: erst
   waagerecht, dann senkrecht. Pro Feld 300 ms (ease-in-out-quad) und 90° Drehung
   in der Bildebene, Richtung je nach Schritt; dabei leichter Bogen (10 % der
   Kante) und leichte Vergrößerung, über den anderen Covern. Am Start erscheint
   ein neues Cover; am Ziel ersetzt das rollende Cover das dortige (Gesamtdrehung
   ist ein Vielfaches von 360°). Kein Ziel gefunden → Fallen.
4. **Abrollen** (Z. 4617–4808). Überschlägt sich Feld für Feld nach unten aus
   dem Bild: pro Feld 180° um die waagerechte Achse, Kreisbogen mit Radius
   Kante/2, 350 ms + 80 ms Pause, `Reihen − Startreihe + 2` Schritte. Am Start
   erscheint ein neues Cover.
5. **Nadel** (Z. 4862–5480). In einem 2×2-Block schwenkt das Cover um den
   Blockmittelpunkt (die „Nadel“, wo sich vier Ecken treffen) ins diagonal
   gegenüberliegende Feld, 800 ms, gleichmäßig. Zwischen 30 % und 70 % läuft es
   **unter** den beiden anderen Covern des Blocks durch und bekommt dort, bei
   etwa 50 %, unsichtbar ein neues Album. Am Start erscheint ein neues Cover, am
   Ziel ersetzt es das dortige. Danach kettet es mit 80 % Wahrscheinlichkeit
   weiter (höchstens 5 Glieder): Nadel beim Nachbarn in Laufrichtung, Nadel beim
   Cover darunter, oder Fallen/Abrollen (50:50) beim Nachbarn darüber bzw.
   daneben — zufällig unter den möglichen. Kein gültiger Block → Flip.
6. **Reihe rollt ab** (Z. 4810–4834). Zufällige Reihe aus der oberen Hälfte;
   jedes Cover von links nach rechts startet „Abrollen“, Cover *i* nach
   *i* × Zufall(200–400 ms).
7. **Reihe fällt** (Z. 4836–4860). Dasselbe mit „Fallen“.

**Abweichung vom Original (Claudes Entscheidung):** Das Original zieht für neue
Cover rein zufällig. Hier werden Alben bevorzugt, die gerade nicht sichtbar
sind, solange die Sammlung groß genug ist. Grund: Anti-Ziel „dasselbe Album
mehrfach“.

## 9. Einlesen, Cache und Aktualisierung

**Cover pro Album.** Album-Schlüssel = Album-Titel + Album-Interpret
(ersatzweise Interpret), normalisiert (Groß/Klein, Leerraum). Ohne Tags: Hash
der Bilddaten. Zusätzlich werden byte-gleiche Bilder nur einmal gezeigt. Das
Cover stammt vom ersten gefundenen Titel des Albums. Titel ohne eingebettetes
Cover werden übersprungen.

**Cache.** Liegt im Caches-Verzeichnis des Screensavers (Weg A: im
`legacyScreenSaver`-Container). Enthält pro Album ein quadratisch
beschnittenes, verkleinertes Bild und einen Index:
Datei (relativer Pfad, Größe, Änderungsdatum) → Album-Schlüssel;
Album-Schlüssel → Cache-Bild. Der Index wird atomar geschrieben.

**Ablauf bei jedem Start:**

1. Index laden, Wand sofort aus dem Cache zeigen.
2. Im Hintergrund, mit niedriger Priorität: Musikordner rekursiv durchgehen
   (versteckte Dateien und Pakete auslassen), `.mp3` mit dem Index vergleichen.
   Neu oder geändert (Größe/Datum) → Cover und Tags lesen. Verschwunden → aus
   dem Index nehmen; ein Album ohne verbleibende Titel → Cache-Bild löschen.
3. Neue Alben kommen sofort in den Topf der laufenden Wand und erscheinen mit
   den nächsten Animationen.
4. **Gelöscht wird nur nach einem vollständigen, fehlerfreien Durchlauf.** Ist
   der Ordner nicht erreichbar (Platte nicht eingehängt, NAS schläft) oder bricht
   der Durchlauf ab, bleibt der Cache unverändert. Nächster Versuch beim nächsten
   Start.
5. Pro Prozess läuft höchstens ein Durchlauf; über Prozesse hinweg sichert eine
   Sperrdatei im Cache-Ordner ab.

**Erster Start.** Kein Ordner gewählt → schwarzer Bildschirm mit ruhigem Hinweis
„Musikordner in den Screensaver-Optionen wählen“. Ordner gewählt, Cache leer →
dezenter Fortschrittstext, bis genug Cover für eine Wand da sind; dann startet
die Wand und füllt sich weiter.

## 10. Optionen-Blatt (Claudes Entscheidung)

- Musikordner wählen, gewählter Pfad sichtbar.
- Status: „1.234 Alben · zuletzt eingelesen vor 2 Std.“ bzw. Hinweis, wenn der
  Ordner nicht erreichbar ist oder die Freigabe abgelaufen ist.
- „Jetzt neu einlesen“.
- Reihen (Standard 6, 3–12) und Intervall (Standard 3 s, 1–10 s), wie im
  Original einstellbar. Animationsgewichte und Hintergrundfarbe bleiben fest.
- Gespeichert in `ScreenSaverDefaults` unter der Bundle-ID.

## 11. Aufbau des Codes (Claudes Entscheidung)

Zwei Teile, damit die Logik auf Linux getestet werden kann:

- **`AlbumArtworkCore`** — reines Swift ohne AppKit: Gitter-Geometrie,
  gewichtete Auswahl, Ziel- und Wegsuche für Rollen und Nadel samt Verkettung,
  Album-Schlüssel, Index-Abgleich (neu/geändert/weg, keine Löschung bei
  unvollständigem Durchlauf). Mit `swift test` auf Linux und macOS testbar.
- **`AlbumArtworkSaver`** — macOS: `ScreenSaverView`, Core-Animation-Wand und
  -Animationen, Cover-Auslesen, Bild-Cache, Optionen-Blatt, Bookmark.

Dazu ein `build-saver.sh`, das `AlbumArtwork.saver` baut und ad-hoc signiert,
und eine kleine **Test-App**, die dieselbe Wand in einem normalen Fenster zeigt —
für die Arbeit an den Animationen, ohne auf den Screensaver warten zu müssen. Sie
läuft ohne Sandbox und ersetzt deshalb keinen Test im echten Screensaver.
**Ort (Entscheidung des Nutzers):** eigener Ordner `AlbumArtworkSaver/` im
BeamerPresenter-Repo, neben `iOS/` und `Linux/`. Darin ein eigenes
`Package.swift`, ein README (nennt das Original und dessen MIT-Lizenz) und eine
eigene Version (Start 1.0) mit eigenem `CHANGELOG.md`. Unabhängig davon gilt die
Repo-Regel aus `CLAUDE.md`: Jede Änderung, die in `main` landet, erhöht auch die
BeamerPresenter-Version.

**CI:** eigener Workflow `.github/workflows/build-saver.yml` mit Pfadfilter
`AlbumArtworkSaver/**`. Er baut auf `macos-latest` das `.saver`, lässt
`swift test` laufen und hängt das `.saver` als Artefakt an. Der bestehende
BeamerPresenter-Workflow bleibt unberührt.

## 12. Dem Builder überlassen

- Cover-Auslesen mit AVFoundation oder eigenem ID3v2-Leser. Anforderungen:
  ID3v2.2–2.4, Bild-Frames `APIC`/`PIC`, Tags Album, Album-Interpret,
  Interpret. Ein eigener Leser liest nur den Tag-Kopf (schneller beim
  Erst-Scan großer Sammlungen, auf Linux testbar); AVFoundation ist robuster.
- Animationstechnik in Core Animation: vorberechnete Keyframe-Animationen oder
  Bild-für-Bild-Update. Vorgabe: flüssig mit 60 fps, wenig CPU.
- Größe der Cache-Bilder. Vorgabe: bei 6 Reihen auf dem größten angeschlossenen
  Bildschirm scharf; beim Laden auf die tatsächliche Feldgröße herunterrechnen.
- Wie viele Cover „genug für eine Wand“ beim ersten Start sind.
- Ob der Zufallsanteil des Takts einmal pro Start (wie im Original) oder bei
  jedem Takt neu gewürfelt wird.
- Index-Format, genaue Normalisierung der Album-Schlüssel, Modul- und
  Dateiaufteilung, Tests.
