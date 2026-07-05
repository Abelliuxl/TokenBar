#!/usr/bin/env bash
# Build TokenBar.app from pure-source tree.
# Mirrors the pattern used by ~/Workplace/MemoryPressureBar.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="TokenBar"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$PROJECT_DIR/Resources/AppIcon.iconset"
ICON_FILE="$PROJECT_DIR/Resources/AppIcon.icns"

# Pre-build secret scan.
"$PROJECT_DIR/scripts/secret_scan.sh"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$PROJECT_DIR/Resources"

# Generate icons (3 colors, 16-512 px).
python3 "$PROJECT_DIR/scripts/generate_icon.py" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

arch="$(uname -m)"
SWIFTC="${SWIFTC:-$(xcrun --find swiftc)}"
SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path)}"

# Compile all .swift files in Sources/ recursively, single invocation.
# -parse-as-library tells swiftc to treat top-level code as members of a library (not a script),
# which is required because main.swift lives alongside other top-level code.
SWIFT_FILES=$(find "$PROJECT_DIR/Sources" -name "*.swift" | sort)
"$SWIFTC" \
  -sdk "$SDKROOT" \
  -target "$arch-apple-macos14.0" \
  -Osize \
  -whole-module-optimization \
  -parse-as-library \
  -framework AppKit -framework SwiftUI -framework WebKit \
  $SWIFT_FILES \
  -o "$MACOS_DIR/$APP_NAME"

cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp -R "$ICON_FILE" "$RESOURCES_DIR/"
plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null

# Ad-hoc code sign so macOS will run the binary without Gatekeeper nagging (only on this Mac).
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP_DIR" >/dev/null
fi

echo "Built: $APP_DIR"
