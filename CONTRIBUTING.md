# Contributing to Tiles

Thanks for helping. A few things keep the project easy to work on.

## Setup

```bash
swift build && swift test
```

```bash
./scripts/build-app.sh && open dist/Tiles.app
```

## Where things go

- **Layout maths, config parsing, scene matching, geometry** → `Sources/TilesCore`. No AppKit here. Add a test in `Tests/TilesCoreTests` for every change.
- **Anything that touches windows, events, hotkeys or the menu** → `Sources/Tiles`.
- **State, timers and flags** → read [`STATE_MACHINES.md`](STATE_MACHINES.md) first. It lists every state machine, which ones are explicit types, and the known gaps. Update it in the same PR when you add or change one.

## Adding a layout

1. Add a case to `LayoutKind` in `Sources/TilesCore/Layout.swift` with a `displayName`.
2. Handle it in `LayoutEngine.frames`.
3. The existing tests check every layout returns one frame per window, stays on screen, and doesn't overlap. Add a test for its specific shape.
4. Document it in the README layouts table.

## Pull requests

- Keep each PR to one change.
- `swift test` must pass. CI runs it on macOS for every push.
- Describe how you tested it on a real Mac, including displays used.
