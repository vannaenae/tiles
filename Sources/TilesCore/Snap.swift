/// Snap mode: drag a window to a screen edge or corner and it fills that part of the screen.
public enum SnapZone: String, CaseIterable {
    case left, right, full, topLeft, topRight, bottomLeft, bottomRight

    /// How close to the edge the pointer has to be, in points.
    public static let edge: Double = 14
    /// How far along an edge counts as its corner, in points.
    public static let corner: Double = 90

    /// The zone under the pointer, or nil away from the edges.
    /// - Parameters:
    ///   - screen: the whole display, where the pointer can travel (top-left coordinates).
    ///   - skipLeft / skipRight: another display touches that side, so the pointer passes through it.
    public static func zone(atX x: Double, y: Double, screen: Rect, skipLeft: Bool = false, skipRight: Bool = false) -> SnapZone? {
        guard screen.contains(x: x, y: y) || (x >= screen.minX - 1 && x <= screen.maxX + 1 && y >= screen.minY - 1 && y <= screen.maxY + 1) else { return nil }
        let atLeft = !skipLeft && x <= screen.minX + edge
        let atRight = !skipRight && x >= screen.maxX - edge
        let atTop = y <= screen.minY + edge
        let atBottom = y >= screen.maxY - edge
        let nearTop = y <= screen.minY + corner
        let nearBottom = y >= screen.maxY - corner
        let nearLeft = x <= screen.minX + corner
        let nearRight = x >= screen.maxX - corner

        if (atLeft && nearTop) || (atTop && nearLeft && !skipLeft) { return .topLeft }
        if (atRight && nearTop) || (atTop && nearRight && !skipRight) { return .topRight }
        if (atLeft && nearBottom) || (atBottom && nearLeft && !skipLeft) { return .bottomLeft }
        if (atRight && nearBottom) || (atBottom && nearRight && !skipRight) { return .bottomRight }
        if atLeft { return .left }
        if atRight { return .right }
        if atTop { return .full }
        return nil
    }

    /// Where a window snapped to this zone goes, inside the display's usable `area`.
    public func frame(in area: Rect, parameters p: LayoutParameters) -> Rect {
        let usable = area.inset(by: max(0, p.outerGap))
        let gap = max(0, p.innerGap)
        let (l, r) = usable.splitColumns(ratio: 0.5, gap: gap)
        switch self {
        case .full: return usable.integral
        case .left: return l.integral
        case .right: return r.integral
        case .topLeft: return l.splitRows(ratio: 0.5, gap: gap).0.integral
        case .bottomLeft: return l.splitRows(ratio: 0.5, gap: gap).1.integral
        case .topRight: return r.splitRows(ratio: 0.5, gap: gap).0.integral
        case .bottomRight: return r.splitRows(ratio: 0.5, gap: gap).1.integral
        }
    }
}

/// The window finder: type a few letters, get the matching windows, best first.
public enum WindowSearch {
    public struct Item: Equatable {
        public var id: UInt32
        public var app: String
        public var title: String

        public init(id: UInt32, app: String, title: String) {
            self.id = id
            self.app = app
            self.title = title
        }
    }

    /// Every word typed must appear in the app name or title. Windows whose app name starts
    /// with the query come first, then other app-name matches, then title matches; ties keep their order.
    public static func rank(_ query: String, in items: [Item]) -> [Item] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return items }
        func score(_ item: Item) -> Int? {
            let app = item.app.lowercased(), title = item.title.lowercased()
            guard words.allSatisfy({ app.contains($0) || title.contains($0) }) else { return nil }
            if app.hasPrefix(words[0]) { return 0 }
            if app.contains(words[0]) { return 1 }
            return 2
        }
        return items.enumerated()
            .compactMap { index, item in score(item).map { (score: $0, index: index, item: item) } }
            .sorted { ($0.score, $0.index) < ($1.score, $1.index) }
            .map(\.item)
    }
}
