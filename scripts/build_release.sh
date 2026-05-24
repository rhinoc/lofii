#!/usr/bin/env bash
# Release build: lofii.app DMG for Sparkle + GitHub Releases (Live2D dylib in Frameworks).
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
DMG_BACKGROUND="$ROOT/assets/dmg-background.png"
DMG_DS_STORE="$ROOT/assets/dmg.DS_Store"
DMG_APPLICATIONS_ALIAS="$ROOT/assets/Applications.alias"
DMG_APPLICATIONS_ICON="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns"

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
if [[ ! -f "$DMG_BACKGROUND" ]]; then
  echo "error: missing DMG background at $DMG_BACKGROUND" >&2
  exit 1
fi
if [[ ! -f "$DMG_DS_STORE" ]]; then
  echo "error: missing DMG Finder layout at $DMG_DS_STORE" >&2
  exit 1
fi
if [[ ! -f "$DMG_APPLICATIONS_ALIAS" ]]; then
  echo "error: missing DMG Applications alias at $DMG_APPLICATIONS_ALIAS" >&2
  exit 1
fi
if [[ ! -f "$DMG_APPLICATIONS_ICON" ]]; then
  echo "error: missing macOS Applications folder icon at $DMG_APPLICATIONS_ICON" >&2
  exit 1
fi
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"
# Ship the same resource layout as SwiftPM's `lofii_lofii.bundle`, but under `Contents/Resources/`
# so `LofiiResources.bundle` resolves to `Bundle.main` and codesign does not require an extra bundle at .app root.
for name in Statics Fonts BongoCat ShatteredGlass FrameworkMetallibs; do
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

# Strip AppleDouble / xattrs so the DMG does not ship ._ sidecar files.
find "$APP" -name '._*' -delete
xattr -cr "$APP"

# Sign the assembled app before wrapping it in the DMG.
"$ROOT/scripts/sign_built_app.sh" "$APP"

mkdir -p "$ROOT/dist"
DMG_ROOT="$STAGE/dmg-root"
mkdir -p "$DMG_ROOT/.background"
cp -R "$APP" "$DMG_ROOT/"
cp "$DMG_BACKGROUND" "$DMG_ROOT/.background/background.png"
cp "$DMG_DS_STORE" "$DMG_ROOT/.DS_Store"
cp "$DMG_APPLICATIONS_ALIAS" "$DMG_ROOT/Applications"
APPLICATIONS_ICON_COPY="$STAGE/ApplicationsFolderIcon.icns"
APPLICATIONS_ICON_RSRC="$STAGE/ApplicationsFolderIcon.rsrc"
cp "$DMG_APPLICATIONS_ICON" "$APPLICATIONS_ICON_COPY"
sips -i "$APPLICATIONS_ICON_COPY" >/dev/null
DeRez -only icns "$APPLICATIONS_ICON_COPY" >"$APPLICATIONS_ICON_RSRC"
Rez -append "$APPLICATIONS_ICON_RSRC" -o "$DMG_ROOT/Applications"
SetFile -a C "$DMG_ROOT/Applications"
find "$DMG_ROOT" -name '._*' -delete
xattr -cr "$DMG_ROOT/lofii.app"
chflags hidden "$DMG_ROOT/.background"

VOLNAME="lofii"
DMG="$ROOT/dist/lofii-${VERSION}-macos.dmg"
rm -f "$DMG"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG" >/dev/null

echo "Built $DMG"
