# State machines in Tiles

Every piece of Tiles that remembers "where it is" between events, what its states are, and who owns it.
**Explicit** machines are enums in `TilesCore` with unit tests. **Implicit** ones are a few variables in
one owner; they're listed here so nobody has to rediscover them. Ask a running Tiles for its state with
`tiles status`.

## Explicit (types in TilesCore, each with unit tests)

### 1. App lifecycle and permission: `AppPhase` (owner: `AppDelegate`)

```
launching ──trusted──▶ running ◀──trusted── permissionLost
    │                    │  ▲                     ▲
 untrusted           untrusted └─────────────────┘ (resume: re-read windows)
    ▼                    ▼
needsPermission ──trusted──▶ running   (start: create window observers, once)
```

A 1-second permission check calls `phase.next(trusted:)`, which returns the new phase and one effect:
`start`, `resume`, `pause` (hide outline and badges) or `none`. Before this was explicit, switching
Accessibility off and on again left Tiles half-started; now it resumes by itself.

### 2. Updater: `UpdatePhase` (owner: `Updater`)

```
idle ─check─▶ checking ─▶ upToDate | offline | available(v)
available(v) | failed(v) ─install─▶ downloading(v) ─▶ installing(v) → quit, swap, reopen
                                          └────────▶ failed(v)   (retry allowed)
```

`canCheck` is false while checking, downloading or installing, so the daily check can't clobber a
download. `installable` is set only in `available` and `failed`, so a double-click on Install can't start
two downloads. The menu and Settings read `message`.

### 3. Status snapshot: `StatusSnapshot` (written by `AppDelegate`)

Not a machine itself: a read-only view of the others (phase, tiling on/off, update phase, config error,
and each display's layout, workspace and window count), plus a plain-language `problem`. Written to
`~/Library/Application Support/Tiles/status.json` at most twice a second, only when it changes, and
deleted on quit. `tiles status` prints it; the e2e test reads it before starting.

### 4. Float override: `FloatOverride` (owner: `TilingManager.floatOverrides`)

Per window: none (follow the app rules), `float`, or `tile`. `⌃⌥F` sets `toggled(isTiled:ruleSaysFloat:)`,
which always flips what you see and drops the override when the rules already agree. One value per
window replaced two sets that could, in principle, both hold the same window.

### 5. Workspaces: `Workspaces` (owner: `TilingManager.workspaces`)

Per display: the workspace it shows. Per window: its workspace and the display that number belongs to.
A window that arrives on another display (dragged over, or its monitor unplugged) joins the workspace
that display is showing, so it can never land hidden. Tested in `WorkspaceTests`.

## Implicit (audited, deliberately left as variables)

Each of these is one optional, one flag or one timer with a single owner. All were audited for bad
combinations; none were found, so an enum would add code without removing risk.

The ones inside `TilingManager`'s event loop overlap in time (you can pan while an animation
finishes; a docking change can land mid-drag), so one enum would forbid real combinations. Each is
covered by the real-Mac test in `scripts/e2e.swift`.

| Machine | States | Variables | Notes |
|---|---|---|---|
| **Tiling on/off** | on, off | `isEnabled` ← `config.enabled` | `⌃⌥T` writes the config; the config change flips the state, so menu, dashboard and next launch agree. Off brings parked windows back. |
| **Snap drag** | idle → tracking(window) → snap to zone / leave | `trackedWindow`, `mouseTimer` (shared with Mouse drag: only one drag at a time) | Untiled windows only (Snap mode or a Float display). Shows a preview while at an edge; a resize never snaps. Zones are `SnapZone` in TilesCore, tested. |
| **Mouse drag** | idle → tracking(window) → swap / move / stack / resize | `trackedWindow`, `mouseTimer` | Starts on a window move with the button down; ends on release. ⌥ held at release means stack. |
| **Programmatic-move quiet time** | quiet until T | `ignoreMovesUntil` | Tiles' own moves fire move events; they're ignored for 0.5 s (plus the animation time) so they aren't mistaken for drags. |
| **Scroll pan** | idle → panning(display) → settle → idle | `panning`, `panWork`, `panEndWork` | While panning, the focused window doesn't pull the strip back. 0.35 s after the last scroll, the window nearest the middle is focused. |
| **Animation** | idle ↔ animating(moves, start) | `animation`, `animationTimer` | New moves restart from where each window currently is. Off during panning and for parking. |
| **Workspace layouts** | per display+workspace: remembered layout | `workspaceLayouts` | Swapped in and out of `layouts` by `switchWorkspace`, the only place a workspace changes. |
| **Parking** | per window: parked (with its frame to return to) or not | `parked` | Hidden-workspace windows wait one point on screen in the corner. Only a *newly* focused hidden window pulls its workspace forward (`lastFocused`, `lastWorkspaceSwitch` debounce). |
| **Stacks and Focus** | per window: stacked on a host or not; one zoomed window or none | `stackedOn`, `zoomed` | Floating windows drop out of stacks; a zoom ends when its window leaves the layout. |
| **Docking** | steady → displays changing (1 s debounce) → restore → autosave blocked 8 s | `displayWork`, `autosaveBlockedUntil`, `undoSnapshot` | Only a different *set* of displays counts; resolution or Dock changes just retile. `⌃⌥Z` undoes one restore. |
| **Refresh / autosave** | idle → scheduled → run | `refreshWork`, `autosaveWork` | Debounces bursts of window events. |
| **Shortcut recording** | listening ↔ not | `ShortcutRecorder.recording`, `AppDelegate.hotkeysPaused` | While listening, global shortcuts stay unregistered even if the config reloads underneath. |
| **Config file** | loaded ↔ error (keeps last good config) | `ConfigStore.lastError`, `lastModified` | Polled every second; errors show in the menu and in `tiles status`. |
| **Settings window** | closed ↔ open (Dock icon shown while open) | `settingsWindow`, `iconPlacement` | Activation policy is derived from both, never stored. |
| **Menu bar message** | blank ↔ showing text | `messageWork` | Clears after 1.6 s (5 s for long text). |

## Adding state

- If it has more than two states, or a bad combination would be a bug, make it an enum in `TilesCore`
  with a transition function and a table test, as `AppPhase` does.
- If a person or agent would want to see it, add it to `StatusSnapshot`.
- Otherwise add a row to the table above.
