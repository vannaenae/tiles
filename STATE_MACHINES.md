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
| **Mouse drag** | idle → tracking(window) → swap / move / stack / resize | `trackedWindow`, `mouseTimer` | Starts on a window move with the button down; ends on release. ⌥ held at release means stack. |
| **Programmatic-move quiet time** | quiet until T | `ignoreMovesUntil` | Tiles' own moves fire move events; they're ignored for 0.5 s (plus the animation time) so they aren't mistaken for drags. |
| **Scroll pan** | idle → panning(display) → settle → idle | `panning`, `panWork`, `panEndWork` | While panning, the focused window doesn't pull the strip back. 0.35 s after the last scroll, the window nearest the middle is focused. |
| **Animation** | idle ↔ animating(moves, start) | `animation`, `animationTimer` | New moves restart from where each window currently is. Off during panning and for parking. |
| **Parking** | per window: parked (with its frame to return to) or not | `parked` | Hidden-workspace windows wait one point on screen in the corner. Only a *newly* focused hidden window pulls its workspace forward (`lastFocused`, `lastWorkspaceSwitch` debounce). |
| **Stacks and Focus** | per window: stacked on a host or not; one zoomed window or none | `stackedOn`, `zoomed` | Floating windows drop out of stacks; a zoom ends when its window leaves the layout. |
| **Docking** | steady → displays changing (1 s debounce) → restore → autosave blocked 8 s | `displayWork`, `autosaveBlockedUntil`, `undoSnapshot` | Only a different *set* of displays counts; resolution or Dock changes just retile. `⌃⌥Z` undoes one restore. |
| **Refresh / autosave** | idle → scheduled → run | `refreshWork`, `autosaveWork` | Debounces bursts of window events. |
| **Shortcut recording** | listening ↔ not | `ShortcutRecorder.recording`, `AppDelegate.hotkeysPaused` | While listening, global shortcuts stay unregistered even if the config reloads underneath. |
| **Config file** | loaded ↔ error (keeps last good config) | `ConfigStore.lastError`, `lastModified` | Polled every second; errors show in the menu and in `tiles status`. |
| **Settings window** | closed ↔ open (Dock icon shown while open) | `settingsWindow`, `iconPlacement` | Activation policy is derived from both, never stored. |
| **Menu bar message** | blank ↔ showing text | `messageWork` | Clears after 1.6 s (5 s for long text). |

## Known gaps (found by audit, not fixed yet)

Each of these is a state the code can reach today where the user sees nothing, or sees something
wrong. None has been reproduced on a Mac yet: confirm each one there before fixing it, one PR per gap.
Each has a proposed screen in the Figma file
[Tiles — Screens & Flows](https://www.figma.com/design/ufzXHsLVavjeuyf72GGcLK) (Screens page,
"Error states" sections).

| Gap | Where | What happens | Figma |
|---|---|---|---|
| **Broken config is overwritten** | `ConfigStore.update` (`ConfigStore.swift:52`) | While `config.json` fails to parse, any change in Settings or the menu writes the last good config over the file, losing the user's hand edits. `lastError` isn't cleared, so the menu keeps showing the old error for a now-valid file. | E2 |
| **Restore while tiling is off** | display-change work item (`TilingManager.swift:164`), `restoreScene` | After docking, the scene restore runs even when tiling is off. `refresh()` does nothing, but the menu bar still shows "Restored … ⌃⌥Z to undo". | — |
| **Messages hidden in Dock-only mode** | `flash` (`AppDelegate.swift:209`), `statusItem.isVisible` (`:450`) | Every menu bar message, including "Config error" and "Tiling is off", goes to a status item that isn't shown. | E9 |
| **Corrupt scenes file replaced** | `SceneStore.load` (`Scene.swift:53-57`) | An unreadable `scenes.json` loads as empty; the next autosave overwrites it and every saved scene is lost, silently. | E7 |
| **Launch at login needs approval** | `AppDelegate.swift:312`, `toggleLogin` (`:403`) | Only `.enabled` counts as on. `.requiresApproval` and `.notFound` both look like plain "off", with no hint what to do. | E5 |
| **Profiles fail silently** | `SettingsModel` profile methods (`SettingsView.swift:83-112`) | Save, apply, delete, export and import all use `try?`: no confirmation before apply replaces every setting, and no message when a file can't be read. | E8 |
| **"No windows" while paused** | display card (`SettingsView.swift:749`) | With tiling off, each card says "No windows on this display.", which reads as a bug. | E3 |
| **"Tiling On ✓" without permission** | menu toggle (`AppDelegate.swift:237`) | In `permissionLost`, the menu still shows Tiling On with a check. `tiles status` explains it (`problem`), but the menu doesn't. | E1 |

## Adding state

- If it has more than two states, or a bad combination would be a bug, make it an enum in `TilesCore`
  with a transition function and a table test, as `AppPhase` does.
- If a person or agent would want to see it, add it to `StatusSnapshot`.
- Otherwise add a row to the table above.
- If it's a state the user can see or get stuck in, design it in the Figma file above, using the
  Issue Banner component for problems.
