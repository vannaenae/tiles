/// A rectangle in top-left-origin screen coordinates (the coordinate space the
/// macOS Accessibility API uses). Kept independent of CoreGraphics so the core
/// engine is portable and trivially testable.
public struct Rect: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = Rect(x: 0, y: 0, width: 0, height: 0)

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var area: Double { max(0, width) * max(0, height) }

    /// Shrinks the rect by `amount` on every side. Never produces negative sizes.
    public func inset(by d: Double) -> Rect {
        Rect(x: x + d, y: y + d, width: max(0, width - 2 * d), height: max(0, height - 2 * d))
    }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= minX && px < maxX && py >= minY && py < maxY
    }

    public func intersection(_ other: Rect) -> Rect {
        let x0 = max(minX, other.minX)
        let y0 = max(minY, other.minY)
        let x1 = min(maxX, other.maxX)
        let y1 = min(maxY, other.maxY)
        if x1 <= x0 || y1 <= y0 { return .zero }
        return Rect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Rounds to whole points so windows land on pixel boundaries.
    public var integral: Rect {
        let x0 = x.rounded(), y0 = y.rounded()
        return Rect(x: x0, y: y0, width: (maxX).rounded() - x0, height: (maxY).rounded() - y0)
    }

    /// True when every edge is within `tolerance` points of `other`.
    public func isClose(to other: Rect, tolerance: Double = 2) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }

    /// Splits horizontally (side by side). `ratio` is the share of the left part.
    public func splitColumns(ratio: Double, gap: Double) -> (Rect, Rect) {
        let r = ratio.clamped(to: 0.05...0.95)
        let usable = max(0, width - gap)
        let leftW = (usable * r).rounded()
        let left = Rect(x: x, y: y, width: leftW, height: height)
        let right = Rect(x: x + leftW + gap, y: y, width: usable - leftW, height: height)
        return (left, right)
    }

    /// Splits vertically (stacked). `ratio` is the share of the top part.
    public func splitRows(ratio: Double, gap: Double) -> (Rect, Rect) {
        let r = ratio.clamped(to: 0.05...0.95)
        let usable = max(0, height - gap)
        let topH = (usable * r).rounded()
        let top = Rect(x: x, y: y, width: width, height: topH)
        let bottom = Rect(x: x, y: y + topH + gap, width: width, height: usable - topH)
        return (top, bottom)
    }

    /// Divides into `count` equal columns separated by `gap`.
    public func columns(_ count: Int, gap: Double) -> [Rect] {
        guard count > 0 else { return [] }
        let usable = max(0, width - gap * Double(count - 1))
        var result: [Rect] = []
        var cursor = x
        for i in 0..<count {
            let end = x + (usable * Double(i + 1) / Double(count)).rounded() + gap * Double(i)
            result.append(Rect(x: cursor, y: y, width: end - cursor, height: height))
            cursor = end + gap
        }
        return result
    }

    /// Divides into `count` equal rows separated by `gap`.
    public func rows(_ count: Int, gap: Double) -> [Rect] {
        guard count > 0 else { return [] }
        let usable = max(0, height - gap * Double(count - 1))
        var result: [Rect] = []
        var cursor = y
        for i in 0..<count {
            let end = y + (usable * Double(i + 1) / Double(count)).rounded() + gap * Double(i)
            result.append(Rect(x: x, y: cursor, width: width, height: end - cursor))
            cursor = end + gap
        }
        return result
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

public enum Direction: String, CaseIterable {
    case left, right, up, down
}

public enum Geometry {
    /// Finds the index of the rect that sits nearest to `rects[index]` in `direction`.
    /// Candidates must lie strictly on that side. Rects that overlap on the
    /// perpendicular axis are preferred, then the closest by edge distance.
    public static func neighbor(of index: Int, in rects: [Rect], direction: Direction) -> Int? {
        guard rects.indices.contains(index) else { return nil }
        let source = rects[index]
        var best: (index: Int, score: Double)?

        for (i, candidate) in rects.enumerated() where i != index {
            let primaryGap: Double
            let overlap: Double
            switch direction {
            case .left:
                guard candidate.midX < source.midX, candidate.maxX <= source.minX + 1 || candidate.midX < source.minX else { continue }
                primaryGap = max(0, source.minX - candidate.maxX)
                overlap = min(source.maxY, candidate.maxY) - max(source.minY, candidate.minY)
            case .right:
                guard candidate.midX > source.midX, candidate.minX >= source.maxX - 1 || candidate.midX > source.maxX else { continue }
                primaryGap = max(0, candidate.minX - source.maxX)
                overlap = min(source.maxY, candidate.maxY) - max(source.minY, candidate.minY)
            case .up:
                guard candidate.midY < source.midY, candidate.maxY <= source.minY + 1 || candidate.midY < source.minY else { continue }
                primaryGap = max(0, source.minY - candidate.maxY)
                overlap = min(source.maxX, candidate.maxX) - max(source.minX, candidate.minX)
            case .down:
                guard candidate.midY > source.midY, candidate.minY >= source.maxY - 1 || candidate.midY > source.maxY else { continue }
                primaryGap = max(0, candidate.minY - source.maxY)
                overlap = min(source.maxX, candidate.maxX) - max(source.minX, candidate.minX)
            }
            // Heavily penalise candidates that don't share an edge span with the source.
            let penalty = overlap > 0 ? 0 : 100_000 + abs(overlap)
            // Among overlapping candidates, prefer the one aligned closest to the source's top/left.
            let alignment: Double
            switch direction {
            case .left, .right: alignment = abs(candidate.minY - source.minY) * 0.01
            case .up, .down: alignment = abs(candidate.minX - source.minX) * 0.01
            }
            let score = primaryGap + penalty + alignment
            if best == nil || score < best!.score {
                best = (i, score)
            }
        }
        return best?.index
    }
}
