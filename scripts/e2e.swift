// Drives Tiles like a person would, on a real Mac: real key presses and mouse drags,
// then checks where the windows ended up. Prints PASS/FAIL per check, exits 1 on any FAIL.
// Needs Accessibility (to post input events). Used by .github/workflows/e2e.yml.
import ApplicationServices
import CoreGraphics
import Foundation

struct Win { let id: Int; let owner: String; let pid: pid_t; let frame: CGRect }

func windows() -> [Win] {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { w in
        guard (w[kCGWindowLayer as String] as? Int) == 0,
              let owner = w[kCGWindowOwnerName as String] as? String, ["TextEdit", "Finder"].contains(owner),
              let id = w[kCGWindowNumber as String] as? Int,
              let pid = w[kCGWindowOwnerPID as String] as? Int,
              let b = w[kCGWindowBounds as String] as? [String: Double] else { return nil }
        return Win(id: id, owner: owner, pid: pid_t(pid), frame: CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!))
    }
}

func frames() -> [Int: CGRect] { Dictionary(uniqueKeysWithValues: windows().map { ($0.id, $0.frame) }) }
func settle(_ seconds: Double = 1.5) { Thread.sleep(forTimeInterval: seconds) }

func press(_ key: CGKeyCode, _ flags: CGEventFlags = [.maskControl, .maskAlternate]) {
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
        usleep(40_000)
    }
}

func drag(from a: CGPoint, to b: CGPoint, beforeRelease: () -> Void = {}) {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: a, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(150_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: a, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(150_000)
    for step in 1...20 {
        let t = Double(step) / 20
        let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(25_000)
    }
    usleep(300_000)
    beforeRelease()
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: b, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func tiles(_ command: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = ["-g", "tiles://\(command)"]
    try? p.run()
    p.waitUntilExit()
    settle()
}

var failures = 0
var step = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "PASS" : "FAIL", what)
    if !ok { failures += 1 }
}

/// Screenshot plus window positions after a step, into out/ (picked up by the workflow).
func snapshot(_ name: String) {
    step += 1
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "out/e2e-\(step)-\(name).png"]
    try? p.run()
    p.waitUntilExit()
    print("  windows after \(name):")
    for w in windows() { print("   \(w.owner) #\(w.id) \(Int(w.frame.minX)),\(Int(w.frame.minY)) \(Int(w.frame.width))x\(Int(w.frame.height))") }
}

/// What a title-bar drag does, minus the part the test machine ignores: the mouse button is
/// down while the window moves under the cursor, then it's released over the drop point.
/// (GitHub's machines don't move windows for synthetic title-bar drags; Tiles sees the same events.)
func dragWindow(_ w: Win, to drop: CGPoint, beforeRelease: () -> Void = {}) {
    let grab = titleBar(w)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: grab, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(150_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: grab, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(150_000)
    let app = AXUIElementCreateApplication(w.pid)
    var list: CFTypeRef?
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &list)
    let element = ((list as? [AXUIElement]) ?? []).first { el in
        var pos: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pos)
        var p = CGPoint.zero
        if let pos { AXValueGetValue(pos as! AXValue, .cgPoint, &p) }
        return abs(p.x - w.frame.minX) < 2 && abs(p.y - w.frame.minY) < 2
    }
    for step in 1...10 {
        let t = Double(step) / 10
        let cursor = CGPoint(x: grab.x + (drop.x - grab.x) * t, y: grab.y + (drop.y - grab.y) * t)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: cursor, mouseButton: .left)?.post(tap: .cghidEventTap)
        var origin = CGPoint(x: cursor.x - (grab.x - w.frame.minX), y: cursor.y - (grab.y - w.frame.minY))
        if let element, let value = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        }
        usleep(40_000)
    }
    usleep(300_000)
    beforeRelease()
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: drop, mouseButton: .left)?.post(tap: .cghidEventTap)
}

/// Empty title-bar space just right of the traffic lights: always grabs the window itself.
func titleBar(_ w: Win) -> CGPoint { CGPoint(x: w.frame.minX + 90, y: w.frame.minY + 10) }

// 1. Master & Stack: every window gets its own tile.
tiles("layout-master-stack")
let start = frames()
check(start.count == 4, "4 test windows on screen (found \(start.count))")
check(Set(start.values.map { "\($0)" }).count == start.count, "every window has its own tile")
snapshot("master-stack")

// 2. Real key presses reach Tiles' global shortcuts.
press(49) // ⌃⌥Space: next layout
settle()
check(frames() != start, "⌃⌥Space switches to the next layout")
press(19) // ⌃⌥2: back to Master & Stack
settle()
check(frames() == start, "⌃⌥2 jumps straight to Master & Stack")

// 3. Drag a window's title bar onto another: they swap.
let byX = windows().sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
if byX.count >= 2 {
    // A TextEdit window (plain title bar) dropped onto the main window.
    let mover = byX.last { $0.owner == "TextEdit" } ?? byX[byX.count - 1], target = byX[0]
    print("  dragging \(mover.owner) #\(mover.id) from \(titleBar(mover)) onto \(target.owner) #\(target.id)")
    dragWindow(mover, to: CGPoint(x: target.frame.midX, y: target.frame.midY)) {
        snapshot("mid-drag")
        check(frames()[mover.id].map { abs($0.minX - mover.frame.minX) > 20 } ?? false, "the window follows the mouse while dragging")
    }
    settle(2)
    snapshot("after-drag-swap")
    let now = frames()
    check(now[mover.id].map { abs($0.minX - target.frame.minX) < 4 && abs($0.minY - target.frame.minY) < 4 } ?? false,
          "dragging a window onto another swaps them")
    check(now[target.id].map { abs($0.minX - mover.frame.minX) < 4 } ?? false, "the other window takes its place")
}

