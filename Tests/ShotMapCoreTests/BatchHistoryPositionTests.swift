import CoreGraphics
import XCTest
@testable import ShotMapApp

final class BatchHistoryPositionTests: XCTestCase {
    @MainActor
    func testFailedRetryKeepsVisibleCompletedFileMetadata() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = StoryboardViewModel()
        defer { model.cancelGeneration() }
        let sources = [directory.appendingPathComponent("saved.mp4"), directory.appendingPathComponent("missing.mp4")]
        model.addVideos(sources)
        _ = await model.completeJob(data: try imageData(), result: StoryboardResult(frames: [], sourceURL: sources[0]),
                                    settings: ExportSettings(format: .jpeg), index: 0, total: 2)
        let saved = try XCTUnwrap(model.lastSavedURL)
        let preview = try XCTUnwrap(model.previewImage)
        model.markJobFailed(index: 1, message: "retry fixture")

        model.retryFailedJobs()
        XCTAssertEqual(model.lastSavedURL, saved)
        let deadline = ContinuousClock.now + .seconds(3)
        while model.isProcessing, ContinuousClock.now < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertFalse(model.isProcessing)
        XCTAssertTrue(model.previewImage === preview)
        XCTAssertEqual(model.lastSavedURL, saved, "The visible retained result must still be revealable after retry failure")
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
    }

    @MainActor
    func testCancelledRetryKeepsUnsavedVisibleResultExportData() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = StoryboardViewModel()
        let source = directory.appendingPathComponent("missing-parent/source.mp4")
        model.addVideos([source])
        let data = try imageData()
        _ = await model.completeJob(data: data, result: StoryboardResult(frames: [], sourceURL: source),
                                    settings: ExportSettings(format: .jpeg), index: 0, total: 1)
        XCTAssertNil(model.lastSavedURL)
        XCTAssertEqual(model.pendingData, data)
        let previewID = try XCTUnwrap(model.completedPreviews.first?.id)

        model.retryFailedJobs()
        XCTAssertEqual(model.pendingData, data)
        model.cancelGeneration()

        XCTAssertEqual(model.pendingData, data, "A cancelled retry must not remove the existing result's Save As data")
        XCTAssertEqual(model.completedPreviews.first?.id, previewID)
        XCTAssertNotNil(model.previewImage)
        XCTAssertNil(model.lastSavedURL)
        XCTAssertEqual(try model.completedPreviews[0].loadData(), data, "Retry must preserve the session cache for an unsaved history entry")

        let nextSource = directory.appendingPathComponent("next.mp4")
        model.addVideos([nextSource])
        _ = await model.completeJob(data: data, result: StoryboardResult(frames: [], sourceURL: nextSource),
                                    settings: ExportSettings(format: .jpeg), index: 1, total: 2)
        XCTAssertEqual(model.selectedPreviewIndex, 1)
        XCTAssertNotEqual(model.completedPreviews[1].id, previewID)
        XCTAssertEqual(model.lastSavedURL, model.completedPreviews[1].savedURL)
        XCTAssertNotNil(model.lastSavedURL)
        XCTAssertNil(model.pendingData, "A newly saved result must replace, rather than inherit, the old pending export")
        XCTAssertEqual(try model.completedPreviews[0].loadData(), data)
    }

    @MainActor
    func testRetryingLastVideoKeepsOriginalQueuePositionAndTotal() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = StoryboardViewModel()
        model.language = .english
        let sources = (0..<5).map { directory.appendingPathComponent("video-\($0).mp4") }
        model.addVideos(sources)
        model.markJobFailed(index: 4, message: "retry fixture")
        // A retry callback retains the source's original queue index, while
        // `total` is the number of jobs in this retry run rather than the queue.
        _ = await model.completeJob(data: try imageData(),
            result: StoryboardResult(frames: [], sourceURL: sources[4]),
            settings: ExportSettings(format: .jpeg), index: 4, total: 1)

        let preview = try XCTUnwrap(model.completedPreviews.last)
        XCTAssertEqual(preview.jobIndex, 4)
        XCTAssertEqual(preview.jobCount, 5)
        let filename = try XCTUnwrap(preview.savedURL).lastPathComponent
        for language in AppLanguage.allCases {
            model.language = language
            XCTAssertEqual(model.outputDescription, language.text("status.saved", 5, 5, filename))
        }
        XCTAssertEqual(model.videoJobs.map(\.url), sources, "Retry must preserve the original queue ordering")
    }

    @MainActor
    func testSparseRetryHistoryAndUnsavedResultsNeverDisplayOutOfRangePositions() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = StoryboardViewModel()
        // The last source's parent is absent, so automatic output fails and
        // exercises the generated-but-unsaved status and temporary history.
        let sources = (0..<5).map { index in
            directory.appendingPathComponent(index == 4 ? "missing/video-4.mp4" : "video-\(index).mp4")
        }
        model.addVideos(sources)
        for index in [2, 4] {
            _ = await model.completeJob(data: try imageData(),
                result: StoryboardResult(frames: [], sourceURL: sources[index]),
                settings: ExportSettings(format: .jpeg), index: index, total: 2)
        }

        XCTAssertEqual(model.completedPreviews.map(\.jobIndex), [2, 4])
        XCTAssertEqual(model.completedPreviews.map(\.jobCount), [5, 5])
        XCTAssertNil(model.completedPreviews.last?.savedURL)
        for language in AppLanguage.allCases {
            model.language = language
            XCTAssertEqual(model.outputDescription, language.text("status.generatedNotSaved", 5, 5))
        }
        model.showPreviousPreview()
        let previous = model.completedPreviews[0]
        for language in AppLanguage.allCases {
            model.language = language
            XCTAssertEqual(model.outputDescription,
                language.text("status.saved", 3, 5, try XCTUnwrap(previous.savedURL).lastPathComponent))
        }
        model.clearVideos()
    }

    @MainActor
    func testRetryLiveProgressUsesRetryPositionWithoutRenumberingQueue() {
        let model = StoryboardViewModel()
        let sources = (0..<5).map { URL(fileURLWithPath: "/tmp/ShotMap-progress-\($0).mp4") }
        model.addVideos(sources)
        model.isProcessing = true
        model.beginJob(source: sources[4], jobIndex: 4, batchIndex: 0, total: 1,
                       gridSide: 3, layoutAspect: .source)
        XCTAssertEqual(model.activeJobIndex, 0)
        XCTAssertEqual(model.activeJobCount, 1)
        XCTAssertEqual(model.videoJobs[4].state, .processing)
        XCTAssertTrue(model.videoJobs.prefix(4).allSatisfy { $0.state == .queued })
        XCTAssertEqual(model.videoJobs.map(\.url), sources)
        model.cancelGeneration()
        XCTAssertEqual(model.videoJobs[4].state, .queued)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotMap-history-position-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func imageData() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 18, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
        return try XCTUnwrap(ImageCodec.jpegData(from: XCTUnwrap(context.makeImage()), compressionQuality: 0.8))
    }
}
