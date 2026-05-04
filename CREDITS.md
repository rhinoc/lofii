# Credits and Third-Party Notices

This project includes or references third-party artwork, media streams, fonts,
icons, and SDK code. Source files and vendored assets keep their upstream
headers where available; this file is the top-level attribution index for
public releases.

## BongoCat

- Bongo interaction design and behavior references:
  [ayangweb/BongoCat](https://github.com/ayangweb/BongoCat). The renderer in
  this project is a native Metal implementation.
- Bundled standard BongoCat model and keyboard assets:
  [ayangweb/BongoCat](https://github.com/ayangweb/BongoCat), originally listed
  as "经典小键盘 · 标准模式" by
  [@MMmmmoko](https://space.bilibili.com/5808772).
- Additional bundled BongoCat-compatible model packs are sourced from the
  [ayangweb/Awesome-BongoCat](https://github.com/ayangweb/Awesome-BongoCat)
  index. Notable bundled packs:
  - "温迪 · 标准模式" by
    [@狐言 0v0](https://www.bilibili.com/video/BV1Dd4y1u7FR)
  - "邦布 · 标准模式" by
    [@4014OvO](https://www.bilibili.com/video/BV1F1421t7HQ)

### BongoCat MIT Notice

The upstream BongoCat project is licensed under the MIT License:

```text
MIT License

Copyright (c) 2025 ayangweb

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Third-party visual media

- Cinematic MP4 scene catalog:
  [ItzAshOffcl/lofi-resources](https://github.com/ItzAshOffcl/lofi-resources),
  preserving animated scene assets originally associated with the now-offline
  Lofi.co experience.
- GIF catalog and TV static transition frames:
  [lofi.cafe](https://www.lofi.cafe), with animated GIF fallback URLs served
  from [Giphy](https://giphy.com).
- Overall GIF-mode inspiration:
  [lofi.cafe](https://www.lofi.cafe).
- Shattered-glass overlay textures and shader reference:
  [Shattered Glass for Ren'Py by Maurimo](https://maurimo.itch.io/shattered-glass),
  adapted into the native Metal post-processing pass.

### Shattered Glass MIT Notice

The upstream Shattered Glass package is licensed under the MIT License:

```text
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Radio and Music Streams

- [Chillhop](https://chillhop.com) live radio and live track metadata.
- [SomaFM](https://somafm.com) stations used by presets:
  Groove Salad, Beat Blender, Fluid, and Drone Zone.
- [Poolsuite](https://poolsuite.net) / Poolsuite FM station stream.
- [Radio.co](https://radio.co) public station APIs and stream infrastructure
  used to resolve the Poolsuite FM stream.

## Fonts and Icons

- [Doto](https://fonts.google.com/specimen/Doto) by Óliver Lalan, licensed
  under the SIL Open Font License 1.1. The bundled license text is in
  `Sources/Lofii/Resources/Fonts/Doto-OFL.txt`.
- [Pixelarticons](https://github.com/halfmage/pixelarticons) by Gerrit
  Halfmann, licensed under MIT. The bundled license text is in
  `Sources/Lofii/Resources/Fonts/PixelartIcons-LICENSE.txt`.

## Live2D / Cubism

- Live2D Cubism Framework source files are Copyright Live2D Inc. and governed
  by the Live2D Open Software license:
  <https://www.live2d.com/eula/live2d-open-software-license-agreement_en.html>.
- The vendored Cubism Framework source files retain their upstream copyright
  headers under `Vendor/CubismNativeSDK/Framework/src/`.
- Live2D Cubism Core (`Live2DCubismCore.h` and
  `libLive2DCubismCore.dylib`) is governed by the Live2D Proprietary Software
  License and is not committed to this repository. It is installed locally or
  in CI from the official Cubism SDK for Native archive.

## App Update Framework

- [Sparkle](https://github.com/sparkle-project/Sparkle) is used for macOS app
  update support. Sparkle is MIT-licensed with additional notices for vendored
  components in its upstream `LICENSE` file.

## Notes for Maintainers

- The `Awesome-BongoCat` repository is an index of model links, not a blanket
  license grant. Before a public release with bundled model packs, verify that
  each bundled pack's original author allows redistribution in this app.
- If adding more GIF/video/radio sources, add them here and keep the README
  summary in sync.
