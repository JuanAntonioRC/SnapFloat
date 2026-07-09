#!/usr/bin/env bash
#
# setup-linux-deps.sh — Install everything needed to build SnapFloat on
# Ubuntu/Debian: build tooling, GTK4 dev headers, and the Swift toolchain.
#
# Two paths, chosen automatically:
#   - Has sudo:    plain `apt-get install` + swiftly (fast, system-wide).
#   - No sudo:     downloads the needed -dev .debs with `apt-get download`
#                  (no root required) and extracts them with `dpkg -x` into
#                  a local sysroot at ~/.cache/snapfloat-sysroot, and installs
#                  the Swift toolchain tarball directly into ~/.local/swift.
#                  Nothing outside $HOME is touched.
#
# After running this, `source scripts/linux-env.sh` before building if you
# went through the no-sudo path.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PACKAGES=(build-essential pkg-config libgtk-4-dev libglib2.0-dev)

HAS_SUDO=0
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    HAS_SUDO=1
elif command -v sudo >/dev/null 2>&1 && sudo -n -l >/dev/null 2>&1; then
    HAS_SUDO=1
fi

install_with_apt() {
    echo "==> sudo available — installing system packages…"
    sudo apt-get update
    sudo apt-get install -y "${PACKAGES[@]}"
}

install_swift_via_swiftly() {
    if command -v swift >/dev/null 2>&1; then
        echo "==> Swift already installed: $(swift --version | head -1)"
        return
    fi
    echo "==> Installing Swift toolchain via swiftly…"
    curl -L https://swiftlang.github.io/swiftly/swiftly-install.sh -o /tmp/swiftly-install.sh
    bash /tmp/swiftly-install.sh -y
    # shellcheck disable=SC1090
    source "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" 2>/dev/null || true
    swiftly install latest
    swiftly use latest
}

# ── No-sudo fallback ─────────────────────────────────────────────────────

