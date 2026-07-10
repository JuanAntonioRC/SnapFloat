#!/usr/bin/env bash
#
# build-deb.sh — Package SnapFloat as a Debian/Ubuntu .deb, the Linux
# counterpart of build-dmg.sh.
#
# Usage:
#   ./scripts/build-deb.sh              # -> dist/snapfloat_<version>_amd64.deb
#   VERSION=1.1 ./scripts/build-deb.sh  # override the package version
#
# The Swift runtime is linked statically (--static-swift-stdlib), so the
# package depends only on stock system libraries (GTK4, X11, glibc) and
# installs cleanly on machines without any Swift toolchain.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${VERSION:-1.0}"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"

if [ -f scripts/linux-env.sh ]; then
    # shellcheck disable=SC1091
    source scripts/linux-env.sh
fi

# The static Swift stdlib links against -lstdc++, which needs the dev
# symlink (libstdc++.so). Systems with g++/build-essential have it; the
# no-sudo vendored sysroot doesn't, so point one at the runtime .so there.
if ! echo 'int main(){}' | clang -x c - -lstdc++ -o /dev/null 2>/dev/null; then
    SNAPFLOAT_SYSROOT="${SNAPFLOAT_SYSROOT:-$HOME/.cache/snapfloat-sysroot}"
    GCC_LIBDIR="$(find "$SNAPFLOAT_SYSROOT/usr/lib/gcc" -maxdepth 3 -name crtbeginS.o 2>/dev/null | head -1 | xargs -r dirname)"
    if [ -n "$GCC_LIBDIR" ] && [ ! -e "$GCC_LIBDIR/libstdc++.so" ]; then
        ln -s /usr/lib/x86_64-linux-gnu/libstdc++.so.6 "$GCC_LIBDIR/libstdc++.so"
        echo "==> Added libstdc++.so dev symlink to the vendored sysroot"
    fi
fi

echo "==> Building SnapFloat (release, static Swift runtime)…"
swift build -c release --static-swift-stdlib

BIN_PATH="$REPO_ROOT/.build/release/snapfloat-linux"
if ldd "$BIN_PATH" | grep -q "swift/linux"; then
    echo "ERROR: binary still links the vendored Swift runtime — static link failed." >&2
    exit 1
fi

PKG_NAME="snapfloat"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
PKG_DIR="$STAGE/${PKG_NAME}_${VERSION}_${ARCH}"

mkdir -p \
    "$PKG_DIR/DEBIAN" \
    "$PKG_DIR/usr/bin" \
    "$PKG_DIR/usr/share/applications" \
    "$PKG_DIR/usr/share/icons/hicolor/scalable/apps" \
    "$PKG_DIR/usr/share/doc/$PKG_NAME"

install -m 755 "$BIN_PATH" "$PKG_DIR/usr/bin/snapfloat-linux"
# Exec=snapfloat-linux resolves via PATH once installed under /usr/bin.
install -m 644 data/com.snapfloat.SnapFloat.desktop "$PKG_DIR/usr/share/applications/"
install -m 644 data/icons/hicolor/scalable/apps/com.snapfloat.SnapFloat.svg \
    "$PKG_DIR/usr/share/icons/hicolor/scalable/apps/"
install -m 644 LICENSE "$PKG_DIR/usr/share/doc/$PKG_NAME/copyright"

INSTALLED_SIZE="$(du -sk "$PKG_DIR/usr" | cut -f1)"

cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: $VERSION
Section: graphics
Priority: optional
Architecture: $ARCH
Installed-Size: $INSTALLED_SIZE
Maintainer: Juan Antonio Redondo <redondo.juanantonio1997@gmail.com>
Depends: libgtk-4-1, libglib2.0-0, libgdk-pixbuf-2.0-0, libcairo2, libx11-6, libstdc++6, libc6
Recommends: xdg-desktop-portal-gnome | xdg-desktop-portal-backend, librsvg2-common
Homepage: https://github.com/JuanAntonioRC/SnapFloat
Description: Region screenshot tool with a floating preview
 SnapFloat captures a screen region and shows a small floating
 thumbnail in the corner: click it to annotate, or use the strip to
 copy or save. GTK4 port of the macOS menu-bar app; screen capture
 and global shortcut go through the XDG desktop portals.
EOF

mkdir -p "$REPO_ROOT/dist"
DEB_PATH="$REPO_ROOT/dist/${PKG_NAME}_${VERSION}_${ARCH}.deb"
dpkg-deb --build --root-owner-group "$PKG_DIR" "$DEB_PATH" >/dev/null

echo ""
echo "==> Built: $DEB_PATH"
echo "    Install with: sudo apt install $DEB_PATH"
