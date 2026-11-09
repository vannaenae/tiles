/// Virtual workspaces: each display shows one numbered set of windows at a time.
/// Windows on the other workspaces wait just off screen, so switching is instant
/// and works without turning off System Integrity Protection.
public struct Workspaces: Equatable {
    public static let numbers = Array(1...9)

    /// Display → the workspace it shows. Missing means 1.
    public private(set) var active: [String: Int] = [:]
    /// Window → its workspace. Missing means "whatever its display shows".
    public private(set) var assigned: [UInt32: Int] = [:]
    /// Window → the display its workspace number belongs to.
    private var home: [UInt32: String] = [:]

    public init() {}

    public func active(on display: String) -> Int { active[display] ?? 1 }

    public func workspace(of window: UInt32, on display: String) -> Int {
        assigned[window] ?? active(on: display)
    }

    public func isShown(_ window: UInt32, on display: String) -> Bool {
        workspace(of: window, on: display) == active(on: display)
    }

    /// New windows join the workspace their display is showing. So does a window that
    /// arrives from another display (dragged over, or its monitor unplugged): workspace 2 of
    /// the LG means nothing on the laptop, and it must not land there hidden.
    public mutating func adopt(_ window: UInt32, on display: String) {
        guard assigned[window] == nil || home[window] != display else { return }
        assigned[window] = active(on: display)
        home[window] = display
    }

    public mutating func show(_ number: Int, on display: String) {
        active[display] = number
    }

    public mutating func move(_ window: UInt32, to number: Int) {
        assigned[window] = number
    }

    /// Drops windows that closed.
    public mutating func keep(only windows: Set<UInt32>) {
        assigned = assigned.filter { windows.contains($0.key) }
        home = home.filter { windows.contains($0.key) }
    }

    /// Workspaces holding at least one of `windows`, plus the one showing, in order.
    public func occupied(by windows: [UInt32], on display: String) -> [Int] {
        Set(windows.map { workspace(of: $0, on: display) } + [active(on: display)]).sorted()
    }
}
