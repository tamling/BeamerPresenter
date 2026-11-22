# AlbumArtwork screensaver

A macOS screensaver that shows the album covers embedded in the MP3s of a music
folder as an animated wall. It recreates
[lingkuma/AlbumArtwork](https://github.com/lingkuma/AlbumArtwork)
(MIT License, © lingkuma): the same grid, the same seven animations and the same
timings, written from scratch as a native `.saver`.

Requirements: macOS 13 or later, Apple Silicon or Intel.

## Getting it

- **From CI:** open the latest green "Build Saver" run on GitHub Actions and
  download the `AlbumArtwork-saver` artifact. GitHub wraps it in a second zip,
  so unzip twice to get `AlbumArtwork.saver`.
- **Build it yourself:** on a Mac run `./build-saver.sh` in this folder (the
  Command Line Tools are enough). The bundle lands in `build/AlbumArtwork.saver`.
  For a build that runs on both architectures use
  `ARCHS="arm64 x86_64" ./build-saver.sh`.

## Installing

The bundle is only ad-hoc signed, so Gatekeeper blocks a downloaded copy. Remove
the quarantine flag first (adjust the path):

```sh
xattr -dr com.apple.quarantine ~/Downloads/AlbumArtwork.saver
```

Then double-click `AlbumArtwork.saver` to install it. Alternatively, double-click
it, then open System Settings → Privacy & Security and choose "Open Anyway".

Afterwards pick "AlbumArtwork" in System Settings → Screen Saver.

## Choosing the music folder

Open the screensaver's Options. Choose the folder with "Ordner wählen…" or type
its path into the field next to "Musikordner:". The status line shows how many
albums are known and when the folder was last read; "Jetzt neu einlesen" reads
it again right away. "Reihen:" sets the number of rows (3–12) and "Intervall:"
the time between animations (1–10 s).

## How updates work

New MP3s are read the next time the screensaver starts. Only new or changed
files are read again. A scan that could not finish (for example because the disk
holding the music is unplugged) never deletes anything: the wall keeps showing
the cached covers, and the status line says the folder is not reachable
("Musikordner nicht erreichbar"). The music folder itself is only ever read.

## Troubleshooting

- **Folder not readable.** With no covers cached yet, the wall shows "Musikordner
  nicht erreichbar – siehe Screensaver-Optionen"; with covers cached, it keeps
  showing those. The status line in the screensaver's Options (System Settings →
  Screen Saver → AlbumArtwork → "Options…") then says "Musikordner nicht erreichbar".
  The screensaver runs in a sandboxed system process, and it tries several ways
  to open the folder. Try the other way: if you used the button, type the path
  instead, or the reverse. Otherwise use a folder under `/Users/Shared`.
- **Old version still running after reinstalling.** Run `killall legacyScreenSaver`
  and start the screensaver again.
- **Bug report.** Collect the log after a start:

  ```sh
  log show --last 10m --style compact --predicate 'subsystem == "app.beamerpresenter.AlbumArtworkSaver"'
  ```

  The lines starting with `folder:` tell which way of accessing the folder worked.
