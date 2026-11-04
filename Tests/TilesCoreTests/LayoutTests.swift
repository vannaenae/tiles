import XCTest
@testable import TilesCore

final class LayoutTests: XCTestCase {
    let screen = Rect(x: 0, y: 25, width: 1440, height: 875)
    let ultrawide = Rect(x: 0, y: 25, width: 3440, height: 1415)
    let noGaps = LayoutParameters(innerGap: 0, outerGap: 0, masterRatio: 0.5, masterCount: 1)

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
            for n in 1...9 {
                for frame in LayoutEngine.frames(count: n, in: screen, kind: kind) {
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
        for kind in LayoutKind.allCases where kind != .float && kind != .monocle {
            for n in 1...9 {
                let frames = LayoutEngine.frames(count: n, in: screen, kind: kind)
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
        for kind in LayoutKind.allCases where kind != .float && kind != .monocle {
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
}
