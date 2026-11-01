import AppKit
import XCTest
@testable import ShotMapApp

final class PreviewCanvasLayoutTests: XCTestCase {
    func testLandscapeFitUsesAvailableWidthWithoutAHeightCap() {
        let image = CGSize(width: 1_920, height: 1_080)
        for (paneWidth, expectedImageWidth) in [(CGFloat(543), CGFloat(519)), (CGFloat(873), CGFloat(849))] {
            let scale = PreviewCanvasLayout.fitScale(imageSize: image, viewportSize: CGSize(width: paneWidth, height: 800))
            XCTAssertEqual(image.width * scale, expectedImageWidth, accuracy: 0.001)
        }
        let large = PreviewCanvasLayout.fitScale(imageSize: image, viewportSize: CGSize(width: 1_200, height: 1_000))
        XCTAssertGreaterThan(image.height * large, 560, "A large preview must not retain the old fixed height cap")
    }

    func testPortraitAndUltrawideImagesKeepTheirWholeAspect() {
        let viewport = CGSize(width: 860, height: 450)
        for image in [CGSize(width: 720, height: 1_280), CGSize(width: 2_560, height: 534)] {
            let scale = PreviewCanvasLayout.fitScale(imageSize: image, viewportSize: viewport)
            let width = image.width * scale
            let height = image.height * scale
            XCTAssertLessThanOrEqual(width, viewport.width - 24 + 0.001)
            XCTAssertLessThanOrEqual(height, viewport.height - 24 + 0.001)
            XCTAssertEqual(width / height, image.width / image.height, accuracy: 0.0001)
        }
    }

    func testProgressiveGridFitsBothAxesIncludingItsGaps() {
        let available = CGSize(width: 519, height: 420)
        for side in 3...8 {
            for aspect in [16.0 / 9, 9.0 / 16, 2.39] {
                let result = PreviewCanvasLayout.gridMetrics(side: side, cardAspect: aspect, availableSize: available)
                XCTAssertLessThanOrEqual(result.gridSize.width, available.width + 0.001)
                XCTAssertLessThanOrEqual(result.gridSize.height, available.height + 0.001)
                XCTAssertEqual(result.tileSize.width / result.tileSize.height, aspect, accuracy: 0.0001)
                XCTAssertEqual(result.gridSize.width,
                               CGFloat(side) * result.tileSize.width + CGFloat(side - 1) * 5, accuracy: 0.001)
                XCTAssertEqual(result.gridSize.height,
                               CGFloat(side) * result.tileSize.height + CGFloat(side - 1) * 5, accuracy: 0.001)
            }
        }
    }

    @MainActor
    func testNativeCanvasKeepsEveryEdgeForLandscapePortraitAndUltrawide() throws {
        let view = StoryboardCanvasScrollView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        for size in [CGSize(width: 1_600, height: 900), CGSize(width: 720, height: 1_280), CGSize(width: 2_560, height: 534)] {
            let image = NSImage(size: size)
            view.configure(image: image, isLightAppearance: true, label: "Preview")
            view.layoutSubtreeIfNeeded()
            let document = try XCTUnwrap(view.documentView)
            let fitted = view.documentVisibleRect
            XCTAssertTrue(fitted.contains(document.bounds), "Every edge of the supplied image must remain visible")
            XCTAssertEqual(fitted.midX, document.bounds.midX, accuracy: 0.01)
            XCTAssertEqual(fitted.midY, document.bounds.midY, accuracy: 0.01)
            XCTAssertFalse(view.allowsMagnification, "Removing zoom controls must not leave an unresettable gesture zoom")
        }
    }

    @MainActor
    func testResizeAndAppearanceChangesKeepTheWholeImageVisible() throws {
        let view = StoryboardCanvasScrollView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        let image = NSImage(size: CGSize(width: 1_600, height: 900))
        view.configure(image: image, isLightAppearance: true, label: "Preview")
        for viewport in [CGSize(width: 300, height: 600), CGSize(width: 900, height: 350)] {
            view.setFrameSize(viewport)
            view.configure(image: image, isLightAppearance: false, label: "プレビュー")
            view.layoutSubtreeIfNeeded()
            let document = try XCTUnwrap(view.documentView)
            XCTAssertTrue(view.documentVisibleRect.contains(document.bounds))
            XCTAssertEqual(view.magnification, view.fitMagnification, accuracy: 0.001)
        }
    }
}
