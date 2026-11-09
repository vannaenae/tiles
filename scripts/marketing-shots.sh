#!/bin/bash
# Captures real screenshots of Tiles for the App Store and the website.
#
#   ./scripts/marketing-shots.sh [output-folder]      (default: marketing-out)
#
# Opens Apple's own apps with real content (Safari, Notes, Calendar, Finder with photos and
# documents, Terminal), lets Tiles arrange them, then saves one PNG per scene.
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

# --- Content: Apple's own apps, each with real content ------------------------------------
# Safari, Notes, Calendar, Finder and Terminal. No empty windows: notes, events, files with
# thumbnails and command output are created first. Set MARKETING_CLAUDE=1 to add the Claude app.
if [ "${MARKETING_CI:-0}" = "1" ]; then defaults write -g NSAllowContinuousSpellChecking -bool false; fi

# Finder: a project folder with photos (macOS's own wallpapers) and real documents, so icon
# view shows thumbnails. Made in a temp folder, so nothing is added to your Documents.
DESK="$WORK/SOULSPACE Collective"
mkdir -p "$DESK/Brand" "$DESK/Launch" "$DESK/Research"
n=0
for pic in /System/Library/Desktop\ Pictures/*.heic /System/Library/Desktop\ Pictures/*.jpg; do
  [ -f "$pic" ] || continue
  n=$((n + 1)); [ $n -le 6 ] || break
  sips -s format jpeg -Z 1600 "$pic" --out "$DESK/Moodboard $n.jpg" >/dev/null 2>&1 || true
done
doc() { # file title body
  printf '<html><body><h1>%s</h1><p>%s</p></body></html>' "$2" "$3" > "$WORK/doc.html"
  textutil -convert rtf "$WORK/doc.html" -output "$DESK/$1" >/dev/null 2>&1 || true
}
doc "Launch plan.rtf" "Launch plan" "Monday: App Store. Tuesday: website and press. Wednesday: community."
doc "Brand notes.rtf" "Brand notes" "Every window, in its place. Indigo to blue. Calm, direct, plain."
doc "Meeting notes.rtf" "Meeting notes" "Screenshots approved. Final copy by Friday."

cat > "$WORK/tiles.command" <<CMD
#!/bin/zsh
clear
cd "$ROOT"
printf '\033]0;tiles\007'
print -P '%F{green}%1~%f %% git log --oneline -8'
git --no-pager log --oneline -8
print
print -P '%F{green}%1~%f %% tiles layout-dwindle'
print
print -nP '%F{green}%1~%f %% '
sleep 100000
CMD
chmod +x "$WORK/tiles.command"

# Notes, Calendar and Reminders content, added with AppleScript (asks for permission once on
# your own Mac). Anything that fails is skipped; the app still opens.
cat > "$WORK/content.applescript" <<'OSA'
on dismissWelcome(appName)
  try
    tell application "System Events" to tell process appName
      repeat with b in {"Continue", "Get Started", "Not Now", "OK", "Done"}
        if exists (button (contents of b) of window 1) then click button (contents of b) of window 1
      end repeat
    end tell
  end try
end dismissWelcome

on addEvent(cal, title, dayOffset, startHour, lengthHours)
  set d to (current date) + dayOffset * days
  set time of d to round (startHour * hours)
  tell application "Calendar" to tell cal to make new event with properties {summary:title, start date:d, end date:d + (lengthHours * hours)}
end addEvent

try
  tell application "Calendar" to activate
  delay 3
  dismissWelcome("Calendar")
  tell application "Calendar" to set cal to first calendar whose writable is true
  addEvent(cal, "Team stand-up", 0, 9.5, 0.5)
  addEvent(cal, "Design review", 0, 11, 1.5)
  addEvent(cal, "Lunch with Ada", 0, 13, 1)
  addEvent(cal, "Launch prep", 0, 15, 2)
  addEvent(cal, "Team stand-up", 1, 9.5, 0.5)
  addEvent(cal, "Press interviews", 1, 10.5, 2)
  addEvent(cal, "Gym", 1, 18, 1)
  addEvent(cal, "Team stand-up", -1, 9.5, 0.5)
  addEvent(cal, "Roadmap planning", -1, 14, 2)
  addEvent(cal, "Website copy", 2, 10, 3)
  addEvent(cal, "Dinner", 2, 19, 2)
  tell application "Calendar"
    switch view to week view
    view calendar at (current date)
  end tell
end try

try
  tell application "Reminders" to activate
  delay 3
  dismissWelcome("Reminders")
  tell application "Reminders" to tell default list
    repeat with r in {"Send the press kit", "Book the launch call", "Update App Store screenshots", "Reply to Ada", "Order new desk lamp"}
      make new reminder with properties {name:(contents of r)}
    end repeat
  end tell
end try

try
  tell application "Notes" to activate
  delay 3
  dismissWelcome("Notes")
  tell application "Notes"
    make new note with properties {body:"<h1>Reading list</h1><ul><li>The Design of Everyday Things</li><li>Shape Up</li><li>The Mom Test</li></ul>"}
    make new note with properties {body:"<h1>Ideas</h1><div>A calmer desk: one shortcut for every layout.</div><div>Scenes for home, office and travel.</div>"}
    set n to make new note with properties {body:"<h1>Launch week</h1><div><b>Monday</b>: App Store goes live</div><div><b>Tuesday</b>: website and press</div><div><b>Wednesday</b>: community Q&amp;A</div><br><ul><li>Screenshots</li><li>Press kit</li><li>Release notes</li></ul>"}
    try
      show n
    end try
  end tell
end try
OSA

# --- Start Tiles, then open the apps so they tile as they arrive --------------------------
open /Applications/Tiles.app
sleep 6
"$TILES" layout-dwindle
open -a Safari "${MARKETING_URL:-https://en.wikipedia.org/wiki/Tiling_window_manager}"
sleep 4
osascript "$WORK/content.applescript" || echo "some app content couldn't be added"
osascript -e 'quit app "Reminders"' >/dev/null 2>&1 || true   # five windows are plenty
sleep 2
open "$DESK"
sleep 3
osascript -e 'tell application "Finder" to set current view of front Finder window to icon view' >/dev/null 2>&1 || true
open -a Terminal "$WORK/tiles.command"
sleep 3
if [ "${MARKETING_CLAUDE:-0}" = "1" ] && [ -d /Applications/Claude.app ]; then
  xattr -dr com.apple.quarantine /Applications/Claude.app 2>/dev/null || true
  open -a Claude
  sleep 10
fi
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
