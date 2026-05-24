---
name: lofi-media-generation
description: Generate custom GIF and video media for Lofii from pixel-art packs, parallax layer packs, sprite sheets, and Aseprite exports.
---

# Lofii Media Generation

Use this skill when creating custom GIF/video media for Lofii from downloaded pixel-art packs, parallax layer packs, sprite sheets, or Aseprite exports.

## Goal

Generate media that works well in Lofii's Custom media mode:

- Prefer MP4 for long, smooth loops. Use GIF only for short low-frame-count animations.
- Output files directly to `~/.lofii/media` unless the user asks for another destination.
- Keep loops seamless: the last frame must transition back to the first frame without a visible jump.
- Favor slow lo-fi atmosphere, but do not confuse slow ambience with physically impossible motion.

## Dependencies

Use local tools first:

- `magick` for layer composition, wrapping crops, opacity, and pixel scaling.
- `ffmpeg` for MP4 encoding.
- `ffprobe` for final verification.
- `aseprite` only when installed and needed for `.ase` / `.aseprite` exports. If it is missing, use available PNG layers/sprites and state that Aseprite sources were not exported.

## Reusable Script

Run the project script from the repo root:

```bash
scripts/generate_lofi_media_videos.sh miami
scripts/generate_lofi_media_videos.sh industrial
scripts/generate_lofi_media_videos.sh forest
scripts/generate_lofi_media_videos.sh city
scripts/generate_lofi_media_videos.sh mountain
scripts/generate_lofi_media_videos.sh requested
scripts/generate_lofi_media_videos.sh all
```

Defaults:

- `INDUSTRIAL_DIR=$HOME/Downloads/parallax-industrial-pack/layers`
- `MIAMI_DIR=$HOME/Downloads/Miami-synth-files`
- `FOREST_DIR=$HOME/Downloads/parallax_forest_pack/layers`
- `CITY_DIR=$HOME/Downloads/City`
- `MOUNTAIN_DIR=$HOME/Downloads/parallax_mountain_pack/layers`
- `OUT=$HOME/.lofii/media`
- `ROOT=/tmp/lofii-media-video`

Override paths with environment variables when using different packs:

```bash
MIAMI_DIR=/path/to/Miami-synth-files OUT="$HOME/.lofii/media" scripts/generate_lofi_media_videos.sh miami
```

## Motion Rules

Use depth-aware motion, not a flat linear scroll.

- Far background: static or nearly static.
- Far buildings: extremely slow movement. If their texture repeats visibly, keep them static or move them at sub-pixel-equivalent cadence using a higher output frame rate.
- Midground trees/buildings: slow but continuous. Avoid integer jumps every several frames at the displayed scale.
- Road/ground: fast enough to sell vehicle motion.
- Foreground objects: fastest. They should cross in front of the subject and show clear relative motion.
- Vehicle in a tracking shot: the car may stay near the same screen position, but the road, foreground, and midground must move relative to it. Do not animate a car in place with a static world unless the scene is explicitly parked/idling.

For a convincing driving shot, a validated speed relationship is:

```text
far sky: static
far buildings: very slow
mid palms: slow and smooth
road: fast
foreground palm: fastest
car sprite: wheel/body animation plus tiny suspension bounce
```

## Smoothness Rules

Match duration, frame rate, and per-frame displacement:

- Low frame rate with slow movement can still look choppy. A 6-7fps GIF is often visibly steppy.
- Use MP4 at 20-40fps when motion needs to be smooth.
- If a layer must move slowly, do not implement it as `i / N` on a low-resolution source when the output is scaled 2x; it will jump every N frames. Instead, upscale the layer first and crop/wrap at output resolution, or raise FPS.
- Keep pixel-art scaling with point filtering.

## Looping Rules

Make every moving layer complete an integer cycle over the total frame count.

- For a wrapped layer width `W`, use offsets like `(i * speed) % W`.
- Choose `frames` so the important moving layers land exactly on a cycle boundary.
- Do not include a duplicate terminal frame equal to the first frame; let playback loop from the last sampled frame back to frame 0.
- Exception: when the user explicitly asks for the first and last frames to be the same, append a terminal frame copied from `f_0000.png` and verify it with `cmp`.
- Use sinusoidal pulses with period `frames`, for example brightness or glow effects.

## Verification

After generation, always verify the media file:

```bash
ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height,nb_frames,r_frame_rate,duration \
  -of default=noprint_wrappers=1 ~/.lofii/media/lofii-miami-synth-cruise.mp4
```

Check the resulting file size and confirm no generation process is still running:

```bash
ls -lh ~/.lofii/media/lofii-*.mp4
pgrep -af 'generate_lofi_media_videos|magick .*lofii-media-video|ffmpeg .*lofii' || true
```

When the user reports visual feedback, update only the affected scene first, then regenerate that file and report the new FPS, duration, frame count, and size.
