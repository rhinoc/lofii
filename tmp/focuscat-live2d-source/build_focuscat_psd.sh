#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ASSETS="$ROOT/assets"
BUILD="$ROOT/build/psd-layers"
SANITIZED="$ROOT/build/sanitized-svg"
QL_STROKES="$ROOT/quicklook-strokes"
OUT="$ROOT/focuscat_import.psd"
PREVIEW="$ROOT/focuscat_layers_preview.png"
SCALE="4.354838709677419"

rm -rf "$BUILD"
mkdir -p "$BUILD" "$SANITIZED"

for svg in "$ASSETS"/*.svg; do
  perl -0pe 's/var\(--[^,]+,\s*([^)]+)\)/$1/g' "$svg" > "$SANITIZED/$(basename "$svg")"
done

perl -0pe 's/fill="white"/fill="none"/g' "$SANITIZED/base.svg" > "$SANITIZED/base_stroke.svg"

ASSETS="$SANITIZED"

render_svg() {
  local file="$1"
  local width="$2"
  local height="$3"
  local out="$4"
  magick -background none "$file" -resize "${width}x${height}!" \
    -alpha on -colorspace sRGB -type TrueColorAlpha "PNG32:$out"
}

place() {
  local canvas="$1"
  local file="$2"
  local x="$3"
  local y="$4"
  local width="$5"
  local height="$6"
  local tmp="$BUILD/tmp-$(basename "$file" .svg)-${x}-${y}.png"
  local ix iy iw ih
  ix="$(awk -v v="$x" -v s="$SCALE" 'BEGIN { printf "%.0f", v * s }')"
  iy="$(awk -v v="$y" -v s="$SCALE" 'BEGIN { printf "%.0f", v * s }')"
  iw="$(awk -v v="$width" -v s="$SCALE" 'BEGIN { printf "%.0f", v * s }')"
  ih="$(awk -v v="$height" -v s="$SCALE" 'BEGIN { printf "%.0f", v * s }')"
  render_svg "$file" "$iw" "$ih" "$tmp"
  magick "$canvas" "$tmp" -geometry "+${ix}+${iy}" -compose over -composite \
    -alpha on -colorspace sRGB -type TrueColorAlpha "PNG32:$canvas"
}

place_ql() {
  local canvas="$1"
  local name="$2"
  local x="$3"
  local y="$4"
  local width="$5"
  local height="$6"
  local source="$QL_STROKES/${name}.svg.png"
  local tmp="$BUILD/tmp-${name}-${x}-${y}.png"
  local ix iy iw ih
  ix="$(awk -v v="$x" -v s="$SCALE" 'BEGIN { printf "%.0f", v * s }')"
  iy="$(awk -v v="$y" -v s="$SCALE" 'BEGIN { printf "%.0f", v * s }')"
  iw="$(awk -v v="$width" -v s="$SCALE" 'BEGIN { printf "%.0f", v * s }')"
  ih="$(awk -v v="$height" -v s="$SCALE" 'BEGIN { printf "%.0f", v * s }')"
  if [[ ! -f "$source" ]]; then
    echo "Missing Quick Look stroke render: $source" >&2
    exit 1
  fi
  magick "$source" -fuzz 3% -transparent white -trim +repage \
    -resize "${iw}x${ih}!" -alpha on -colorspace sRGB -type TrueColorAlpha "PNG32:$tmp"
  magick "$canvas" "$tmp" -geometry "+${ix}+${iy}" -compose over -composite \
    -alpha on -colorspace sRGB -type TrueColorAlpha "PNG32:$canvas"
}

new_layer() {
  local name="$1"
  magick -size 1080x1080 xc:none -alpha on -colorspace sRGB \
    -type TrueColorAlpha "PNG32:$BUILD/${name}.png"
}

new_layer body_base
place "$BUILD/body_base.png" "$ASSETS/base.svg" 51.775 86.247 154.42 78.758
place "$BUILD/body_base.png" "$ASSETS/base_right.svg" 170.644 111 19.356 23.080
place "$BUILD/body_base.png" "$ASSETS/base_left.svg" 96.844 95 10.967 9.925
place_ql "$BUILD/body_base.png" base_stroke 51.775 86.247 154.42 78.758

new_layer left_hand
place "$BUILD/left_hand.png" "$ASSETS/left_hand_fill.svg" 37.09 119.16 37.912 43.836
place "$BUILD/left_hand.png" "$ASSETS/left_hand_paw.svg" 37.59 124.98 22.411 23.022
place_ql "$BUILD/left_hand.png" left_hand_stroke 35.088 117.161 41.916 47.834

new_layer face
place "$BUILD/face.png" "$ASSETS/eye_left.svg" 88 134 9 9
place "$BUILD/face.png" "$ASSETS/eye_right.svg" 139 139 9 9
place_ql "$BUILD/face.png" mouth 101.499 136.999 23.001 8.036
place "$BUILD/face.png" "$ASSETS/cheek.svg" 74 139 13.56 10.555
place "$BUILD/face.png" "$ASSETS/cheek.svg" 148 146 13.56 10.555

new_layer hat
place "$BUILD/hat.png" "$ASSETS/hat_background.svg" 116.99 72.47 35.94 35.954
place_ql "$BUILD/hat.png" hat_outline 113.19 69.951 41.744 40.466
place_ql "$BUILD/hat.png" hat_beak 116.5 80.5 8.001 5.001
place_ql "$BUILD/hat.png" hat_eye 128.0 79.0 4.5 9.0
place_ql "$BUILD/hat.png" hat_wing 130.999 93 15.501 10.014

new_layer right_hand
place "$BUILD/right_hand.png" "$ASSETS/right_hand_fill.svg" 150.85 144 53.344 37.091
place_ql "$BUILD/right_hand.png" right_hand_stroke 148.849 142.001 57.345 41.089

new_layer tap_marks
place_ql "$BUILD/tap_marks.png" bong_marks 130.999 176 33.5 21.5

magick \
  "$BUILD/body_base.png" \
  "$BUILD/left_hand.png" \
  "$BUILD/face.png" \
  "$BUILD/hat.png" \
  "$BUILD/right_hand.png" \
  "$BUILD/tap_marks.png" \
  -background none -compose over -flatten \
  -alpha on -colorspace sRGB -type TrueColorAlpha "PNG32:$PREVIEW"

magick \
  "$PREVIEW" \
  -label body_base "$BUILD/body_base.png" \
  -label left_hand "$BUILD/left_hand.png" \
  -label face "$BUILD/face.png" \
  -label hat "$BUILD/hat.png" \
  -label right_hand "$BUILD/right_hand.png" \
  -label tap_marks "$BUILD/tap_marks.png" \
  -alpha on -colorspace sRGB -type TrueColorAlpha \
  "$OUT"

magick identify "$OUT"
