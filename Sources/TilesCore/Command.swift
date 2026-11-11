import Foundation

/// Everything a hotkey, menu item, or `tiles://` URL can ask Tiles to do.
public enum Command: Equatable {
    case focus(Direction)
    case swap(Direction)
    case promote
    case setLayout(LayoutKind)
    case nextLayout
    case previousLayout
    case growMaster
    case shrinkMaster
    case increaseMasterCount
    case decreaseMasterCount
    case toggleFloat
    case toggleTiling
    case retile
    case focusNextWindow
    case focusPreviousWindow
    case moveToNextDisplay
    case moveToPreviousDisplay
    case increaseGaps
    case decreaseGaps
    case saveScene
    case restoreScene
    case undoRestore
    case toggleZoom
    case cycleWidth
    case centerWindow
    /// Show workspace 1–9 on the active display.
    case workspace(Int)
    /// Send the focused window to workspace 1–9 on its display.
    case moveToWorkspace(Int)
    /// Pop up the cheat sheet of everyday shortcuts.
    case showShortcuts
    /// Type a few letters to jump to any window.
    case findWindow
    /// The welcome tour.
    case showTour
    /// Zoom in a level: from the overview to the tiles, from the tiles to one window filling the display.
    case zoomIn
    /// Zoom out a level: from one window to the tiles, from the tiles to an overview of every window.
    case zoomOut
    /// Windows sharing a tile: show them as tabs, or side by side inside the tile.
    case toggleNest

    /// Stable string form used in config files and URLs, e.g. `focus-left`, `layout-columns`.
    public var name: String {
        switch self {
        case .focus(let d): return "focus-\(d.rawValue)"
        case .swap(let d): return "swap-\(d.rawValue)"
        case .promote: return "promote"
        case .setLayout(let k): return "layout-\(k.rawValue)"
        case .nextLayout: return "next-layout"
        case .previousLayout: return "previous-layout"
        case .growMaster: return "grow-master"
        case .shrinkMaster: return "shrink-master"
        case .increaseMasterCount: return "increase-master-count"
        case .decreaseMasterCount: return "decrease-master-count"
        case .toggleFloat: return "toggle-float"
        case .toggleTiling: return "toggle-tiling"
        case .retile: return "retile"
        case .focusNextWindow: return "focus-next"
        case .focusPreviousWindow: return "focus-previous"
        case .moveToNextDisplay: return "move-to-next-display"
        case .moveToPreviousDisplay: return "move-to-previous-display"
        case .increaseGaps: return "increase-gaps"
        case .decreaseGaps: return "decrease-gaps"
        case .saveScene: return "save-scene"
        case .restoreScene: return "restore-scene"
        case .undoRestore: return "undo-restore"
        case .toggleZoom: return "toggle-zoom"
        case .cycleWidth: return "cycle-width"
        case .centerWindow: return "center-window"
        case .workspace(let n): return "workspace-\(n)"
        case .moveToWorkspace(let n): return "move-to-workspace-\(n)"
        case .showShortcuts: return "show-shortcuts"
        case .findWindow: return "find-window"
        case .showTour: return "show-tour"
        case .zoomIn: return "zoom-in"
        case .zoomOut: return "zoom-out"
        case .toggleNest: return "toggle-nest"
        }
    }

    public static let all: [Command] =
        Direction.allCases.map(Command.focus) + Direction.allCases.map(Command.swap)
        + LayoutKind.allCases.map(Command.setLayout) + [
            .promote, .nextLayout, .previousLayout, .growMaster, .shrinkMaster,
            .increaseMasterCount, .decreaseMasterCount, .toggleFloat, .toggleTiling,
            .retile, .focusNextWindow, .focusPreviousWindow, .moveToNextDisplay,
            .moveToPreviousDisplay, .increaseGaps, .decreaseGaps, .saveScene, .restoreScene, .undoRestore, .toggleZoom, .cycleWidth, .centerWindow, .showShortcuts, .findWindow, .showTour, .zoomIn, .zoomOut, .toggleNest,
        ] + Workspaces.numbers.map(Command.workspace) + Workspaces.numbers.map(Command.moveToWorkspace)

    public static var allNames: [String] { all.map(\.name) }

    public init?(name: String) {
        let name = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = Command.all.first(where: { $0.name == name }) else { return nil }
        self = match
    }
}

/// A parsed keyboard shortcut such as `ctrl+alt+left`.
public struct Shortcut: Equatable, Hashable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }

    public var modifiers: Modifiers
    /// Lower-cased key name: a letter, digit, `left`, `return`, `f5`, `=`, ...
    public var key: String

    public init(modifiers: Modifiers, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Parses strings like `ctrl+alt+h`, `cmd+shift+return`, `hyper+1`.
    /// `hyper` means ctrl+alt+cmd+shift; `meh` means ctrl+alt+shift.
    public init?(_ string: String) {
        let parts = string.lowercased()
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last else { return nil }
        // Allow "ctrl+alt++" to mean the plus key.
        var keyPart = last
        var modParts = Array(parts.dropLast())
        if keyPart.isEmpty, modParts.last == "" {
            keyPart = "+"
            modParts.removeLast()
        }
        guard !keyPart.isEmpty, Shortcut.knownKeys.contains(keyPart) else { return nil }

        var mods: Modifiers = []
        for m in modParts {
            switch m {
            case "cmd", "command", "⌘": mods.insert(.command)
            case "alt", "opt", "option", "⌥": mods.insert(.option)
            case "ctrl", "control", "⌃": mods.insert(.control)
            case "shift", "⇧": mods.insert(.shift)
            case "hyper": mods.formUnion([.command, .option, .control, .shift])
            case "meh": mods.formUnion([.option, .control, .shift])
            default: return nil
            }
        }
        guard !mods.isEmpty else { return nil }
        self.modifiers = mods
        self.key = keyPart
    }

    public var description: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        let symbols: [String: String] = [
            "left": "←", "right": "→", "up": "↑", "down": "↓",
            "return": "↩", "space": "Space", "tab": "⇥", "delete": "⌫", "escape": "⎋",
        ]
        return s + (symbols[key] ?? key.uppercased())
    }

    public static let knownKeys: Set<String> = {
        var keys = Set("abcdefghijklmnopqrstuvwxyz0123456789".map(String.init))
        keys.formUnion(["left", "right", "up", "down", "return", "enter", "space", "tab", "delete",
                        "escape", "-", "=", "+", "[", "]", ";", "'", ",", ".", "/", "\\", "`"])
        for i in 1...20 { keys.insert("f\(i)") }
        return keys
    }()
}
