import XCTest
@testable import ShotMapApp

final class ExportSettingsValidationTests: XCTestCase {
    func testInvalidGridSettingsRenderWithinTheSupportedBudget() throws {
        let result = StoryboardResult(frames: [], sourceURL: URL(fileURLWithPath: "/tmp/empty.mp4"))
        for (requestedSide, expectedSide) in [(Int.min, 3), (0, 3), (Int.max, 8)] {
            let settings = ExportSettings(gridSide: requestedSide, format: .jpeg, width: 1920)
            XCTAssertEqual(settings.gridSide, expectedSide)
            XCTAssertEqual(settings.frameCount, expectedSide * expectedSide)
            let data = try StoryboardComposer.render(result: result, settings: settings)
            let image = try XCTUnwrap(ImageCodec.cgImage(from: data))
            XCTAssertEqual(image.width, 1920)
            XCTAssertGreaterThan(image.height, 0)
        }
    }

    func testChangingGridKeepsSupportedChoicesAndOtherExportSettings() {
        var settings = ExportSettings(layoutAspect: .portrait, language: .japanese,
                                      format: .jpeg, width: 3840, background: .ivory,
                                      showTimestamps: true, showTitleWatermark: true)
        for side in StoryboardGrid.availableSides {
            settings.gridSide = side
            XCTAssertEqual(settings.gridSide, side)
            XCTAssertEqual(settings.frameCount, side * side)
        }
        settings.gridSide = Int.max
        XCTAssertEqual(settings.frameCount, 64)
        settings.gridSide = Int.min
        XCTAssertEqual(settings.frameCount, 9)
        XCTAssertEqual(settings.safeWidth, 3840)
        XCTAssertEqual(settings.language, .japanese)
        XCTAssertEqual(settings.layoutAspect, .portrait)
        XCTAssertEqual(settings.format, .jpeg)
        XCTAssertEqual(settings.background, .ivory)
        XCTAssertTrue(settings.showTimestamps && settings.showTitleWatermark)
    }

    func testQueueRowIdentityFollowsTheJobWhenItsPositionChanges() {
        let first = VideoJob(url: URL(fileURLWithPath: "/tmp/first.mp4"))
        let second = VideoJob(url: URL(fileURLWithPath: "/tmp/second.mp4"))
        let original = IndexedVideoJobs(jobs: [first, second])
        let reordered = IndexedVideoJobs(jobs: [second, first])
        XCTAssertEqual(original[1].id, reordered[0].id)
        XCTAssertEqual(reordered[0].index, 0)
        XCTAssertEqual(reordered[0].job.url, second.url)
        XCTAssertEqual(Array(original).map(\.id), [first.id, second.id])
        XCTAssertTrue(IndexedVideoJobs(jobs: []).isEmpty)
    }
}
