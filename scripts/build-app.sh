#!/usr/bin/env bash
# Builds a universal (Apple silicon + Intel) Tiles.app into dist/ and zips it.
#   VERSION=1.2.0 ./scripts/build-app.sh
#   CODESIGN_IDENTITY="Developer ID Application: You (TEAMID)" ./scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
IDENTITY="${CODESIGN_IDENTITY:--}"   # "-" = ad-hoc signature

echo "==> Building Tiles $VERSION ($BUILD)"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

APP="dist/Tiles.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Tiles" "$APP/Contents/MacOS/Tiles"
cp scripts/tiles "$APP/Contents/Resources/tiles"
plutil -lint Resources/Localization/*.lproj/Localizable.strings >/dev/null
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/en.lproj"   # English is the development language
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

echo "==> Icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing ($IDENTITY)"
if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --verbose "$APP"

ZIP="dist/Tiles-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> dist/Tiles.app and dist/Tiles-$VERSION.zip ready"
