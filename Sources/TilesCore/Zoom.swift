import Foundation

/// Tabs: when several windows share a tile, a strip along the top names each one.
public enum TabStrips {
    public struct Strip: Equatable {
        /// Where the strip is drawn: the top of the shared tile.
        public let frame: Rect
        /// Indexes (into the frames passed in) of the windows sharing the tile, in the order given.
        public let members: [Int]
    }

    /// Tiles shorter than this many strips keep the plain overlap: there's no room for tabs.
    static let minimumTileHeights = 4.0

    /// Finds frames that coincide (windows sharing a tile), and moves those windows down by
    /// `height` so a tab strip fits above them. Frames that are alone come back unchanged.
    public static func carve(_ frames: [Rect], height: Double) -> (frames: [Rect], strips: [Strip]) {
        guard height > 0 else { return (frames, []) }
        var groups: [[Int]] = []
        for (i, frame) in frames.enumerated() {
            if let g = groups.firstIndex(where: { frames[$0[0]].isClose(to: frame, tolerance: 1) }) {
                groups[g].append(i)
            } else {
                groups.append([i])
            }
        }
        var result = frames
        var strips: [Strip] = []
        for group in groups where group.count > 1 {
            let tile = frames[group[0]]
            guard tile.height >= height * minimumTileHeights else { continue }
            strips.append(Strip(frame: Rect(x: tile.x, y: tile.y, width: tile.width, height: height), members: group))
            for i in group {
                result[i] = Rect(x: tile.x, y: tile.y + height, width: tile.width, height: tile.height - height)
            }
        }
        return (result, strips)
    }
}

/// Nested tiles: the windows sharing a tile, laid out inside it instead of overlapping.
public enum Nesting {
    /// Splits `tile` into `count` equal parts along its longer side.
    public static func frames(count: Int, in tile: Rect, gap: Double) -> [Rect] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [tile] }
        let g = max(0, gap)
        return tile.width >= tile.height ? tile.columns(count, gap: g) : tile.rows(count, gap: g)
    }
}

/// How far in a display is zoomed. Zooming in and out steps along:
/// overview (every window in a grid) ← tiles (the normal layout) → focus (one window fills the display).
public enum ZoomLevel: String, Equatable, CaseIterable {
    case overview, tiles, focus

    /// The next level in that direction. At either end it stays put.
    public func stepped(zoomingIn: Bool) -> ZoomLevel {
        switch (self, zoomingIn) {
        case (.overview, true), (.focus, false): return .tiles
        case (.tiles, true), (.focus, true): return .focus
        case (.tiles, false), (.overview, false): return .overview
        }
    }
}

/// Turns the stream of small magnification changes a trackpad pinch sends into one zoom step
/// per gesture. Time is passed in, so it can be tested without a clock.
public struct PinchGesture: Equatable {
    public enum Zoom: Equatable { case zoomIn, zoomOut }

    /// Total magnification that counts as a deliberate pinch.
    public var threshold: Double
    /// Seconds without an event after which the next one starts a new gesture.
    public var idleGap: Double
    private var total = 0.0
    private var lastTime = -Double.infinity
    private var fired = false

    public init(threshold: Double = 0.18, idleGap: Double = 0.3) {
        self.threshold = threshold
        self.idleGap = idleGap
    }

    /// Feed each magnify event. Returns a zoom step once per gesture, when it passes the threshold.
    /// Spreading two fingers (positive magnification) zooms in; pinching zooms out.
    public mutating func feed(magnification: Double, at time: Double) -> Zoom? {
        if time - lastTime > idleGap {
            total = 0
            fired = false
        }
        lastTime = time
        guard !fired else { return nil }
        total += magnification
        guard abs(total) >= threshold else { return nil }
        fired = true
        return total > 0 ? .zoomIn : .zoomOut
    }
}
