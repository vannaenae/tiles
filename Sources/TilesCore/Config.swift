import Foundation

/// Where a newly opened window is placed in the tiling order.
public enum NewWindowPlacement: String, Codable, CaseIterable {
    /// At the end of the stack (least prominent).
    case end
    /// Becomes the master window.
    case master
    /// Right after the currently focused window.
    case afterFocused = "after-focused"
}

/// Colour theme for the app and the focus outline.
public enum Theme: String, Codable, CaseIterable {
    case orange, blue, green, purple, pink

    public var hex: String {
        switch self {
        case .orange: return "#E8643C"
        case .blue: return "#3478F6"
        case .green: return "#30A46C"
        case .purple: return "#8E5CF7"
        case .pink: return "#E84393"
        }
    }

    public var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// Light, dark, or follow macOS.
public enum AppearanceMode: String, Codable, CaseIterable {
    case system, light, dark
}

/// A rule that matches windows by app and, optionally, title.
public struct WindowRule: Codable, Equatable {
    /// Bundle identifier (`com.apple.Safari`) or app name (`Safari`). Case-insensitive.
    public var app: String?
    /// Matches when the window title contains this text. Case-insensitive.
    public var titleContains: String?
    /// `true` keeps matching windows floating (never tiled).
    public var float: Bool?

    public init(app: String? = nil, titleContains: String? = nil, float: Bool? = nil) {
        self.app = app
        self.titleContains = titleContains
        self.float = float
    }

    public func matches(bundleID: String?, appName: String?, title: String?) -> Bool {
        if let app = app?.lowercased(), !app.isEmpty {
            let bid = bundleID?.lowercased()
            let name = appName?.lowercased()
            guard app == bid || app == name else { return false }
        }
        if let needle = titleContains?.lowercased(), !needle.isEmpty {
            guard let title = title?.lowercased(), title.contains(needle) else { return false }
        }
        return app != nil || titleContains != nil
    }
}

public struct Config: Codable, Equatable {
    /// Master switch. When false, Tiles leaves every window alone.
    public var enabled: Bool
    /// Layout used on displays without a more specific setting.
    public var defaultLayout: LayoutKind
    /// Layout used automatically on ultrawide displays (aspect ratio at or
    /// above `layout.ultrawideAspectRatio`).
    public var ultrawideLayout: LayoutKind
    /// Per-display layouts, keyed by part of the display's name (e.g. `"LG"`, `"Built-in"`).
    public var displays: [String: LayoutKind]
    public var layout: LayoutParameters
    public var newWindowPlacement: NewWindowPlacement
    /// Drag a tiled window onto another to swap them.
    public var dragToSwap: Bool
    /// Resize the master window with the mouse to change the master ratio.
    public var resizeToAdjustRatio: Bool
    /// Remember the arrangement for each set of displays and bring it back when that set reappears.
    public var autoRestoreScenes: Bool
    /// Move the mouse pointer to the centre of a window focused with the keyboard.
    public var mouseFollowsFocus: Bool
    /// Border drawn around the focused tiled window, as `#RRGGBB`. Empty turns it off.
    public var outlineColor: String
    public var theme: Theme
    public var appearance: AppearanceMode
    public var rules: [WindowRule]
    /// Shortcut → command name. Merged on top of the defaults; map a shortcut
    /// to `"none"` to remove a default binding.
    public var hotkeys: [String: String]

    public init(
        enabled: Bool = true,
        defaultLayout: LayoutKind = .dwindle,
        ultrawideLayout: LayoutKind = .centeredMaster,
        displays: [String: LayoutKind] = [:],
        layout: LayoutParameters = .default,
        newWindowPlacement: NewWindowPlacement = .end,
        dragToSwap: Bool = true,
        resizeToAdjustRatio: Bool = true,
        autoRestoreScenes: Bool = true,
        mouseFollowsFocus: Bool = false,
        outlineColor: String = "#E8643C",
        theme: Theme = .orange,
        appearance: AppearanceMode = .system,
        rules: [WindowRule] = Config.defaultRules,
        hotkeys: [String: String] = [:]
    ) {
        self.enabled = enabled
        self.defaultLayout = defaultLayout
        self.ultrawideLayout = ultrawideLayout
        self.displays = displays
        self.layout = layout
        self.newWindowPlacement = newWindowPlacement
        self.dragToSwap = dragToSwap
        self.resizeToAdjustRatio = resizeToAdjustRatio
        self.autoRestoreScenes = autoRestoreScenes
        self.mouseFollowsFocus = mouseFollowsFocus
        self.outlineColor = outlineColor
        self.theme = theme
        self.appearance = appearance
        self.rules = rules
        self.hotkeys = hotkeys
    }

