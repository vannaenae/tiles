# Tiles

**A free, open-source auto-tiling window manager for macOS.**
Every window snaps into place the moment it opens. Ultrawide displays get layouts built for them. Your arrangement comes back on its own when you dock.

- Lives in the menu bar, the Dock, or both: your choice.
- macOS 13 Ventura or later, Apple silicon and Intel.
- MIT licensed. No account, no telemetry, nothing leaves your Mac.

---

## Why Tiles

| | Tiles |
|---|---|
| Price | Free, MIT licensed |
| macOS | 13 Ventura and later |
| Layouts | 11: Dwindle, Master & Stack, Wide Master, Centered Master, Columns, Thirds, Rows, Grid, Monocle, Scrolling, Float |
| Ultrawide | Detected automatically. Centered Master by default, and a width cap stops any tile stretching across a 49" screen |
| Full screen | Each display holds as many tiles as fit its size; further windows stack on the last tile |
| Focus | One shortcut lets a window fill its display; press again to put it back |
| Settings | Settings window with a live preview for laptop, 27", 34" and 49" displays, plus a focus outline in your colour |
| Scenes | Saved automatically per set of displays, restored when that set reconnects, one-step undo |
| Mouse | Drag a window onto another to swap. Drag to another display to move. Resize to change the split |
| Keyboard | 40+ global shortcuts, all remappable |
| Automation | `tiles://` URL scheme and a `tiles` CLI for Raycast, Alfred, Shortcuts, skhd |
| App | A dashboard showing every display and its windows live, plus settings for layouts, gaps, colours, shortcuts, app rules and scenes |
| Look | Light, Dark or follow macOS, with five colour themes: orange, blue, green, purple, pink |
| Profiles | Save your settings as named profiles, switch in one click, export and import between Macs |
| Config | Also one plain JSON file, hot-reloaded on save |
| Per-display | Different layout for each monitor, by name or by shape |
| Rules | Float any app or window title |
| Privacy | Scenes store app identifiers only, never window titles |

## Install

**Terminal (easiest):** paste this into Terminal. It downloads the latest Tiles, puts it in Applications and opens it, with no security prompt.

```bash
curl -fsSL https://github.com/vannaenae/tiles/releases/latest/download/install.sh | bash
```

Run the same line again to update. To remove Tiles: `curl -fsSL https://github.com/vannaenae/tiles/releases/latest/download/install.sh | bash -s uninstall`

**Homebrew:**

```bash
brew tap vannaenae/tiles https://github.com/vannaenae/tiles
```

```bash
brew install --cask vannaenae/tiles/tiles
```

Update with `brew upgrade --cask --greedy tiles`.

