#!/usr/bin/env bash
#
# build-dmg.sh — Build SnapFloat.app (Release) and package it into a DMG.
#
# Usage:
#   ./scripts/build-dmg.sh            # uses version from Info.plist
#   ./scripts/build-dmg.sh 1.2.0      # override version string
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

SCHEME="SnapFloat"
APP_NAME="SnapFloat"
BUILD_DIR="$REPO_ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

# Version may be provided as argument; otherwise read from built app later
ARG_VERSION="${1:-}"

echo "==> Building $APP_NAME (Release)…"

# Clean previous build artifacts
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build (not archive — more reliable for asset catalogs on CI)
xcodebuild build \
    -project "$REPO_ROOT/$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_ALLOWED=YES \
    MARKETING_VERSION="${ARG_VERSION:-1.0}" \
    | tail -3

# Copy the built .app out of DerivedData
BUILT_APP=$(find "$DERIVED" -name "$APP_NAME.app" -type d | head -1)
if [[ -z "$BUILT_APP" ]]; then
    echo "ERROR: $APP_NAME.app not found in DerivedData" >&2
    exit 1
fi
cp -R "$BUILT_APP" "$APP_PATH"

# Resolve version: argument > built app's Info.plist
if [[ -n "$ARG_VERSION" ]]; then
    VERSION="$ARG_VERSION"
else
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
        "$APP_PATH/Contents/Info.plist")
fi

DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

echo "==> App built at $APP_PATH (version $VERSION)"

# ── Create DMG ──

DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

echo "==> Creating DMG…"

# Create a temporary read/write DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDRW \
    "$BUILD_DIR/tmp-rw.dmg" \
    > /dev/null

# Mount it to apply visual settings
MOUNT_POINT=$(hdiutil attach -readwrite -noverify "$BUILD_DIR/tmp-rw.dmg" \
    | grep "/Volumes/" | tail -1 | awk -F'\t' '{print $NF}')

# Apply Finder view settings via AppleScript
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        delay 0.5
        set the bounds of container window to {100, 100, 640, 400}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 80
        set position of item "$APP_NAME.app" of container window to {150, 150}
        set position of item "Applications" of container window to {390, 150}
        close
    end tell
end tell
APPLESCRIPT

# Finalise: detach and convert to compressed read-only DMG
hdiutil detach "$MOUNT_POINT" -quiet || true
sleep 1

hdiutil convert \
    "$BUILD_DIR/tmp-rw.dmg" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH" \
    > /dev/null

rm -f "$BUILD_DIR/tmp-rw.dmg"
rm -rf "$DMG_STAGING"

echo ""
echo "==> DMG ready: $DMG_PATH"
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"
