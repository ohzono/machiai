#!/bin/bash
# Build an ad-hoc signed Release Machiai.app into build/Machiai.app (and a zip next to it).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOG="build/release-build.log"
mkdir -p build
tuist generate --no-open > "$LOG" 2>&1
set +e
xcodebuild build \
  -workspace Machiai.xcworkspace -scheme Machiai -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData >> "$LOG" 2>&1
status=$?
set -e
if [ "$status" -ne 0 ]; then
  grep -n -B2 -A6 'error:' "$LOG" | head -60 || true
  echo "Build failed (exit $status). Full log: $LOG" >&2
  exit "$status"
fi

rm -rf build/Machiai.app
cp -R build/DerivedData/Build/Products/Release/Machiai.app build/Machiai.app
(cd build && rm -f Machiai.zip && ditto -c -k --keepParent Machiai.app Machiai.zip)
echo "Built build/Machiai.app and build/Machiai.zip"
