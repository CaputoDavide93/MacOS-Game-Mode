#!/usr/bin/env bash
# Renders tools/social-preview.html to docs/assets/social-preview.png (1280x640, metadata
# stripped) with headless Chrome. GitHub's social preview is uploaded by hand in the
# repository settings.
set -euo pipefail
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[[ -x "$CHROME" ]] || { echo "Google Chrome is needed to render the preview" >&2; exit 1; }
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
  --force-device-scale-factor=1 --window-size=1280,640 \
  --screenshot="$PWD/docs/assets/social-preview.png" "file://$PWD/tools/social-preview.html" >/dev/null 2>&1
python3 tools/strip_png.py docs/assets/social-preview.png
