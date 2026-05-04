#!/usr/bin/env bash
# Install Live2D Cubism Core from an official Cubism SDK for Native archive.
#
# Cubism Core is not stored in this repository. Download the official SDK after
# accepting Live2D's terms, then either pass the archive path as the first
# argument or let the script download the default official SDK URL below.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/CubismNativeSDK/Core"
HEADER="$DEST/include/Live2DCubismCore.h"
DYLIB="$DEST/dll/macos/libLive2DCubismCore.dylib"
DEFAULT_CUBISM_NATIVE_SDK_URL="https://cubism.live2d.com/sdk-native/bin/CubismSdkForNative-5-r.5.zip?event=cubism_sdk_download&sdk_type=Native&user_status=update&user_type=&version=5-r.5&lang=en"

if [[ "${1:-}" == "--check" ]]; then
  if [[ -f "$HEADER" && -f "$DYLIB" ]]; then
    exit 0
  fi
  cat >&2 <<EOF
Live2D Cubism Core is missing.

Expected:
  $HEADER
  $DYLIB

Install it with:
  scripts/install_cubism_core.sh /path/to/CubismSdkForNative-*.zip

Without a local archive path, the script downloads the default official SDK
archive URL. Set CUBISM_NATIVE_SDK_URL only if you need to override it.
EOF
  exit 1
fi

if [[ -f "$HEADER" && -f "$DYLIB" && "${FORCE_CUBISM_CORE_INSTALL:-0}" != "1" ]]; then
  echo "Live2D Cubism Core already installed at $DEST"
  exit 0
fi

archive="${1:-}"
tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

if [[ -n "$archive" ]]; then
  if [[ ! -f "$archive" ]]; then
    echo "error: archive not found: $archive" >&2
    exit 1
  fi
else
  CUBISM_NATIVE_SDK_URL="${CUBISM_NATIVE_SDK_URL:-$DEFAULT_CUBISM_NATIVE_SDK_URL}"
  archive="$tmpdir/cubism-native-sdk"
  echo "Downloading Live2D Cubism SDK for Native..."
  curl -fsSL "$CUBISM_NATIVE_SDK_URL" -o "$archive"
fi

if [[ -n "${CUBISM_NATIVE_SDK_SHA256:-}" ]]; then
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  if [[ "$actual" != "$CUBISM_NATIVE_SDK_SHA256" ]]; then
    echo "error: SHA-256 mismatch for Cubism SDK archive" >&2
    echo "expected: $CUBISM_NATIVE_SDK_SHA256" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
fi

extract="$tmpdir/extract"
mkdir -p "$extract"
case "$archive" in
  *.zip)
    ditto -x -k "$archive" "$extract"
    ;;
  *.tar.gz|*.tgz)
    tar -xzf "$archive" -C "$extract"
    ;;
  *.tar.xz|*.txz)
    tar -xJf "$archive" -C "$extract"
    ;;
  *)
    if unzip -tq "$archive" >/dev/null 2>&1; then
      ditto -x -k "$archive" "$extract"
    else
      echo "error: unsupported archive format: $archive" >&2
      exit 1
    fi
    ;;
esac

header_src="$(find "$extract" -path '*/Core/include/Live2DCubismCore.h' -type f | head -n1)"
dylib_src="$(find "$extract" -path '*/Core/dll/macos/libLive2DCubismCore.dylib' -type f | head -n1)"

if [[ -z "$header_src" || -z "$dylib_src" ]]; then
  echo "error: could not find required Cubism Core files in archive" >&2
  echo "required: Core/include/Live2DCubismCore.h" >&2
  echo "required: Core/dll/macos/libLive2DCubismCore.dylib" >&2
  exit 1
fi

mkdir -p "$DEST/include" "$DEST/dll/macos"
cp "$header_src" "$HEADER"
cp "$dylib_src" "$DYLIB"

echo "Installed Live2D Cubism Core:"
echo "  $HEADER"
echo "  $DYLIB"
