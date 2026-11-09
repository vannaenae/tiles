import Foundation

/// The app's top-level state: has Tiles got Accessibility access, and is it tiling?
/// See STATE_MACHINES.md for every state machine in the app.
public enum AppPhase: String, Codable, Equatable, CaseIterable {
    /// Before the first permission check.
    case launching
    /// No Accessibility access yet. Tiles waits and shows how to grant it.
    case needsPermission
    /// Access granted and tiling started.
    case running
    /// Was running, then access was switched off. Resumes by itself when it's switched back on.
    case permissionLost

    /// What the app has to do on a transition.
    public enum Effect: Equatable {
        case none
        /// First grant: start observing windows.
        case start
        /// Access came back: re-read every window.
        case resume
        /// Access went away: hide the outline and badges, they'd go stale.
        case pause
    }

    /// The phase after a permission check reports `trusted`, and what to do about it.
    public func next(trusted: Bool) -> (phase: AppPhase, effect: Effect) {
        switch (self, trusted) {
        case (.launching, false), (.needsPermission, false): return (.needsPermission, .none)
        case (.launching, true), (.needsPermission, true): return (.running, .start)
        case (.running, true): return (.running, .none)
        case (.running, false): return (.permissionLost, .pause)
        case (.permissionLost, false): return (.permissionLost, .none)
        case (.permissionLost, true): return (.running, .resume)
        }
    }

    /// Tiling has been started at least once (window observers exist).
    public var hasStarted: Bool { self == .running || self == .permissionLost }
}

/// The built-in updater. Only one check or install runs at a time, and a daily check
/// can never interrupt a download.
public enum UpdatePhase: Equatable, Codable {
    case idle
    case checking
    case upToDate
    /// GitHub couldn't be reached. Try again later.
    case offline
    case available(version: String)
    case downloading(version: String)
    /// Download or signature check failed. The same version can be retried.
    case failed(version: String)
    /// Verified; Tiles is quitting so the new copy can replace it.
    case installing(version: String)

    /// A check may start: nothing else is in flight.
    public var canCheck: Bool {
        switch self {
        case .checking, .downloading, .installing: return false
        default: return true
        }
    }

    /// The version an Install button would install, if any.
    public var installable: String? {
        switch self {
        case .available(let v), .failed(let v): return v
        default: return nil
        }
    }

    /// Result of a check: `latest` is the newest release on GitHub, nil if unreachable.
    public static func checked(latest: String?, current: String) -> UpdatePhase {
        guard let latest else { return .offline }
        return Version.isNewer(latest, than: current) ? .available(version: latest) : .upToDate
    }

    /// One line for the Settings window and menu.
    public var message: String {
        switch self {
        case .idle: return ""
        case .checking: return "Checking…"
        case .upToDate: return "Tiles is up to date"
        case .offline: return "Couldn't reach GitHub"
        case .available(let v): return "Tiles \(v) is available"
        case .downloading(let v): return "Downloading Tiles \(v)…"
        case .failed: return "The update couldn't be downloaded or verified"
        case .installing(let v): return "Installing Tiles \(v)…"
        }
    }
}

/// Everything worth knowing about a running Tiles, written to
/// `~/Library/Application Support/Tiles/status.json` and printed by `tiles status`.
/// For people troubleshooting, scripts and AI agents: read this instead of guessing from window positions.
public struct StatusSnapshot: Codable, Equatable {
    public struct DisplayInfo: Codable, Equatable {
        public var name: String
        public var layout: LayoutKind
        public var workspace: Int
        public var workspaces: [Int]
        public var windows: Int

        public init(name: String, layout: LayoutKind, workspace: Int, workspaces: [Int], windows: Int) {
            self.name = name
            self.layout = layout
            self.workspace = workspace
            self.workspaces = workspaces
            self.windows = windows
        }
    }

    public var version: String
    public var pid: Int32
    public var phase: AppPhase
    public var tilingEnabled: Bool
    public var update: UpdatePhase
    public var configError: String?
    public var displays: [DisplayInfo]
    /// Plain-language answer to "why isn't Tiles moving my windows?", or nil when all is well.
    public var problem: String?

    public init(version: String, pid: Int32, phase: AppPhase, tilingEnabled: Bool, update: UpdatePhase,
                configError: String?, displays: [DisplayInfo]) {
        self.version = version
        self.pid = pid
        self.phase = phase
        self.tilingEnabled = tilingEnabled
        self.update = update
        self.configError = configError
        self.displays = displays
        self.problem = Self.problem(phase: phase, tilingEnabled: tilingEnabled, configError: configError)
    }

    static func problem(phase: AppPhase, tilingEnabled: Bool, configError: String?) -> String? {
        switch phase {
        case .launching: return "Tiles is starting."
        case .needsPermission, .permissionLost:
            return "Tiles needs Accessibility access: System Settings → Privacy & Security → Accessibility → switch Tiles on."
        case .running:
            if !tilingEnabled { return "Tiling is switched off. Press ⌃⌥T or use the menu bar icon." }
            if let configError { return "The config file has an error (\(configError)); Tiles is using the last good settings." }
            return nil
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
