#!/usr/bin/env bash
# Cold-start TokenBar.app and verify it stays alive for 4 seconds without panicking.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$PROJECT_DIR/build/TokenBar.app"

if [ ! -d "$APP" ]; then
  echo "Build first: ./scripts/build.sh"
  exit 1
fi

LOG="$PROJECT_DIR/build/smoke.log"
"$APP/Contents/MacOS/TokenBar" >"$LOG" 2>&1 &
PID=$!
sleep 4
if kill -0 $PID 2>/dev/null; then
  echo "TokenBar alive (pid=$PID)"
  kill $PID
  if grep -qiE "crash|panic|fatal|assertion failure|abort trap" "$LOG"; then
    echo "Suspicious log content:"
    cat "$LOG"
    exit 1
  fi
  exit 0
else
  echo "TokenBar died; log:"
  cat "$LOG"
  exit 1
fi
