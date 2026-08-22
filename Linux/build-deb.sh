#!/usr/bin/env bash
# Builds the BeamerPresenter .deb package.
# Prerequisites: Rust, the WebKitGTK dev packages (see README.md), and Node
# (only used to fetch the prebuilt Tauri CLI — no frontend build happens).
set -euo pipefail
cd "$(dirname "$0")/src-tauri"

if command -v cargo-tauri >/dev/null; then
    TAURI=(cargo tauri)
else
    TAURI=(npx --yes @tauri-apps/cli@^2)
fi

"${TAURI[@]}" build --bundles deb
echo
echo "Package:"
ls -1 target/release/bundle/deb/*.deb
