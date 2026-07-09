#!/usr/bin/env bash
#
# build-linux.sh — Build SnapFloat for Linux in release mode.
#
# Usage:
#   ./scripts/build-linux.sh
#
# If you went through the no-sudo path in setup-linux-deps.sh, this sources
# scripts/linux-env.sh automatically so pkg-config/Swift are found.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [ -f scripts/linux-env.sh ]; then
    # shellcheck disable=SC1091
    source scripts/linux-env.sh
fi

echo "==> Building SnapFloat (release)…"
swift build -c release

BIN_PATH="$REPO_ROOT/.build/release/snapfloat-linux"
echo ""
echo "==> Built: $BIN_PATH"
echo "    Run directly, or install with: ./scripts/install-linux.sh"
