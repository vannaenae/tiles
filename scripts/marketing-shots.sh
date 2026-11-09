#!/bin/bash
# Captures real screenshots of Tiles for the App Store and the website.
#
#   ./scripts/marketing-shots.sh [output-folder]      (default: marketing-out)
#
# Opens real apps on real pages (Safari on Tiles' GitHub, Claude and Google; the App Store on
# 3D Habits; Terminal with a made-up session), lets Tiles arrange them, saves one PNG per scene.
# It takes over the screen for about 3 minutes; don't touch the mouse or keyboard meanwhile.
#
# Needs: macOS, /Applications/Tiles.app running with Accessibility access, and screen-recording
# and Accessibility permission for your terminal (it types the Safari addresses). Your Tiles config is backed up and put back.
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

# --- Content: real apps on real pages -------------------------------------------------------
# Safari on Tiles' GitHub page, the Claude homepage and Google (three windows), the App Store
# on a product page, and Terminal with a made-up developer session (no real names or paths).
# Change the pages with MARKETING_GITHUB_URL, MARKETING_CLAUDE_URL, MARKETING_GOOGLE_URL and
# MARKETING_APPSTORE_URL (an apps.apple.com link).
if [ "${MARKETING_CI:-0}" = "1" ]; then defaults write -g NSAllowContinuousSpellChecking -bool false; fi
GITHUB_URL="${MARKETING_GITHUB_URL:-https://github.com/vannaenae/tiles}"
CLAUDE_URL="${MARKETING_CLAUDE_URL:-https://claude.com}"
GOOGLE_URL="${MARKETING_GOOGLE_URL:-https://www.google.com}"
APPSTORE_URL="${MARKETING_APPSTORE_URL:-https://apps.apple.com/us/app/3d-habits/id6756032720}"

# Terminal: a generated session for a fictional project, so nothing real is shown. It ends at a
# real, idle zsh prompt inside a folder named weather-app, so the title bar reads like a normal one.
PROJECT="$WORK/weather-app"
mkdir -p "$PROJECT" "$WORK/zsh"
cat > "$WORK/zsh/.zshrc" <<'RC'
PROMPT='%F{green}~/Projects/weather-app%f %% '
p() { print -nP "$PROMPT"; print -- "$1"; }
clear; printf '\033[3J'   # also clear the scrollback, so "Last login" never shows
p "swift build"
print "Building for debugging..."
print "[42/42] Linking WeatherApp"
print -P "%F{green}Build complete!%f (6.84s)"
print
p "swift test"
print "Test Suite 'All tests' started at 2026-11-09 09:41:03.112"
print "Test Suite 'ForecastTests' passed (64 tests)"
print "Test Suite 'LocationTests' passed (38 tests)"
print "Test Suite 'WidgetTests' passed (26 tests)"
print -P "%F{green}Executed 128 tests, with 0 failures%f (0 unexpected) in 2.318 seconds"
print
p "git status"
print "On branch main"
print "Your branch is up to date with 'origin/main'."
print
print "nothing to commit, working tree clean"
print
RC
cat > "$WORK/session.command" <<CMD
#!/bin/zsh
cd "$PROJECT"
SHELL_SESSIONS_DISABLE=1 ZDOTDIR="$WORK/zsh" exec /bin/zsh -i
CMD
chmod +x "$WORK/session.command"

# Separate Safari windows (not tabs) need real key presses: ⌘N, then the address.
# marketing-keys needs Accessibility; set MARKETING_KEYS to a prebuilt copy (CI does).
KEYS="${MARKETING_KEYS:-$WORK/marketing-keys}"
[ -x "$KEYS" ] || swiftc -O "$ROOT/scripts/marketing-keys.swift" -o "$KEYS" 2>/dev/null || KEYS=""
new_window() { # url
  if [ -n "$KEYS" ]; then open -a Safari; sleep 1; "$KEYS" new-window "$1"
  else open -a Safari "$1"; fi   # falls back to a tab
}

# --- Start Tiles, then open the apps so they tile as they arrive --------------------------
# Order matters in Dwindle: earlier windows get bigger tiles, and the App Store can't shrink much.
open /Applications/Tiles.app
sleep 6
"$TILES" layout-dwindle
open -a Safari "$GITHUB_URL"
sleep 8
open "${APPSTORE_URL/https:/macappstore:}"
sleep 10
# A fresh Mac shows welcome sheets ("What's New", notifications) over the page; click past them.
[ -n "$KEYS" ] && "$KEYS" dismiss "App Store"
new_window "$CLAUDE_URL"
sleep 6
new_window "$GOOGLE_URL"
sleep 6
# Terminal. On CI, start it in the project folder with the made-up session as its shell setup, so
# the title bar reads "weather-app — -zsh". Elsewhere, run the session as a .command file.
if [ "${MARKETING_CI:-0}" = "1" ] && ! pgrep -xq Terminal \
   && open --env ZDOTDIR="$WORK/zsh" --env SHELL_SESSIONS_DISABLE=1 -a Terminal "$PROJECT" 2>/dev/null; then :
else
  open -a Terminal "$WORK/session.command"
fi
sleep 5
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
echo "Screenshots are in $OUT"
