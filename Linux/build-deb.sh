#!/usr/bin/env bash
# Builds the BeamerPresenter .deb package.
#
# Uses the Tauri CLI when available (cargo-tauri, or npx if Node is
# installed); otherwise falls back to plain `cargo build` + `dpkg-deb`,
# which needs nothing beyond Rust and a Debian-ish system.
set -euo pipefail
cd "$(dirname "$0")/src-tauri"

# ---- Preflight: fail early, with instructions, not mid-build. --------------
missing=()
command -v cargo >/dev/null || missing+=(
  "Rust (cargo):      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
                     (then restart the shell)")
command -v dpkg-deb >/dev/null || missing+=(
  "dpkg-deb:          sudo apt install dpkg-dev")
{ command -v pkg-config >/dev/null && pkg-config --exists webkit2gtk-4.1; } || missing+=(
  "WebKitGTK dev:     sudo apt install libwebkit2gtk-4.1-dev build-essential pkg-config")
if [ ${#missing[@]} -gt 0 ]; then
    echo "Cannot build — missing prerequisites:" >&2
    printf ' * %s\n' "${missing[@]}" >&2
    echo >&2
    echo "No toolchain? Grab a prebuilt .deb instead: GitHub → Actions →" >&2
    echo "'Linux .deb' → latest run → Artifacts (built on every push to main)." >&2
    exit 1
fi

if command -v cargo-tauri >/dev/null; then
    cargo tauri build --bundles deb
    echo; echo "Package:"; ls -1 target/release/bundle/deb/*.deb
    exit 0
elif command -v npx >/dev/null; then
    npx --yes @tauri-apps/cli@^2 build --bundles deb
    echo; echo "Package:"; ls -1 target/release/bundle/deb/*.deb
    exit 0
fi

echo "No Tauri CLI found — packaging with cargo + dpkg-deb."
command -v dpkg-deb >/dev/null || { echo "dpkg-deb not found — install dpkg-dev."; exit 1; }

cargo build --release

VERSION=$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)
ARCH=$(dpkg --print-architecture)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

install -Dm755 target/release/beamerpresenter "$STAGE/usr/bin/beamerpresenter"
install -Dm644 icons/32x32.png      "$STAGE/usr/share/icons/hicolor/32x32/apps/beamerpresenter.png"
install -Dm644 icons/128x128.png    "$STAGE/usr/share/icons/hicolor/128x128/apps/beamerpresenter.png"
install -Dm644 icons/128x128@2x.png "$STAGE/usr/share/icons/hicolor/256x256/apps/beamerpresenter.png"

install -d "$STAGE/usr/share/applications"
cat > "$STAGE/usr/share/applications/BeamerPresenter.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=BeamerPresenter
Comment=Present LaTeX Beamer PDFs with speaker notes
Exec=beamerpresenter
Icon=beamerpresenter
Terminal=false
Categories=Education;
DESKTOP

install -d "$STAGE/DEBIAN"
cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: beamer-presenter
Version: $VERSION
Architecture: $ARCH
Installed-Size: $(du -ks "$STAGE" | cut -f1)
Maintainer: beamerpresenter
Priority: optional
Section: education
Depends: xdg-desktop-portal, libwebkit2gtk-4.1-0, libgtk-3-0
Recommends: xdg-desktop-portal-gtk, libreoffice-impress, latexmk, texlive-latex-recommended
Description: Present LaTeX Beamer PDFs with speaker notes
 Presenter console for LaTeX Beamer and PDF decks: current and next
 slide, speaker notes (from split PDFs, \note{} in the .tex, or
 PowerPoint files), clock and timer, overview grid, whiteboard,
 blackout - with a clean audience window on the projector.
CONTROL

OUT="target/release/bundle/deb"
mkdir -p "$OUT"
DEB="$OUT/BeamerPresenter_${VERSION}_${ARCH}.deb"
dpkg-deb --build --root-owner-group "$STAGE" "$DEB"
echo; echo "Package:"; ls -1 "$DEB"
