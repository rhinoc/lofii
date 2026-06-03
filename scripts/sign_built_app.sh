#!/usr/bin/env bash
# Sign assembled lofii.app (liltr relies on xcodebuild; SPM bundle is signed here).
set -euo pipefail
APP="${1:?usage: sign_built_app.sh /path/to/lofii.app}"

IDENTITY="$(
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}'
)"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | awk -F'"' '/Apple Development/ {print $2; exit}'
  )"
fi

sign_parts() {
  local id="$1"
  shift
  if [[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]]; then
    codesign --force --deep "$@" --sign "$id" "$APP/Contents/Frameworks/Sparkle.framework"
  fi
  codesign --force "$@" --sign "$id" "$APP/Contents/Frameworks/libLive2DCubismCore.dylib"
  if [[ -f "$APP/Contents/MacOS/lofii-agent-hook" ]]; then
    codesign --force "$@" --sign "$id" "$APP/Contents/MacOS/lofii-agent-hook"
  fi
  codesign --force "$@" --sign "$id" "$APP/Contents/MacOS/lofii"
  codesign --force "$@" --sign "$id" "$APP"
}

if [[ -z "$IDENTITY" ]]; then
  echo "error: no Apple Development or Developer ID signing identity found." >&2
  echo "Refusing to publish an ad-hoc signed Sparkle/GitHub release." >&2
  exit 1
fi

echo "Signing with: $IDENTITY"
if [[ "$IDENTITY" == Developer\ ID* ]]; then
  sign_parts "$IDENTITY" --options runtime --timestamp
else
  sign_parts "$IDENTITY"
fi

codesign --verify --verbose=2 "$APP"
