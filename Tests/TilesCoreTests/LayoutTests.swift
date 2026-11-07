import XCTest
@testable import TilesCore

final class LayoutTests: XCTestCase {
    let screen = Rect(x: 0, y: 25, width: 1440, height: 875)
    let ultrawide = Rect(x: 0, y: 25, width: 3440, height: 1415)
    let noGaps = LayoutParameters(innerGap: 0, outerGap: 0, masterRatio: 0.5, masterCount: 1, maxTileWidth: 0, maxTiles: 100)
    let roomy = LayoutParameters(maxTiles: 100)

    func testEmptyAndFloatProduceNoFrames() {
        XCTAssertEqual(LayoutEngine.frames(count: 0, in: screen, kind: .dwindle).count, 0)
        XCTAssertEqual(LayoutEngine.frames(count: 3, in: screen, kind: .float).count, 0)
    }

    func testEveryLayoutReturnsOneFramePerWindow() {
        for kind in LayoutKind.allCases where kind != .float {
            for n in 1...12 {
                let frames = LayoutEngine.frames(count: n, in: screen, kind: kind)
                XCTAssertEqual(frames.count, n, "\(kind) with \(n) windows")
            }
        }
    }

    func testFramesStayInsideTheScreen() {
        for kind in LayoutKind.allCases where kind != .float {
            for n in 1...9 where kind != .scrolling {
                for frame in LayoutEngine.frames(count: n, in: screen, kind: kind, parameters: roomy) {
                    XCTAssertGreaterThanOrEqual(frame.minX, screen.minX, "\(kind) \(n)")
                    XCTAssertGreaterThanOrEqual(frame.minY, screen.minY, "\(kind) \(n)")
                    XCTAssertLessThanOrEqual(frame.maxX, screen.maxX, "\(kind) \(n)")
                    XCTAssertLessThanOrEqual(frame.maxY, screen.maxY, "\(kind) \(n)")
                    XCTAssertGreaterThan(frame.width, 0)
                    XCTAssertGreaterThan(frame.height, 0)
                }
            }
        }
    }

    func testTilingLayoutsDoNotOverlap() {
        for kind in LayoutKind.allCases where kind != .float && kind != .monocle && kind != .scrolling {
            for n in 1...9 {
                let frames = LayoutEngine.frames(count: n, in: screen, kind: kind, parameters: roomy)
                for i in frames.indices {
                    for j in frames.indices where j > i {
                        XCTAssertEqual(frames[i].intersection(frames[j]).area, 0, "\(kind) n=\(n) frames \(i),\(j)")
                    }
                }
            }
        }
    }

    func testTilingLayoutsCoverTheScreenWithoutGaps() {
        let area = screen.area
        for kind in LayoutKind.allCases where kind != .float && kind != .monocle && kind != .scrolling {
            for n in 1...9 {
                let total = LayoutEngine.frames(count: n, in: screen, kind: kind, parameters: noGaps).map(\.area).reduce(0, +)
                XCTAssertEqual(total, area, accuracy: 1, "\(kind) n=\(n)")
            }
        }
    }

    func testSingleWindowFillsScreenMinusOuterGap() {
        let p = LayoutParameters(innerGap: 10, outerGap: 12)
        let frames = LayoutEngine.frames(count: 1, in: screen, kind: .dwindle, parameters: p)
        XCTAssertEqual(frames, [Rect(x: 12, y: 37, width: 1416, height: 851)])
    }

    func testMasterStackRespectsRatio() {
        var p = noGaps
        p.masterRatio = 0.6
        let frames = LayoutEngine.frames(count: 3, in: screen, kind: .masterStack, parameters: p)
        XCTAssertEqual(frames[0], Rect(x: 0, y: 25, width: 864, height: 875))
        XCTAssertEqual(frames[1].x, 864)
        XCTAssertEqual(frames[2].x, 864)
        XCTAssertEqual(frames[1].height + frames[2].height, 875, accuracy: 1)
    }

    func testMasterCountPutsSeveralWindowsInMasterColumn() {
        var p = noGaps
        p.masterCount = 2
        let frames = LayoutEngine.frames(count: 4, in: screen, kind: .masterStack, parameters: p)
        XCTAssertEqual(frames[0].x, 0)
        XCTAssertEqual(frames[1].x, 0)
        XCTAssertEqual(frames[2].x, 720)
        XCTAssertEqual(frames[3].x, 720)
    }

