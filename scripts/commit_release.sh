#!/usr/bin/env bash
# Commit VERSION bump after release (chore message skips re-running release workflow).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(tr -d '[:space:]' <VERSION)"

git config user.name github-actions
git config user.email github-actions@github.com
git add VERSION Sources/Lofii/Info.plist appcast.xml
git commit -m "chore: auto release $VERSION"
git push
