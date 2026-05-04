#!/usr/bin/env bash
# Release build: lofii.app zip for Sparkle + GitHub Releases (Live2D dylib in Frameworks).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(tr -d '[:space:]' <VERSION)"

scripts/install_cubism_core.sh --check
swift build -c release --product lofii
BIN="$(swift build -c release --show-bin-path)/lofii"
SPARKLE_FW="$(dirname "$BIN")/Sparkle.framework"
DYLIB_SRC="$ROOT/Vendor/CubismNativeSDK/Core/dll/macos/libLive2DCubismCore.dylib"
PLIST_SRC="$ROOT/Sources/Lofii/Info.plist"
ICON_SRC="$ROOT/Sources/Lofii/Resources/AppIcon.icns"
LOFII_RES="$ROOT/Sources/Lofii/Resources"
METAL_SRC="$ROOT/Sources/Lofii/StageMetalShaders.metal"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

APP="$STAGE/lofii.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$PLIST_SRC" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/lofii"
cp "$DYLIB_SRC" "$APP/Contents/Frameworks/libLive2DCubismCore.dylib"
if [[ ! -d "$SPARKLE_FW" ]]; then
  echo "error: Sparkle.framework not found next to release binary (expected: $SPARKLE_FW)" >&2
  exit 1
fi
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"
# Ship the same resource layout as SwiftPM's `lofii_lofii.bundle`, but under `Contents/Resources/`
# so `LofiiResources.bundle` resolves to `Bundle.main` and codesign does not require an extra bundle at .app root.
for name in Statics Fonts BongoCat FrameworkMetallibs; do
  if [[ ! -d "$LOFII_RES/$name" ]]; then
    echo "error: missing $LOFII_RES/$name" >&2
    exit 1
  fi
  cp -R "$LOFII_RES/$name" "$APP/Contents/Resources/"
done
cp "$METAL_SRC" "$APP/Contents/Resources/"
cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.icns"
install_name_tool -change @rpath/libLive2DCubismCore.dylib \
  @executable_path/../Frameworks/libLive2DCubismCore.dylib \
  "$APP/Contents/MacOS/lofii"
# SPM links Sparkle as @rpath/Sparkle.framework/...; ship the framework and resolve rpath at runtime.
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/lofii"

# Strip AppleDouble / xattrs so the zip does not ship ._ sidecar files.
find "$APP" -name '._*' -delete
xattr -cr "$APP"

# Match liltr: real signing when CI keychain has a cert; else ad-hoc.
"$ROOT/scripts/sign_built_app.sh" "$APP"

mkdir -p "$ROOT/dist"
ZIP="$ROOT/dist/lofii-${VERSION}-macos.zip"
rm -f "$ZIP"
# `zip` keeps the archive clean; `ditto -c -k` often injects AppleDouble `._*` files.
( cd "$STAGE" && /usr/bin/zip -q -r "$ZIP" lofii.app )

echo "Built $ZIP"
