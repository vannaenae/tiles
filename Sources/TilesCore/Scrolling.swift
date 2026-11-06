/// The Scrolling layout: windows sit left to right in a strip that can be wider
/// than the screen, each at its own width. The screen shows a window of that
/// strip; windows outside it wait at the edge as a thin sliver.
public enum ScrollingLayout {
    /// Widths a window cycles through, as a share of the screen width.
    public static let widthPresets: [Double] = [1.0 / 3, 0.5, 2.0 / 3, 1]
    /// How much of an off-screen window stays visible at the edge, in points.
    public static let sliver: Double = 6

    public struct Result: Equatable {
        public var frames: [Rect]
        /// Where the visible part of the strip starts, in points. Keep it and pass it back next time.
        public var offset: Double
    }

    /// - Parameters:
    ///   - widths: each window's width as a share of the screen width, in strip order.
    ///   - focused: index of the window that must be fully on screen.
    ///   - offset: the previous result's offset, so the strip only scrolls when it has to.
    ///   - hideLeft / hideRight: another display touches that edge, so off-screen windows
    ///     tuck into the bottom corner instead of showing a sliver that would land on it.
    public static func layout(
        widths: [Double],
        in area: Rect,
        parameters p: LayoutParameters,
        focused: Int?,
        offset: Double,
        hideLeft: Bool = false,
        hideRight: Bool = false
    ) -> Result {
        guard !widths.isEmpty else { return Result(frames: [], offset: 0) }
        let view = area.inset(by: max(0, p.outerGap))
        let gap = max(0, p.innerGap)
        let w = widths.map { ($0.clamped(to: 0.1...1) * view.width).rounded() }

        var x: [Double] = []
        var cursor = 0.0
        for width in w {
            x.append(cursor)
            cursor += width + gap
        }
        let total = cursor - gap

        // Scroll just enough to bring the focused window fully into view.
        var off = offset
        if let f = focused, w.indices.contains(f) {
            if x[f] < off { off = x[f] }
            if x[f] + w[f] > off + view.width { off = x[f] + w[f] - view.width }
        }
        off = off.clamped(to: 0...max(0, total - view.width))

        let frames = w.indices.map { i -> Rect in
            let screenX = view.x + x[i] - off
            if screenX >= view.minX - 1, screenX + w[i] <= view.maxX + 1 {
                return Rect(x: screenX, y: view.y, width: w[i], height: view.height)
            }
            // ponytail: corner-hiding assumes no display sits below this one; arrange displays side by side.
            if screenX < view.minX {
                return hideLeft
                    ? Rect(x: area.minX - w[i] + 1, y: area.maxY - 1, width: w[i], height: view.height)
                    : Rect(x: view.minX - w[i] + sliver, y: view.y, width: w[i], height: view.height)
            }
            return hideRight
                ? Rect(x: area.maxX - 1, y: area.maxY - 1, width: w[i], height: view.height)
                : Rect(x: view.maxX - sliver, y: view.y, width: w[i], height: view.height)
        }
        return Result(frames: frames.map(\.integral), offset: off)
    }

    /// Offset that puts window `index` in the middle of the screen.
    public static func centeredOffset(widths: [Double], index: Int, in area: Rect, parameters p: LayoutParameters) -> Double {
        let view = area.inset(by: max(0, p.outerGap))
        let gap = max(0, p.innerGap)
        let w = widths.map { ($0.clamped(to: 0.1...1) * view.width).rounded() }
        guard w.indices.contains(index) else { return 0 }
        let start = w[..<index].reduce(0) { $0 + $1 + gap }
        return max(0, start + w[index] / 2 - view.width / 2)
    }

    /// The next preset wider than `current`, wrapping back to the narrowest.
    public static func nextPreset(after current: Double) -> Double {
        widthPresets.first { $0 > current + 0.01 } ?? widthPresets[0]
    }
}
