#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

CONFIG="${1:-release}"
TARGET_NAME="ForkLiftClone"    # internal SwiftPM target / executable name
APP_NAME="Lumen"               # user-facing app name
APP_DIR="$ROOT/build/$APP_NAME.app"

echo "==> Building $CONFIG binary"
# swift build occasionally emits a non-fatal build.db SQLite warning that
# returns exit 1 even on success — verify by checking the output binary.
swift build -c "$CONFIG" --product "$TARGET_NAME" || true

BIN_PATH=$(swift build -c "$CONFIG" --show-bin-path 2>/dev/null)
BIN="$BIN_PATH/$TARGET_NAME"

if [[ ! -x "$BIN" ]]; then
    echo "Binary not found at $BIN — build failed" >&2
    exit 1
fi

# Clean both old and new app names so we never end up with two of them
rm -rf "$ROOT/build/ForkLiftClone.app"
echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Keep the executable file name matching CFBundleExecutable (= "ForkLiftClone")
cp "$BIN" "$APP_DIR/Contents/MacOS/$TARGET_NAME"
cp "$ROOT/App/Info.plist" "$APP_DIR/Contents/Info.plist"

# App icon — regenerate from source if the .icns is missing or older than the script
ICONSET_DIR="$ROOT/build/Lumen.iconset"
ICNS="$ROOT/build/AppIcon.icns"
GEN_SCRIPT="$ROOT/scripts/generate-icon.swift"

if [[ ! -f "$ICNS" || "$GEN_SCRIPT" -nt "$ICNS" ]]; then
    echo "==> Generating app icon"
    swift "$GEN_SCRIPT" >/dev/null
    iconutil -c icns "$ICONSET_DIR" -o "$ICNS"
fi
cp "$ICNS" "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "==> Codesigning (ad-hoc)"
codesign --force --sign - "$APP_DIR"

# Force Finder/Dock to refresh the icon cache for this bundle
touch "$APP_DIR"

echo "==> Done."
echo "    .app: $APP_DIR"
echo "    Launch: open '$APP_DIR'"
