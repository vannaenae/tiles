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
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

echo "==> Signing ($IDENTITY)"
if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --verbose "$APP"

ditto -c -k --keepParent "$APP" "dist/Tiles-$VERSION.zip"
echo "==> dist/Tiles.app and dist/Tiles-$VERSION.zip ready"
