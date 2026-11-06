/// Every tiling layout Tiles can arrange windows in.
public enum LayoutKind: String, Codable, CaseIterable {
    /// Recursive binary split that follows the longer side (a.k.a. dwindle / BSP).
    case dwindle
    /// One or more master windows on the left, the rest stacked on the right.
    case masterStack = "master-stack"
    /// Master windows on top, the rest side by side underneath.
    case wideMaster = "wide-master"
    /// Master in the middle, stacks on both sides. Built for ultrawide displays.
    case centeredMaster = "centered-master"
    /// Equal-width columns.
    case columns
    /// Two thirds + one third; from three windows on, the right third stacks.
    case thirds
    /// Equal-height rows.
    case rows
    /// Even grid.
    case grid
    /// Every window fills the screen; cycle focus to switch.
    case monocle
    /// Windows in a row wider than the screen, each at its own width; the screen scrolls to the focused one.
    case scrolling
    /// Tiles leaves this display alone.
    case float

    public var displayName: String {
        switch self {
        case .dwindle: return "Dwindle"
        case .masterStack: return "Master & Stack"
        case .wideMaster: return "Wide Master"
        case .centeredMaster: return "Centered Master (Ultrawide)"
        case .columns: return "Columns"
        case .thirds: return "Thirds"
        case .rows: return "Rows"
        case .grid: return "Grid"
        case .monocle: return "Monocle"
        case .scrolling: return "Scrolling"
        case .float: return "Float (Off)"
        }
    }
}

public struct LayoutParameters: Equatable, Codable {
    /// Gap between neighbouring windows, in points.
    public var innerGap: Double
    /// Gap between windows and the screen edge, in points.
    public var outerGap: Double
    /// Share of the screen the master area takes (0.1 – 0.9).
    public var masterRatio: Double
    /// Number of windows in the master area.
    public var masterCount: Int
    /// On displays wider than this aspect ratio, a lone window is centred
    /// instead of stretched edge to edge. Set to 0 to disable.
    public var ultrawideAspectRatio: Double
    /// Width share a lone window gets on an ultrawide display.
    public var ultrawideSingleWindowRatio: Double
    /// No tile gets wider than this, so nothing stretches across a 49" screen.
    /// Wider tiles are centred in their slot. 0 turns the cap off.
    public var maxTileWidth: Double
    /// Most tiles per display. Further windows stack on the last tile.
    /// 0 picks a number from the display's size.
    public var maxTiles: Int
    /// Scrolling layout: width of a new window, as a share of the screen.
    public var scrollWidth: Double

    public init(
        innerGap: Double = 8,
        outerGap: Double = 8,
        masterRatio: Double = 0.55,
        masterCount: Int = 1,
        ultrawideAspectRatio: Double = 2.0,
        ultrawideSingleWindowRatio: Double = 0.6,
        maxTileWidth: Double = 2600,
        maxTiles: Int = 0,
        scrollWidth: Double = 0.5
    ) {
        self.innerGap = innerGap
        self.outerGap = outerGap
        self.masterRatio = masterRatio
        self.masterCount = masterCount
        self.ultrawideAspectRatio = ultrawideAspectRatio
        self.ultrawideSingleWindowRatio = ultrawideSingleWindowRatio
        self.maxTileWidth = maxTileWidth
        self.maxTiles = maxTiles
        self.scrollWidth = scrollWidth
    }

    public static let `default` = LayoutParameters()
}

public enum LayoutEngine {
    /// Computes one frame per window, in window order, inside `area` (the
    /// display's visible frame). Returns an empty array for `.float`.
    public static func frames(count total: Int, in area: Rect, kind: LayoutKind, parameters p: LayoutParameters = .default) -> [Rect] {
        guard total > 0, kind != .float else { return [] }
        let usable = area.inset(by: max(0, p.outerGap))
        let gap = max(0, p.innerGap)
        let ratio = p.masterRatio.clamped(to: 0.1...0.9)
        let masterCount = max(1, p.masterCount)

        // Ultrawide: a single window is centred rather than stretched.
        if total == 1, kind != .monocle, isUltrawide(usable, p) {
            return [cap(centered(in: usable, widthRatio: p.ultrawideSingleWindowRatio), p.maxTileWidth).integral]
        }

        // Scrolling never runs out of room. Previews show every window at the default width.
        if kind == .scrolling {
            return ScrollingLayout.layout(widths: Array(repeating: p.scrollWidth, count: total), in: area,
                                          parameters: p, focused: 0, offset: 0).frames
        }

        // Screen full: extra windows stack on the last tile instead of shrinking everything.
        let count = kind == .monocle ? total : min(total, maxTiles(in: usable, p))
        let overflow = total - count

        let frames: [Rect]
        switch kind {
        case .dwindle:
            frames = dwindle(count: count, in: usable, gap: gap, firstRatio: ratio)
        case .masterStack:
            frames = masterStack(count: count, in: usable, gap: gap, ratio: ratio, masterCount: masterCount, vertical: false)
        case .wideMaster:
            frames = masterStack(count: count, in: usable, gap: gap, ratio: ratio, masterCount: masterCount, vertical: true)
        case .centeredMaster:
            frames = centeredMaster(count: count, in: usable, gap: gap, ratio: ratio, masterCount: masterCount)
        case .columns:
            frames = usable.columns(count, gap: gap)
        case .thirds:
            frames = thirds(count: count, in: usable, gap: gap)
        case .rows:
            frames = usable.rows(count, gap: gap)
        case .grid:
            frames = grid(count: count, in: usable, gap: gap)
        case .monocle:
            frames = Array(repeating: usable, count: count)
        case .scrolling:
            frames = []
        case .float:
            frames = []
        }
        let capped = frames.map { cap($0, p.maxTileWidth) }
        return (capped + Array(repeating: capped[capped.count - 1], count: overflow)).map(\.integral)
    }

