#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/tmp/lofii-media-video}"
OUT="${OUT:-$HOME/.lofii/media}"
INDUSTRIAL_DIR="${INDUSTRIAL_DIR:-$HOME/Downloads/parallax-industrial-pack/layers}"
MIAMI_DIR="${MIAMI_DIR:-$HOME/Downloads/Miami-synth-files}"
FOREST_DIR="${FOREST_DIR:-$HOME/Downloads/parallax_forest_pack/layers}"
CITY_DIR="${CITY_DIR:-$HOME/Downloads/City}"
MOUNTAIN_DIR="${MOUNTAIN_DIR:-$HOME/Downloads/parallax_mountain_pack/layers}"
FPS=20

mkdir -p "$ROOT" "$OUT"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required tool: $1" >&2
    exit 1
  fi
}

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "missing source file: $1" >&2
    exit 1
  fi
}

make_layer_canvas() {
  local img="$1" w="$2" h="$3" gravity="$4" out="$5"
  magick -size "${w}x${h}" canvas:none "$img" -gravity "$gravity" -composite "$out"
}

crop_wrap() {
  local img="$1" w="$2" h="$3" off="$4" out="$5"
  magick "$img" "$img" "$img" +append -crop "${w}x${h}+${off}+0" +repage "$out"
}

encode_mp4() {
  local frames_dir="$1" out="$2"
  ffmpeg -hide_banner -loglevel error -y \
    -framerate "$FPS" -i "$frames_dir/f_%04d.png" \
    -vf "format=yuv420p" \
    -c:v libx264 -preset medium -crf 18 -movflags +faststart \
    "$out"
}

duplicate_first_frame() {
  local frames_dir="$1" terminal_index="$2"
  cp "$frames_dir/f_0000.png" "$frames_dir/f_$(printf '%04d' "$terminal_index").png"
}

build_industrial_video() {
  local dir="$ROOT/industrial"; rm -rf "$dir"; mkdir -p "$dir/layers" "$dir/frames"
  local src="$INDUSTRIAL_DIR"
  local frames=816

  require_file "$src/skill-desc_0002_far-buildings.png"
  require_file "$src/skill-desc_0001_buildings.png"
  require_file "$src/skill-desc_0000_foreground.png"
  require_file "$src/skill-desc_0003_bg.png"

  make_layer_canvas "$src/skill-desc_0002_far-buildings.png" 272 160 South "$dir/layers/far.png"
  make_layer_canvas "$src/skill-desc_0001_buildings.png" 272 160 South "$dir/layers/buildings.png"
  make_layer_canvas "$src/skill-desc_0000_foreground.png" 272 160 South "$dir/layers/foreground.png"
  magick "$src/skill-desc_0003_bg.png" -filter point -resize 544x320 "$dir/layers/bg.png"
  magick "$dir/layers/far.png" -filter point -resize 544x320 "$dir/layers/far-2x.png"
  magick "$dir/layers/buildings.png" -filter point -resize 544x320 "$dir/layers/buildings-2x.png"
  magick "$dir/layers/foreground.png" -filter point -resize 544x320 "$dir/layers/foreground-2x.png"

  for i in $(seq 0 $((frames - 1))); do
    local far=$(( ((i * 2) / 3) % 544 ))
    local buildings=$(( ((i * 4) / 3) % 544 ))
    local fore=$(( (i * 2) % 544 ))
    crop_wrap "$dir/layers/far-2x.png" 544 320 "$far" "$dir/far.png"
    crop_wrap "$dir/layers/buildings-2x.png" 544 320 "$buildings" "$dir/buildings.png"
    crop_wrap "$dir/layers/foreground-2x.png" 544 320 "$fore" "$dir/foreground.png"
    magick "$dir/layers/bg.png" "$dir/far.png" -composite "$dir/buildings.png" -composite "$dir/foreground.png" -composite "$dir/frames/f_$(printf '%04d' "$i").png"
  done

  local previous_fps="$FPS"
  FPS=20
  encode_mp4 "$dir/frames" "$OUT/lofii-parallax-industrial-smooth.mp4"
  FPS="$previous_fps"
}

