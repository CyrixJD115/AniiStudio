#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-run}"
BUILD_DIR="${ANII_BUILD_DIR:-${TMPDIR:-/tmp}/aniimo-atlas-build}"
STAGE_DIR="${TMPDIR:-/tmp}/aniimo-atlas-stage"
mkdir -p "$STAGE_DIR"
# File Provider metadata on source resources prevents SwiftPM's generated
# resource bundle from being signed in place. Stage clean copies for building.
ditto --norsrc Sources "$STAGE_DIR/Sources"
ditto --norsrc Tests "$STAGE_DIR/Tests"
cp Package.swift "$STAGE_DIR/Package.swift"
swift build --package-path "$STAGE_DIR" --scratch-path "$BUILD_DIR"
BIN_DIR="$(swift build --package-path "$STAGE_DIR" --scratch-path "$BUILD_DIR" --show-bin-path)"
PACKAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aniimo-atlas-package.XXXXXX")"
trap 'rm -rf "$PACKAGE_DIR"' EXIT
PACKAGE_APP="$PACKAGE_DIR/AniimoAtlas.app"
mkdir -p "$PACKAGE_APP/Contents/MacOS" "$PACKAGE_APP/Contents/Resources" "$PACKAGE_APP/Contents/Frameworks" "$PACKAGE_APP/Contents/Helpers"
cp "$BIN_DIR/AniimoAtlas" "$PACKAGE_APP/Contents/MacOS/"
ditto --norsrc "$BIN_DIR/AniimoAtlas_AniimoAtlas.bundle" "$PACKAGE_APP/Contents/Resources/AniimoAtlas_AniimoAtlas.bundle"
ditto --norsrc "$BIN_DIR/GLTFKit2.framework" "$PACKAGE_APP/Contents/Frameworks/GLTFKit2.framework"
CAPTURE_TOOL_ROOT="${ANII_CAPTURE_TOOL_ROOT:-$PWD/tools/aniimo-memory-capture}"
if [[ -f "$CAPTURE_TOOL_ROOT/scan.c" && -f "$CAPTURE_TOOL_ROOT/debugger-entitlements.plist" ]]; then
  clang -O2 -Wall -Wextra -Werror "$CAPTURE_TOOL_ROOT/scan.c" -o "$PACKAGE_APP/Contents/Helpers/aniimo-memory-scan"
  codesign --force --sign - --entitlements "$CAPTURE_TOOL_ROOT/debugger-entitlements.plist" "$PACKAGE_APP/Contents/Helpers/aniimo-memory-scan"
fi
if [[ -f "$CAPTURE_TOOL_ROOT/scan-lua-links.c" && -f "$CAPTURE_TOOL_ROOT/debugger-entitlements.plist" ]]; then
  clang -O2 -Wall -Wextra -Werror "$CAPTURE_TOOL_ROOT/scan-lua-links.c" -o "$PACKAGE_APP/Contents/Helpers/aniimo-lua-link-scan"
  codesign --force --sign - --entitlements "$CAPTURE_TOOL_ROOT/debugger-entitlements.plist" "$PACKAGE_APP/Contents/Helpers/aniimo-lua-link-scan"
fi
install_name_tool -add_rpath "@executable_path/../Frameworks" "$PACKAGE_APP/Contents/MacOS/AniimoAtlas"
cat > "$PACKAGE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>AniimoAtlas</string><key>CFBundleIdentifier</key><string>com.kevin.aniimoatlas</string><key>CFBundleName</key><string>Aniimo Atlas</string><key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSPrincipalClass</key><string>NSApplication</string></dict></plist>
PLIST
codesign --force --sign - "$PACKAGE_APP/Contents/Frameworks/GLTFKit2.framework"
codesign --force --sign - "$PACKAGE_APP"
codesign --verify --deep --strict "$PACKAGE_APP"
mkdir -p "$PWD/dist" "$HOME/Applications"
ditto -c -k --norsrc --keepParent "$PACKAGE_APP" "$PWD/dist/AniimoAtlas.app.zip"
APP="$HOME/Applications/AniimoAtlas.app"
ditto --norsrc "$PACKAGE_APP" "$APP"
if [[ "$MODE" == "--build" ]]; then exit 0; fi
pkill -f "$APP/Contents/MacOS/AniimoAtlas" || true
open -n "$APP"
if [[ "$MODE" == "--verify" ]]; then sleep 2; pgrep -x AniimoAtlas; fi
