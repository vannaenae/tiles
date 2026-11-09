// Types into the frontmost app with real key presses, for scripts/marketing-shots.sh.
//
//   marketing-keys new-window <url>   ⌘N, then type the URL and press Return (Safari: a new window, not a tab)
//   marketing-keys dismiss <app name> clicks through first-run sheets (Continue, Not Now...) by button name
//   marketing-keys hide <app name>    hides the app (like ⌘H), so its windows leave the layout
//
// Needs Accessibility (to post input events and read other apps' buttons).
import AppKit
import ApplicationServices

func post(_ key: CGKeyCode, _ flags: CGEventFlags = []) {
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
        usleep(30_000)
    }
    // Let go of the modifiers so they don't stick to the next key.
    for mod: CGKeyCode in [55, 56, 58, 59] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: mod, keyDown: false)
        e?.flags = []
        e?.post(tap: .cghidEventTap)
    }
    usleep(60_000)
}

func type(_ text: String) {
    for ch in text.utf16 {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
            var c = ch
            e?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            e?.flags = []
            e?.post(tap: .cghidEventTap)
            usleep(12_000)
        }
    }
}

// Buttons that move past a welcome or permissions sheet without signing in or turning anything on.
let skipButtons: Set<String> = ["continue", "not now", "later", "maybe later", "skip", "no thanks", "done", "ok"]

func string(_ e: AXUIElement, _ attribute: String) -> String? {
    var v: CFTypeRef?
    AXUIElementCopyAttributeValue(e, attribute as CFString, &v)
    return v as? String
}

func findSkipButton(in e: AXUIElement, depth: Int = 0) -> AXUIElement? {
    if string(e, kAXRoleAttribute) == kAXButtonRole as String,
       let name = string(e, kAXTitleAttribute) ?? string(e, kAXDescriptionAttribute), skipButtons.contains(name.lowercased()) {
        return e
    }
    guard depth < 12 else { return nil }
    var v: CFTypeRef?
    AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v)
    for child in (v as? [AXUIElement]) ?? [] {
        if let hit = findSkipButton(in: child, depth: depth + 1) { return hit }
    }
    return nil
}

func buttonNames(in e: AXUIElement, depth: Int = 0, into names: inout [String]) {
    if string(e, kAXRoleAttribute) == kAXButtonRole as String,
       let name = string(e, kAXTitleAttribute) ?? string(e, kAXDescriptionAttribute), !name.isEmpty {
        names.append(name)
    }
    guard depth < 12, names.count < 40 else { return }
    var v: CFTypeRef?
    AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v)
    for child in (v as? [AXUIElement]) ?? [] { buttonNames(in: child, depth: depth + 1, into: &names) }
}

func app(named name: String) -> NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first { $0.localizedName == name }
}

/// Sheets can arrive one after another, a few seconds apart, so keep watching until
/// none has shown up for a while.
func dismissSheets(of appName: String) {
    guard let target = app(named: appName) else { print("\(appName) isn't running"); return }
    let root = AXUIElementCreateApplication(target.processIdentifier)
    var quietSince = Date()
    while Date().timeIntervalSince(quietSince) < 8 {
        if let button = findSkipButton(in: root) {
            print("\(appName): pressed \(string(button, kAXTitleAttribute) ?? "button")")
            AXUIElementPerformAction(button, kAXPressAction as CFString)
            quietSince = Date()
        }
        Thread.sleep(forTimeInterval: 1)
    }
    var names: [String] = []
    buttonNames(in: root, into: &names)
    print("\(appName) buttons now: \(names.joined(separator: ", "))")
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "new-window" where args.count == 2:
    post(45, .maskCommand)          // ⌘N
    Thread.sleep(forTimeInterval: 1.5)
    post(37, .maskCommand)          // ⌘L, in case the address bar isn't focused
    Thread.sleep(forTimeInterval: 0.4)
    type(args[args.startIndex + 1])
    post(36)                        // Return
case "dismiss" where args.count == 2:
    dismissSheets(of: args[args.startIndex + 1])
case "hide" where args.count == 2:
    app(named: args[args.startIndex + 1])?.hide()
default:
    FileHandle.standardError.write("usage: marketing-keys new-window <url> | dismiss <app name> | hide <app name>\n".data(using: .utf8)!)
    exit(2)
}
