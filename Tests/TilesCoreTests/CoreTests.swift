import XCTest
@testable import TilesCore

final class GeometryTests: XCTestCase {
    // A 2x2 grid:  0 1
    //              2 3
    let grid = [
        Rect(x: 0, y: 0, width: 100, height: 100),
        Rect(x: 100, y: 0, width: 100, height: 100),
        Rect(x: 0, y: 100, width: 100, height: 100),
        Rect(x: 100, y: 100, width: 100, height: 100),
    ]

    func testNeighbors() {
        XCTAssertEqual(Geometry.neighbor(of: 0, in: grid, direction: .right), 1)
        XCTAssertEqual(Geometry.neighbor(of: 0, in: grid, direction: .down), 2)
        XCTAssertEqual(Geometry.neighbor(of: 3, in: grid, direction: .left), 2)
        XCTAssertEqual(Geometry.neighbor(of: 3, in: grid, direction: .up), 1)
        XCTAssertNil(Geometry.neighbor(of: 0, in: grid, direction: .left))
        XCTAssertNil(Geometry.neighbor(of: 0, in: grid, direction: .up))
    }

    func testNeighborFromTallMasterPrefersTopAlignedWindow() {
        let frames = [
            Rect(x: 0, y: 0, width: 100, height: 200),
            Rect(x: 100, y: 0, width: 100, height: 100),
            Rect(x: 100, y: 100, width: 100, height: 100),
        ]
        XCTAssertEqual(Geometry.neighbor(of: 0, in: frames, direction: .right), 1)
        XCTAssertEqual(Geometry.neighbor(of: 2, in: frames, direction: .left), 0)
    }

    func testSplitHelpers() {
        let r = Rect(x: 0, y: 0, width: 1000, height: 500)
        let (a, b) = r.splitColumns(ratio: 0.3, gap: 10)
        XCTAssertEqual(a.width + b.width + 10, 1000)
        XCTAssertEqual(b.maxX, 1000)
        let cols = r.columns(3, gap: 10)
        XCTAssertEqual(cols.last?.maxX, 1000)
        XCTAssertEqual(cols[1].minX - cols[0].maxX, 10)
    }
}

final class TilingOrderTests: XCTestCase {
    func testSyncRemovesGoneAndAppendsNew() {
        let r = TilingOrder.sync([1, 2, 3], present: [3, 1, 4], placement: .end, focused: nil)
        XCTAssertEqual(r, [1, 3, 4])
    }

    func testSyncMasterPlacement() {
        XCTAssertEqual(TilingOrder.sync([1, 2], present: [1, 2, 9], placement: .master, focused: nil), [9, 1, 2])
    }

    func testSyncAfterFocused() {
        XCTAssertEqual(TilingOrder.sync([1, 2, 3], present: [1, 2, 3, 9], placement: .afterFocused, focused: 1), [1, 9, 2, 3])
        XCTAssertEqual(TilingOrder.sync([1, 2], present: [1, 2, 9], placement: .afterFocused, focused: nil), [1, 2, 9])
    }

    func testPromote() {
        XCTAssertEqual(TilingOrder.promote([1, 2, 3], 3), [3, 1, 2])
        XCTAssertEqual(TilingOrder.promote([1, 2, 3], 1), [2, 1, 3])
    }

    func testSwapAndCycle() {
        XCTAssertEqual(TilingOrder.swap([1, 2, 3], 1, 3), [3, 2, 1])
        XCTAssertEqual(TilingOrder.cycle([1, 2, 3], from: 3, forward: true), 1)
        XCTAssertEqual(TilingOrder.cycle([1, 2, 3], from: 1, forward: false), 3)
        XCTAssertNil(TilingOrder.cycle([Int](), from: nil, forward: true))
    }
}

final class CommandTests: XCTestCase {
    func testEveryCommandNameRoundTrips() {
        for name in Command.allNames {
            let command = Command(name: name)
            XCTAssertNotNil(command, name)
            XCTAssertEqual(command?.name, name)
        }
        XCTAssertNil(Command(name: "launch-rockets"))
    }

    func testShortcutParsing() {
        let s = Shortcut("ctrl+alt+shift+left")
        XCTAssertEqual(s?.key, "left")
        XCTAssertEqual(s?.modifiers, [.control, .option, .shift])
        XCTAssertEqual(Shortcut("hyper+1")?.modifiers, [.control, .option, .shift, .command])
        XCTAssertEqual(Shortcut("Cmd + Return")?.key, "return")
        XCTAssertEqual(Shortcut("ctrl+alt++")?.key, "+")
        XCTAssertNil(Shortcut("left"))           // needs a modifier
        XCTAssertNil(Shortcut("ctrl+banana"))
        XCTAssertNil(Shortcut("super+h"))
    }
}