    public static func maxTiles(in area: Rect, _ p: LayoutParameters) -> Int {
        if p.maxTiles > 0 { return p.maxTiles }
        // ~600x420pt minimum per tile: 4 on a laptop, 12 on a 27", 24 on a 49".
        return max(2, Int(area.width / 600)) * max(1, Int(area.height / 420))
    }

    static func cap(_ r: Rect, _ maxWidth: Double) -> Rect {
        guard maxWidth > 0, r.width > maxWidth else { return r }
        return Rect(x: r.x + (r.width - maxWidth) / 2, y: r.y, width: maxWidth, height: r.height)
    }

    static func thirds(count: Int, in area: Rect, gap: Double) -> [Rect] {
        if count == 1 { return [area] }
        if count == 2 {
            let (a, b) = area.splitColumns(ratio: 2.0 / 3, gap: gap)
            return [a, b]
        }
        let cols = area.columns(3, gap: gap)
        return [cols[0], cols[1]] + cols[2].rows(count - 2, gap: gap)
    }

    static func isUltrawide(_ area: Rect, _ p: LayoutParameters) -> Bool {
        guard p.ultrawideAspectRatio > 0, area.height > 0 else { return false }
        return area.width / area.height >= p.ultrawideAspectRatio
    }

    static func centered(in area: Rect, widthRatio: Double) -> Rect {
        let w = (area.width * widthRatio.clamped(to: 0.2...1)).rounded()
        return Rect(x: area.x + (area.width - w) / 2, y: area.y, width: w, height: area.height)
    }

    static func dwindle(count: Int, in area: Rect, gap: Double, firstRatio: Double) -> [Rect] {
        var result: [Rect] = []
        var remaining = area
        for i in 0..<count {
            if i == count - 1 {
                result.append(remaining)
                break
            }
            let ratio = i == 0 ? firstRatio : 0.5
            if remaining.width >= remaining.height {
                let (a, b) = remaining.splitColumns(ratio: ratio, gap: gap)
                result.append(a)
                remaining = b
            } else {
                let (a, b) = remaining.splitRows(ratio: ratio, gap: gap)
                result.append(a)
                remaining = b
            }
        }
        return result
    }

    static func masterStack(count: Int, in area: Rect, gap: Double, ratio: Double, masterCount: Int, vertical: Bool) -> [Rect] {
        if count <= masterCount {
            return vertical ? area.columns(count, gap: gap) : area.rows(count, gap: gap)
        }
        if vertical {
            let (top, bottom) = area.splitRows(ratio: ratio, gap: gap)
            return top.columns(masterCount, gap: gap) + bottom.columns(count - masterCount, gap: gap)
        } else {
            let (left, right) = area.splitColumns(ratio: ratio, gap: gap)
            return left.rows(masterCount, gap: gap) + right.rows(count - masterCount, gap: gap)
        }
    }

    static func centeredMaster(count: Int, in area: Rect, gap: Double, ratio: Double, masterCount: Int) -> [Rect] {
        if count <= masterCount {
            return area.rows(count, gap: gap)
        }
        let stackCount = count - masterCount
        if stackCount == 1 {
            // Two-pane: master left, one stack on the right.
            let (left, right) = area.splitColumns(ratio: ratio, gap: gap)
            return left.rows(masterCount, gap: gap) + [right]
        }
        // Master centred, stacks on both sides.
        let masterW = ((area.width - 2 * gap) * ratio).rounded()
        let sideW = ((area.width - 2 * gap - masterW) / 2).rounded()
        let leftCol = Rect(x: area.x, y: area.y, width: sideW, height: area.height)
        let master = Rect(x: leftCol.maxX + gap, y: area.y, width: masterW, height: area.height)
        let rightCol = Rect(x: master.maxX + gap, y: area.y, width: area.maxX - master.maxX - gap, height: area.height)

        // Alternate stack windows: right, left, right, left...
        let rightCount = (stackCount + 1) / 2
        let leftCount = stackCount / 2
        let rights = rightCol.rows(rightCount, gap: gap)
        let lefts = leftCol.rows(leftCount, gap: gap)
        var stack: [Rect] = []
        for i in 0..<stackCount {
            stack.append(i % 2 == 0 ? rights[i / 2] : lefts[i / 2])
        }
        return master.rows(masterCount, gap: gap) + stack
    }

    static func grid(count: Int, in area: Rect, gap: Double) -> [Rect] {
        let side = Int(Double(count).squareRoot().rounded(.up))
        // Landscape: fewer rows than columns. Portrait: the other way round.
        let rowCount = area.width >= area.height ? (count + side - 1) / side : side
        var remaining = count
        var result: [Rect] = []
        for (i, row) in area.rows(rowCount, gap: gap).enumerated() {
            let rowsLeft = rowCount - i
            let inRow = (remaining + rowsLeft - 1) / rowsLeft
            result += row.columns(inRow, gap: gap)
            remaining -= inRow
        }
        return result
    }
}
