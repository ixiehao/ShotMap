import CoreGraphics
import XCTest
@testable import ShotMapApp

final class MainWindowStartupLayoutTests: XCTestCase {
    func testEmptyWorkspaceStartsCompactWithBothSidebarsVisible() {
        XCTAssertEqual(MainWindowStartupLayout.contentSize, CGSize(width: 840, height: 680))
        let canvasWidth = MainWindowStartupLayout.contentSize.width
            - StudioLayout.queueWidth(availableWidth: MainWindowStartupLayout.contentSize.width)
            - StudioLayout.inspectorWidth - 2
        XCTAssertGreaterThanOrEqual(canvasWidth, 430)
    }

    func testOldLandscapeFrameIsReplacedWithoutMovingItsTopOrCenter() {
        let restored = CGRect(x: 100, y: 100, width: 1_500, height: 900)
        let screen = CGRect(x: 0, y: 0, width: 1_728, height: 1_060)
        let nativeSize = CGSize(width: 840, height: 702)
        let compact = MainWindowStartupLayout.frame(
            currentFrame: restored, desiredFrameSize: nativeSize, visibleFrame: screen
        )
        XCTAssertEqual(compact.size, nativeSize)
        XCTAssertEqual(compact.midX, restored.midX)
        XCTAssertEqual(compact.maxY, restored.maxY)
        XCTAssertTrue(screen.contains(compact))
    }

    func testCompactStartupFitsNegativeOriginDisplayAndSmallScreens() {
        let restored = CGRect(x: 200, y: 900, width: 1_500, height: 900)
        for screen in [CGRect(x: -1_440, y: 40, width: 1_440, height: 860),
                       CGRect(x: 50, y: 70, width: 600, height: 400)] {
            let compact = MainWindowStartupLayout.frame(
                currentFrame: restored,
                desiredFrameSize: MainWindowStartupLayout.contentSize,
                visibleFrame: screen
            )
            XCTAssertTrue(screen.contains(compact))
            XCTAssertEqual(compact.width, min(840, screen.width))
            XCTAssertEqual(compact.height, min(680, screen.height))
        }
    }
}
