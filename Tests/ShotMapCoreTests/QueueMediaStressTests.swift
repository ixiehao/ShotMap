import AppKit
import CryptoKit
import XCTest
@testable import ShotMapApp

/// Opt-in local stress run with licensed, encoded video files. No private or
/// third-party media is bundled in the repository. See docs/DEVELOPMENT.md.
final class QueueMediaStressTests: XCTestCase {
    @MainActor
    func testMixedMediaBatchPauseResumeCancellationAndClearWhenRequested() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let sourceDirectory = environment["SHOTMAP_STRESS_MEDIA_DIR"],
              let outputDirectory = environment["SHOTMAP_STRESS_OUTPUT_DIR"] else {
            throw XCTSkip("Set SHOTMAP_STRESS_MEDIA_DIR and SHOTMAP_STRESS_OUTPUT_DIR for the local media stress run")
        }
        let manager = FileManager.default
        let sources = try manager.contentsOfDirectory(at: URL(fileURLWithPath: sourceDirectory),
            includingPropertiesForKeys: nil).filter { SupportedVideoInput.accepts($0) }.sorted { $0.path < $1.path }
        XCTAssertGreaterThanOrEqual(sources.count, 2, "Supply at least two encoded media sources")
        guard sources.count >= 2 else { return }
        let directory = URL(fileURLWithPath: outputDirectory).appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        var validIndices: [Int] = []
        for index in 0..<28 {
            let destination = directory.appendingPathComponent(String(format: "%03d-旅行 clip.mp4", index))
            if index % 7 == 3 {
                try Data("intentionally invalid media fixture".utf8).write(to: destination)
            } else {
                try manager.linkItem(at: sources[validIndices.count % sources.count], to: destination)
                validIndices.append(index)
            }
            urls.append(destination)
        }
        let model = StoryboardViewModel()
        defer { model.cancelGeneration(); model.clearVideos() }
        model.language = .english
        model.addVideos(urls)
        let originalIDs = model.videoJobs.map(\.id)
        let start = ProcessInfo.processInfo.systemUptime
        model.generate()
        try await waitUntil(timeout: 10) { model.videoJobs.first?.state == .processing }
        model.requestPause()
        try await waitUntil(timeout: 90) { model.isPaused || !model.isProcessing }
        XCTAssertTrue(model.isPaused, "Pause must finish the active video and retain the rest of the queue")
        guard model.isPaused else { return }
        XCTAssertEqual(model.completedPreviews.count, 1)
        let first = try XCTUnwrap(model.completedPreviews.first?.savedURL)
        let firstHash = SHA256.hash(data: try Data(contentsOf: first))
        model.format = .png
        model.background = .white
        model.showTimestamps = false
        model.showTitleWatermark = true
        model.resumeGeneration()
        try await waitUntil(timeout: 240) { !model.isProcessing }
        let batchSeconds = ProcessInfo.processInfo.systemUptime - start
        XCTAssertEqual(model.videoJobs.map(\.id), originalIDs)
        XCTAssertEqual(model.videoJobs.map(\.url), urls)
        XCTAssertEqual(model.completedPreviews.count, 24)
        XCTAssertEqual(model.failedJobs.count, 4)
        XCTAssertTrue(model.failedJobs.allSatisfy {
            if case let .failed(failure) = $0.state { return failure.kind == .permanent }
            return false
        })
        XCTAssertEqual(model.completedPreviews.map(\.jobIndex), validIndices)
        XCTAssertTrue(model.completedPreviews.allSatisfy { $0.jobCount == 28 && $0.frameCount == 9 })
        for (offset, preview) in model.completedPreviews.enumerated() {
            let saved = try XCTUnwrap(preview.savedURL)
            XCTAssertNil(preview.fallbackData, "Completed batches should retain disk paths, not all exports in RAM")
            XCTAssertEqual(preview.storageURL, saved)
            let image = try XCTUnwrap(ImageCodec.cgImage(from: Data(contentsOf: saved)))
            XCTAssertEqual(image.width, 1920)
            XCTAssertEqual(saved.pathExtension, offset == 0 ? "jpg" : "png")
            if offset > 0 {
                XCTAssertEqual(preview.settings.background, .white)
                XCTAssertFalse(preview.settings.showTimestamps)
                XCTAssertTrue(preview.settings.showTitleWatermark)
            }
        }
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: first)), firstHash)
        model.showPreviousPreview()
        try await waitUntil(timeout: 5) { !model.isLoadingPreview }
        XCTAssertEqual(model.selectedPreviewIndex, 22)
        model.showNextPreview()
        try await waitUntil(timeout: 5) { !model.isLoadingPreview }
        XCTAssertEqual(model.selectedPreviewIndex, 23)
        model.clearVideos()
        XCTAssertNil(model.previewImage)
        XCTAssertTrue(model.completedPreviews.isEmpty)

        // A real decoder runs at the front of a thousand-file queue. Stop it,
        // then import a new queue while old asynchronous work is winding down.
        let cancelDirectory = directory.appendingPathComponent("cancel-1000")
        try manager.createDirectory(at: cancelDirectory, withIntermediateDirectories: true)
        let many = try (0..<1_000).map { index -> URL in
            let destination = cancelDirectory.appendingPathComponent("clip-\(index).mp4")
            try manager.linkItem(at: sources[index % sources.count], to: destination)
            return destination
        }
        model.addVideos(many)
        model.generate()
        try await waitUntil(timeout: 10) { model.livePreviewSlots.filledCount > 0 || !model.isProcessing }
        XCTAssertTrue(model.isProcessing)
        let cancelStart = ProcessInfo.processInfo.systemUptime
        model.cancelGeneration()
        model.clearVideos()
        model.addVideos(Array(urls.prefix(2)))
        let newIDs = model.videoJobs.map(\.id)
        // Allow the cancelled decoder, Vision and writer callbacks to arrive.
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(model.isBusy)
        XCTAssertEqual(model.videoJobs.map(\.id), newIDs)
        XCTAssertEqual(model.videoJobs.map(\.url), Array(urls.prefix(2)))
        XCTAssertTrue(model.videoJobs.allSatisfy { $0.state == .queued })
        XCTAssertTrue(model.completedPreviews.isEmpty)
        XCTAssertNil(model.lastSavedURL)
        XCTAssertNil(model.previewImage)
        XCTAssertEqual(model.livePreviewSlots.filledCount, 0)
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: first)), firstHash)
        print("QUEUE_MEDIA_STRESS paths=28 valid=24 invalid=4 source_contents=\(sources.count) batch_s=\(batchSeconds) cancellation_observation_s=\(ProcessInfo.processInfo.systemUptime - cancelStart) cancel_queue=1000 output=\(directory.path)")
    }

    @MainActor
    private func waitUntil(timeout: Double, _ condition: @MainActor () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !condition(), ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), "Timed out after \(timeout)s")
    }
}
