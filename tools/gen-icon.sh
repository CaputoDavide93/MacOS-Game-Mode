#!/usr/bin/env bash
# Renders App/Design/AppIcon.svg into every size the macOS app icon needs: once at
# 1024 px with headless Chrome, then scaled down with sips. Run when the design changes.
set -euo pipefail
cd "$(dirname "$0")/.."
SVG="$PWD/App/Design/AppIcon.svg"
OUT="App/Resources/Assets.xcassets/AppIcon.appiconset"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[[ -x "$CHROME" ]] || { echo "Google Chrome is needed to render the icon" >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf '<html><body style="margin:0;background:transparent"><img src="file://%s" width="1024" height="1024"></body></html>' "$SVG" > "$TMP/i.html"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
  --allow-file-access-from-files --window-size=1024,1024 --screenshot="$TMP/master.png" "file://$TMP/i.html" >/dev/null 2>&1
[[ -s "$TMP/master.png" ]] || { echo "render failed" >&2; exit 1; }

images=()
for spec in 16:1 16:2 32:1 32:2 128:1 128:2 256:1 256:2 512:1 512:2; do
  pt=${spec%%:*}; scale=${spec##*:}; px=$((pt * scale))
  suffix=""; if [[ $scale == 2 ]]; then suffix="@2x"; fi
  name="icon_${pt}x${pt}${suffix}.png"
  sips -z "$px" "$px" "$TMP/master.png" --out "$OUT/$name" >/dev/null
  images+=("{\"filename\":\"$name\",\"idiom\":\"mac\",\"scale\":\"${scale}x\",\"size\":\"${pt}x${pt}\"}")
done
( IFS=,; printf '{"images":[%s],"info":{"author":"xcode","version":1}}\n' "${images[*]}" ) | python3 -m json.tool > "$OUT/Contents.json"
echo "icon: ${#images[@]} sizes"
