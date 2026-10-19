#!/usr/bin/env bash
# Compile Sources/ into a testable module, build the XCTest bundle, and run it.
#
# The project builds with swiftc directly (no SPM, no Xcode project), so the
# module, the bundle layout and the XCTest search paths are assembled by hand.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${TMPDIR:-/tmp}/tokenbar-tests"
BUNDLE="$WORK_DIR/TokenBarTests.xctest"

SDK="$(xcrun --show-sdk-path)"
PLATFORM="$(xcrun --show-sdk-platform-path)"
ARCH="$(uname -m)"
TARGET="$ARCH-apple-macos14.0"
XCTEST_MODULE_DIR="$PLATFORM/Developer/usr/lib"
XCTEST_FRAMEWORK_DIR="$PLATFORM/Developer/Library/Frameworks"

rm -rf "$WORK_DIR"
mkdir -p "$BUNDLE/Contents/MacOS"

# main.swift holds the app entry point (@main); it is not part of the module.
find "$PROJECT_DIR/Sources" -name '*.swift' ! -name 'main.swift' | sort > "$WORK_DIR/sources.txt"

echo "== compiling module =="
xcrun swiftc -emit-library -emit-module -enable-testing -module-name TokenBar \
  -sdk "$SDK" -target "$TARGET" \
  -framework AppKit -framework SwiftUI -framework WebKit -framework Security \
  $(cat "$WORK_DIR/sources.txt") \
  -emit-module-path "$WORK_DIR/TokenBar.swiftmodule" \
  -o "$WORK_DIR/libTokenBar.dylib"

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TokenBarTests</string>
<key>CFBundleIdentifier</key><string>com.liuxiaoliang.tokenbar.tests</string>
<key>CFBundleName</key><string>TokenBarTests</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST

echo "== compiling tests =="
xcrun swiftc -sdk "$SDK" -target "$TARGET" \
  -I "$WORK_DIR" -L "$WORK_DIR" -lTokenBar \
  -I "$XCTEST_MODULE_DIR" -L "$XCTEST_MODULE_DIR" \
  -F "$XCTEST_FRAMEWORK_DIR" \
  -Xlinker -bundle \
  -Xlinker -rpath -Xlinker "$WORK_DIR" \
  "$PROJECT_DIR/tests/TokenBarTests/"*.swift \
  -o "$BUNDLE/Contents/MacOS/TokenBarTests"

echo "== running tests =="
xcrun xctest "$BUNDLE"
