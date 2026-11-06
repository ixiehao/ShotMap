import AVFoundation
import XCTest
@testable import ShotMapApp

final class MediaImageGeneratorTests: XCTestCase {
    func testExportAndRefinementKeepExactSeekingAndOrientation() {
        let asset = AVURLAsset(url: URL(fileURLWithPath: "/unused-fixture.mov"))
        let generator = MediaImageGenerator.make(asset: asset, maximumEdge: 1_920)
        XCTAssertTrue(generator.appliesPreferredTrackTransform)
        XCTAssertEqual(generator.maximumSize, CGSize(width: 1_920, height: 1_920))
        XCTAssertEqual(CMTimeCompare(generator.requestedTimeToleranceBefore, .zero), 0)
        XCTAssertEqual(CMTimeCompare(generator.requestedTimeToleranceAfter, .zero), 0)
    }

    func testCoarsePassPreservesExplicitToleranceWithoutChangingExport() {
        let asset = AVURLAsset(url: URL(fileURLWithPath: "/unused-fixture.mov"))
        let tolerance = CMTime(value: 1, timescale: 4)
        let coarse = MediaImageGenerator.make(asset: asset, maximumEdge: 480, tolerance: tolerance)
        let exact = MediaImageGenerator.make(asset: asset, maximumEdge: 1_600)
        XCTAssertFalse(coarse === exact, "Each caller owns its decoder and cancellation lifetime")
        XCTAssertEqual(CMTimeCompare(coarse.requestedTimeToleranceAfter, tolerance), 0)
        XCTAssertEqual(CMTimeCompare(coarse.requestedTimeToleranceBefore, tolerance), 0)
        XCTAssertEqual(CMTimeCompare(exact.requestedTimeToleranceAfter, .zero), 0)
        XCTAssertEqual(exact.maximumSize.width, 1_600)
    }
}
