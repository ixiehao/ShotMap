import CoreGraphics
import XCTest
@testable import ShotMapApp

final class PreviewWindowAutoFitTests: XCTestCase {
    func testManualAspectChangeRefitsTheSameHistoryRecordWithoutRefittingResolutionUpgrades() {
        let panels = PreviewWindowPanelConfiguration(queueVisible: true, inspectorVisible: true)
        let original = PreviewWindowAutoFitRequest(sourceID: "same-history-record", aspectRatio: 1.78,
                                                   layoutAspect: .landscape, panels: panels)
        let sharperImage = PreviewWindowAutoFitRequest(sourceID: "same-history-record", aspectRatio: 1.779,
                                                       layoutAspect: .landscape, panels: panels)
        let portraitEdit = PreviewWindowAutoFitRequest(sourceID: "same-history-record", aspectRatio: 0.56,
                                                       layoutAspect: .portrait, panels: panels)
        XCTAssertEqual(original.trigger, sharperImage.trigger)
        XCTAssertNotEqual(original.trigger, portraitEdit.trigger)
    }

    private let frame = CGRect(x: 200, y: 100, width: 1_280, height: 800)
    private let viewport = CGSize(width: 872, height: 664)
    private let screen = CGRect(x: 0, y: 0, width: 1_728, height: 1_060)
    private let minimum = CGSize(width: 720, height: 480)

    func testCompactStartupStillExpandsTheFirstLandscapeResult() throws {
        let startup = MainWindowStartupLayout.contentSize
        let width = PreviewWindowAutoFitGeometry.initialLandscapeWidth(
            currentWidth: startup.width, startupWidth: startup.width
        )
        let fitted = try XCTUnwrap(PreviewWindowAutoFitGeometry.fittedFrame(
            currentFrame: CGRect(x: 200, y: 100, width: startup.width, height: startup.height),
            viewportSize: CGSize(width: startup.width - 408, height: startup.height - 136),
            visibleFrame: screen, minimumSize: minimum, aspectRatio: 16.0 / 9.0,
            preferredLandscapeWidth: width
        ))
        XCTAssertEqual(fitted.width, 1_280)
        XCTAssertEqual(fitted.height, 637)
        XCTAssertTrue(screen.contains(fitted))
    }

    func testCompactStartupStillFitsTheFirstPortraitResult() throws {
        let startup = MainWindowStartupLayout.contentSize
        let fitted = try XCTUnwrap(PreviewWindowAutoFitGeometry.fittedFrame(
            currentFrame: CGRect(x: 200, y: 100, width: startup.width, height: startup.height),
            viewportSize: CGSize(width: startup.width - 408, height: startup.height - 136),
            visibleFrame: screen, minimumSize: minimum, aspectRatio: 9.0 / 16.0
        ))
        XCTAssertEqual(fitted.width, 837)
        XCTAssertEqual(fitted.height, 880)
        XCTAssertTrue(screen.contains(fitted))
    }

    func testWidthAdjustedBeforeFirstResultRemainsTheLandscapePreference() {
        for width in [CGFloat(780), 960, 1_440] {
            XCTAssertEqual(PreviewWindowAutoFitGeometry.initialLandscapeWidth(
                currentWidth: width, startupWidth: MainWindowStartupLayout.contentSize.width
            ), width)
        }
        XCTAssertEqual(PreviewWindowAutoFitGeometry.initialLandscapeWidth(currentWidth: 600, startupWidth: 600), 1_280)
    }

    func testLandscapeKeepsPreferredWidthAndUsesMeasuredChrome() throws {
        let fitted = try XCTUnwrap(PreviewWindowAutoFitGeometry.fittedFrame(
            currentFrame: frame, viewportSize: viewport, visibleFrame: screen,
            minimumSize: minimum, aspectRatio: 16.0 / 9.0))
        XCTAssertEqual(fitted.width, 1_280)
        XCTAssertEqual(fitted.height, 637)
        XCTAssertEqual(fitted.maxY, frame.maxY)
        XCTAssertEqual(fitted.midX, frame.midX)
        XCTAssertEqual((fitted.width - 408 - 24) / (fitted.height - 136 - 24), 16.0 / 9.0, accuracy: 0.001)
    }

