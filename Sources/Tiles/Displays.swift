import AppKit
import TilesCore

/// A connected display, with its usable area in Accessibility (top-left origin) coordinates.
struct Display: Equatable {
    /// Stable across reboots and reconnects (the display's UUID).
    let id: String
    let name: String
    /// Visible frame (minus menu bar and Dock) in top-left-origin global coordinates.
    let area: Rect
    let fullFrame: Rect

    var aspectRatio: Double { area.height > 0 ? area.width / area.height : 1 }

    static func current() -> [Display] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let primaryHeight = Double(primary.frame.height)
        return screens.map { screen in
            Display(
                id: screen.stableID,
                name: screen.localizedName,
                area: flip(screen.visibleFrame, primaryHeight: primaryHeight),
                fullFrame: flip(screen.frame, primaryHeight: primaryHeight)
            )
        }
        .sorted { ($0.fullFrame.x, $0.fullFrame.y) < ($1.fullFrame.x, $1.fullFrame.y) }
    }

    /// Converts AppKit's bottom-left-origin rect to the Accessibility API's top-left origin.
    static func flip(_ r: NSRect, primaryHeight: Double) -> Rect {
        Rect(x: Double(r.minX), y: primaryHeight - Double(r.maxY), width: Double(r.width), height: Double(r.height))
    }

    /// The display a window mostly sits on.
    static func best(for frame: Rect, in displays: [Display]) -> Display? {
        let overlaps = displays.map { ($0, $0.fullFrame.intersection(frame).area) }
        if let hit = overlaps.max(by: { $0.1 < $1.1 }), hit.1 > 0 { return hit.0 }
        return display(atX: frame.midX, y: frame.midY, in: displays)
    }

    /// The display containing a point, or the nearest one.
    static func display(atX x: Double, y: Double, in displays: [Display]) -> Display? {
        if let hit = displays.first(where: { $0.fullFrame.contains(x: x, y: y) }) { return hit }
        return displays.min { a, b in
            hypot(a.fullFrame.midX - x, a.fullFrame.midY - y) < hypot(b.fullFrame.midX - x, b.fullFrame.midY - y)
        }
    }

    /// Mouse location in top-left-origin coordinates.
    static func mouseLocation() -> (x: Double, y: Double) {
        let p = NSEvent.mouseLocation
        let primaryHeight = Double(NSScreen.screens.first?.frame.height ?? 0)
        return (Double(p.x), primaryHeight - Double(p.y))
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var stableID: String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) as String? {
            return string
        }
        return "display-\(displayID)"
    }
}