build_miami_cruise_video() {
  local dir="$ROOT/miami-cruise"; rm -rf "$dir"; mkdir -p "$dir/frames"
  local layers="$MIAMI_DIR/Layers"
  local cars="$MIAMI_DIR/sprites/running"
  local frames=896
  local previous_fps="$FPS"
  FPS=40

  require_file "$layers/back.png"
  require_file "$layers/sun.png"
  require_file "$layers/buildings.png"
  require_file "$layers/palms.png"
  require_file "$layers/highway.png"
  require_file "$layers/palm-tree.png"
  for c in 1 2 3 4; do
    require_file "$cars/car-running${c}.png"
  done

  magick "$layers/buildings.png" -filter point -resize 512x480 "$dir/buildings-2x.png"
  magick "$layers/palms.png" -filter point -resize 448x480 "$dir/palms-2x.png"
  for c in 1 2 3 4; do
    magick "$cars/car-running${c}.png" -filter point -resize 368x136 "$dir/car-${c}-2x.png"
  done

  for i in $(seq 0 $((frames - 1))); do
    local buildings=$(( ((i * 4) / 7) % 512 ))
    local palms=$(( (i / 2) % 448 ))
    local road=$(( (i * 12) % 896 ))
    local palm_x=$(( 315 - ((i * 14) % 448) ))
    local palm_geom
    if (( palm_x >= 0 )); then
      palm_geom="+${palm_x}+32"
    else
      palm_geom="${palm_x}+32"
    fi

    local car_idx=$(( ((i / 2) % 4) + 1 ))
    local car_y car_y2 glow
    car_y=$(awk -v i="$i" -v n="$frames" 'BEGIN { pi=atan2(0,-1); printf "%d", 152 + int(0.5 + 1.0 * sin(8*pi*i/n)) }')
    car_y2=$(( car_y * 2 ))
    glow=$(awk -v i="$i" -v n="$frames" 'BEGIN { pi=atan2(0,-1); printf "%.3f", 0.80 + 0.14 * (1 + sin(2*pi*i/n)) / 2 }')

    crop_wrap "$layers/highway.png" 224 240 "$road" "$dir/highway.png"
    crop_wrap "$dir/buildings-2x.png" 448 480 "$buildings" "$dir/buildings.png"
    crop_wrap "$dir/palms-2x.png" 448 480 "$palms" "$dir/palms.png"
    magick "$layers/sun.png" -channel A -evaluate multiply "$glow" +channel "$dir/sun-glow.png"
    magick -size 224x240 canvas:none "$layers/palm-tree.png" -geometry "$palm_geom" -composite "$dir/foreground-palm.png"
    magick "$dir/highway.png" -filter point -resize 448x480 "$dir/highway-2x.png"
    magick "$dir/foreground-palm.png" -filter point -resize 448x480 "$dir/foreground-palm-2x.png"
    magick "$layers/back.png" "$dir/sun-glow.png" -composite -filter point -resize 448x480 "$dir/sky.png"
    magick "$dir/sky.png" "$dir/buildings.png" -composite "$dir/palms.png" -composite "$dir/highway-2x.png" -composite "$dir/car-${car_idx}-2x.png" -geometry "+48+${car_y2}" -composite "$dir/foreground-palm-2x.png" -composite "$dir/frames/f_$(printf '%04d' "$i").png"
  done

  encode_mp4 "$dir/frames" "$OUT/lofii-miami-synth-cruise.mp4"
  FPS="$previous_fps"
}

build_forest_video() {
  local dir="$ROOT/forest"; rm -rf "$dir"; mkdir -p "$dir/layers" "$dir/frames"
  local src="$FOREST_DIR"
  local frames=1088
  local previous_fps="$FPS"
  FPS=40

  require_file "$src/parallax-forest-back-trees.png"
  require_file "$src/parallax-forest-middle-trees.png"
  require_file "$src/parallax-forest-lights.png"
  require_file "$src/parallax-forest-front-trees.png"

  magick "$src/parallax-forest-back-trees.png" -filter point -resize 544x320 "$dir/layers/back.png"
  magick "$src/parallax-forest-middle-trees.png" -filter point -resize 544x320 "$dir/layers/middle-2x.png"
  magick "$src/parallax-forest-lights.png" -filter point -resize 544x320 "$dir/layers/lights-2x.png"
  magick "$src/parallax-forest-front-trees.png" -filter point -resize 544x320 "$dir/layers/front-2x.png"

  for i in $(seq 0 $((frames - 1))); do
    local middle=$(( (i / 2) % 544 ))
    local lights=$(( (i / 2) % 544 ))
    local front=$(( i % 544 ))
    local glow
    glow=$(awk -v i="$i" -v n="$frames" 'BEGIN { pi=atan2(0,-1); printf "%.3f", 0.72 + 0.18 * (1 + sin(2*pi*i/n)) / 2 }')

    crop_wrap "$dir/layers/middle-2x.png" 544 320 "$middle" "$dir/middle.png"
    crop_wrap "$dir/layers/lights-2x.png" 544 320 "$lights" "$dir/lights.png"
    crop_wrap "$dir/layers/front-2x.png" 544 320 "$front" "$dir/front.png"
    magick "$dir/lights.png" -channel A -evaluate multiply "$glow" +channel "$dir/lights-glow.png"
    magick "$dir/layers/back.png" "$dir/middle.png" -composite "$dir/lights-glow.png" -composite "$dir/front.png" -composite "$dir/frames/f_$(printf '%04d' "$i").png"
  done

  duplicate_first_frame "$dir/frames" "$frames"
  encode_mp4 "$dir/frames" "$OUT/lofii-parallax-forest-smooth.mp4"
  FPS="$previous_fps"
}

