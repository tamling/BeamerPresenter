#!/usr/bin/env bash
#
# Builds the AlbumArtwork screensaver and its TestHost with plain swiftc — no
# Xcode project; the Command Line Tools are enough. Run on macOS:
#
#   ./build-saver.sh                         # this Mac's arch — default
#   ARCHS="arm64 x86_64" ./build-saver.sh    # universal (Apple Silicon + Intel)
#   MACOS_MIN=14.0 ./build-saver.sh          # raise the deployment target (default 13.0)
#
# Produces build/AlbumArtwork.saver (ad-hoc signed; double-click to install) and
# build/TestHost (the same view in a plain window).
#
set -euo pipefail
cd "$(dirname "$0")"

PRODUCT="AlbumArtwork"
MACOS_MIN="${MACOS_MIN:-13.0}"
ARCHS="${ARCHS:-$(uname -m)}"           # space-separated
BUILD_DIR="build"
SAVER="$BUILD_DIR/$PRODUCT.saver"

if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "✗ swiftc not found. Install the Command Line Tools once with:" >&2
    echo "      xcode-select --install" >&2
    exit 1
fi

# Core and saver compile into ONE module, so the core's types stay internal and
# the macOS files never import AlbumArtworkCore.
SOURCES=(Sources/AlbumArtworkCore/*.swift Sources/AlbumArtworkSaver/*.swift)
FRAMEWORKS=(-framework ScreenSaver -framework AppKit -framework QuartzCore
            -framework ImageIO -framework UniformTypeIdentifiers)

# compile <module> <output> <swiftc args…> — one swiftc run per arch, then lipo.
compile() {
    local module="$1" output="$2"
    shift 2
    local name arch slice
    local slices=()
    name="$(basename "$output")"
    for arch in $ARCHS; do
        slice="$BUILD_DIR/obj/$arch/$name"
        mkdir -p "$(dirname "$slice")"
        swiftc -swift-version 5 -O -module-name "$module" \
            -target "$arch-apple-macos$MACOS_MIN" "$@" "${FRAMEWORKS[@]}" -o "$slice"
        slices+=("$slice")
    done
    if [ "${#slices[@]}" -eq 1 ]; then
        cp "${slices[0]}" "$output"
    else
        lipo -create "${slices[@]}" -output "$output"
    fi
}

mkdir -p "$BUILD_DIR"

echo "▶︎ Building $PRODUCT.saver ($ARCHS, macOS $MACOS_MIN+)…"
# A loadable Mach-O bundle (MH_BUNDLE), not an executable or a dylib.
compile AlbumArtworkSaver "$BUILD_DIR/$PRODUCT" \
    -emit-executable -Xclang-linker -bundle "${SOURCES[@]}"

echo "▶︎ Building TestHost ($ARCHS)…"
compile AlbumArtworkTestHost "$BUILD_DIR/TestHost" \
    -emit-executable "${SOURCES[@]}" Sources/TestHost/main.swift

echo "▶︎ Assembling ${SAVER}…"
rm -rf "$SAVER"
mkdir -p "$SAVER/Contents/MacOS"
mv "$BUILD_DIR/$PRODUCT" "$SAVER/Contents/MacOS/$PRODUCT"
cp Resources/Info.plist "$SAVER/Contents/Info.plist"
plutil -replace LSMinimumSystemVersion -string "$MACOS_MIN" "$SAVER/Contents/Info.plist"
echo "▶︎ Architectures: $(lipo -archs "$SAVER/Contents/MacOS/$PRODUCT")"

echo "▶︎ Codesigning ad-hoc…"
codesign --force --sign - "$SAVER"

echo "✓ Built $SAVER and $BUILD_DIR/TestHost"
echo "  Install:  double-click $SAVER"
echo "  Try it:   ./$BUILD_DIR/TestHost"
