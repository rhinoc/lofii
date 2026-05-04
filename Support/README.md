# Support Tools

This directory contains maintainer/user tools for preparing local assets that
are not part of the main app target.

## Adding a BongoCat Model

Imported BongoCat packs live outside the repository at:

```text
~/.lofii/bongo/<pack-name>/
```

`lofii` scans that directory and shows valid packs in the Bongo model picker.
Use a simple folder name such as `my-model`, `miku`, or `keyboard-cat`.

### Required Layout

A valid pack needs a Live2D model JSON and the `.moc3` file referenced by that
JSON:

```text
~/.lofii/bongo/my-model/
  cat.model3.json              # preferred name
  demomodel.moc3               # or whatever FileReferences.Moc points to
  demomodel.1024/
    texture_00.png
  resources/
    background.png             # keyboard/desktop image behind the Live2D model
    left-keys/
      KeyA.png
      KeyS.png
      Space.png
```

If `cat.model3.json` is not present, `lofii` uses the first sorted
`*.model3.json` file in the pack root. The pack is considered invalid if no
model JSON is found or the referenced `.moc3` file is missing.

Keep any texture, expression, physics, pose, and motion paths in the same
relative layout expected by the model JSON.

### Optional Files

```text
resources/
  cover.png
  desktop-layout.json
  bongo-parameter-map.json
  bongo-arrow-overlay-params.json
  left-keys/
    <KeyStem>.png
```

- `resources/background.png`: used as the stage background. For imported packs,
  its pixel size also defines the model stage size; the app halves it for Retina
  parity.
- `resources/left-keys/*.png`: overlay images shown while a matching physical
  key is held. The file stem must match a supported key stem such as `KeyA`,
  `KeyS`, `KeyD`, `KeyW`, `Space`, `Return`, `Tab`, `ShiftLeft`, `ArrowUp`, or
  `UpArrow`.
- `resources/desktop-layout.json`: controls the desktop mask cut line when the
  Bongo desktop mask is enabled.
- `resources/bongo-parameter-map.json`: maps app-side input parameter names to
  the parameter IDs used by your model.
- `resources/bongo-arrow-overlay-params.json`: maps overlay key image stems to
  extra Live2D parameter IDs to drive while that key is held.

### Parameter Mapping

By default, `lofii` sends these app-side parameter IDs:

```text
CatParamLeftHandDown
CatParamRightHandDown
ParamMouseLeftDown
ParamMouseRightDown
```

If your model uses different Live2D parameter IDs, copy the example map:

```bash
cp Support/bongo-parameter-map.example.json \
  ~/.lofii/bongo/my-model/resources/bongo-parameter-map.json
```

Then edit the values:

```json
{
  "CatParamLeftHandDown": "YourLeftHandParamId",
  "CatParamRightHandDown": "YourRightHandParamId",
  "ParamMouseLeftDown": "YourLeftMouseParamId",
  "ParamMouseRightDown": "YourRightMouseParamId"
}
```

Arrow/minimal packs can also drive per-key accessory parameters:

```bash
cp Support/bongo-arrow-overlay-params.example.json \
  ~/.lofii/bongo/my-model/resources/bongo-arrow-overlay-params.json
```

Example:

```json
{
  "UpArrow": "Param17",
  "DownArrow": "Param18",
  "LeftArrow": "Param19",
  "RightArrow": "Param20"
}
```

### Desktop Cut Line Tool

Use `bongo-cutline-tool.html` to create `resources/desktop-layout.json` for a
custom `background.png`.

Open it from the repository root:

```bash
open Support/bongo-cutline-tool.html
```

Workflow:

1. Choose `Custom upload`.
2. Upload your `resources/background.png`.
3. Drag the cut-line handles until the desktop mask follows the edge of the
   keyboard/desk in the image.
4. Optionally use `Pick from image` to sample the desktop color.
5. Click `Copy JSON`.
6. Save the copied JSON as:

```text
~/.lofii/bongo/my-model/resources/desktop-layout.json
```

The app currently reads:

```json
{
  "cutLineMidYRatio": 0.5739,
  "cutLineAngleDeg": 10.138
}
```

Other fields emitted by the tool are harmless metadata for humans and future
tooling.

### Loading the Pack in the App

After copying files into `~/.lofii/bongo/<pack-name>/`:

1. Open `lofii`.
2. Enable the Bongo overlay.
3. Open Settings -> Bongo -> Model -> Reload Models, or use the right-click
   menu: Bongo Cat -> Model -> Reload Models.
4. Select the imported pack from the model list.

If the pack disappears after reload, check that the model root contains a valid
`cat.model3.json` or `*.model3.json`, and that the referenced `.moc3` file
exists.

### Licensing

Only import or redistribute model packs that you are allowed to use. If a model
is added to this repository or shipped in a release, include its source URL,
license, redistribution permission, and attribution in `CREDITS.md`.
