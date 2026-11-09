# Notes for AI agents and contributors

Tiles is a macOS tiling window manager: a Swift package with a pure core and an AppKit app.

## Layout

- `Sources/TilesCore/`: layouts, commands, config, scenes, workspaces, lifecycle. No AppKit; builds and
  tests on Linux too. Put logic here whenever you can.
- `Sources/Tiles/`: the app. `TilingManager` is the event loop, `AppDelegate` owns the menu bar and lifecycle.
- `scripts/`: `build-app.sh` (makes `dist/Tiles.app`), `e2e.swift` (real keyboard and mouse test),
  `tiles` (CLI), `localize.py` (translations).
- `STATE_MACHINES.md`: every state machine in the app. Read it before touching timers, flags or `Date`s.

## Check your work

```bash
swift test                          # unit tests (any OS with Swift 5.9+)
./scripts/build-app.sh              # macOS: build the app
./scripts/test-on-my-mac.sh         # macOS: real-input test, takes over keyboard and mouse ~3 min
```

CI runs the unit tests on macOS for every push; the `End-to-end test` workflow runs the real-input test
on a GitHub Mac.

## Drive and observe a running Tiles

- Do things: `tiles <command>` or `open -g tiles://<command>` (`tiles --help` lists them all).
- See things: `tiles status` prints JSON with `phase`, `tilingEnabled`, `displays` (layout, workspace,
  window count), `update` and a plain-language `problem` when something is wrong. Check it before
  concluding Tiles is broken.

## Rules of thumb

- Every new command goes in `Command.all`; it then gets a name, a `tiles://` link and a Settings row for free.
- New config keys must decode with `decodeIfPresent` and a default, so old config files keep working.
- New user-facing strings: add them to `scripts/localize.py` and run it.
