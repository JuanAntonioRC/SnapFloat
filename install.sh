#!/bin/sh
#
# install.sh — one-line SnapFloat install for Ubuntu/GNOME:
#
#   curl -fsSL https://raw.githubusercontent.com/JuanAntonioRC/SnapFloat/main/install.sh | sh
#
# Downloads the newest Linux release's .snap, installs it, turns on
# "Launch at login" and starts the app. Re-run it to update.
#
# Not on the Snap Store yet, so the snap installs with --dangerous (i.e.
# unsigned by the store) and won't auto-update.
#
# SNAPFLOAT_SNAP=/path/to/file.snap installs a local file instead of
# downloading one (for testing a build before releasing it).
#
set -eu

REPO="JuanAntonioRC/SnapFloat"

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31mError: %s\033[0m\n' "$*" >&2; exit 1; }

command -v snap >/dev/null 2>&1 \
    || die "snapd isn't installed. Run: sudo apt install snapd — then run this again."
[ "$(uname -m)" = "x86_64" ] || die "SnapFloat is only built for x86_64 (this is $(uname -m))."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -n "${SNAPFLOAT_SNAP:-}" ]; then
    SNAP_FILE="$SNAPFLOAT_SNAP"
else
    say "Finding the latest SnapFloat for Linux…"
    # /releases/latest can point at a macOS-only release, so take the
    # newest release that actually has a .snap attached (the API lists
    # newest first).
    URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases" \
        | grep -o '"browser_download_url": *"[^"]*\.snap"' \
        | head -n 1 | sed 's/.*"\(https[^"]*\)"/\1/')" || true
    [ -n "$URL" ] || die "couldn't find a .snap in https://github.com/$REPO/releases"
    say "Downloading $(basename "$URL")…"
    SNAP_FILE="$TMP/snapfloat.snap"
    curl -fL --progress-bar -o "$SNAP_FILE" "$URL"
fi

# snapd refuses to replace a snap whose app is still running.
if pgrep -x snapfloat-linux >/dev/null 2>&1; then
    say "Closing the running SnapFloat…"
    pkill -x snapfloat-linux || true
    sleep 1
fi

say "Installing (asks for your password)…"
sudo snap install --dangerous "$SNAP_FILE"

# Auto-connects on a normal install, but a --dangerous one isn't covered
# by the store's auto-connect rules on every snapd version — the tray
# icon needs it.
sudo snap connect snapfloat:unity7 2>/dev/null || true

# Launch at login, same file the in-app Settings checkbox writes
# (LinuxAutostart.swift) — under confinement that's the snap's own
# ~/snap/snapfloat/<rev>/.config, which snapd's autostart helper reads.
# Only on first install: an update keeps whatever the user chose.
REV="$(snap list snapfloat | awk 'NR==2 {print $3}')"
AUTOSTART_DIR="$HOME/snap/snapfloat/$REV/.config/autostart"
if [ ! -e "$HOME/snap/snapfloat/$REV/.config" ]; then
    mkdir -p "$AUTOSTART_DIR"
    cat > "$AUTOSTART_DIR/com.snapfloat.SnapFloat.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=SnapFloat
Exec=/snap/bin/snapfloat
Icon=com.snapfloat.SnapFloat
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
fi

say "Starting SnapFloat…"
nohup /snap/bin/snapfloat >/dev/null 2>&1 &

cat <<'EOF'

SnapFloat is installed and running — look for its icon in the top bar.
  • Capture:   Ctrl+Shift+2 (change it in Settings, from the tray icon)
  • It starts automatically when you log in (toggle in Settings)
  • Update:    run the same install command again
  • Uninstall: sudo snap remove snapfloat
EOF
