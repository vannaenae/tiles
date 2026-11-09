#!/usr/bin/env bash
# Runs the real-input test on your own Mac. Takes over the keyboard and mouse for ~3 minutes.
# Needs: Tiles running and allowed in Accessibility, and Terminal allowed in Accessibility.
set -euo pipefail
cd "$(dirname "$0")/.."

if pgrep -x TextEdit >/dev/null || [ "$(osascript -e 'tell application "Finder" to count Finder windows')" != "0" ]; then
  echo "Please quit TextEdit and close all Finder windows first (the test counts them), then run this again."
  exit 1
fi

docs="$(mktemp -d)"
for i in 1 2 3; do printf 'Tiles test %s\n' "$i" > "$docs/doc$i.txt"; done
open /Applications/Tiles.app
open -a TextEdit "$docs/doc1.txt" "$docs/doc2.txt" "$docs/doc3.txt"
open "$HOME"
sleep 4

mkdir -p out
swiftc -O scripts/e2e.swift -o # Clean up after ourselves: close the test documents without saving, so TextEdit
# doesn't reopen them next time, and delete them. (The test restores your Tiles settings itself.)
cleanup() {
  osascript -e 'tell application "TextEdit" to close (every document whose path contains "'"$docs"'") saving no' >/dev/null 2>&1 || true
  osascript -e 'tell application "TextEdit" to if (count of documents) is 0 then quit' >/dev/null 2>&1 || true
  rm -rf "$docs" "${TMPDIR:-/tmp}/rule-test.txt"
}
trap cleanup EXIT
"$docs/tiles-e2e"
"$docs/tiles-e2e"
