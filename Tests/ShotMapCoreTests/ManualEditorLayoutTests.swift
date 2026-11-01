import AppKit
import AVFoundation
import XCTest
@testable import ShotMapApp

final class ManualEditorLayoutTests: XCTestCase {
    func testPortraitGridShowsFiveOrSixWholeFramesAtSupportedWidths() {
        for (width, expectedColumns) in [(CGFloat(1_000), 5), (CGFloat(1_280), 6), (CGFloat(1_920), 6)] {
            let columns = ManualEditorLayout.candidateColumnCount(availableWidth: width, sourceAspectRatio: 9.0 / 16)
            XCTAssertEqual(columns, expectedColumns)
            let cell = ManualEditorLayout.candidateTileWidth(availableWidth: width, columns: columns)
            XCTAssertEqual(cell * CGFloat(columns) + ManualEditorLayout.candidateGap * CGFloat(columns - 1) + ManualEditorLayout.horizontalInset * 2, width, accuracy: 0.001)
            if width <= 1_280 {
                let remainingHeight = (width == 1_000 ? CGFloat(680) : CGFloat(800))
                    - ManualEditorLayout.workspaceHeight(mediaHeight: ManualEditorLayout.mediaHeight(availableHeight: width == 1_000 ? 680 : 800))
                    - ManualEditorLayout.candidateGridBottom - ManualEditorLayout.candidateGridTop
                XCTAssertLessThan(cell / (9.0 / 16), remainingHeight, "One full portrait row must fit without a footer")
            }
        }
    }

    func testLandscapeGridRetainsLargerThumbnails() {
        XCTAssertEqual(ManualEditorLayout.candidateColumnCount(availableWidth: 1_280, sourceAspectRatio: 16.0 / 9), 4)
        XCTAssertEqual(ManualEditorLayout.candidateColumnCount(availableWidth: 1_000, sourceAspectRatio: 16.0 / 9), 3)
    }