    public static let `default` = Config()

    /// Apps that are almost always better left floating.
    public static let defaultRules: [WindowRule] = [
        WindowRule(app: "com.apple.systempreferences", float: true),
        WindowRule(app: "com.apple.calculator", float: true),
        WindowRule(app: "com.apple.FaceTime", float: true),
        WindowRule(app: "com.apple.ScreenContinuity", float: true),
        WindowRule(app: "com.apple.PhotoBooth", float: true),
        WindowRule(app: "com.apple.archiveutility", float: true),
        WindowRule(app: "com.apple.Stickies", float: true),
    ]

    /// Built-in bindings. All use ⌃⌥ (control + option) so they rarely clash with apps.
    public static let defaultHotkeys: [String: String] = [
        "ctrl+alt+h": "focus-left", "ctrl+alt+j": "focus-down",
        "ctrl+alt+k": "focus-up", "ctrl+alt+l": "focus-right",
        "ctrl+alt+left": "focus-left", "ctrl+alt+down": "focus-down",
        "ctrl+alt+up": "focus-up", "ctrl+alt+right": "focus-right",
        "ctrl+alt+shift+h": "swap-left", "ctrl+alt+shift+j": "swap-down",
        "ctrl+alt+shift+k": "swap-up", "ctrl+alt+shift+l": "swap-right",
        "ctrl+alt+shift+left": "swap-left", "ctrl+alt+shift+down": "swap-down",
        "ctrl+alt+shift+up": "swap-up", "ctrl+alt+shift+right": "swap-right",
        "ctrl+alt+return": "promote",
        "ctrl+alt+space": "next-layout", "ctrl+alt+shift+space": "previous-layout",
        "ctrl+alt+1": "layout-dwindle", "ctrl+alt+2": "layout-master-stack",
        "ctrl+alt+3": "layout-centered-master", "ctrl+alt+4": "layout-columns",
        "ctrl+alt+5": "layout-grid", "ctrl+alt+6": "layout-monocle",
        "ctrl+alt+7": "layout-wide-master", "ctrl+alt+8": "layout-rows",
        "ctrl+alt+9": "layout-thirds",
        "ctrl+alt+0": "layout-float",
        "ctrl+alt+=": "grow-master", "ctrl+alt+-": "shrink-master",
        "ctrl+alt+,": "increase-master-count", "ctrl+alt+.": "decrease-master-count",
        "ctrl+alt+shift+=": "increase-gaps", "ctrl+alt+shift+-": "decrease-gaps",
        "ctrl+alt+f": "toggle-float", "ctrl+alt+m": "toggle-zoom", "ctrl+alt+t": "toggle-tiling",
        "ctrl+alt+r": "retile",
        "ctrl+alt+n": "focus-next", "ctrl+alt+p": "focus-previous",
        "ctrl+alt+]": "move-to-next-display", "ctrl+alt+[": "move-to-previous-display",
        "ctrl+alt+s": "save-scene", "ctrl+alt+z": "undo-restore",
    ]

    enum CodingKeys: String, CodingKey {
        case enabled, defaultLayout, ultrawideLayout, displays, layout, newWindowPlacement
        case dragToSwap, resizeToAdjustRatio, autoRestoreScenes, mouseFollowsFocus, outlineColor, theme, appearance, rules, hotkeys
    }

    /// Every key is optional so a config file only needs the settings it changes.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.default
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        defaultLayout = try c.decodeIfPresent(LayoutKind.self, forKey: .defaultLayout) ?? d.defaultLayout
        ultrawideLayout = try c.decodeIfPresent(LayoutKind.self, forKey: .ultrawideLayout) ?? d.ultrawideLayout
        displays = try c.decodeIfPresent([String: LayoutKind].self, forKey: .displays) ?? d.displays
        layout = try c.decodeIfPresent(PartialLayoutParameters.self, forKey: .layout)?.resolved ?? d.layout
        newWindowPlacement = try c.decodeIfPresent(NewWindowPlacement.self, forKey: .newWindowPlacement) ?? d.newWindowPlacement
        dragToSwap = try c.decodeIfPresent(Bool.self, forKey: .dragToSwap) ?? d.dragToSwap
        resizeToAdjustRatio = try c.decodeIfPresent(Bool.self, forKey: .resizeToAdjustRatio) ?? d.resizeToAdjustRatio
        autoRestoreScenes = try c.decodeIfPresent(Bool.self, forKey: .autoRestoreScenes) ?? d.autoRestoreScenes
        mouseFollowsFocus = try c.decodeIfPresent(Bool.self, forKey: .mouseFollowsFocus) ?? d.mouseFollowsFocus
        outlineColor = try c.decodeIfPresent(String.self, forKey: .outlineColor) ?? d.outlineColor
        theme = try c.decodeIfPresent(Theme.self, forKey: .theme) ?? d.theme
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? d.appearance
        rules = try c.decodeIfPresent([WindowRule].self, forKey: .rules) ?? d.rules
        hotkeys = try c.decodeIfPresent([String: String].self, forKey: .hotkeys) ?? d.hotkeys
    }

