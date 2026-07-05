#!/usr/bin/env bash
# Build and run the Chrome DevTools Protocol inspector.
#
# This tool connects to a running Chrome instance (with --remote-debugging-port=9222)
# and either:
#   A) monitors network traffic to auto-detect API endpoints (default)
#   B) extracts cookies from Chrome and saves them to the Keychain (--extract-cookies)
#
# Usage:
#   ./scripts/inspect.sh --provider deepseek --url https://platform.deepseek.com
#   ./scripts/inspect.sh --extract-cookies --provider deepseek --url https://platform.deepseek.com
#
# Before running:
#   1. Start Chrome with remote debugging:
#      /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --remote-debugging-port=9222
#   2. Log in to the provider in Chrome.
#   3. Run this script.
#
# Options:
#   --extract-cookies  Extract cookies from Chrome and save to Keychain (then exit)
#   --provider <id>    Provider identifier (default: "unknown")
#   --url <url>        Provider URL (default: "https://example.com")
#   --port <port>      Chrome remote debugging port (default: 9222)
#   --host <host>      Chrome host (default: localhost)
#   --verbose, -v      Show all JSON responses, not just matched ones
#
# Examples:
#   ./scripts/inspect.sh --provider deepseek --url https://platform.deepseek.com
#   ./scripts/inspect.sh --extract-cookies --provider deepseek --url https://platform.deepseek.com
#   ./scripts/inspect.sh --provider volcano --url https://console.volcengine.com -v
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSPECTOR_DIR="$PROJECT_DIR/scripts/Inspector"
BUILD_DIR="$PROJECT_DIR/build"

arch="$(uname -m)"
SWIFTC="${SWIFTC:-$(xcrun --find swiftc)}"
SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path --sdk macosx)}"

mkdir -p "$BUILD_DIR"

# Collect Swift files (explicit array to avoid shell expansion issues)
SWIFT_FILES=(
  "$INSPECTOR_DIR/CDPClient.swift"
  "$INSPECTOR_DIR/main.swift"
)

echo "🔨 Building inspector..."

"$SWIFTC" \
  -sdk "$SDKROOT" \
  -target "$arch-apple-macos14.0" \
  -Osize \
  -parse-as-library \
  -framework Foundation \
  -framework Security \
  "${SWIFT_FILES[@]}" \
  -o "$BUILD_DIR/inspect"

echo "✅ Built: $BUILD_DIR/inspect"
echo ""

# Forward all original arguments to the binary
"$BUILD_DIR/inspect" "$@"