install_swift_tarball_nosudo() {
    if [ -x "$HOME/.local/swift/usr/bin/swift" ]; then
        echo "==> Swift already installed at ~/.local/swift"
    else
        echo "==> No sudo — installing Swift toolchain tarball into ~/.local/swift…"
        local RELEASES_JSON LATEST_VER URL
        RELEASES_JSON="$(curl -s https://www.swift.org/api/v1/install/releases.json)"
        LATEST_VER="$(python3 -c "
import json
d = json.loads('''$RELEASES_JSON''')
for r in reversed(d):
    if any(p['name'] == 'Ubuntu 24.04' for p in r['platforms']):
        print(r['name']); break
")"
        URL="https://download.swift.org/swift-${LATEST_VER}-release/ubuntu2404/swift-${LATEST_VER}-RELEASE/swift-${LATEST_VER}-RELEASE-ubuntu24.04.tar.gz"
        echo "    Fetching Swift ${LATEST_VER} (Ubuntu 24.04 toolchain, ~1GB; runs fine on newer Ubuntu via glibc compat)…"
        mkdir -p "$HOME/.local/swift"
        curl -L -o /tmp/swift-toolchain.tar.gz "$URL"
        tar -xzf /tmp/swift-toolchain.tar.gz -C "$HOME/.local/swift" --strip-components=1
        rm -f /tmp/swift-toolchain.tar.gz
    fi

    # The two fixups below are idempotent (each checks for its own marker
    # file first), so they run every time in case a previous run of this
    # script installed Swift but didn't get this far.

    # This toolchain is built against Ubuntu 24.04's libxml2 (soname 2).
    # Very new Ubuntu releases ship a newer libxml2 with a bumped soname, so
    # swift-build fails to start. Vendor the matching old libxml2.so.2
    # straight from the 24.04 archive pool — used only by the toolchain's
    # own tooling, doesn't touch the system.
    if ! ldconfig -p 2>/dev/null | grep -q 'libxml2\.so\.2\b'; then
        echo "    Fetching libxml2.so.2 for the toolchain (not shipped by this OS release)…"
        mkdir -p "$HOME/.local/swift/extra-libs" /tmp/libxml2-extract
        curl -sL -o /tmp/libxml2_noble.deb \
            "http://archive.ubuntu.com/ubuntu/pool/main/libx/libxml2/libxml2_2.12.7+dfsg+really2.9.14-0.4ubuntu0.4_amd64.deb"
        dpkg -x /tmp/libxml2_noble.deb /tmp/libxml2-extract
        cp -a /tmp/libxml2-extract/usr/lib/x86_64-linux-gnu/libxml2.so.2* "$HOME/.local/swift/extra-libs/"
        rm -rf /tmp/libxml2-extract /tmp/libxml2_noble.deb
    fi

    # This OS release has no gcc/libgcc-<N>-dev installed (only the runtime
    # .so), so clang can't find crtbeginS.o / libgcc.a / libgcc_s.so to
    # finish linking anything, including swift build's own Package.swift
    # manifest step. Vendor it *relative to the Swift toolchain's own
    # install prefix* (~/.local/swift/usr/lib/gcc/<triple>/<ver>) — clang
    # auto-detects a GCC installation co-located with itself, no extra
    # flags or env vars needed.
    if [ ! -f "$HOME/.local/swift/usr/lib/gcc/x86_64-linux-gnu"/*/crtbeginS.o ] 2>/dev/null; then
        local gcc_ver
        gcc_ver="$(dpkg-query -W -f='${Package}\n' 'gcc-*-base' 2>/dev/null | grep -oP '(?<=gcc-)\d+(?=-base)' | head -1)"
        if [ -n "$gcc_ver" ] && apt-cache show "libgcc-${gcc_ver}-dev" >/dev/null 2>&1; then
            echo "    Fetching libgcc-${gcc_ver}-dev for crt startup objects (no gcc installed on this OS release)…"
            mkdir -p /tmp/libgcc-extract
            (cd /tmp/libgcc-extract && apt-get download "libgcc-${gcc_ver}-dev")
            dpkg -x /tmp/libgcc-extract/libgcc-"${gcc_ver}"-dev*.deb /tmp/libgcc-extract/root
            mkdir -p "$HOME/.local/swift/usr/lib/gcc/x86_64-linux-gnu"
            cp -a "/tmp/libgcc-extract/root/usr/lib/gcc/x86_64-linux-gnu/${gcc_ver}" \
                  "$HOME/.local/swift/usr/lib/gcc/x86_64-linux-gnu/${gcc_ver}"
            rm -rf /tmp/libgcc-extract
        else
            echo "    WARNING: couldn't detect a matching libgcc-<N>-dev package — linking may fail." >&2
        fi
    fi
}

vendor_gtk_headers_nosudo() {
    local SYSROOT="$HOME/.cache/snapfloat-sysroot"
    local DL="$HOME/.cache/snapfloat-sysroot-debs"
    if [ -x "$SYSROOT/usr/bin/pkg-config" ]; then
        echo "==> Vendored GTK4/pkg-config sysroot already present at $SYSROOT"
        return
    fi
    echo "==> No sudo — vendoring GTK4 dev headers into $SYSROOT (no system changes)…"
    mkdir -p "$SYSROOT" "$DL"

    local closure="$DL/closure.txt" missing="$DL/missing.txt"
    apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts \
        --no-breaks --no-replaces --no-enhances -i \
        libgtk-4-dev libglib2.0-dev pkg-config 2>/dev/null \
        | grep -oP '^\w[\w0-9.+-]*$' | sort -u > "$closure"

    # Only fetch what isn't already installed system-wide, and drop a
    # handful of unrelated packages apt-cache's -i resolution pulls in via
    # unrelated alternative dependencies (virtualization/XFCE helpers).
    : > "$missing"
    while read -r pkg; do
        dpkg -s "$pkg" >/dev/null 2>&1 || echo "$pkg" >> "$missing"
    done < "$closure"
    grep -vE '^(libxfconf-0-3|ubuntu-helper-virt-hwe|qemu-|ubuntu-virt|xfconf|gawk$|original-awk|cdebconf|dbus-broker|dbus-x11|fonts-|cross-exe-wrapper|lsb-base|native-architecture|opensysusers|systemd-standalone-sysusers|python3-packaging|icu-devtools|girepository-tools|gir1\.2-|libtextwrap1|libxfce4util|libdebian-installer4|libdav1d|libheif-plugin|libgles1$|libopengl0$|libpkgconf7$|pkgconf$|pkgconf-bin$)' \
        "$missing" > "$missing.filtered"
    printf '%s\n' pkgconf pkgconf-bin libpkgconf7 >> "$missing.filtered"
    sort -u -o "$missing.filtered" "$missing.filtered"

    echo "    Downloading $(wc -l < "$missing.filtered") packages…"
    (cd "$DL" && xargs -a "$missing.filtered" apt-get download)

    echo "    Extracting into sysroot…"
    for deb in "$DL"/*.deb; do dpkg -x "$deb" "$SYSROOT"; done

    # -dev packages ship unversioned .so symlinks (e.g. libgtk-4.so ->
    # libgtk-4.so.1) that point at the *runtime* .so which lives on the real
    # system, not in our sysroot. Repoint any dangling ones at the real
    # system path so the linker can resolve them.
    while IFS= read -r -d '' link; do
        target="$(readlink "$link")"
        case "$target" in
            /*) abs_target="$target" ;;
            *)  abs_target="$(dirname "$link")/$target" ;;
        esac
        if [ ! -e "$abs_target" ]; then
            real_dir="$(dirname "$link")"; real_dir="${real_dir#$SYSROOT}"
            candidate="$real_dir/$(basename "$target")"
            [ -e "$candidate" ] && ln -sf "$candidate" "$link"
        fi
    done < <(find "$SYSROOT/usr/lib" -xtype l -print0 2>/dev/null)

    mkdir -p "$SYSROOT/usr/bin"
    local pkgconf_bin
    pkgconf_bin="$(find "$SYSROOT" -type f -name pkgconf | head -1)"
    chmod +x "$pkgconf_bin"
    ln -sf "$pkgconf_bin" "$SYSROOT/usr/bin/pkg-config"
    ln -sf "$pkgconf_bin" "$SYSROOT/usr/bin/pkgconf"

    rm -rf "$DL"
    echo "==> Sysroot ready at $SYSROOT"
}

# ── Main ─────────────────────────────────────────────────────────────────

if [ "$HAS_SUDO" -eq 1 ]; then
    install_with_apt
    install_swift_via_swiftly
else
    echo "==> No sudo access detected on this machine — using no-root fallback."
    vendor_gtk_headers_nosudo
    install_swift_tarball_nosudo
    echo ""
    echo "==> Done. Before building, run:"
    echo "    source \"$REPO_ROOT/scripts/linux-env.sh\""
    exit 0
fi

echo ""
echo "==> Done. Verify with:"
echo "    swift --version"
echo "    pkg-config --modversion gtk4"