// 4. Drag the main window's right edge: the split follows.
tiles("layout-master-stack")
if let master = windows().min(by: { $0.frame.minX < $1.frame.minX }) {
    let edge = CGPoint(x: master.frame.maxX - 1, y: master.frame.midY)
    drag(from: edge, to: CGPoint(x: edge.x + 120, y: edge.y))
    settle(2)
    snapshot("after-edge-drag")
    let grown = frames()[master.id]
    check((grown?.width ?? 0) > master.frame.width + 60, "dragging the main window's edge widens it (\(Int(master.frame.width)) → \(Int(grown?.width ?? 0)))")
    let others = windows().filter { $0.id != master.id }
    check(others.allSatisfy { $0.frame.minX >= (grown?.maxX ?? 0) - 1 }, "the stack moves over to make room")
}

// 5. Scrolling: ⌃⌥W widens the focused window.
tiles("layout-scrolling")
let narrow = frames()
press(13) // ⌃⌥W
settle()
let wide = frames()
check(narrow.contains { id, f in (wide[id]?.width ?? 0) > f.width + 50 }, "⌃⌥W widens a window in Scrolling")
snapshot("scrolling-wider")

tiles("layout-dwindle")
snapshot("back-to-dwindle")
let dwindle = frames()
check(Set(frames().values.map { "\($0)" }).count == 4, "switching back to Dwindle gives every window a tile again")
// 6. Opening the dashboard must not change the layout (it used to trigger a scene restore).
let reopen = Process()
reopen.executableURL = URL(fileURLWithPath: "/usr/bin/open")
reopen.arguments = ["/Applications/Tiles.app"]
try? reopen.run()
reopen.waitUntilExit()
settle(4)
snapshot("dashboard-open")
// A few points of slack: apps with a minimum size (Finder) get nudged by macOS.
let afterOpen = frames()
check(dwindle.allSatisfy { id, f in afterOpen[id].map { abs($0.minX - f.minX) <= 4 && abs($0.minY - f.minY) <= 4 } ?? false },
      "opening the dashboard leaves the layout alone")

press(13, .maskCommand) // ⌘W closes the dashboard so it doesn't cover the windows
settle()

/// Changes ~/.config/tiles/config.json the way a person editing it would; Tiles picks it up within a second.
func editConfig(_ change: (inout [String: Any]) -> Void) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/tiles/config.json")
    var config = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
    change(&config)
    try? JSONSerialization.data(withJSONObject: config).write(to: url)
    settle(2.5)
}

func badges() -> [CGRect] {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { w in
        guard (w[kCGWindowOwnerName as String] as? String) == "Tiles",
              let b = w[kCGWindowBounds as String] as? [String: Double], b["Width"] == 30, b["Height"] == 22 else { return nil }
        return CGRect(x: b["X"]!, y: b["Y"]!, width: 30, height: 22)
    }
}

/// The stacked window drawn on top: the first of them in front-to-back order.
func frontOf(_ ids: Set<Int>) -> Int? { windows().first { ids.contains($0.id) }?.id }

// 7. Stacks: with only 2 tiles allowed, 3 windows share the second tile; its badge flips through them.
editConfig { c in
    var layout = c["layout"] as? [String: Any] ?? [:]
    layout["maxTiles"] = 2
    c["layout"] = layout
}
tiles("layout-columns")
let stacked = Set(Dictionary(grouping: windows(), by: { "\($0.frame)" }).values.first { $0.count > 1 }?.map(\.id) ?? [])
check(stacked.count == 3, "extra windows stack on the last tile (\(stacked.count) stacked)")
let shownBadges = badges()
check(shownBadges.count == 1, "a badge shows on the stacked tile (\(shownBadges.count) badges)")
snapshot("stack-badge")
if let badge = shownBadges.first, let before = frontOf(stacked) {
    let p = CGPoint(x: badge.midX, y: badge.midY)
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(80_000)
    }
    settle()
    check(frontOf(stacked) != before, "clicking the badge brings the next stacked window forward")
}
editConfig { c in
    var layout = c["layout"] as? [String: Any] ?? [:]
    layout["maxTiles"] = 0
    c["layout"] = layout
}
check(badges().isEmpty, "the badge goes away when the windows no longer stack")

// 8. App rule: new TextEdit windows open in the main tile.
tiles("layout-master-stack")
editConfig { c in
    var rules = c["rules"] as? [[String: Any]] ?? []
    rules.append(["app": "TextEdit", "master": true])
    c["rules"] = rules
}
let known = Set(frames().keys)
let doc = FileManager.default.temporaryDirectory.appendingPathComponent("rule-test.txt")
try? "Opened by a rule test".write(to: doc, atomically: true, encoding: .utf8)
let openDoc = Process()
openDoc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
openDoc.arguments = ["-a", "TextEdit", doc.path]
try? openDoc.run()
openDoc.waitUntilExit()
settle(3)
snapshot("app-rule")
let all = windows()
if let fresh = all.first(where: { !known.contains($0.id) }) {
    let leftmost = all.map(\.frame.minX).min() ?? 0
    check(abs(fresh.frame.minX - leftmost) < 2 && fresh.frame.height > 500, "a rule puts the new TextEdit window in the main tile")
} else {
    check(false, "a new TextEdit window opened")
}

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
