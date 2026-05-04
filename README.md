# lofii

`lofii` is a native macOS desktop widget for lofi radio, ambient scenes, GIF mode, and a Live2D BongoCat mode. It is titlebar-free, pinnable, draggable, resizable, and designed to stay out of the way while keeping music and motion on screen.

The project is a Swift Package executable. It uses SwiftUI/AppKit for the shell, AVFoundation for audio/video playback, Metal for scene rendering, Sparkle for app updates, and Live2D Cubism Native SDK components for the BongoCat renderer.

## Features

- Persistent transparent widget window with rounded corners, hover-only controls, drag support, and always-on-top mode.
- Cinematic scene mode with day, night, rain, and night-rain variants loaded on demand and cached locally.
- GIF scene mode with lofi.cafe-style GIFs and bundled TV-static transition frames.
- Live audio stations from Chillhop, SomaFM, and Poolsuite FM, with live track metadata where available.
- Scroll-wheel volume control, keyboard shortcuts, fullscreen support, and per-mode settings.
- Native Live2D BongoCat mode with keyboard and mouse input reactions.

## Requirements

- macOS 26.0 or newer.
- Xcode 26.4 or a compatible Swift 6.3 toolchain.
- Live2D Cubism SDK for Native. This repository does not commit Cubism Core; install it from the official SDK archive before building.
- Network access on first launch for remote scene, GIF, radio, and metadata requests.
- For release builds with automatic updates: Sparkle signing keys and, for public distribution, Apple code-signing/notarization credentials.

## Install

Clone the repository and run the executable target. `scripts/install_cubism_core.sh` downloads the official Live2D Cubism SDK for Native by default and extracts only the Core files needed for linking.

```bash
git clone https://github.com/rhinoc/lofii.git
cd lofii
scripts/install_cubism_core.sh
swift run lofii
```

You can also open `Package.swift` in Xcode and run the `lofii` executable target.

## Usage

First launch downloads the selected scene or GIF into the local cache. Scene MP4s are roughly 1-4 MB each.

Local cache locations:

- Cinematic scenes: `~/Library/Caches/Lofii/scenes/`
- GIF assets: `~/Library/Caches/Lofii/gifs/`
- Imported BongoCat packs: `~/.lofii/bongo/<name>/`

Custom BongoCat model import and preparation tools are documented in
[Support/README.md](./Support/README.md).

Keyboard shortcuts:

- `Space`: play or pause
- `Left Arrow` / `Right Arrow`: switch scenes
- `Command-V`: cycle day, night, rain, and night-rain variants in Cinematic mode
- `Command-M`: switch Cinematic / GIF / BongoCat modes
- `G`: next GIF in GIF mode
- `Command-T`: toggle always-on-top

## Development

Build and test from the repository root:

```bash
scripts/install_cubism_core.sh
swift build
swift test
```

Create a local release zip:

```bash
scripts/build_release.sh
```

Release automation is documented in [SPARKLE.md](./SPARKLE.md). The release workflow expects GitHub Actions secrets for Sparkle update signing and optional Apple code signing.

## Contributing

Issues and pull requests are welcome. Before opening a large change, open an issue to discuss the direction and licensing impact.

For local setup, coding conventions, tests, asset rules, and release boundaries, read [CONTRIBUTING.md](./CONTRIBUTING.md).

## Third-Party Assets and Licenses

Original project source code is licensed under the Mozilla Public License 2.0. See [LICENSE](./LICENSE).

That license does not override third-party terms. This repository includes or references assets, fonts, SDK components, and services with separate licenses or usage terms. See [CREDITS.md](./CREDITS.md) for attribution and current redistribution notes.

Important boundaries:

- Live2D Cubism Framework source is governed by the Live2D Open Software License.
- Live2D Cubism Core headers and runtime library are governed by the Live2D Proprietary Software License and are installed from the official SDK package, not committed to this repository.
- Bundled BongoCat-compatible model packs and lofi visual media require source-by-source redistribution verification before a public release.