    public static func decode(_ data: Data) throws -> Config {
        try JSONDecoder().decode(Config.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Layout for a display, by explicit name match, then ultrawide detection, then the default.
    public func layoutKind(forDisplayNamed name: String, aspectRatio: Double) -> LayoutKind {
        let lowered = name.lowercased()
        // Longest match wins so "LG UltraFine" beats "LG".
        if let match = displays
            .filter({ !$0.key.isEmpty && lowered.contains($0.key.lowercased()) })
            .max(by: { $0.key.count < $1.key.count }) {
            return match.value
        }
        if layout.ultrawideAspectRatio > 0, aspectRatio >= layout.ultrawideAspectRatio {
            return ultrawideLayout
        }
        return defaultLayout
    }

    /// Whether a window should float. The last matching rule wins.
    public func shouldFloat(bundleID: String?, appName: String?, title: String?) -> Bool {
        var result = false
        for rule in rules where rule.matches(bundleID: bundleID, appName: appName, title: title) {
            if let f = rule.float { result = f }
        }
        return result
    }

    public struct HotkeyBinding: Equatable {
        public var shortcut: Shortcut
        public var command: Command
    }

    /// Defaults merged with user overrides, parsed. Invalid entries are reported, not fatal.
    public func resolvedHotkeys() -> (bindings: [HotkeyBinding], errors: [String]) {
        var merged = Config.defaultHotkeys
        for (k, v) in hotkeys { merged[k] = v }
        var bindings: [HotkeyBinding] = []
        var errors: [String] = []
        var seen = Set<Shortcut>()
        for (key, value) in merged.sorted(by: { $0.key < $1.key }) {
            let v = value.trimmingCharacters(in: .whitespaces).lowercased()
            if v.isEmpty || v == "none" { continue }
            guard let shortcut = Shortcut(key) else {
                errors.append("Unknown shortcut \"\(key)\"")
                continue
            }
            guard let command = Command(name: v) else {
                errors.append("Unknown command \"\(value)\" for \(key)")
                continue
            }
            guard !seen.contains(shortcut) else { continue }
            seen.insert(shortcut)
            bindings.append(HotkeyBinding(shortcut: shortcut, command: command))
        }
        return (bindings, errors)
    }
}

/// Lets the `layout` section of a config file specify only some fields.
struct PartialLayoutParameters: Decodable {
    var innerGap: Double?
    var outerGap: Double?
    var masterRatio: Double?
    var masterCount: Int?
    var ultrawideAspectRatio: Double?
    var ultrawideSingleWindowRatio: Double?
    var maxTileWidth: Double?
    var maxTiles: Int?

    var resolved: LayoutParameters {
        let d = LayoutParameters.default
        return LayoutParameters(
            innerGap: innerGap ?? d.innerGap,
            outerGap: outerGap ?? d.outerGap,
            masterRatio: masterRatio ?? d.masterRatio,
            masterCount: masterCount ?? d.masterCount,
            ultrawideAspectRatio: ultrawideAspectRatio ?? d.ultrawideAspectRatio,
            ultrawideSingleWindowRatio: ultrawideSingleWindowRatio ?? d.ultrawideSingleWindowRatio,
            maxTileWidth: maxTileWidth ?? d.maxTileWidth,
            maxTiles: maxTiles ?? d.maxTiles
        )
    }
}

extension Shortcut {
    /// Canonical form for the config file, e.g. `ctrl+alt+shift+h`.
    public var configString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("alt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        return (parts + [key]).joined(separator: "+")
    }
}

extension Config {
    public func shortcuts(for command: Command) -> [Shortcut] {
        resolvedHotkeys().bindings.filter { $0.command == command }.map(\.shortcut)
    }

    /// Makes `shortcut` the only binding for `command` (nil clears it).
    /// Whatever else used `shortcut` loses it.
    public mutating func bind(_ shortcut: Shortcut?, to command: Command) {
        let merged = Config.defaultHotkeys.merging(hotkeys) { $1 }
        for (key, value) in merged {
            guard let existing = Shortcut(key), Command(name: value) == command || existing == shortcut else { continue }
            hotkeys[key] = Config.defaultHotkeys[key] != nil ? "none" : nil
        }
        if let shortcut { hotkeys[shortcut.configString] = command.name }
    }
}
