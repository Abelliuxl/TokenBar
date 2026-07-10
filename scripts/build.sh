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
VERSION_FILE="$PROJECT_DIR/VERSION"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "Missing VERSION file: $VERSION_FILE" >&2
  exit 1
fi
MARKETING_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ ! "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must use MAJOR.MINOR.PATCH, got: $MARKETING_VERSION" >&2
  exit 1
fi
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$PROJECT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)}"

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
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
cp -R "$ICON_FILE" "$RESOURCES_DIR/"
plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null

# Ad-hoc code sign so macOS will run the binary without Gatekeeper nagging (only on this Mac).
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP_DIR" >/dev/null
fi

echo "Built: $APP_DIR (v$MARKETING_VERSION build $BUILD_NUMBER)"
