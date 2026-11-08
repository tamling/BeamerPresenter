# BeamerPresenter — Usability-Review

> **Methode:** heuristische Evaluation (Nielsens zehn Heuristiken) und Cognitive
> Walkthrough der Kernaufgaben einer Vorlesung auf **macOS**, mit Zählung der Klickpfade
> (Klicks, Tasten, Dialoge) direkt aus dem Code (`AppDelegate.setupMenu`, `handleKey`,
> `PresenterView`, `WelcomeView`, `SettingsView`). Abgleich der Tastenbelegung mit dem
> Linux-Port (`Linux/ui/js/presenter.js`) und der iPad-App
> (`iOS/BeamerPresenter/KeyCommandView.swift`). Keine Probandentests; die App konnte auf
> der Prüfmaschine nicht gestartet werden — Aussagen zum Aussehen sind aus dem Code
> abgeleitet und auf einem Mac zu bestätigen.
>
> **Stand: 2026-11-04**

---

## Methodik

1. **Kernaufgaben** aus dem Vorlesungsalltag festgelegt (öffnen, starten, Zielschirm,
   Timer, Schwarzbild, Zeichnen, Whiteboard, Sichern, Mentimeter, Beenden, Notizen).
2. Für jede Aufgabe **alle Wege** im Code gesucht (Startbildschirm, Menü, ⌘-Kürzel,
   Einzeltaste, Knopf in der Steuerleiste, Einstellungen) und die Schritte gezählt.
3. Jede Abweichung von macOS-Konventionen und jede Stelle, an der man sich vor Publikum
   „verklicken“ kann, als **Reibungspunkt** notiert: 🔴 stört im Vortrag / Datenverlust,
   🟡 kostet Zeit oder verwirrt, 🟢 Feinschliff.
4. Vorschläge in drei **Stufen** nach Aufwand geordnet; Stufe 1 ist in dieser Iteration
   umgesetzt (siehe Anhang).

---

## Tastatur und Menü (macOS)

Einzeltasten wirken nur mit geöffnetem Deck und nicht, während ein Textfeld den Fokus hat
(dort steuern nur Pfeile/Bild-Tasten die Folien).

