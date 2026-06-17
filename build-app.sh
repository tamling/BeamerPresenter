#!/usr/bin/env bash
#
# Builds a release binary with SwiftPM and wraps it into a double-clickable
# BeamerPresenter.app bundle. Run on macOS (Apple Silicon):
#
#   ./build-app.sh
#
# Optional: pass a Developer ID to codesign the result:
#
#   ./build-app.sh "Developer ID Application: Your Name (TEAMID)"
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="BeamerPresenter"
CONFIG="release"
ARCH="arm64"
SIGN_IDENTITY="${1:-}"

echo "▶︎ Building ($CONFIG, $ARCH)…"
swift build -c "$CONFIG" --arch "$ARCH"

BIN_DIR="$(swift build -c "$CONFIG" --arch "$ARCH" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
[ -x "$BIN" ] || { echo "✗ Binary not found at $BIN"; exit 1; }

echo "▶︎ Building app icon…"
python3 Tools/make_icon.py
iconutil -c icns Resources/AppIcon.iconset -o Resources/BeamerPresenter.icns

APP="build/$APP_NAME.app"
echo "▶︎ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/BeamerPresenter.icns "$APP/Contents/Resources/BeamerPresenter.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -n "$SIGN_IDENTITY" ]; then
    echo "▶︎ Codesigning with: $SIGN_IDENTITY"
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --verbose "$APP"
fi

echo "✓ Built $APP"
echo "  Open it with:  open \"$APP\""
