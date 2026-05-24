# FocusCat Live2D Source Kit

Source:
https://www.figma.com/design/yuv6HqRhKBI5sKFhbg5Efj/Bongo-Cat-Asset-Kit--Tapling---FocusCat---Community-?node-id=28-361

License: CC BY 4.0

This directory is a preparation kit, not a finished Live2D model. Lofii needs a
Cubism runtime export containing `cat.model3.json`, a referenced `.moc3`, and
the texture files exported by Live2D Cubism Editor.

## Contents

- `composed.png`: 1080x1080 rendered reference from the Figma node.
- `focuscat_import.psd`: generated layered PSD for Cubism import.
- `focuscat_layers_preview.png`: transparent flattened preview of the PSD
  layers.
- `focuscat_layers_preview_white.png`: preview on a white background for
  checking dark tap marks and outlines.
- `assets/*.svg`: individual vector parts exported from the Figma node.
- `lofii-pack/`: target folder shape for testing under `~/.lofii/bongo/focuscat/`.
- `build_focuscat_psd.sh`: reproducible PSD generator. It uses ImageMagick for
  most vector parts and pre-rendered Quick Look PNGs for stroke-only SVGs that
  ImageMagick does not render correctly.

## Cubism Build Steps

1. Open `focuscat_import.psd` in Cubism Editor and choose `Create new model from
   PSD file`.
2. Keep these major moving parts separate:
   - body/base
   - left hand
   - right hand
   - face details
   - hat
   - bong/tap marks
3. Create parameters expected by Lofii:
   - `CatParamLeftHandDown`
   - `CatParamRightHandDown`
   - `ParamMouseLeftDown`
   - `ParamMouseRightDown`
4. Optional enrichment parameters:
   - `ParamMouseX`
   - `ParamMouseY`
   - `ParamAngleX`
   - `ParamAngleY`
   - `ParamAngleZ`
   - `ParamEyeBallX`
   - `ParamEyeBallY`
5. Export embedded runtime data from Cubism Editor:
   - `.moc3`
   - `.model3.json`
   - texture PNGs
   - optional `.cdi3.json`, `.physics3.json`, `.motion3.json`, `.exp3.json`
6. Rename or copy the exported model setting file to:
   - `lofii-pack/cat.model3.json`
7. Put the exported `.moc3` and texture folders next to `cat.model3.json`.
8. Copy `lofii-pack/` to `~/.lofii/bongo/focuscat/` and use Reload Models in
   Lofii.

## Runtime Pack Layout

```text
~/.lofii/bongo/focuscat/
  cat.model3.json
  demomodel.moc3
  demomodel.1024/
    texture_00.png
  resources/
    cover.png
    background.png
    desktop-layout.json
    bongo-parameter-map.json
    left-keys/
    right-keys/
```

`resources/background.png` should be the keyboard or desktop layer behind the
Live2D model, not the whole cat render. The whole `composed.png` is only useful
as a cover or visual reference.

## Attribution Text

Use this in `CREDITS.md` once bundled:

FocusCat / Bongo Cat Asset Kit by Tapling / FocusCat Community, licensed under
CC BY 4.0. Source:
https://www.figma.com/design/yuv6HqRhKBI5sKFhbg5Efj/Bongo-Cat-Asset-Kit--Tapling---FocusCat---Community-
Adapted into a Live2D/Cubism Bongo model for Lofii.