    @MainActor
    func testFullToolbarFitsAllSevenLanguagesAnd64FramesAtSupportedSizes() {
        for (width, height) in [(CGFloat(1_000), CGFloat(680)), (1_280, 800)] {
            let mediaHeight = ManualEditorLayout.mediaHeight(availableHeight: height)
            let workspaceWidth = width - ManualEditorLayout.horizontalInset * 2
            for aspect in [CGFloat(16.0 / 9), CGFloat(9.0 / 16)] {
                let availableMonitorWidth = workspaceWidth - ManualEditorLayout.workspaceGap - 544
                let monitorWidth = min(548, max(220, min(mediaHeight * aspect, availableMonitorWidth)))
                let availableWidth = workspaceWidth - ManualEditorLayout.workspaceGap - monitorWidth
                    - ManualEditorLayout.controlDeckInset * 2
                for language in AppLanguage.allCases {
                    let metrics = ManualEditorLayout.toolbarMetrics(language: language, selectionLimit: 64)
                    XCTAssertLessThanOrEqual(metrics.singleRowWidth, availableWidth, language.rawValue)
                    XCTAssertFalse(metrics.stacksCommitButtons(availableWidth: availableWidth), language.rawValue)
                    let labels: [(String, CGFloat, NSFont.Weight)] = [
                        ("editor.smartSelect.short", metrics.smartSelectionWidth, .medium),
                        ("editor.regenerate.short", metrics.newCandidatesWidth, .medium),
                        ("editor.cancel", metrics.cancelWidth, .medium),
                        ("editor.apply.short", metrics.applyWidth, .semibold)
                    ]
                    for (key, buttonWidth, weight) in labels {
                        let text = language.text(key) as NSString
                        let glyphWidth = text.size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: weight)]).width
                        XCTAssertGreaterThanOrEqual(buttonWidth, glyphWidth + 20, "\(language.rawValue): \(key)")
                    }
                }
            }
        }
    }

    @MainActor
    func testSelectionCountReservesTheFullSizeMaximumWithoutChangingWidth() {
        let font = ManualEditorLayout.selectionCountFont
        XCTAssertEqual(font.pointSize, 28)
        for limit in [9, 64, 256] {
            let metrics = ManualEditorLayout.toolbarMetrics(language: .english, selectionLimit: limit)
            for count in 0...limit {
                let text = "\(count) / \(limit)" as NSString
                XCTAssertGreaterThanOrEqual(metrics.countWidth, text.size(withAttributes: [.font: font]).width)
            }
        }
    }

    @MainActor
    func testOversizedToolbarFallsBackToTwoCompleteRows() {
        let metrics = ManualEditorLayout.toolbarMetrics(language: .french, selectionLimit: 256)
        XCTAssertTrue(metrics.stacksCommitButtons(availableWidth: 520))
        XCTAssertLessThanOrEqual(metrics.workingWidth, 520)
        XCTAssertLessThanOrEqual(metrics.commitWidth, 520)
        XCTAssertEqual(metrics.height(availableWidth: 520), 72)
        XCTAssertFalse(metrics.stacksCommitButtons(availableWidth: metrics.singleRowWidth))
        XCTAssertEqual(metrics.height(availableWidth: metrics.singleRowWidth), 36)
    }

    func testSelectedMarkerRowTradesOnlyFilmstripHeightAndKeepsNavigationStationary() {
        for mediaHeight in [CGFloat(298), 320] {
            for toolbarHeight in [CGFloat(36), 72] {
                for hairline in [CGFloat(0.5), 1] {
                    let emptyStrip = ManualEditorLayout.timelineFilmstripHeight(
                        mediaHeight: mediaHeight, toolbarHeight: toolbarHeight,
                        hasSelections: false, hairline: hairline
                    )
                    let selectedStrip = ManualEditorLayout.timelineFilmstripHeight(
                        mediaHeight: mediaHeight, toolbarHeight: toolbarHeight,
                        hasSelections: true, hairline: hairline
                    )
                    XCTAssertEqual(emptyStrip - selectedStrip, 24)
                    XCTAssertGreaterThanOrEqual(selectedStrip, 62)
                    let emptyTimelineBottom = toolbarHeight + ManualEditorLayout.toolbarTimelineGap + emptyStrip
                    let selectedTimelineBottom = toolbarHeight + ManualEditorLayout.toolbarTimelineGap + 24 + selectedStrip
                    XCTAssertEqual(emptyTimelineBottom, selectedTimelineBottom)
                    let totalHeight = ManualEditorLayout.controlDeckInset * 2 + emptyTimelineBottom
                        + ManualEditorLayout.filmstripScrubberGap + ManualEditorLayout.navigationHeight
                        + hairline + ManualEditorLayout.commandsTopGap + ManualEditorLayout.compactControlHeight
                    XCTAssertLessThanOrEqual(totalHeight, mediaHeight)
                    XCTAssertLessThan(mediaHeight - totalHeight, 1)
                }
            }
        }
    }

    @MainActor
    func testFloatingAddStaysInsideNavigationHitAreaAndClearOfRealEndpointLabels() {
        XCTAssertGreaterThanOrEqual(ManualEditorLayout.floatingAddTop, ManualEditorLayout.scrubberHeight)
        XCTAssertEqual(ManualEditorLayout.floatingAddTop + ManualEditorLayout.floatingAddHeight, ManualEditorLayout.navigationHeight)
        let duration = 360_000.0
        let timeFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        let endpointWidth = ceil(max(
            (TimestampFormatter.string(for: 0) as NSString).size(withAttributes: [.font: timeFont]).width,
            (TimestampFormatter.string(for: duration) as NSString).size(withAttributes: [.font: timeFont]).width
        )) + 8
        for language in AppLanguage.allCases {
            let title = language.text("editor.addCurrentFrame.short") as NSString
            let buttonWidth = ceil(title.size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width) + 24
            for time in [0.0, duration / 2, duration] {
                let x = ManualTimelineGeometry.insertionOrigin(
                    time: time, duration: duration, width: 520,
                    buttonWidth: buttonWidth, endpointWidth: endpointWidth
                )
                XCTAssertGreaterThanOrEqual(x, endpointWidth, language.rawValue)
                XCTAssertLessThanOrEqual(x + buttonWidth, 520 - endpointWidth, language.rawValue)
            }
        }
    }

    @MainActor
    func testPlayerLetterboxAdoptsThemeColorWithoutCroppingTheVideo() throws {
        let player = AVPlayer()
        let light = NSColor(calibratedRed: 0.898, green: 0.910, blue: 0.922, alpha: 1)
        let view = ManualVideoSurface(player: player, fillColor: light)
        let layer = try XCTUnwrap(view.layer as? AVPlayerLayer)
        XCTAssertTrue(layer.player === player)
        XCTAssertEqual(layer.videoGravity, .resizeAspect)
        XCTAssertEqual(try XCTUnwrap(layer.backgroundColor), light.cgColor)
        let dark = NSColor(calibratedRed: 0.141, green: 0.165, blue: 0.196, alpha: 1)
        view.update(player: player, fillColor: dark)
        XCTAssertTrue(layer.player === player)
        XCTAssertEqual(try XCTUnwrap(layer.backgroundColor), dark.cgColor)
    }
}
