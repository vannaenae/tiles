#!/bin/bash
# Installs (or updates) Tiles from the latest GitHub release.
#   curl -fsSL https://github.com/vannaenae/tiles/releases/latest/download/install.sh | bash
# Remove it again:
#   curl -fsSL https://github.com/vannaenae/tiles/releases/latest/download/install.sh | bash -s uninstall
set -euo pipefail

REPO="vannaenae/tiles"
DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"

quit_tiles() {
  osascript -e 'quit app "Tiles"' >/dev/null 2>&1 || true
  sleep 1
  pkill -x Tiles >/dev/null 2>&1 || true
}

if [ "${1:-}" = "uninstall" ]; then
  quit_tiles
  rm -rf "/Applications/Tiles.app" "$HOME/Applications/Tiles.app"
  for dir in /opt/homebrew/bin /usr/local/bin; do
    [ -L "$dir/tiles" ] && rm -f "$dir/tiles"
  done
  echo "Tiles removed. Your settings are still in ~/.config/tiles; delete that folder to remove them too."
  exit 0
fi

[ "$(uname)" = "Darwin" ] || { echo "Tiles is a Mac app. Run this on macOS." >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading the latest Tiles"
curl -fL --progress-bar "https://github.com/$REPO/releases/latest/download/Tiles.zip" -o "$TMP/Tiles.zip"
ditto -x -k "$TMP/Tiles.zip" "$TMP"

echo "==> Installing to $DEST"
quit_tiles
mkdir -p "$DEST"
rm -rf "$DEST/Tiles.app"
mv "$TMP/Tiles.app" "$DEST/Tiles.app"
# curl downloads aren't quarantined, but clear it in case, so no "unidentified developer" prompt.
xattr -dr com.apple.quarantine "$DEST/Tiles.app" 2>/dev/null || true

# The `tiles` command (tiles focus-left, tiles layout-columns, ...), if a bin folder is writable.
for dir in /opt/homebrew/bin /usr/local/bin; do
  if [ -d "$dir" ] && [ -w "$dir" ]; then
    ln -sf "$DEST/Tiles.app/Contents/Resources/tiles" "$dir/tiles"
    echo "==> Added the 'tiles' command to $dir"
    break
  fi
done

echo "==> Opening Tiles"
open "$DEST/Tiles.app"
echo "Done. Allow Tiles under System Settings → Privacy & Security → Accessibility when asked."
