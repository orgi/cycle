#!/usr/bin/env bash
# Renders Radl's PNG icons from assets/branding/radl_icon.svg (written by
# tool/gen_icons.py): legacy Android launcher icons (API < 26), every iOS
# AppIcon size, and the two store icons.
#
# Runs on the host, not in the Flutter container: it needs Firefox (headless)
# to rasterise the SVG — ImageMagick's built-in SVG renderer drops strokes,
# which is most of this logo — and ImageMagick (`magick`) to scale and mask.
#
#   python3 tool/gen_icons.py && tool/gen_icon_pngs.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/assets/branding/radl_icon.svg"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. Rasterise the full-bleed master at 1024 px.
cp "$SRC" "$TMP/icon.svg"
cat > "$TMP/render.html" <<'EOF'
<!doctype html><html><body style="margin:0"><img src="icon.svg" width="1024" height="1024" style="display:block"></body></html>
EOF
mkdir "$TMP/profile"  # Firefox waits forever on a profile dir that doesn't exist
timeout 60 firefox --headless --no-remote --profile "$TMP/profile" --window-size=1024,1024 \
  --screenshot "$TMP/master.png" "file://$TMP/render.html" >/dev/null 2>&1
[[ "$(magick identify -format '%wx%h' "$TMP/master.png")" == 1024x1024 ]] ||
  { echo "unexpected render size" >&2; exit 1; }
# Opaque square: what iOS and both stores want (they apply their own mask).
# Written as PNG24: at tiny sizes ImageMagick otherwise picks a palette PNG
# with a transparency entry, and iOS rejects icons with alpha.
magick "$TMP/master.png" -alpha off "$TMP/square.png"

# 2. Store icons.
STORE="$REPO/assets/branding/store"
mkdir -p "$STORE"
magick "$TMP/square.png" -alpha off "PNG24:$STORE/app_store_icon_1024.png"
magick "$TMP/square.png" -filter Lanczos -resize 512x512 -alpha off "PNG24:$STORE/play_store_icon_512.png"

# 3. iOS AppIcon: every size listed in Contents.json, opaque.
ICONSET="$REPO/ios/Runner/Assets.xcassets/AppIcon.appiconset"
python3 - "$ICONSET/Contents.json" <<'EOF' | while read -r px name; do
import json, sys
for i in json.load(open(sys.argv[1]))["images"]:
    w = float(i["size"].split("x")[0]) * float(i["scale"].rstrip("x"))
    print(round(w), i["filename"])
EOF
  magick "$TMP/square.png" -filter Lanczos -resize "${px}x${px}" -alpha off "PNG24:$ICONSET/$name"
done

# 4. Legacy Android launcher icons (API 24-25; newer devices use the adaptive
#    vector icon): rounded square with transparent corners, radius 112/512.
magick -size 1024x1024 xc:none -fill white -draw "roundrectangle 0,0 1023,1023 224,224" "$TMP/mask.png"
magick "$TMP/square.png" "$TMP/mask.png" -alpha off -compose CopyOpacity -composite "$TMP/rounded.png"
RES="$REPO/android/app/src/main/res"
for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  magick "$TMP/rounded.png" -filter Lanczos -resize "${d#*:}x${d#*:}" "$RES/mipmap-${d%%:*}/ic_launcher.png"
done

echo "wrote store icons, iOS AppIcon and legacy Android launcher PNGs"