build_city_video() {
  local dir="$ROOT/city"; rm -rf "$dir"; mkdir -p "$dir/layers" "$dir/frames"
  local src="$CITY_DIR"
  local frames=960
  local previous_fps="$FPS"
  FPS=40

  require_file "$src/BG.png"
  require_file "$src/Background 1.png"
  require_file "$src/Middle.png"
  require_file "$src/Foreground.png"

  magick "$src/BG.png" -filter point -resize 480x270 "$dir/layers/bg.png"
  magick "$src/Background 1.png" -filter point -resize 480x270 "$dir/layers/background-2x.png"
  magick "$src/Middle.png" -filter point -resize 480x270 "$dir/layers/middle-2x.png"
  magick "$src/Foreground.png" -filter point -resize 480x270 "$dir/layers/foreground-2x.png"

  for i in $(seq 0 $((frames - 1))); do
    local background=$(( (i / 2) % 480 ))
    local middle=$(( i % 480 ))
    local foreground=$(( (i * 2) % 480 ))
    local stars
    stars=$(awk -v i="$i" -v n="$frames" 'BEGIN { pi=atan2(0,-1); printf "%.3f", 0.86 + 0.10 * (1 + sin(2*pi*i/n)) / 2 }')

    crop_wrap "$dir/layers/background-2x.png" 480 270 "$background" "$dir/background.png"
    crop_wrap "$dir/layers/middle-2x.png" 480 270 "$middle" "$dir/middle.png"
    crop_wrap "$dir/layers/foreground-2x.png" 480 270 "$foreground" "$dir/foreground.png"
    magick "$dir/layers/bg.png" -channel RGB -evaluate multiply "$stars" +channel "$dir/bg-pulse.png"
    magick "$dir/bg-pulse.png" "$dir/background.png" -composite "$dir/middle.png" -composite "$dir/foreground.png" -composite "$dir/frames/f_$(printf '%04d' "$i").png"
  done

  duplicate_first_frame "$dir/frames" "$frames"
  encode_mp4 "$dir/frames" "$OUT/lofii-city-night-smooth.mp4"
  FPS="$previous_fps"
}

build_mountain_video() {
  local dir="$ROOT/mountain"; rm -rf "$dir"; mkdir -p "$dir/layers" "$dir/frames"
  local src="$MOUNTAIN_DIR"
  local frames=1088
  local previous_fps="$FPS"
  FPS=40

  require_file "$src/parallax-mountain-bg.png"
  require_file "$src/parallax-mountain-montain-far.png"
  require_file "$src/parallax-mountain-mountains.png"
  require_file "$src/parallax-mountain-trees.png"
  require_file "$src/parallax-mountain-foreground-trees.png"

  magick "$src/parallax-mountain-bg.png" -filter point -resize 544x320 "$dir/layers/bg.png"
  magick "$src/parallax-mountain-montain-far.png" -filter point -resize 544x320 "$dir/layers/far-2x.png"
  magick "$src/parallax-mountain-mountains.png" -filter point -resize 1088x320 "$dir/layers/mountains-2x.png"
  magick "$src/parallax-mountain-trees.png" -filter point -resize 1088x320 "$dir/layers/trees-2x.png"
  magick "$src/parallax-mountain-foreground-trees.png" -filter point -resize 1088x320 "$dir/layers/foreground-2x.png"

  for i in $(seq 0 $((frames - 1))); do
    local far=$(( (i / 2) % 544 ))
    local mountains=$(( (i / 2) % 1088 ))
    local trees=$(( i % 1088 ))
    local foreground=$(( (i * 2) % 1088 ))

    crop_wrap "$dir/layers/far-2x.png" 544 320 "$far" "$dir/far.png"
    crop_wrap "$dir/layers/mountains-2x.png" 544 320 "$mountains" "$dir/mountains.png"
    crop_wrap "$dir/layers/trees-2x.png" 544 320 "$trees" "$dir/trees.png"
    crop_wrap "$dir/layers/foreground-2x.png" 544 320 "$foreground" "$dir/foreground.png"
    magick "$dir/layers/bg.png" "$dir/far.png" -composite "$dir/mountains.png" -composite "$dir/trees.png" -composite "$dir/foreground.png" -composite "$dir/frames/f_$(printf '%04d' "$i").png"
  done

  duplicate_first_frame "$dir/frames" "$frames"
  encode_mp4 "$dir/frames" "$OUT/lofii-parallax-mountain-smooth.mp4"
  FPS="$previous_fps"
}

require_tool magick
require_tool ffmpeg

case "${1:-all}" in
  industrial)
    build_industrial_video
    ;;
  miami)
    build_miami_cruise_video
    ;;
  forest)
    build_forest_video
    ;;
  city)
    build_city_video
    ;;
  mountain)
    build_mountain_video
    ;;
  all)
    build_industrial_video
    build_miami_cruise_video
    build_forest_video
    build_city_video
    build_mountain_video
    ;;
  requested)
    build_forest_video
    build_city_video
    build_mountain_video
    ;;
  *)
    echo "usage: $0 [all|requested|industrial|miami|forest|city|mountain]" >&2
    exit 2
    ;;
esac