    func testInnerGapSeparatesWindows() {
        let p = LayoutParameters(innerGap: 10, outerGap: 0, masterRatio: 0.5)
        let frames = LayoutEngine.frames(count: 2, in: screen, kind: .columns, parameters: p)
        XCTAssertEqual(frames[1].minX - frames[0].maxX, 10)
    }

    func testUltrawideCentersASingleWindow() {
        let frames = LayoutEngine.frames(count: 1, in: ultrawide, kind: .dwindle, parameters: noGaps)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].midX, ultrawide.midX, accuracy: 1)
        XCTAssertLessThan(frames[0].width, ultrawide.width)
    }

    func testUltrawideCenteringCanBeDisabled() {
        var p = noGaps
        p.ultrawideAspectRatio = 0
        let frames = LayoutEngine.frames(count: 1, in: ultrawide, kind: .dwindle, parameters: p)
        XCTAssertEqual(frames[0], ultrawide)
    }

    func testCenteredMasterPutsMasterInTheMiddle() {
        let frames = LayoutEngine.frames(count: 3, in: ultrawide, kind: .centeredMaster, parameters: noGaps)
        XCTAssertEqual(frames[0].midX, ultrawide.midX, accuracy: 2)
        XCTAssertGreaterThan(frames[1].minX, frames[0].minX) // first stack window goes right
        XCTAssertLessThan(frames[2].minX, frames[0].minX)    // second goes left
    }

    func testGridIsBalanced() {
        let frames = LayoutEngine.frames(count: 4, in: screen, kind: .grid, parameters: noGaps)
        let widths = frames.map(\.width)
        let heights = frames.map(\.height)
        // Equal to within a point of rounding.
        XCTAssertLessThanOrEqual(widths.max()! - widths.min()!, 1)
        XCTAssertLessThanOrEqual(heights.max()! - heights.min()!, 1)
        XCTAssertEqual(Set(frames.map(\.x)).count, 2)
        XCTAssertEqual(Set(frames.map(\.y)).count, 2)
    }

    func testDwindleSplitsAlongLongerSide() {
        let frames = LayoutEngine.frames(count: 3, in: screen, kind: .dwindle, parameters: noGaps)
        // Landscape: first split is vertical (side by side), then the right half splits horizontally.
        XCTAssertEqual(frames[0].height, screen.height)
        XCTAssertEqual(frames[1].x, frames[2].x)
        XCTAssertLessThan(frames[1].y, frames[2].y)
    }

    func testThirds() {
        let two = LayoutEngine.frames(count: 2, in: screen, kind: .thirds, parameters: noGaps)
        XCTAssertEqual(two[0].width, 960)
        let five = LayoutEngine.frames(count: 5, in: screen, kind: .thirds, parameters: noGaps)
        XCTAssertEqual(Set(five[2...].map(\.x)).count, 1) // windows 3–5 share the right third
    }

    func testWidthCapCentresWideTiles() {
        let wide = Rect(x: 0, y: 0, width: 5120, height: 1440)
        var p = noGaps
        p.maxTileWidth = 2000
        let frames = LayoutEngine.frames(count: 2, in: wide, kind: .columns, parameters: p)
        XCTAssertEqual(frames.map(\.width), [2000, 2000])
        XCTAssertEqual(frames[0].midX, 1280, accuracy: 1)
    }

    func testFullScreenStacksExtraWindowsOnLastTile() {
        var p = noGaps
        p.maxTiles = 3
        let frames = LayoutEngine.frames(count: 5, in: screen, kind: .columns, parameters: p)
        XCTAssertEqual(frames.count, 5)
        XCTAssertEqual(Set(frames.map(\.x)).count, 3)
        XCTAssertEqual(frames[2], frames[4])
    }

    func testAutoTileLimitScalesWithDisplay() {
        let laptop = LayoutEngine.maxTiles(in: Rect(x: 0, y: 0, width: 1512, height: 944), .default)
        let ultrawide = LayoutEngine.maxTiles(in: Rect(x: 0, y: 0, width: 5120, height: 1415), .default)
        XCTAssertEqual(laptop, 4)
        XCTAssertGreaterThan(ultrawide, laptop)
    }

    func testScrollingKeepsWidthsAndParksOffscreenWindows() {
        let r = ScrollingLayout.layout(widths: [0.5, 0.5, 0.5], in: screen, parameters: noGaps, focused: 0, offset: 0)
        XCTAssertEqual(r.frames.map(\.width), [720, 720, 720])
        XCTAssertEqual(r.frames[0].x, 0)
        XCTAssertEqual(r.frames[1].x, 720)
        XCTAssertEqual(r.frames[2].x, 1440 - ScrollingLayout.sliver) // waits at the right edge
        XCTAssertEqual(r.offset, 0)
    }

    func testScrollingBringsFocusedWindowIntoView() {
        let r = ScrollingLayout.layout(widths: [0.5, 0.5, 0.5], in: screen, parameters: noGaps, focused: 2, offset: 0)
        XCTAssertEqual(r.offset, 720)
        XCTAssertEqual(r.frames[2].maxX, 1440)
        XCTAssertEqual(r.frames[0].maxX, ScrollingLayout.sliver) // now waits at the left edge
        // Stays put when the focused window is already visible.
        XCTAssertEqual(ScrollingLayout.layout(widths: [0.5, 0.5, 0.5], in: screen, parameters: noGaps, focused: 1, offset: 720).offset, 720)
    }

    func testScrollingHidesInCornerNextToAnotherDisplay() {
        let r = ScrollingLayout.layout(widths: [0.5, 0.5, 0.5], in: screen, parameters: noGaps, focused: 0, offset: 0, hideRight: true)
        XCTAssertEqual(r.frames[2].x, screen.maxX - 1)
        XCTAssertEqual(r.frames[2].y, screen.maxY - 1)
    }

    func testScrollingCentreAndPresets() {
        let off = ScrollingLayout.centeredOffset(widths: [0.5, 0.5, 0.5], index: 1, in: screen, parameters: noGaps)
        XCTAssertEqual(off, 360)
        XCTAssertEqual(ScrollingLayout.nextPreset(after: 0.5), 2.0 / 3)
        XCTAssertEqual(ScrollingLayout.nextPreset(after: 1), 1.0 / 3)
        XCTAssertEqual(LayoutEngine.frames(count: 5, in: screen, kind: .scrolling).count, 5)
    }

    func testScrollingHalvesFitWithGaps() {
        // Found on a real Mac: two halves plus the gap overflowed, pushing the second off screen.
        let p = LayoutParameters(innerGap: 8, outerGap: 8)
        let r = ScrollingLayout.layout(widths: [0.5, 0.5, 0.5], in: screen, parameters: p, focused: 0, offset: 0)
        XCTAssertEqual(r.frames[0].minX, 8)
        XCTAssertEqual(r.frames[1].maxX, screen.maxX - 8)
        XCTAssertEqual(r.frames[1].minX - r.frames[0].maxX, 8)
        XCTAssertEqual(ScrollingLayout.layout(widths: [1], in: screen, parameters: p, focused: 0, offset: 0).frames[0].width, 1424)
    }

    func testSmallScreensStillGetFourTiles() {
        // Found on a real Mac: a 1024x768 screen allowed only 2 tiles and stacked the rest.
        XCTAssertEqual(LayoutEngine.maxTiles(in: Rect(x: 0, y: 0, width: 1008, height: 676), .default), 4)
        let frames = LayoutEngine.frames(count: 4, in: Rect(x: 0, y: 25, width: 1024, height: 692), kind: .dwindle)
        XCTAssertEqual(Set(frames.map { "\($0)" }).count, 4) // four different tiles
    }

    func testScrollingLetsAPartlyVisibleWindowHangOffTheEdge() {
        // Found on a real Mac: scrolling right parked the half-visible window and left half the screen empty.
        let r = ScrollingLayout.layout(widths: [2.0 / 3, 0.5, 0.5], in: screen, parameters: noGaps, focused: 1, offset: 0)
        XCTAssertEqual(r.offset, 240)
        XCTAssertEqual(r.frames[0].x, -240)    // hangs off the left edge, still filling the screen
        XCTAssertEqual(r.frames[1].maxX, 1440) // focused, fully visible
        // With another display on the left it tucks away instead of spilling onto it.
        let hidden = ScrollingLayout.layout(widths: [2.0 / 3, 0.5, 0.5], in: screen, parameters: noGaps, focused: 1, offset: 0, hideLeft: true)
        XCTAssertEqual(hidden.frames[0].y, screen.maxY - 1)
    }

    func testScrollingResizeKeepsTheDraggedWidth() {
        // Mouse-resizing used a different formula and the window shrank a few points after release.
        let p = LayoutParameters(innerGap: 8, outerGap: 8)
        for width in [300.0, 708, 1000, 1424] {
            let share = ScrollingLayout.share(forWidth: width, in: screen, parameters: p)
            let laidOut = ScrollingLayout.layout(widths: [share], in: screen, parameters: p, focused: 0, offset: 0)
            XCTAssertEqual(laidOut.frames[0].width, width, accuracy: 1)
        }
    }
}
