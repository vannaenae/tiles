// Drives Tiles like a person would, on a real Mac: real key presses and mouse drags,
// then checks where the windows ended up. Prints PASS/FAIL per check, exits 1 on any FAIL.
// Needs Accessibility (to post input events). Used by .github/workflows/e2e.yml.
import CoreGraphics
import Foundation

struct Win { let id: Int; let owner: String; let frame: CGRect }

func windows() -> [Win] {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { w in
        guard (w[kCGWindowLayer as String] as? Int) == 0,
              let owner = w[kCGWindowOwnerName as String] as? String, ["TextEdit", "Finder"].contains(owner),
              let id = w[kCGWindowNumber as String] as? Int,
              let b = w[kCGWindowBounds as String] as? [String: Double] else { return nil }
        return Win(id: id, owner: owner, frame: CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!))
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

func drag(from a: CGPoint, to b: CGPoint) {
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
func check(_ ok: Bool, _ what: String) {
    print(ok ? "PASS" : "FAIL", what)
    if !ok { failures += 1 }
}

// 1. Master & Stack: every window gets its own tile.
tiles("layout-master-stack")
let start = frames()
check(start.count == 4, "4 test windows on screen (found \(start.count))")
check(Set(start.values.map { "\($0)" }).count == start.count, "every window has its own tile")

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
    let mover = byX[0], target = byX[byX.count - 1]
    drag(from: CGPoint(x: mover.frame.midX, y: mover.frame.minY + 12), to: CGPoint(x: target.frame.midX, y: target.frame.midY))
    settle(2)
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

tiles("layout-dwindle")
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
