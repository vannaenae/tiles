/// Every tiling layout Tiles can arrange windows in.
public enum LayoutKind: String, Codable, CaseIterable, Identifiable {
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
    /// Equal-height rows.
    case rows
    /// Even grid.
    case grid
    /// Every window fills the screen; cycle focus to switch.
    case monocle
    /// Tiles leaves this display alone.
    case float

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dwindle: return "Dwindle"
        case .masterStack: return "Master & Stack"
        case .wideMaster: return "Wide Master"
        case .centeredMaster: return "Centered Master (Ultrawide)"
        case .columns: return "Columns"
        case .rows: return "Rows"
        case .grid: return "Grid"
        case .monocle: return "Monocle"
        case .float: return "Float (Off)"
        }
    }

    /// Whether the master ratio / master count settings change this layout.
    public var usesMaster: Bool {
        switch self {
        case .masterStack, .wideMaster, .centeredMaster, .dwindle: return true
        default: return false
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

    public init(
        innerGap: Double = 8,
        outerGap: Double = 8,
        masterRatio: Double = 0.55,
        masterCount: Int = 1,
        ultrawideAspectRatio: Double = 2.0,
        ultrawideSingleWindowRatio: Double = 0.6
    ) {
        self.innerGap = innerGap
        self.outerGap = outerGap
        self.masterRatio = masterRatio
        self.masterCount = masterCount
        self.ultrawideAspectRatio = ultrawideAspectRatio
        self.ultrawideSingleWindowRatio = ultrawideSingleWindowRatio
    }

    public static let `default` = LayoutParameters()
}

public enum LayoutEngine {
    /// Computes one frame per window, in window order, inside `area` (the
    /// display's visible frame). Returns an empty array for `.float`.
    public static func frames(count: Int, in area: Rect, kind: LayoutKind, parameters p: LayoutParameters = .default) -> [Rect] {
        guard count > 0, kind != .float else { return [] }
        let usable = area.inset(by: max(0, p.outerGap))
        let gap = max(0, p.innerGap)
        let ratio = p.masterRatio.clamped(to: 0.1...0.9)
        let masterCount = max(1, p.masterCount)

        // Ultrawide: a single window is centred rather than stretched.
        if count == 1, kind != .monocle, isUltrawide(usable, p) {
            return [centered(in: usable, widthRatio: p.ultrawideSingleWindowRatio).integral]
        }

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
        case .rows:
            frames = usable.rows(count, gap: gap)
        case .grid:
            frames = grid(count: count, in: usable, gap: gap)
        case .monocle:
            frames = Array(repeating: usable, count: count)
        case .float:
            frames = []
        }
        return frames.map(\.integral)
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
        // Pick the column count that keeps cells closest to the area's aspect.
        let landscape = area.width >= area.height
        var cols = Int(Double(count).squareRoot().rounded(.up))
        var rows = Int((Double(count) / Double(cols)).rounded(.up))
        if !landscape { swap(&cols, &rows) }
        if landscape {
            let rowRects = area.rows(rows, gap: gap)
            var result: [Rect] = []
            var remaining = count
            for (r, row) in rowRects.enumerated() {
                let inRow = r == rowRects.count - 1 ? remaining : min(cols, remaining)
                result += row.columns(inRow, gap: gap)
                remaining -= inRow
            }
            return result
        } else {
            let colRects = area.columns(cols, gap: gap)
            var result: [Rect] = []
            var remaining = count
            for (c, col) in colRects.enumerated() {
                let inCol = c == colRects.count - 1 ? remaining : min(rows, remaining)
                result += col.rows(inCol, gap: gap)
                remaining -= inCol
            }
            return result
        }
    }
}
