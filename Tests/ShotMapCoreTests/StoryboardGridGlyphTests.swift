import CoreGraphics
import XCTest
@testable import ShotMapApp

final class StoryboardGridGlyphTests: XCTestCase {
    func testEachAvailableChoiceShowsItsActualGrid() {
        for side in StoryboardGrid.availableSides {
            let cells = StoryboardGridGlyphLayout.cells(side: side, extent: 30, displayScale: 2)
            XCTAssertEqual(cells.count, side * side)
            XCTAssertEqual(Set(cells.map(\.minX)).count, side)
            XCTAssertEqual(Set(cells.map(\.minY)).count, side)
        }
    }

    func testCellsAreEqualUncroppedAndPixelAlignedAtBothDisplayScales() throws {
        for scale in [CGFloat(1), CGFloat(2)] {
            for side in StoryboardGrid.availableSides {
                let cells = StoryboardGridGlyphLayout.cells(side: side, extent: 30, displayScale: scale)
                let first = try XCTUnwrap(cells.first)
                let bounds = cells.reduce(CGRect.null) { $0.union($1) }
                XCTAssertLessThanOrEqual(abs(bounds.midX - 15), 1 / scale)
                XCTAssertLessThanOrEqual(abs(bounds.midY - 15), 1 / scale)
                for cell in cells {
                    XCTAssertEqual(cell.size, first.size)
                    XCTAssertTrue(CGRect(x: 0, y: 0, width: 30, height: 30).contains(cell))
                    for edge in [cell.minX, cell.minY, cell.maxX, cell.maxY] {
                        XCTAssertEqual(edge * scale, (edge * scale).rounded(), accuracy: 0.001)
                    }
                }
            }
        }
    }
}
