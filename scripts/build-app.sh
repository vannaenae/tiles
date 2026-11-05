#!/usr/bin/env bash
# Builds a universal (Apple silicon + Intel) Tiles.app into dist/ and zips it.
#   VERSION=1.2.0 ./scripts/build-app.sh
#   CODESIGN_IDENTITY="Developer ID Application: You (TEAMID)" ./scripts/build-app.sh
# Add NOTARIZE=1 to notarize and staple, with either
#   an App Store Connect API key: APPLE_API_KEY (.p8 contents), APPLE_API_KEY_ID, APPLE_API_ISSUER_ID
#   or an Apple ID: APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD
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

if [ "${NOTARIZE:-0}" = "1" ]; then
  echo "==> Notarizing (takes a few minutes)"
  if [ -n "${APPLE_API_KEY:-}" ]; then
    KEY_FILE="$(mktemp -d)/AuthKey.p8"
    printf '%s\n' "$APPLE_API_KEY" > "$KEY_FILE"
    AUTH=(--key "$KEY_FILE" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID")
  else
    AUTH=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
  fi
  xcrun notarytool submit "$ZIP" "${AUTH[@]}" --wait
  xcrun stapler staple "$APP"
  rm "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"   # re-zip with the ticket stapled
  spctl --assess --type execute --verbose "$APP"
fi
echo "==> dist/Tiles.app and dist/Tiles-$VERSION.zip ready"
