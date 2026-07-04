#!/usr/bin/env bash
# Pre-build secret scan.
# Blocks the build if any well-known secret-shaped token is found in source files.
# Catches: OpenAI sk-, Google AIza, generic sessionid= cookies, generic token= query strings.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATTERNS='sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{35}|sessionid=[A-Za-z0-9]{8,}|token=[A-Za-z0-9]{20,}|password=[A-Za-z0-9]{6,}'

# Scan Sources, scripts, Info.plist.
# Test files under tests/ are included: they contain real Keychain test UUIDs which don't match
# the patterns above, so they remain clean.
TARGETS=(
  "$PROJECT_DIR/Sources"
  "$PROJECT_DIR/scripts"
  "$PROJECT_DIR/Info.plist"
)

found=0
for target in "${TARGETS[@]}"; do
  if [ -e "$target" ]; then
    if grep -rEn "$PATTERNS" "$target" 2>/dev/null; then
      found=1
    fi
  fi
done

if [ "$found" -ne 0 ]; then
  echo "❌ Possible secret found. Refusing to build." >&2
  exit 1
fi
echo "✅ secret_scan clean"
