#!/usr/bin/env bash
# Release build: lofii.app DMG for Sparkle + GitHub Releases (Live2D dylib in Frameworks).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(tr -d '[:space:]' <VERSION)"

scripts/install_cubism_core.sh --check
swift build -c release --product lofii
swift build -c release --product lofii-agent-hook
BIN="$(swift build -c release --show-bin-path)/lofii"
AGENT_HOOK_BIN="$(swift build -c release --show-bin-path)/lofii-agent-hook"
SPARKLE_FW="$(dirname "$BIN")/Sparkle.framework"
DYLIB_SRC="$ROOT/Vendor/CubismNativeSDK/Core/dll/macos/libLive2DCubismCore.dylib"
PLIST_SRC="$ROOT/Sources/Lofii/Info.plist"
ICON_SRC="$ROOT/Sources/Lofii/Resources/AppIcon.icns"
LOFII_RES="$ROOT/Sources/Lofii/Resources"
METAL_SRC="$ROOT/Sources/Lofii/StageMetalShaders.metal"
DMG_BACKGROUND="$ROOT/assets/dmg-background.png"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

APP="$STAGE/lofii.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$PLIST_SRC" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/lofii"
cp "$AGENT_HOOK_BIN" "$APP/Contents/MacOS/lofii-agent-hook"
cp "$DYLIB_SRC" "$APP/Contents/Frameworks/libLive2DCubismCore.dylib"
if [[ ! -d "$SPARKLE_FW" ]]; then
  echo "error: Sparkle.framework not found next to release binary (expected: $SPARKLE_FW)" >&2
  exit 1
fi
if [[ ! -f "$DMG_BACKGROUND" ]]; then
  echo "error: missing DMG background at $DMG_BACKGROUND" >&2
  exit 1
fi
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"
# Ship the same resource layout as SwiftPM's `lofii_lofii.bundle`, but under `Contents/Resources/`
# so `LofiiResources.bundle` resolves to `Bundle.main` and codesign does not require an extra bundle at .app root.
for name in Statics Fonts BongoCat AgentCompanion ShatteredGlass FrameworkMetallibs; do
  if [[ ! -d "$LOFII_RES/$name" ]]; then
    echo "error: missing $LOFII_RES/$name" >&2
    exit 1
  fi
  cp -R "$LOFII_RES/$name" "$APP/Contents/Resources/"
done
cp "$METAL_SRC" "$APP/Contents/Resources/"
cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.icns"
cp "$LOFII_RES/MenuBarIcon.svg" "$APP/Contents/Resources/MenuBarIcon.svg"
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
DMG="$ROOT/dist/lofii-${VERSION}-macos.dmg"
rm -f "$DMG"

DMG_BACKGROUND_COPY="$STAGE/dmg-background.png"
DMG_BACKGROUND_RETINA_COPY="$STAGE/dmg-background@2x.png"
sips -z 373 661 "$DMG_BACKGROUND" --out "$DMG_BACKGROUND_COPY" >/dev/null
sips -z 746 1322 "$DMG_BACKGROUND" --out "$DMG_BACKGROUND_RETINA_COPY" >/dev/null
sips -s dpiWidth 72 -s dpiHeight 72 "$DMG_BACKGROUND_COPY" >/dev/null
sips -s dpiWidth 144 -s dpiHeight 144 "$DMG_BACKGROUND_RETINA_COPY" >/dev/null

APPDMG_JSON="$STAGE/appdmg.json"
cat >"$APPDMG_JSON" <<EOF
{
  "title": "lofii",
  "icon": "$ICON_SRC",
  "background": "$DMG_BACKGROUND_COPY",
  "icon-size": 80,
  "window": {
    "position": { "x": 120, "y": 559 },
    "size": { "width": 661, "height": 379 }
  },
  "format": "UDZO",
  "filesystem": "HFS+",
  "contents": [
    { "x": 180, "y": 197, "type": "file", "path": "$APP" },
    { "x": 480, "y": 197, "type": "link", "path": "/Applications" }
  ]
}
EOF

npx --yes "appdmg@${APPDMG_VERSION:-0.6.6}" "$APPDMG_JSON" "$DMG"

echo "Built $DMG"
