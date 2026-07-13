#!/usr/bin/env bash
#
# install-linux.sh — User-level install (no sudo/root): copies the built
# binary, desktop entry, and icon into the standard XDG user directories.
#
# Usage:
#   ./scripts/build-linux.sh   # build first
#   ./scripts/install-linux.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BIN_PATH="$REPO_ROOT/.build/release/snapfloat-linux"
if [ ! -x "$BIN_PATH" ]; then
    echo "ERROR: $BIN_PATH not found — run ./scripts/build-linux.sh first." >&2
    exit 1
fi

BIN_DIR="$HOME/.local/bin"
APPS_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"

mkdir -p "$BIN_DIR" "$APPS_DIR" "$ICON_DIR"

cp "$BIN_PATH" "$BIN_DIR/snapfloat-linux"
cp "$REPO_ROOT/data/com.snapfloat.SnapFloat.desktop" "$APPS_DIR/"
cp "$REPO_ROOT/data/icons/hicolor/scalable/apps/com.snapfloat.SnapFloat.svg" "$ICON_DIR/"

# Point the installed .desktop entry at the installed binary's absolute path,
# keeping the env wrapper (allocator tuning + GSK_RENDERER, see the .desktop
# file's own comment) that ships in the Exec= line.
sed -i "s|^Exec=.*|Exec=env MALLOC_ARENA_MAX=2 MALLOC_MMAP_THRESHOLD_=131072 GSK_RENDERER=cairo $BIN_DIR/snapfloat-linux|" "$APPS_DIR/com.snapfloat.SnapFloat.desktop"

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "NOTE: $BIN_DIR is not on your PATH — add it in ~/.bashrc/~/.zshrc, or launch SnapFloat from your app menu." ;;
esac

echo "==> Installed. Launch from your application menu (\"SnapFloat\") or run: $BIN_DIR/snapfloat-linux"