    func testPortraitKeepsPreferredHeightAndNarrowsWindow() throws {
        let fitted = try XCTUnwrap(PreviewWindowAutoFitGeometry.fittedFrame(
            currentFrame: frame, viewportSize: viewport, visibleFrame: screen,
            minimumSize: minimum, aspectRatio: 9.0 / 16.0))
        XCTAssertEqual(fitted.height, 880)
        XCTAssertEqual(fitted.width, 837)
        XCTAssertEqual(fitted.maxY, frame.maxY)
        XCTAssertEqual(fitted.midX, frame.midX)
        XCTAssertEqual((fitted.width - 408 - 24) / (fitted.height - 136 - 24), 9.0 / 16.0, accuracy: 0.001)
    }

    func testSquareShrinksBothAxesToFitNegativeOriginExternalDisplay() throws {
        let display = CGRect(x: -1_440, y: 40, width: 1_440, height: 860)
        let current = CGRect(x: -1_400, y: 90, width: 1_280, height: 800)
        let fitted = try XCTUnwrap(PreviewWindowAutoFitGeometry.fittedFrame(
            currentFrame: current, viewportSize: viewport, visibleFrame: display,
            minimumSize: minimum, aspectRatio: 1))
        XCTAssertEqual(fitted.width, 1_132)
        XCTAssertEqual(fitted.height, 860)
        XCTAssertTrue(display.contains(fitted))
        XCTAssertEqual(fitted.width - 408 - 24, fitted.height - 136 - 24)
    }

    func testNativeMinimumHeightIsHonouredForWideResults() throws {
        let fitted = try XCTUnwrap(PreviewWindowAutoFitGeometry.fittedFrame(
            currentFrame: frame, viewportSize: viewport, visibleFrame: screen,
            minimumSize: CGSize(width: 720, height: 508), aspectRatio: 4))
        XCTAssertEqual(fitted.height, 508)
        XCTAssertEqual(fitted.width, 1_280)
        XCTAssertTrue(screen.contains(fitted))
    }

    func testRemovedPanelsUseTheActualWiderViewportInsteadOfFixedSidebarWidth() throws {
        let fitted = try XCTUnwrap(PreviewWindowAutoFitGeometry.fittedFrame(
            currentFrame: frame, viewportSize: CGSize(width: 1_280, height: 664),
            visibleFrame: screen, minimumSize: CGSize(width: 480, height: 480),
            aspectRatio: 16.0 / 9.0))
        XCTAssertEqual(fitted.width, 1_280)
        XCTAssertEqual(fitted.height, 867)
        XCTAssertGreaterThan(fitted.height, 637)
        XCTAssertEqual((fitted.width - 24) / (fitted.height - 136 - 24), 16.0 / 9.0, accuracy: 0.002)
    }

    func testScreenSmallerThanDeclaredMinimumStillContainsEntireFrame() throws {
        let display = CGRect(x: 50, y: 70, width: 600, height: 400)
        let fitted = try XCTUnwrap(PreviewWindowAutoFitGeometry.fittedFrame(
            currentFrame: CGRect(x: -900, y: 1_500, width: 1_280, height: 800),
            viewportSize: viewport, visibleFrame: display, minimumSize: minimum,
            aspectRatio: 9.0 / 16.0))
        XCTAssertEqual(fitted, display)
    }

    func testInvalidAspectAndUnmeasuredViewDoNotProduceFrames() {
        for aspect in [Double.zero, -.infinity, .infinity, .nan, -1] {
            XCTAssertNil(PreviewWindowAutoFitGeometry.fittedFrame(
                currentFrame: frame, viewportSize: viewport, visibleFrame: screen,
                minimumSize: minimum, aspectRatio: aspect))
        }
        XCTAssertNil(PreviewWindowAutoFitGeometry.fittedFrame(
            currentFrame: frame, viewportSize: .zero, visibleFrame: screen,
            minimumSize: minimum, aspectRatio: 1))
    }

    func testPanelConfigurationsExposeTheSameMinimumWidthsAsWorkspace() {
        XCTAssertEqual(PreviewWindowPanelConfiguration(queueVisible: true, inspectorVisible: true).minimumWindowWidth, 720)
        XCTAssertEqual(PreviewWindowPanelConfiguration(queueVisible: true, inspectorVisible: false).minimumWindowWidth, 600)
        XCTAssertEqual(PreviewWindowPanelConfiguration(queueVisible: false, inspectorVisible: true).minimumWindowWidth, 600)
        XCTAssertEqual(PreviewWindowPanelConfiguration(queueVisible: false, inspectorVisible: false).minimumWindowWidth, 480)
    }
}
