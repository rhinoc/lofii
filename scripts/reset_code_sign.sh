#!/usr/bin/env bash
# Tear down CI signing keychain (liltr reset_secret.sh keychain portion).
set -euo pipefail
KEYCHAIN_PATH="${RUNNER_TEMP:-/tmp}/app-signing.keychain-db"
security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