final class ConfigTests: XCTestCase {
    func testEmptyFileGivesDefaults() throws {
        let config = try Config.decode(Data("{}".utf8))
        XCTAssertEqual(config, Config.default)
    }

    func testThemeAndAppearance() throws {
        let config = try Config.decode(Data(#"{"theme": "purple", "appearance": "dark"}"#.utf8))
        XCTAssertEqual(config.theme, .purple)
        XCTAssertEqual(config.appearance, .dark)
        XCTAssertEqual(Config.default.iconPlacement, .menuBar)
        XCTAssertEqual(try Config.decode(Data(#"{"iconPlacement": "both"}"#.utf8)).iconPlacement, .both)
        XCTAssertEqual(Theme.allCases.count, 5)
        XCTAssertEqual(Set(Theme.allCases.map(\.hex)).count, 5)
    }

    func testPartialLayoutSection() throws {
        let config = try Config.decode(Data(#"{"layout": {"innerGap": 20}, "defaultLayout": "columns"}"#.utf8))
        XCTAssertEqual(config.layout.innerGap, 20)
        XCTAssertEqual(config.layout.outerGap, LayoutParameters.default.outerGap)
        XCTAssertEqual(config.defaultLayout, .columns)
    }

    func testRoundTrip() throws {
        var config = Config.default
        config.displays = ["LG": .centeredMaster]
        config.hotkeys = ["cmd+alt+x": "retile"]
        XCTAssertEqual(try Config.decode(config.encoded()), config)
    }

    func testDefaultHotkeysAreAllValid() {
        let (bindings, errors) = Config.default.resolvedHotkeys()
        XCTAssertEqual(errors, [])
        XCTAssertEqual(bindings.count, Config.defaultHotkeys.count)
    }

    func testHotkeyOverridesAndRemovals() {
        var config = Config.default
        config.hotkeys = ["ctrl+alt+h": "none", "cmd+shift+9": "layout-grid", "ctrl+alt+q": "nope"]
        let (bindings, errors) = config.resolvedHotkeys()
        XCTAssertFalse(bindings.contains { $0.shortcut == Shortcut("ctrl+alt+h") })
        XCTAssertTrue(bindings.contains { $0.shortcut == Shortcut("cmd+shift+9") && $0.command == .setLayout(.grid) })
        XCTAssertEqual(errors.count, 1)
    }

    func testBindReplacesShortcuts() {
        var config = Config.default
        config.bind(Shortcut("cmd+shift+k"), to: .focus(.left))
        XCTAssertEqual(config.shortcuts(for: .focus(.left)), [Shortcut("cmd+shift+k")!])

        // Taking another command's shortcut removes it from that command.
        config.bind(Shortcut("ctrl+alt+f"), to: .retile)
        XCTAssertEqual(config.shortcuts(for: .retile), [Shortcut("ctrl+alt+f")!])
        XCTAssertEqual(config.shortcuts(for: .toggleFloat), [])

        config.bind(nil, to: .retile)
        XCTAssertEqual(config.shortcuts(for: .retile), [])
        XCTAssertEqual(config.resolvedHotkeys().errors, [])
        XCTAssertEqual(try Config.decode(config.encoded()), config)
    }

    func testDisplayLayoutSelection() {
        var config = Config.default
        config.displays = ["LG": .columns, "LG UltraFine": .grid]
        XCTAssertEqual(config.layoutKind(forDisplayNamed: "LG UltraFine 5K", aspectRatio: 1.7), .grid)
        XCTAssertEqual(config.layoutKind(forDisplayNamed: "LG HDR 4K", aspectRatio: 1.7), .columns)
        XCTAssertEqual(config.layoutKind(forDisplayNamed: "Dell U3423WE", aspectRatio: 2.38), .centeredMaster)
        XCTAssertEqual(config.layoutKind(forDisplayNamed: "Built-in Retina Display", aspectRatio: 1.54), .dwindle)
    }

    func testEmptyRuleMatchesNothing() {
        // "Add Empty Rule" used to float every window until an app name was typed.
        var config = Config.default
        config.rules = [WindowRule(app: "", titleContains: "", float: true)]
        XCTAssertFalse(config.shouldFloat(bundleID: "com.apple.Safari", appName: "Safari", title: "Docs"))
    }

    func testPlacementRules() {
        var config = Config.default
        config.rules = [
            WindowRule(app: "Slack", display: "Built-in"),
            WindowRule(app: "com.apple.dt.Xcode", display: "LG", master: true),
        ]
        XCTAssertEqual(config.placement(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", title: nil).display, "Built-in")
        let xcode = config.placement(bundleID: "com.apple.dt.Xcode", appName: "Xcode", title: nil)
        XCTAssertEqual(xcode.display, "LG")
        XCTAssertTrue(xcode.master)
        XCTAssertNil(config.placement(bundleID: "x", appName: "Notes", title: nil).display)
        // A later, more specific rule can switch "main tile" back off.
        config.rules.append(WindowRule(app: "Xcode", titleContains: "Console", master: false))
        XCTAssertFalse(config.placement(bundleID: "com.apple.dt.Xcode", appName: "Xcode", title: "Console").master)
        XCTAssertTrue(config.placement(bundleID: "com.apple.dt.Xcode", appName: "Xcode", title: "Editor").master)
        // Placement rules don't float anything.
        XCTAssertFalse(config.shouldFloat(bundleID: "com.apple.dt.Xcode", appName: "Xcode", title: nil))
        XCTAssertEqual(try Config.decode(config.encoded()), config)
    }

    func testVersionComparison() {
        XCTAssertTrue(Version.isNewer("0.10.0", than: "0.9.2"))
        XCTAssertTrue(Version.isNewer("0.4.3", than: "0.4.2"))
        XCTAssertFalse(Version.isNewer("0.4.2", than: "0.4.2"))
        XCTAssertFalse(Version.isNewer("0.3.9", than: "0.4.0"))
    }

    func testFloatRules() {
        var config = Config.default
        config.rules = [
            WindowRule(app: "Safari", float: true),
            WindowRule(app: "com.apple.Safari", titleContains: "Main", float: false),
            WindowRule(titleContains: "Picture in Picture", float: true),
        ]
        XCTAssertTrue(config.shouldFloat(bundleID: "com.apple.Safari", appName: "Safari", title: "Docs"))
        XCTAssertFalse(config.shouldFloat(bundleID: "com.apple.Safari", appName: "Safari", title: "Main Window"))
        XCTAssertTrue(config.shouldFloat(bundleID: "x", appName: "X", title: "Picture in Picture"))
        XCTAssertFalse(config.shouldFloat(bundleID: "com.apple.Notes", appName: "Notes", title: "Notes"))
        XCTAssertTrue(Config.default.shouldFloat(bundleID: "com.apple.systempreferences", appName: "System Settings", title: nil))
    }
}

final class SceneTests: XCTestCase {
    func testFingerprintIgnoresOrder() {
        XCTAssertEqual(SceneStore.fingerprint(displayIDs: ["b", "a"]), SceneStore.fingerprint(displayIDs: ["a", "b"]))
    }

    func testAssignRestoresAppsToSavedDisplaysInOrder() {
        let scene = Scene(displays: [
            "laptop": SceneDisplay(layout: .dwindle, masterRatio: 0.5, masterCount: 1, apps: ["slack"]),
            "monitor": SceneDisplay(layout: .centeredMaster, masterRatio: 0.5, masterCount: 1, apps: ["code", "safari", "safari"]),
        ])
        let windows = [
            SceneWindow(id: 1, bundleID: "safari", display: "laptop"),
            SceneWindow(id: 2, bundleID: "slack", display: "laptop"),
            SceneWindow(id: 3, bundleID: "code", display: "laptop"),
            SceneWindow(id: 4, bundleID: "safari", display: "laptop"),
            SceneWindow(id: 5, bundleID: "music", display: "laptop"),
        ]
        let result = SceneMatcher.assign(scene: scene, windows: windows, displays: ["laptop", "monitor"])
        XCTAssertEqual(result["monitor"], [3, 1, 4])
        XCTAssertEqual(result["laptop"], [2, 5])
    }

    func testAssignPrefersWindowsAlreadyOnTheDisplay() {
        let scene = Scene(displays: [
            "a": SceneDisplay(layout: .dwindle, masterRatio: 0.5, masterCount: 1, apps: ["term"]),
            "b": SceneDisplay(layout: .dwindle, masterRatio: 0.5, masterCount: 1, apps: ["term"]),
        ])
        let windows = [
            SceneWindow(id: 10, bundleID: "term", display: "b"),
            SceneWindow(id: 11, bundleID: "term", display: "a"),
        ]
        let result = SceneMatcher.assign(scene: scene, windows: windows, displays: ["a", "b"])
        XCTAssertEqual(result["a"], [11])
        XCTAssertEqual(result["b"], [10])
    }

    func testStoreRoundTripsThroughDisk() throws {
        var store = SceneStore()
        let scene = Scene(displays: ["x": SceneDisplay(layout: .grid, masterRatio: 0.4, masterCount: 2, apps: ["a"])],
                          savedAt: Date(timeIntervalSince1970: 1_700_000_000))
        store.save(scene, for: ["x"])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("scenes.json")
        try store.write(to: url)
        XCTAssertEqual(SceneStore.load(from: url), store)
    }
}

final class WorkspaceTests: XCTestCase {
    func testNewWindowsJoinTheShowingWorkspace() {
        var w = Workspaces()
        w.adopt(1, on: "A")
        w.show(2, on: "A")
        w.adopt(2, on: "A")
        XCTAssertFalse(w.isShown(1, on: "A"))
        XCTAssertTrue(w.isShown(2, on: "A"))
        XCTAssertEqual(w.occupied(by: [1, 2], on: "A"), [1, 2])
        // Displays switch independently.
        XCTAssertEqual(w.active(on: "B"), 1)
    }

    func testMoveAndForget() {
        var w = Workspaces()
        w.adopt(7, on: "A")
        w.move(7, to: 3)
        XCTAssertEqual(w.workspace(of: 7, on: "A"), 3)
        w.keep(only: [])
        XCTAssertEqual(w.workspace(of: 7, on: "A"), 1)
    }

    func testWorkspaceCommandsRoundTrip() {
        XCTAssertEqual(Command(name: "workspace-3"), .workspace(3))
        XCTAssertEqual(Command(name: "move-to-workspace-9"), .moveToWorkspace(9))
        XCTAssertNil(Command(name: "workspace-10"))
        XCTAssertEqual(Config.default.shortcuts(for: .workspace(2)).map(\.description), ["⌃⌘2"])
    }
}

final class LifecycleTests: XCTestCase {
    func testAppPhaseTransitions() {
        // Every (phase, trusted) pair: where it goes and what the app must do.
        let table: [(AppPhase, Bool, AppPhase, AppPhase.Effect)] = [
            (.launching, false, .needsPermission, .none),
            (.launching, true, .running, .start),
            (.needsPermission, false, .needsPermission, .none),
            (.needsPermission, true, .running, .start),
            (.running, true, .running, .none),
            (.running, false, .permissionLost, .pause),
            (.permissionLost, false, .permissionLost, .none),
            (.permissionLost, true, .running, .resume), // switched back on: resumes, never starts twice
        ]
        XCTAssertEqual(table.count, AppPhase.allCases.count * 2)
        for (from, trusted, to, effect) in table {
            let result = from.next(trusted: trusted)
            XCTAssertEqual(result.phase, to, "\(from) trusted=\(trusted)")
            XCTAssertEqual(result.effect, effect, "\(from) trusted=\(trusted)")
        }
        XCTAssertFalse(AppPhase.needsPermission.hasStarted)
        XCTAssertTrue(AppPhase.permissionLost.hasStarted)
    }

    func testUpdatePhaseNeverInterruptsADownload() {
        XCTAssertFalse(UpdatePhase.checking.canCheck)
        XCTAssertFalse(UpdatePhase.downloading(version: "1.0").canCheck)
        XCTAssertFalse(UpdatePhase.installing(version: "1.0").canCheck)
        XCTAssertTrue(UpdatePhase.failed(version: "1.0").canCheck)
        // Install is offered when available, and again after a failure; never mid-download.
        XCTAssertEqual(UpdatePhase.available(version: "1.0").installable, "1.0")
        XCTAssertEqual(UpdatePhase.failed(version: "1.0").installable, "1.0")
        XCTAssertNil(UpdatePhase.downloading(version: "1.0").installable)
        XCTAssertNil(UpdatePhase.upToDate.installable)
    }

    func testUpdateCheckResult() {
        XCTAssertEqual(UpdatePhase.checked(latest: "0.10.0", current: "0.9.2"), .available(version: "0.10.0"))
        XCTAssertEqual(UpdatePhase.checked(latest: "0.6.0", current: "0.6.0"), .upToDate)
        XCTAssertEqual(UpdatePhase.checked(latest: nil, current: "0.6.0"), .offline)
    }

    func testStatusSnapshotExplainsProblemsAndRoundTrips() throws {
        func snapshot(_ phase: AppPhase, enabled: Bool = true, error: String? = nil) -> StatusSnapshot {
            StatusSnapshot(version: "0.7.0", pid: 42, phase: phase, tilingEnabled: enabled, update: .upToDate,
                           configError: error, displays: [.init(name: "LG", layout: .dwindle, workspace: 2, workspaces: [1, 2], windows: 3)])
        }
        XCTAssertNil(snapshot(.running).problem)
        XCTAssertTrue(snapshot(.needsPermission).problem?.contains("Accessibility") == true)
        XCTAssertTrue(snapshot(.permissionLost).problem?.contains("Accessibility") == true)
        XCTAssertTrue(snapshot(.running, enabled: false).problem?.contains("⌃⌥T") == true)
        XCTAssertTrue(snapshot(.running, error: "Invalid JSON").problem?.contains("Invalid JSON") == true)

        let original = snapshot(.running)
        let decoded = try JSONDecoder().decode(StatusSnapshot.self, from: original.encoded())
        XCTAssertEqual(decoded, original)
        let text = String(decoding: try original.encoded(), as: UTF8.self)
        XCTAssertTrue(text.contains("\"phase\" : \"running\""))
    }
}
