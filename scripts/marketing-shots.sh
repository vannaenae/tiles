#!/bin/bash
# Captures real screenshots of Tiles for the App Store and the website.
#
#   ./scripts/marketing-shots.sh [output-folder]      (default: marketing-out)
#
# Opens Safari (Tiles on GitHub), Tiles' own source code, Terminal (`tiles --help`) and a
# TextEdit note, lets Tiles arrange them, then saves one PNG per scene with screencapture.
# It takes over the screen for about 3 minutes; don't touch the mouse or keyboard meanwhile.
#
# Needs: macOS, /Applications/Tiles.app running with Accessibility access, and
# screen-recording permission for your terminal. Your Tiles config is backed up and put back.
#
# On a CI machine set MARKETING_CI=1: it also hides the Dock and desktop icons and, if
# displayplacer is installed, switches the display to its sharpest mode (Retina if offered).
set -u

OUT="${1:-marketing-out}"
mkdir -p "$OUT"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TILES="$ROOT/scripts/tiles"
CONFIG="$HOME/.config/tiles/config.json"
WORK="$(mktemp -d)"

shot() { # name [seconds to wait first]
  sleep "${2:-2}"
  if screencapture -x "$OUT/$1.png"; then echo "captured $1"; else echo "screencapture failed for $1"; fi
}

# --- CI only: a clean, sharp screen -------------------------------------------------------
if [ "${MARKETING_CI:-0}" = "1" ]; then
  defaults write com.apple.dock autohide -bool true && killall Dock || true
  defaults write com.apple.finder CreateDesktop -bool false && killall Finder || true
  if command -v displayplacer >/dev/null; then
    displayplacer list > "$OUT/displays-before.txt" 2>&1 || true
    # Prefer a HiDPI (Retina) mode at least 1280 points wide, then the most pixels, then 16:10.
    # (Written to a file first: macOS's bash 3.2 can mis-parse a heredoc inside $(...).)
    cat > "$WORK/pick-mode.py" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
sid = re.search(r'Persistent screen id: (\S+)', t)
if not sid:
    sys.exit()
best = None
for m in re.finditer(r'mode (\d+): res:(\d+)x(\d+)[^\n]*', t):
    n, w, h, line = int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(0)
    hidpi = 'scaling:on' in line
    score = (hidpi and w >= 1280, w * h * (4 if hidpi else 1), abs(w / h - 1.6) < 0.01)
    if best is None or score > best[0]:
        best = (score, n)
if best:
    print(f"id:{sid.group(1)} mode:{best[1]} origin:(0,0) degree:0")
PY
    arg=$(python3 "$WORK/pick-mode.py" "$OUT/displays-before.txt")
    if [ -n "$arg" ]; then
      echo "displayplacer $arg"
      displayplacer "$arg" || echo "couldn't change the display mode"
      sleep 4
    fi
    displayplacer list > "$OUT/displays-after.txt" 2>&1 || true
  fi
  system_profiler SPDisplaysDataType > "$OUT/displays-profile.txt" 2>&1 || true
fi

# --- Keep the user's settings safe --------------------------------------------------------
[ -f "$CONFIG" ] && cp "$CONFIG" "$WORK/config.backup.json"
restore_config() { [ -f "$WORK/config.backup.json" ] && cp "$WORK/config.backup.json" "$CONFIG"; }
trap restore_config EXIT

# --- Content: real apps, Tiles' own material, no third-party brands -----------------------
# No red spelling underlines in TextEdit.
defaults write com.apple.TextEdit CheckSpellingWhileTyping -bool false 2>/dev/null || true
# Set MARKETING_XCODE=1 to show the code in Xcode. Off by default: on a fresh Mac, Xcode can
# open a component-download prompt that covers the code.
XCODE_APP=""
if [ "${MARKETING_XCODE:-0}" = "1" ]; then
  dev="$(xcode-select -p 2>/dev/null || true)"
  case "$dev" in */Contents/Developer) XCODE_APP="${dev%/Contents/Developer}" ;; esac
fi
cat > "$WORK/Tiles launch notes.txt" <<'TXT'
Tiles launch notes

Every window, in its place.

- Windows snap into place the moment they open
- 11 layouts: Dwindle, Columns, Grid, Centered Master, Scrolling...
- Ultrawide displays get Centered Master automatically
- Scenes come back when you dock
- 50+ shortcuts, all remappable
- Free and open source. No account, no telemetry.
TXT

cat > "$WORK/tiles.command" <<CMD
#!/bin/zsh
clear
cd "$ROOT"
printf '\033]0;tiles\007'
print -P '%F{green}%1~%f %% tiles --help'
"$TILES" --help
print
print -nP '%F{green}%1~%f %% '
sleep 100000
CMD
chmod +x "$WORK/tiles.command"

defaults write com.apple.dt.Xcode XCShowWelcomeWindow -bool false 2>/dev/null || true

# --- Start Tiles, then open the apps so they tile as they arrive --------------------------
open /Applications/Tiles.app
sleep 6
"$TILES" layout-dwindle
# Tiles' home page. Set MARKETING_URL to show another page, such as the website once it's live.
open -a Safari "${MARKETING_URL:-https://github.com/vannaenae/tiles}"
sleep 3
if [ -n "$XCODE_APP" ] && open -a "$XCODE_APP" "$ROOT/Sources/TilesCore/Layout.swift"; then
  echo "opened Layout.swift in $XCODE_APP"
else
  open -a TextEdit "$ROOT/Sources/TilesCore/Layout.swift"
fi
sleep 6
open -a Terminal "$WORK/tiles.command"
sleep 3
open -a TextEdit "$WORK/Tiles launch notes.txt"
sleep 4
"$TILES" retile
open -a Safari
shot 01-dwindle 4

# --- Every layout -------------------------------------------------------------------------
for layout in master-stack columns grid centered-master scrolling wide-master; do
  "$TILES" "layout-$layout"
  shot "02-$layout" 3
done

# --- Scenes: save, change, restore; the notice shows in the menu bar ----------------------
"$TILES" layout-dwindle
sleep 2
"$TILES" save-scene
sleep 2
"$TILES" layout-columns
sleep 2
"$TILES" restore-scene
shot 03-scene-restored 1

# --- The Tiles window (Dashboard), light then dark purple ---------------------------------
open /Applications/Tiles.app   # opening it again shows the Dashboard
shot 04-dashboard-light 4
python3 - "$CONFIG" <<'PY'
import json, sys
p = sys.argv[1]
c = json.load(open(p)); c["appearance"] = "dark"; c["theme"] = "purple"
json.dump(c, open(p, "w"), indent=2)
PY
shot 05-dashboard-dark-purple 4

"$TILES" status > "$OUT/status.json" 2>&1 || true
osascript -e 'quit app "Terminal"' >/dev/null 2>&1 || true
echo "Screenshots are in $OUT"
