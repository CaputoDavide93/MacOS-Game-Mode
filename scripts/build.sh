#!/usr/bin/env bash
# Builds "Game Ready.app" for Apple silicon and zips it into dist/.
#   scripts/build.sh            # ad-hoc signed (runs on this Mac; others: right-click → Open)
#   SIGN_ID="Developer ID Application: …" scripts/build.sh   # signed for distribution
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet
xcodebuild -project GameReady.xcodeproj -scheme GameReady -configuration Release \
  -arch arm64 -derivedDataPath build/dd ${SIGN_ID:+CODE_SIGN_IDENTITY="$SIGN_ID"} build -quiet

APP="build/dd/Build/Products/Release/Game Ready.app"
mkdir -p dist
rm -f "dist/Game-Ready.zip"
ditto -c -k --keepParent "$APP" "dist/Game-Ready.zip"
echo "$APP"
echo "dist/Game-Ready.zip"
