# Contributing to lofii

Thanks for taking the time to improve `lofii`. This project is a native macOS app with bundled third-party assets, so contributions need to be clear about both code behavior and licensing impact.

## Development Setup

Requirements:

- macOS 26.0 or newer
- Xcode 26.4 or a compatible Swift 6.3 toolchain
- Git
- Live2D Cubism SDK for Native. The install script downloads the official SDK archive by default.

Clone and verify the project:

```bash
git clone https://github.com/rhinoc/lofii.git
cd lofii
scripts/install_cubism_core.sh
swift build
swift test
```

Run the app:

```bash
swift run lofii
```

## Pull Requests

- Open an issue first for large UI, rendering, release, dependency, or asset changes.
- Keep pull requests focused on one behavior or one small set of related files.
- Include tests when changing model logic, station selection, caching behavior, input handling, parsing, or release scripts.
- Run `swift test` before submitting.
- Update `README.md`, `CREDITS.md`, or `SPARKLE.md` when behavior, dependencies, assets, release artifacts, or user-facing setup changes.

## Code Style

- Prefer existing SwiftUI/AppKit, actor, and service patterns in `Sources/Lofii`.
- Keep rendering changes scoped; Metal and Live2D integration code has a larger blast radius than UI-only changes.
- Avoid global state unless it matches an existing app-level model or cache pattern.
- Do not add logging that prints secrets, full local paths containing usernames, or private release configuration.

## Assets and Third-Party Content

Do not add new bundled artwork, fonts, model packs, audio, videos, GIFs, SDK files, or binary blobs unless the pull request includes:

- Original source URL.
- License or usage terms.
- Redistribution permission for inclusion in this repository and packaged app.
- Attribution text for `CREDITS.md`.
- File size and runtime impact.

For uncertain assets, prefer a downloader or user-supplied import path over bundling the file in the repository.

BongoCat model import layout and support tools are documented in
[Support/README.md](./Support/README.md). Imported local packs belong under
`~/.lofii/bongo/<name>/`; bundled packs require explicit redistribution rights.

## Release and Signing

Do not commit release zips, `.app` bundles, notarization logs, certificates, private keys, passwords, or local Sparkle signing exports.

Release automation lives in:

- `.github/workflows/release.yml`
- `scripts/build_release.sh`
- `scripts/update_appcast.sh`
- `scripts/code_sign.sh`
- `scripts/sign_built_app.sh`
- `scripts/install_cubism_core.sh`
- `SPARKLE.md`

Changes to these files should explain how local builds, GitHub Releases, Sparkle appcast entries, signing, and notarization are affected.

CI uses the default official Cubism SDK for Native download URL. `CUBISM_NATIVE_SDK_URL` can be set as a repository variable to override the URL, and `CUBISM_NATIVE_SDK_SHA256` can be set as a repository variable to pin the archive checksum.

## Security Reports

For signing key exposure, update-feed compromise, or other sensitive issues, follow [SECURITY.md](./SECURITY.md) instead of opening a public issue.