| Funktion | Einzeltaste | Menü | ⌘-Kürzel | Knopf (Tooltip) |
|---|---|---|---|---|
| Nächste / vorige Folie | → Leertaste Bild↓ / ← Bild↑ | Presentation › Next/Previous Slide | ⌘] / ⌘[ | Prev / Next |
| Erste / letzte Folie | Pos1 / Ende | Presentation › First/Last Slide | – | – |
| Übersicht | G | Presentation › Toggle Overview | **⌘1** | Grid |
| Publikum schwarz | B | Presentation › Black Out Audience | ⌘B | Black |
| Schwarzbild-Nachricht/-Bild | – | Presentation › Black Screen › … | – | – |
| Publikum Vollbild | **F** (neu, nur mit 2. Bildschirm) | Presentation › Audience Full Screen | – | – |
| Übersetztes Deck | E | Presentation › Show Translated Deck in Console | ⌘E | Transl |
| Timer Start/Stopp | **T** (neu) | Presentation › Start / Stop Timer | ⌘T | Start/Pause |
| Timer zurücksetzen | R | Presentation › Reset Timer | ⌘R | Reset |
| Stift / Laser | P / L | Tools › Pen / Laser Pointer | ⌘P / ⌘L | Pen / Laser |
| Strich rückgängig | Z | Tools › Undo Stroke | **⌘Z** | Undo |
| Tinte löschen | C | Tools › Clear Ink | – | Clear |
| Whiteboard | W | Whiteboard › Toggle Whiteboard | **–** | Board |
| Whiteboard sichern / einfügen | – | Whiteboard › Save … / Insert into PDF … | ⌘S / ⌘I | – |
| Deck mit Tinte sichern | – | File › Save Presentation As… | ⌘⇧S | – |
| Notizen sichern | – | File › Save Notes… | – | – |
| Mentimeter | – | File › Mentimeter… | – | – |
| Präsentation schließen | (Esc: **nein**) | File › Close Presentation | ⌘W | Exit |
| Einstellungen / Beenden | – | BeamerPresenter › Settings… / Quit | ⌘, / ⌘Q | – |
| Werkzeug/Board/Übersicht schließen | Esc (Reihenfolge: Auswahl → Werkzeug → Board → Übersicht) | – | – | Cursor |

### Plattformvergleich der Einzeltasten

| Taste | macOS | Linux | iPad (Hardware-Tastatur) |
|---|---|---|---|
| T | Timer (neu) | Timer | – |
| F | Publikum Vollbild (neu, nur mit 2. Bildschirm) | Publikum Vollbild | – |
| P / L | Stift / Laser | – | – |
| C | Tinte der Folie löschen (mit Z rückholbar) | **Whiteboard** leeren (nur bei offenem Board) | – |
| Z | Strich rückgängig (Folie und Board) | Strich rückgängig (**nur Whiteboard**) | – |
| G / E / W / R | ja | ja | – |
| B | Schwarz | Schwarz | Schwarz |
| `.` (Presenter-Fernbedienungen senden oft `.` für Schwarz) | – | – | Schwarz |
| ↑ / ↓ | – | – | vorige / nächste Folie |
| Esc | Auswahl → Werkzeug → Board → Übersicht | Übersicht → Board → **Schwarzbild aufheben** | Board schließen |

---

## Klickpfade pro Kernaufgabe (macOS)

Gezählt sind Aktionen (Klick, Taste, Dialogknopf); Tippen von Text zählt als eine Aktion.

**1 · Deck öffnen und loslegen**

| Weg | Schritte | Anmerkung |
|---|---|---|
| Karte auf dem Startbildschirm | 1 | Favoriten/Recents als Karten |
| Datei auf das Fenster ziehen | 1 Geste | |
| ⌘O → Datei → Öffnen | 3 | |
| … dann Schwarzbild aufheben (B / Black) | +1 | Deck öffnet standardmäßig schwarz; Timer startet jetzt erst hier (neu) |

**2 · LaTeX-Quelle ohne PDF öffnen**

| Weg | Schritte | Anmerkung |
|---|---|---|
| ⌘O → `talk.tex` → Öffnen → „Compile“ | 4 | +1 gegenüber vorher (Sicherheits-Rückfrage, H1) |
| … mit „Always trust this folder“ beim nächsten Mal | 3 | in Downloads/Desktop/Home/Temp nicht angeboten |
| … Projekt mit Symlinks nach außen | +1 | kritische Warnung, Standardknopf „Cancel“ |
| Build abbrechen | 1 | ✕ im HUD (neu) |

**3 · Publikum auf den Beamer (Vollbild)**

| Weg | Schritte | Anmerkung |
|---|---|---|
| F | 1 | neu; ohne 2. Bildschirm passiert nichts (kein Hinweis) |
| Presentation › Audience Full Screen | 2 | |
| ⌘, → „Fill the external display“ | 2 | wirkt als Standard; Einstellung und Menü heißen verschieden |

**4 · Timer**

| Weg | Schritte | Anmerkung |
|---|---|---|
| T / ⌘T / Knopf Start-Pause | 1 | T neu |
| R / ⌘R / Knopf Reset | 1 | **ohne Rückfrage** — ein Vertipper löscht die Laufzeit |

**5 · Schwarzbild mit Nachricht („Pause bis 10:15“)**

| Weg | Schritte | Anmerkung |
|---|---|---|
| Presentation › Black Screen › Vorlage, dann B | 4 | |
| Presentation › Black Screen › Custom Message… → tippen → OK, dann B | 6 | |
| ⌘, → Abschnitt „Audience black screen“ → tippen → schließen, dann B | 5 | **doppelt**: dieselben Einstellungen an zwei Orten |

**6 · Zeichnen und aufräumen**

| Weg | Schritte | Anmerkung |
|---|---|---|
| P → zeichnen → Z (letzter Strich) | 3 | |
| C (alles weg) → Z (alles zurück) | 2 | Rückholen neu; ⌘Z im Menü jetzt auch nach C aktiv |
| Farbe wechseln | 1 | Farbfelder in der Leiste, Tooltip „Pen colour: …“ |

**7 · Whiteboard**

| Weg | Schritte | Anmerkung |
|---|---|---|
| W bzw. Knopf Board | 1 | im Menü **ohne** ⌘-Kürzel |
| Whiteboard › Save Whiteboard as PDF… (⌘S) → Ort → Sichern | 3 | Deck als Ziel wird abgelehnt (neu) |

**8 · Annotiertes Deck sichern**

| Weg | Schritte | Anmerkung |
|---|---|---|
| ⌘⇧S → Ort → Sichern → Zusammenfassung OK | 4 | |

**9 · Mentimeter zeigen**

| Weg | Schritte | Anmerkung |
|---|---|---|
| File › Mentimeter… → (Login) → Präsentation öffnen → „Present“ | ≥ 4 | nur im **File**-Menü, eigenes Fenster, keine Taste |
| Recents-Menü im Mentimeter-Fenster | 3 | nur Mentimeter-Adressen (neu) |

**10 · Präsentation verlassen**

| Weg | Schritte | Anmerkung |
|---|---|---|
| ⌘W oder Knopf Exit → (Sichern? bei Tinte) → „Home Screen“ / „Quit“ | 2–3 | Dialog 1 |
| Roter Fensterknopf → „Save & Hide / Hide / Quit / Cancel“ | 2 | Dialog 2, versteckt in die Menüleiste |
| ⌘Q → (Sichern? bei Tinte) | 1–2 | Dialog 3 |
| Esc | – | verlässt nie die Präsentation |

**11 · Notizen aus einer bestimmten Datei**

| Weg | Schritte | Anmerkung |
|---|---|---|
| Datei `<deck>.tex` daneben legen bzw. umbenennen | außerhalb der App | macOS hat **keinen** Notizen-Dateiwähler (das iPad schon) |

---

## Bewertung

| Heuristik | Note (1–5) | Begründung |
|---|---|---|
| Sichtbarkeit des Systemstatus | 4 | Folienzähler, Timer, Schwarz-Status, Kompilier-HUD; neu: Notizquelle im Platzhalter. |
| Übereinstimmung mit der realen Welt | 4 | Begriffe aus dem Hörsaal (Black, Board, Laser); „tap to select“ ist iPad-Sprache. |
| Kontrolle und Freiheit | 3 | Neu: Clear rückholbar, Build abbrechbar. Weiter: Reset ohne Rückfrage, Esc verlässt nichts, drei Verlassen-Dialoge. |
| Konsistenz und Standards | 2 | Kein Edit-Menü (⌘Z = Strich, ⌘C/⌘V im Notizfeld fraglich), ⌘1 für Übersicht, W ohne ⌘-Kürzel, Tasten je Plattform verschieden. |
| Fehlervermeidung | 4 | Rückfrage vor Build, Deck nicht überschreibbar, Timer wartet auf Start. |
| Wiedererkennen statt Erinnern | 3 | Neu: Tooltips mit Taste an jedem Knopf. Die Tastenkarte verschwindet, sobald Favoriten **und** Recents existieren. |
| Flexibilität und Effizienz | 4 | Fast alles per Einzeltaste; T/F ergänzt. |
| Ästhetik / Minimalismus | 4 | Ruhige Steuerleiste; Schwarzbild-Einstellungen doppelt. |
| Fehlermeldungen | 4 | Logs im Klartext, neue Timeout-Meldung; Linux erklärt Paranoid-Ablehnungen. |
| Hilfe | 3 | Tastenkarte nur für Neue; keine Hilfe-Seite. |

**Gesamt:** solide für den Vortragsalltag; die größten Hebel sind **Konsistenz** (Edit-Menü,
Plattform-Tasten) und **ein** klarer Weg aus der Präsentation.

---

## Reibungspunkte

| | Reibungspunkt | Status |
|---|---|---|
| 🔴 | Kein Einzeltasten-Kürzel für den Timer | **behoben** — T |
| 🔴 | Timer läuft ab dem Laden, auch wenn das Deck schwarz startet (Pause vor dem Vortrag zählt mit) | **behoben** — Start beim ersten Aufheben des Schwarzbilds; manuelles T/R übernimmt |
| 🔴 | C löscht alle Striche der Folie sofort und endgültig | **behoben** — Z / ⌘Z holt sie zurück (solange auf der Folie nichts Neues gezeichnet wurde; auf Whiteboards weiter endgültig) |
| 🔴 | Kein Edit-Menü: im Notizfeld landet ⌘Z bei „Undo Stroke“, ⌘C/⌘V/⌘X/⌘A haben keine Menü-Kürzel | **offen** — auf dem Mac zu bestätigen; Lösung Stufe 2 |
| 🔴 | Drei verschiedene Verlassen-Wege mit drei Dialogen (⌘W/Exit, roter Knopf → Verstecken, ⌘Q) | **offen** — Stufe 2 |
| 🟡 | F (Publikum Vollbild) fehlte auf macOS | **behoben** — F; ohne 2. Bildschirm stumm |
| 🟡 | Keine Tooltips an den Knöpfen | **behoben** — Funktion + Taste an jedem Knopf |
| 🟡 | Notizen-Platzhalter nannte immer „.tex“, auch bei `.pptx`-Notizen | **behoben** — Quelle aus `notesSource` |
| 🟡 | Notizen fallen still auf eine andere `.tex` im Ordner zurück | **teilweise** — Platzhalter sagt jetzt „the .tex next to the PDF“, nennt aber den Dateinamen nicht (`TexNotes` meldet ihn nicht) |
| 🟡 | Kein Notizen-Dateiwähler auf macOS | **offen** — Stufe 2 |
| 🟡 | R setzt den Timer ohne Rückfrage zurück | **offen** — Stufe 2 (Rückholen statt Dialog) |
| 🟡 | Tastenkarte nur, solange Favoriten oder Recents leer sind | **offen** — Stufe 2 (Hilfe-Menü / `?`) |
| 🟡 | Übersicht doppelt belegt: G und ⌘1 (Menü zeigt nur ⌘1) | **offen** |
| 🟡 | Whiteboard-Umschalter im Menü ohne ⌘-Kürzel | **offen** |
| 🟡 | Schwarzbild-Einstellungen doppelt (Settings und Menü) | **offen** — Stufe 3 |
| 🟡 | Mentimeter nur im File-Menü, eigenes Fenster | **offen** — Stufe 3 |
| 🟡 | „Always trust this folder“ lässt sich nirgends zurücknehmen (macOS: `forgetTrustedBuildFolders` existiert, ist aber nicht verdrahtet; Linux: kein Gegenstück) | **macOS behoben** (Einstellungen › „Forget All“; Sicherheitsbefund L10), Linux offen — Stufe 1-Nachtrag |
| 🟡 | Tastenbelegung je Plattform verschieden (T/F/P/L/C/Esc/`.`) | **teilweise** — T und F jetzt auf macOS; Rest Stufe 2 |
| 🟡 | Linux: Fenster reagierte während eines Builds nicht, kein Abbrechen | **teilweise** — Fenster bleibt jetzt bedienbar; Abbrechen fehlt (LX13-Rest) |
| 🟡 | Linux: Konsole hängt bei einer `.tex` mit offenem `\note{` minutenlang (Fixture `notes-unclosed`) | **behoben** (Sicherheitsbefund LX12) |
| 🟢 | Esc verlässt die Präsentation nie | **akzeptiert** — schützt vor versehentlichem Ende vor Publikum |
| 🟢 | Wort „tap“ auf macOS (Whiteboard-Tooltip „Drag to move · tap to select“) | **offen** |
| 🟢 | Settings-Fenster fest, nicht skalierbar (Startgröße 480×340, Inhalt 500×620) | **offen** — auf dem Mac prüfen, ob unten etwas abgeschnitten wird |
| 🟢 | Build-Rückfrage kostet einen Klick mehr | **akzeptiert** — Sicherheit (H1); „Always trust“ für eigene Ordner |

---

## GUI-Überarbeitungsvorschlag

### Stufe 1 — kleine Eingriffe, sofort (umgesetzt, siehe Anhang)

- T für den Timer, F für das Publikums-Vollbild; beides in der Tastenkarte.
- Timer startet beim ersten Aufheben des Schwarzbilds.
- Clear rückholbar (Z / ⌘Z, Menüpunkt bleibt aktiv).
- Tooltips mit Funktion und Taste an jedem Knopf der Steuerleiste.
- Notizen-Platzhalter nennt die Quelle (`.pptx`, `.tex`, geteiltes PDF).
- *Nachtrag offen:* „Vertrauten Ordnern nicht mehr vertrauen“ in den Einstellungen
  (macOS ruft `AppDelegate.forgetTrustedBuildFolders()`, Linux löscht `trustedFolders`).

### Stufe 2 — Konsistenz (mittlerer Aufwand)

- **Edit-Menü** mit Standard-Responder-Aktionen (Undo/Redo, Ausschneiden, Kopieren,
  Einfügen, Alles auswählen); „Undo Stroke“ auf ⌥⌘Z oder nur Z, damit ⌘Z im Notizfeld
  Text rückgängig macht.
- **Ein Verlassen-Weg:** ⌘W und Exit zeigen *einen* Dialog (Sichern? → Startbildschirm);
  der rote Knopf verhält sich wie ⌘W; „In die Menüleiste verstecken“ nur im
  Hintergrundmodus.
- **Reset rückholbar** (wie Clear) statt Rückfrage.
- **Einheitliche Tasten auf allen Plattformen:** `.` = Schwarz auch auf macOS/Linux,
  P/L auf Linux, T/R/G/W auf dem iPad; Esc überall gleich (Linux hebt heute zusätzlich
  das Schwarzbild auf).
- **Notizen-Quelle wählbar:** „Notes › Choose Notes File…“ auf macOS (wie
  `NotesPanel` auf dem iPad); `TexNotes` meldet den tatsächlich benutzten Dateinamen.
- **Hilfe:** Tastenübersicht dauerhaft über Help-Menü und `?`.
- **Linux:** Abbrechen-Knopf für Builds (LX13-Rest; asynchron laufen sie bereits).

### Stufe 3 — Struktur (größerer Umbau)

- Schwarzbild-Gestaltung nur noch an **einem** Ort (Popover am Black-Knopf), Settings
  hält nur den Standard „Start black“.
- Mentimeter als Modus der Konsole (Knopf in der Steuerleiste, Taste), nicht als
  eigenes Fenster im File-Menü.
- Settings-Fenster skalierbar bzw. als Tabs.
- Gemeinsame Tastenbelegung als Datei, aus der macOS, Linux und iPad ihre Tabellen
  (und die Tastenkarte) erzeugen.

---

## Anhang: in dieser Iteration umgesetzt

| Änderung | Datei(en) |
|---|---|
| T = Timer Start/Stopp, F = Publikum Vollbild (nur mit zweitem Bildschirm) | `Sources/BeamerPresenter/AppDelegate.swift` (`handleKey`) |
| Tastenkarte um F und T erweitert, Platz dafür reserviert | `Sources/BeamerPresenter/WelcomeView.swift` |
| Timer wartet bei schwarzem Start auf das erste Aufheben; T/R übernehmen | `Sources/BeamerPresenter/PresentationState.swift` |
| Clear rückholbar (`clearedStrokes`, `canUndoInk`); Undo-Knopf und ⌘Z-Menüpunkt nutzen `canUndoInk` | `PresentationState.swift`, `PresenterView.swift`, `AppDelegate.swift` (`validateMenuItem`) |
| Tooltips (Funktion + Taste) an allen Knöpfen, Farbfeldern und der Vortragsdauer | `Sources/BeamerPresenter/PresenterView.swift` |
| Notizquelle (`NotesSource`) im Platzhalter; Hinweis auf `.pptx`-Notizen | `PresentationState.swift`, `PresenterView.swift` |
| Aus der Sicherheitsarbeit, für Bedienung relevant: Build-Rückfrage mit „Always trust this folder“, Abbrechen im Kompilier-HUD, Timeout-Meldung, Download-Rückfrage in Mentimeter, Ablehnung des Decks als Exportziel | `AppDelegate.swift`, `Mentimeter/MentiBrowser.swift`, `WhiteboardView.swift` |
| iPad-Fernbedienung: Presenter-Liste statt Auto-Kopplung, 6-stelliger Code, „Locked“-Anzeige nach Fehlversuchen | `iOS/BeamerPresenter/RemoteView.swift`, `RemoteLink.swift`, `ContentView.swift` |
| Linux: Vertrauensdialog vor Build/Konvertierung (Esc = Abbrechen, Fokus auf Cancel) | `Linux/ui/index.html`, `Linux/ui/js/presenter.js` |

Nicht kompiliert (kein Xcode auf der Prüfmaschine): alle SwiftUI/AppKit-Änderungen sind
vor dem Release auf einem Mac zu bauen und die Klickpfade 1–10 einmal durchzuspielen.
