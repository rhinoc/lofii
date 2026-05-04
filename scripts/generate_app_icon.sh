#!/usr/bin/env bash
# Generate the macOS .icns app icon from the project icon source image.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/assets/app-icon-source.png"
TRANSPARENT="$ROOT/assets/app-icon-transparent.png"
OUT_DIR="$ROOT/Sources/Lofii/Resources"
OUT="$OUT_DIR/AppIcon.icns"

if [[ ! -f "$SRC" ]]; then
  echo "Missing icon source: $SRC" >&2
  exit 1
fi

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick 'magick' is required to generate the app icon." >&2
  exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
  echo "macOS iconutil is required to generate the app icon." >&2
  exit 1
fi

dimensions=($(magick identify -format '%w %h' "$SRC"))
width="${dimensions[0]}"
height="${dimensions[1]}"
max_x=$((width - 1))
max_y=$((height - 1))

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$OUT_DIR"

corner_alpha_sum="$(magick "$SRC" -format "%[fx:p{0,0}.a+p{$max_x,0}.a+p{0,$max_y}.a+p{$max_x,$max_y}.a]" info:)"
if awk "BEGIN { exit !($corner_alpha_sum < 0.5) }"; then
  magick "$SRC" -alpha on "$TRANSPARENT"
else
  # Remove only the background connected to the four corners. The radio body
  # is also warm beige, so global color transparency would damage it.
  magick "$SRC" \
    -alpha set \
    -fuzz 7% \
    -fill none \
    -draw "color 0,0 floodfill" \
    -draw "color $max_x,0 floodfill" \
    -draw "color 0,$max_y floodfill" \
    -draw "color $max_x,$max_y floodfill" \
    "$TRANSPARENT"
fi

iconset="$tmp/AppIcon.iconset"
mkdir -p "$iconset"

for spec in \
  16:icon_16x16.png \
  32:icon_16x16@2x.png \
  32:icon_32x32.png \
  64:icon_32x32@2x.png \
  128:icon_128x128.png \
  256:icon_128x128@2x.png \
  256:icon_256x256.png \
  512:icon_256x256@2x.png \
  512:icon_512x512.png \
  1024:icon_512x512@2x.png
do
  size="${spec%%:*}"
  name="${spec#*:}"
  magick "$TRANSPARENT" -filter Lanczos -resize "${size}x${size}" "$iconset/$name"
done

iconutil -c icns "$iconset" -o "$OUT"
echo "Generated $OUT"
