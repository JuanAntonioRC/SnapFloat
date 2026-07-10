#!/usr/bin/env bash
#
# linux-env.sh — source this before building/running SnapFloat on machines
# without sudo access, e.g.:
#
#   source scripts/linux-env.sh
#   swift build -c release
#
# It wires up:
#   - the Swift toolchain installed under ~/.local/swift (see setup-linux-deps.sh)
#   - the vendored "sysroot" of GTK4/GLib -dev headers + pkgconf under
#     ~/.cache/snapfloat-sysroot, built without root by downloading .debs with
#     `apt-get download` and extracting them with `dpkg -x` (no `apt install`).
#
# If you *do* have sudo and ran `apt-get install libgtk-4-dev ...` normally,
# you don't need this file — system pkg-config will already find everything.

SNAPFLOAT_SWIFT_HOME="${SNAPFLOAT_SWIFT_HOME:-$HOME/.local/swift}"
SNAPFLOAT_SYSROOT="${SNAPFLOAT_SYSROOT:-$HOME/.cache/snapfloat-sysroot}"

if [ -d "$SNAPFLOAT_SWIFT_HOME/usr/bin" ]; then
    export PATH="$SNAPFLOAT_SWIFT_HOME/usr/bin:$PATH"
fi

# The toolchain is built against Ubuntu 24.04's libxml2 (soname 2), which
# newer Ubuntu releases (26.04+) no longer ship (bumped to soname 16+).
# extra-libs/ holds a vendored libxml2.so.2 fetched straight from the
# Ubuntu 24.04 archive pool for swift-build's own tooling to link against.
if [ -d "$SNAPFLOAT_SWIFT_HOME/extra-libs" ]; then
    export LD_LIBRARY_PATH="$SNAPFLOAT_SWIFT_HOME/extra-libs:${LD_LIBRARY_PATH:-}"
fi

if [ -d "$SNAPFLOAT_SYSROOT" ]; then
    export PATH="$SNAPFLOAT_SYSROOT/usr/bin:$PATH"
    export PKG_CONFIG_SYSROOT_DIR="$SNAPFLOAT_SYSROOT"
    export PKG_CONFIG_PATH="$SNAPFLOAT_SYSROOT/usr/lib/x86_64-linux-gnu/pkgconfig:$SNAPFLOAT_SYSROOT/usr/lib/pkgconfig:$SNAPFLOAT_SYSROOT/usr/share/pkgconfig"
    PKGCONF_LIBDIR="$(dirname "$(find "$SNAPFLOAT_SYSROOT" -name 'libpkgconf.so*' 2>/dev/null | head -1)")"
    if [ -n "$PKGCONF_LIBDIR" ] && [ -d "$PKGCONF_LIBDIR" ]; then
        export LD_LIBRARY_PATH="$PKGCONF_LIBDIR:${LD_LIBRARY_PATH:-}"
    fi
    # This OS release has no gcc/libgcc-dev installed at all (only the
    # runtime .so), so clang can't find crtbeginS.o / libgcc.a / libgcc_s.so
    # for the final link step. Vendored via libgcc-<N>-dev into the sysroot;
    # LIBRARY_PATH is honored by clang the same way -L is.
    # (depth 3: gcc/<triple>/<version>/crtbeginS.o)
    GCC_LIBDIR="$(find "$SNAPFLOAT_SYSROOT/usr/lib/gcc" -maxdepth 3 -name crtbeginS.o 2>/dev/null | head -1 | xargs -r dirname)"
    if [ -n "$GCC_LIBDIR" ]; then
        export LIBRARY_PATH="$GCC_LIBDIR:${LIBRARY_PATH:-}"
    fi
fi

echo "SnapFloat Linux build environment ready:"
echo "  swift:      $(command -v swift || echo 'NOT FOUND')"
echo "  pkg-config: $(command -v pkg-config || echo 'NOT FOUND')"
