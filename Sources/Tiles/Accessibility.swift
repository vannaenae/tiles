import AppKit
import ApplicationServices
import TilesCore

typealias WindowID = CGWindowID

/// Private but long-stable API used by every macOS window manager (Amethyst,
/// Rectangle, yabai, AeroSpace) to map an AX element to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Clears Tiles' Accessibility entry, then asks again. Fixes the switch showing "on"
    /// for an older build of Tiles while this one is still blocked.
    static func reset() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "io.github.vannaenae.tiles"]
        try? task.run()
        task.waitUntilExit()
        request()
    }

    /// Quits and reopens Tiles. macOS sometimes applies a new permission only after a restart.
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// Adds Tiles to the Accessibility list and opens that settings pane.
    static func request() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    func element(_ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func elements(_ name: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success,
              let array = value as? [AnyObject] else { return [] }
        return array.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    func axValue<T>(_ name: String, type: AXValueType, initial: T) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = initial
        guard AXValueGetValue(value as! AXValue, type, &result) else { return nil }
        return result
    }

    @discardableResult
    func set(_ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, name as CFString, value) == .success
    }

    func isSettable(_ name: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(self, name as CFString, &settable) == .success else { return false }
        return settable.boolValue
    }

    var windowID: WindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(self, &id) == .success, id != 0 else { return nil }
        return id
    }
}

/// A top-level window of a running app, reached through Accessibility.
final class Window {
    let element: AXUIElement
    let id: WindowID
    let pid: pid_t
    let bundleID: String?
    let appName: String?

    init?(element: AXUIElement, app: NSRunningApplication) {
        guard let id = element.windowID else { return nil }
        self.element = element
        self.id = id
        self.pid = app.processIdentifier
        self.bundleID = app.bundleIdentifier
        self.appName = app.localizedName
    }

    var title: String? { element.attribute(kAXTitleAttribute) }
    var role: String? { element.attribute(kAXRoleAttribute) }
    var subrole: String? { element.attribute(kAXSubroleAttribute) }
    var isMinimized: Bool { element.attribute(kAXMinimizedAttribute) ?? false }
    var isFullscreen: Bool { element.attribute("AXFullScreen") ?? false }
    var isMovable: Bool { element.isSettable(kAXPositionAttribute) }
    var isResizable: Bool { element.isSettable(kAXSizeAttribute) }

    /// Frame in top-left-origin global coordinates.
    var frame: CGRect? {
        guard let origin = element.axValue(kAXPositionAttribute, type: .cgPoint, initial: CGPoint.zero),
              let size = element.axValue(kAXSizeAttribute, type: .cgSize, initial: CGSize.zero) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Normal app windows only: no sheets, panels, popovers or palettes.
    var isStandard: Bool {
        role == kAXWindowRole && subrole == kAXStandardWindowSubrole
    }

    func setFrame(_ rect: CGRect) {
        // Size → position → size: the first resize lets the window fit on a
        // smaller display, the second fixes apps that clamp size by position.
        var size = rect.size
        var origin = rect.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size),
              let originValue = AXValueCreate(.cgPoint, &origin) else { return }
        element.set(kAXSizeAttribute, sizeValue)
        element.set(kAXPositionAttribute, originValue)
        element.set(kAXSizeAttribute, sizeValue)
    }

    /// One position and one size call: cheap enough for animation frames.
    func setPositionAndSize(_ rect: CGRect) {
        var size = rect.size
        var origin = rect.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size),
              let originValue = AXValueCreate(.cgPoint, &origin) else { return }
        element.set(kAXPositionAttribute, originValue)
        element.set(kAXSizeAttribute, sizeValue)
    }

    func focus() {
        let app = NSRunningApplication(processIdentifier: pid)
        let appElement = AXUIElementCreateApplication(pid)
        element.set(kAXMainAttribute, kCFBooleanTrue)
        appElement.set(kAXFocusedWindowAttribute, element)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        if #available(macOS 14.0, *) {
            app?.activate()
        } else {
            app?.activate(options: [.activateIgnoringOtherApps])
        }
    }
}

extension NSRunningApplication {
    var axElement: AXUIElement { AXUIElementCreateApplication(processIdentifier) }

    /// Runs `body` with "enhanced user interface" disabled. Chrome, Electron and
    /// some other apps turn it on for VoiceOver, and it makes them animate and
    /// ignore programmatic resizes.
    func withEnhancedUIDisabled(_ body: () -> Void) {
        let app = axElement
        let enhanced: Bool = app.attribute("AXEnhancedUserInterface") ?? false
        if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanFalse) }
        body()
        if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanTrue) }
    }
}

extension CGRect {
    init(_ r: Rect) {
        self.init(x: r.x, y: r.y, width: r.width, height: r.height)
    }

    var tilesRect: Rect {
        Rect(x: Double(origin.x), y: Double(origin.y), width: Double(size.width), height: Double(size.height))
    }
}

/// IDs of windows currently visible on screen (i.e. on the active Space and
/// not minimised or hidden). Needs no Screen Recording permission.
func onScreenWindowIDs() -> Set<WindowID> { Set(onScreenWindowOrder()) }

/// The app window drawn on top at a point (top-left coordinates), whatever app owns it.
func topWindow(atX x: Double, y: Double) -> WindowID? {
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
    for entry in info where (entry[kCGWindowLayer as String] as? Int) == 0 {
        guard let b = entry[kCGWindowBounds as String] as? [String: Double],
              let number = entry[kCGWindowNumber as String] as? Int else { continue }
        if Rect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0).contains(x: x, y: y) {
            return WindowID(number)
        }
    }
    return nil
}

/// Same windows, front to back: the first is the one drawn on top.
func onScreenWindowOrder() -> [WindowID] {
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
    return info.compactMap { entry in
        guard (entry[kCGWindowLayer as String] as? Int) == 0, let number = entry[kCGWindowNumber as String] as? Int else { return nil }
        return WindowID(number)
    }
}
