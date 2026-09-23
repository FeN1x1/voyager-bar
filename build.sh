#!/bin/bash
# Builds "Voyager Bar.app" (universal: Apple silicon + Intel) into ./build.
#
#   ./build.sh              build the app
#   ./build.sh --install    build and install into /Applications (INSTALL_DIR to override)
#   ./build.sh --dmg        build and package build/VoyagerBar-<version>.dmg (+ .zip)
#
#   UNIVERSAL=0  arm64 only (faster)      ICON=1  re-render the app icon
set -euo pipefail
cd "$(dirname "$0")"

NAME="Voyager Bar"
EXE="VoyagerBar"
VERSION="$(cat VERSION)"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

# Stage outside the (possibly iCloud-synced) project folder: File Provider
# attributes on the bundle would make codesign refuse to sign it.
STAGE="$(mktemp -d)"
APP="$STAGE/$NAME.app"
trap 'rm -rf "$STAGE"' EXIT
BIN="$APP/Contents/MacOS/$EXE"
FLAGS=(-O -swift-version 5 -framework AppKit -framework SceneKit -framework Metal -framework MetalKit
       -framework SwiftUI -framework Security -framework IOKit -framework ServiceManagement)

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/ephemeris.bin Resources/stars.bin Resources/bodies.bin Resources/star_names.json "$APP/Contents/Resources/"
cp -R Resources/Textures "$APP/Contents/Resources/"

echo "› Compiling $NAME $VERSION (arm64)…"
swiftc "${FLAGS[@]}" -target arm64-apple-macos13.0 Sources/*.swift -o build/obj/$EXE-arm64
if [[ "${UNIVERSAL:-1}" == "1" ]]; then
    echo "› Compiling (x86_64)…"
    swiftc "${FLAGS[@]}" -target x86_64-apple-macos13.0 Sources/*.swift -o build/obj/$EXE-x86_64
    lipo -create build/obj/$EXE-arm64 build/obj/$EXE-x86_64 -output "$BIN"
else
    cp build/obj/$EXE-arm64 "$BIN"
fi

# App icon: rendered from the scene itself.
if [[ ! -f Resources/AppIcon.icns || "${ICON:-0}" == "1" ]]; then
    echo "› Rendering app icon…"
    "$BIN" --icon build/obj/icon-1024.png
    ICONSET=build/obj/AppIcon.iconset
    rm -rf "$ICONSET"; mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s build/obj/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s*2)) $((s*2)) build/obj/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

echo "› Signing (${SIGN_IDENTITY:-ad hoc})…"
xattr -cr "$APP"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --deep --sign - "$APP" >/dev/null
fi
rm -rf "build/$NAME.app"
ditto "$APP" "build/$NAME.app"
echo "✓ Built build/$NAME.app"

case "${1:-}" in
--install)
    DEST="${INSTALL_DIR:-/Applications}"
    pkill -x "$EXE" 2>/dev/null || true
    pkill -x Voyager1 2>/dev/null || true          # pre-1.2 name
    rm -rf "$DEST/$NAME.app" "$DEST/Voyager 1.app"
    ditto "$APP" "$DEST/$NAME.app"
    echo "✓ Installed to $DEST/$NAME.app"
    ;;
--dmg)
    DMG="build/VoyagerBar-$VERSION.dmg"
    ZIP="build/VoyagerBar-$VERSION.zip"
    ROOT="$STAGE/dmg"
    mkdir -p "$ROOT"
    ditto "$APP" "$ROOT/$NAME.app"
    ln -s /Applications "$ROOT/Applications"
    cp packaging/INSTALL.txt "$ROOT/Read Me First.txt"
    rm -f "$DMG"
    hdiutil create -volname "$NAME $VERSION" -srcfolder "$ROOT" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null
    rm -f "$ZIP"
    (cd "$STAGE" && ditto -c -k --keepParent "$NAME.app" "$OLDPWD/$ZIP")
    shasum -a 256 "$DMG" "$ZIP"
    echo "✓ Packaged $DMG and $ZIP"
    ;;
esac