**Download:** grab `Tiles-x.y.z.zip` from [Releases](https://github.com/vannaenae/tiles/releases), unzip, drag `Tiles.app` to Applications.

First launch only: right-click `Tiles.app` → **Open** → **Open** (releases are signed but not notarized). If macOS still refuses, run `xattr -dr com.apple.quarantine /Applications/Tiles.app`.

**Build from source** (Xcode 15+ or the Swift 5.9+ toolchain):

```bash
git clone https://github.com/vannaenae/tiles.git
```

```bash
cd tiles && ./scripts/build-app.sh && open dist/Tiles.app
```

### Accessibility permission

Tiles uses the macOS Accessibility API to read each window's position, size and app, and to move it. On first launch it asks you to enable it in **System Settings → Privacy & Security → Accessibility**, then starts on its own.

If you rebuild from source, macOS may treat the new build as a different app. Remove the old Tiles entry from the Accessibility list and add it again.

## Layouts

| Layout | What it does | Best for |
|---|---|---|
| **Dwindle** | Each new window halves the remaining space, splitting along the longer side | Laptops, general use (default) |
| **Master & Stack** | Main window on the left, the rest stacked on the right | Editor + references |
| **Wide Master** | Main window on top, the rest side by side below | Vertical monitors |
| **Centered Master** | Main window in the middle, others alternate right and left | Ultrawides (default there) |
| **Columns** | Equal columns | Ultrawides, comparing documents |
| **Thirds** | Two thirds + one third; the right third stacks from three windows | Main app + sidebar apps |
| **Rows** | Equal rows | Vertical monitors |
| **Grid** | Balanced grid | Dashboards, many small windows |
| **Scrolling** | Windows in a row wider than the screen, each at its own width. Focus one and the row scrolls to it; the rest wait at the edge | Laptops, people who hate squashed windows |
| **Monocle** | Every window full-screen; cycle with focus keys | Small screens, deep focus |
| **Float** | Tiles leaves this display alone | Presentations |

Each display has its own layout. Pick one from the menu bar, cycle with `⌃⌥Space`, or jump with `⌃⌥1`–`⌃⌥9`.

## Keyboard shortcuts

All defaults use **⌃⌥ (Control + Option)**, which apps rarely claim.

| Shortcut | Action |
|---|---|
| `⌃⌥` + `H` `J` `K` `L` or arrows | Focus window left / down / up / right |
| `⌃⌥⇧` + `H` `J` `K` `L` or arrows | Swap with window left / down / up / right |
| `⌃⌥↩` | Promote focused window to master (again to swap back) |
| `⌃⌥N` / `⌃⌥P` | Focus next / previous window |
| `⌃⌥Space` / `⌃⌥⇧Space` | Next / previous layout |
| `⌃⌥1` … `⌃⌥9`, `⌃⌥0` | Dwindle, Master & Stack, Centered Master, Columns, Grid, Monocle, Wide Master, Rows, Thirds; Float |
| `⌃⌥M` | Focus: fill the display with this window, again to put it back |
| `⌃⌥W` | Scrolling: cycle the window's width through ⅓, ½, ⅔ and full |
| `⌃⌥C` | Centre the window (Scrolling, or a floating window) |
| `⌃⌥=` / `⌃⌥-` | Grow / shrink master area (in Scrolling: the window's width by 5%) |
| `⌃⌥,` / `⌃⌥.` | More / fewer master windows |
| `⌃⌥⇧=` / `⌃⌥⇧-` | Bigger / smaller gaps |
| `⌃⌥]` / `⌃⌥[` | Move window to next / previous display |
| `⌃⌥F` | Float or tile the focused window |
| `⌃⌥T` | Turn tiling on or off |
| `⌃⌥R` | Retile everything |
| `⌃⌥S` | Save scene for this display setup |
| `⌃⌥Z` | Undo the last scene restore |

Remap anything in the config file (see below). Shortcuts use key positions on a US layout.

## Mouse

- **Drag a window onto another** to swap them.
- **Drag a window to another display** to move it there.
- **Resize a window** with the mouse and the split follows (master ratio in Master & Stack, Wide Master, Centered Master and Dwindle). Other resizes snap back.

## Scenes

A scene is the arrangement for one combination of displays: each display's layout, split ratio, and which apps sit in which tile.

- Tiles saves the scene automatically a few seconds after you rearrange things.
- When you dock or undock, Tiles waits for the displays to settle and restores the scene saved for that exact set.
- A notice like *Restored LG UltraFine · 3 windows* appears in the menu bar. `⌃⌥Z` or **Undo Scene Restore** puts things back.
- `⌃⌥S` saves on demand; **Restore Scene** in the menu re-applies it.
- Scenes store bundle identifiers (`com.apple.Safari`), never window titles. They live in `~/Library/Application Support/Tiles/scenes.json`.

## Configuration

**Settings…** (`⌘,` from the menu) covers the everyday options with a live preview. Everything, including rules and shortcuts, lives in `~/.config/tiles/config.json`; **Edit Config File…** in the menu opens it. Tiles reloads it the moment you save. Every key is optional; anything you leave out uses the default.

```json
{
  "defaultLayout": "dwindle",
  "ultrawideLayout": "centered-master",
  "displays": {
    "Built-in": "monocle",
    "DELL U3423WE": "columns"
  },
  "layout": {
    "innerGap": 8,
    "outerGap": 8,
    "masterRatio": 0.55,
    "masterCount": 1,
    "ultrawideAspectRatio": 2.0,
    "ultrawideSingleWindowRatio": 0.6,
    "maxTileWidth": 2600,
    "maxTiles": 0,
    "scrollWidth": 0.5
  },
  "outlineColor": "#E8643C",
  "theme": "orange",
  "appearance": "system",
  "iconPlacement": "menu-bar",
  "newWindowPlacement": "end",
  "dragToSwap": true,
  "resizeToAdjustRatio": true,
  "autoRestoreScenes": true,
  "mouseFollowsFocus": false,
  "rules": [
    { "app": "com.apple.systempreferences", "float": true },
    { "app": "Finder", "titleContains": "Copy", "float": true }
  ],
  "hotkeys": {
    "hyper+h": "focus-left",
    "ctrl+alt+h": "none"
  }
}
```

| Key | Meaning |
|---|---|
| `defaultLayout` | Layout for displays with no specific setting |
| `ultrawideLayout` | Layout for displays at or above `ultrawideAspectRatio` (2.0 ≈ 21:9 and wider) |
| `displays` | Layout per display, matched on part of its name. Longest match wins |
| `layout.innerGap` / `outerGap` | Space between windows / around the edge, in points |
| `layout.masterRatio` | Share of the screen for the master area, 0.1–0.9 |
| `layout.masterCount` | Windows in the master area |
| `layout.ultrawideSingleWindowRatio` | Width share for a lone window on an ultrawide. Set `ultrawideAspectRatio` to 0 to always fill |
| `layout.maxTileWidth` | Widest a tile may get, in points; wider tiles are centred. 0 turns it off |
| `layout.scrollWidth` | Scrolling: width of a new window, as a share of the screen |
| `restoreWindowsOnQuit` | Put windows back where they were when Tiles quits (default on) |
| `layout.maxTiles` | Most tiles per display before windows stack. 0 picks from display size |
| `theme` | `orange`, `blue`, `green`, `purple` or `pink` |
| `appearance` | `system`, `light` or `dark` |
| `iconPlacement` | `menu-bar`, `dock` or `both` |
| `outlineColor` | Focus outline colour as `#RRGGBB`, `""` for none |
| `newWindowPlacement` | `end`, `master`, or `after-focused` |
| `rules` | Match on `app` (bundle ID or name) and/or `titleContains`. Last match wins. Replaces the default list when set |
| `hotkeys` | Merged over the defaults. Map a shortcut to `"none"` to remove it |

**Shortcut syntax:** modifiers `cmd`, `alt`/`opt`, `ctrl`, `shift`, plus `hyper` (all four) and `meh` (all but cmd), joined with `+` to a key: a letter, digit, `left` `right` `up` `down`, `return`, `space`, `tab`, `f1`–`f20`, or punctuation such as `-` `=` `[` `]` `,` `.` `/`.

**Commands:** `focus-left|right|up|down`, `swap-left|right|up|down`, `promote`, `focus-next`, `focus-previous`, `layout-<name>`, `next-layout`, `previous-layout`, `grow-master`, `shrink-master`, `increase-master-count`, `decrease-master-count`, `increase-gaps`, `decrease-gaps`, `toggle-float`, `toggle-tiling`, `retile`, `move-to-next-display`, `move-to-previous-display`, `save-scene`, `restore-scene`, `undo-restore`, `toggle-zoom`, `cycle-width`, `center-window`.

## Automation

Every command is also a URL, so anything that can open a link can drive Tiles:

```bash
open -g "tiles://layout-centered-master"
```

Or install the tiny CLI wrapper:

```bash
sudo cp scripts/tiles /usr/local/bin/tiles
```

```bash
tiles swap-left
```

## How it works

```
Sources/
  TilesCore/      Pure Swift, no AppKit. Layout maths, config, scenes, geometry. Unit-tested.
  Tiles/          The app: Accessibility, window events, hotkeys, menu bar.
Tests/            XCTest suite for TilesCore.
scripts/          build-app.sh (universal .app + zip), tiles (CLI).
```

1. `WorkspaceObserver` subscribes to Accessibility notifications from every regular app: window created, destroyed, moved, resized, minimised.
2. `TilingManager` reads every standard, resizable window on the current Space, keeps a per-display tiling order, and asks `LayoutEngine` for frames.
3. Only windows that are out of place get moved, so re-tiling is cheap and flicker-free.
4. Moves the user makes with the mouse are told apart from Tiles' own moves; a drag swaps, a resize changes the ratio.

Known limits: windows in native full-screen are left alone, Tiles tiles the current Space only, and Stage Manager should be off.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE).

## Releasing (maintainers)

Push a tag such as `v0.2.0`. The Release workflow tests, builds a universal app, and publishes it. It signs and notarizes when these repository secrets exist (Settings → Secrets and variables → Actions):

| Secret | What it is |
|---|---|
| `MACOS_CERTIFICATE` | Your **Developer ID Application** certificate exported from Keychain Access as `.p12`, then base64-encoded: `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PASSWORD` | The password you set when exporting the `.p12` |

For notarization, either an App Store Connect API key (recommended):

| Secret | What it is |
|---|---|
| `APPLE_API_KEY` | Full contents of the `AuthKey_XXXX.p8` file from App Store Connect → Users and Access → Integrations → Team Keys |
| `APPLE_API_KEY_ID` | The key's ID shown next to it |
| `APPLE_API_ISSUER_ID` | Issuer ID shown above the keys list |

or an Apple ID: `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` (app-specific password).
