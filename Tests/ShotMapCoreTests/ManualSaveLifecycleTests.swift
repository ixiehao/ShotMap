import CoreGraphics
import Foundation
import XCTest
@testable import ShotMapApp

final class ManualSaveLifecycleTests: XCTestCase {
    @MainActor
    func testResultStatusUsesCurrentLanguageAfterSavingAndBrowsing() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = StoryboardViewModel()
        let data = try imageData(red: 0.3)
        let id = try await appendUnsaved(data, to: model, directory: directory, index: 0)
        for language in [AppLanguage.english, .chinese, .japanese] {
            model.language = language
            XCTAssertEqual(model.outputDescription, language.text("status.generatedNotSaved", 1, 2))
            XCTAssertEqual(model.previewStatus, model.outputDescription)
        }
        let destination = directory.appendingPathComponent("旅行-saved.jpg")
        try data.write(to: destination, options: .atomic)
        model.completeManualSave(to: destination, targetPreviewID: id)
        for language in [AppLanguage.english, .chinese, .japanese] {
            model.language = language
            XCTAssertEqual(model.outputDescription, language.text("status.manualSaved", destination.lastPathComponent))
            XCTAssertEqual(model.previewStatus, model.outputDescription)
        }
        _ = try await appendUnsaved(imageData(red: 0.8), to: model, directory: directory, index: 1)
        model.showPreviousPreview()
        for language in [AppLanguage.english, .chinese, .japanese] {
            model.language = language
            XCTAssertEqual(model.outputDescription, language.text("status.saved", 1, 2, destination.lastPathComponent))
        }
    }

    @MainActor
    func testPauseAndCancellationStatusFollowLanguageChanges() {
        let model = StoryboardViewModel()
        model.markPausedAtCheckpoint()
        for language in [AppLanguage.english, .chinese, .japanese] {
            model.language = language
            XCTAssertEqual(model.outputDescription, language.text("status.paused"))
            XCTAssertEqual(model.previewStatus, language.text("status.paused"))
        }
        model.cancelGeneration()
        for language in [AppLanguage.english, .chinese, .japanese] {
            model.language = language
            XCTAssertEqual(model.outputDescription, language.text("status.cancelled"))
        }
    }

    @MainActor
    func testCompletedBatchRetainsCountsWhenLanguageChanges() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = StoryboardViewModel()
        let first = directory.appendingPathComponent("first.mp4")
        let second = directory.appendingPathComponent("second.mp4")
        model.addVideos([first, second])
        _ = await model.completeJob(data: try imageData(red: 0.3), result: StoryboardResult(frames: [], sourceURL: first),
                                    settings: ExportSettings(format: .jpeg), index: 0, total: 2)
        model.markJobFailed(index: 1, message: "fixture failure")
        model.finishBatch()
        for language in [AppLanguage.english, .chinese, .japanese] {
            model.language = language
            let expected = language.text("status.batchCompletedWithFailures", 1, 1)
            XCTAssertEqual(model.outputDescription, expected)
            XCTAssertEqual(model.previewStatus, expected)
        }
    }

    @MainActor
    func testSavingCurrentResultReleasesPendingDataAndUsesSavedFileForHistory() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = StoryboardViewModel()
        let data = try imageData(red: 0.3)
        let id = try await appendUnsaved(data, to: model, directory: directory, index: 0)
        XCTAssertEqual(model.pendingData, data)
        let cached = try XCTUnwrap(model.completedPreviews.first?.storageURL)
        let destination = directory.appendingPathComponent("saved.jpg")
        try data.write(to: destination, options: .atomic)

        model.completeManualSave(to: destination, targetPreviewID: id)

        XCTAssertNil(model.pendingData)
        XCTAssertEqual(model.lastSavedURL, destination)
        let preview = try XCTUnwrap(model.completedPreviews.first)
        XCTAssertEqual(preview.savedURL, destination)
        XCTAssertEqual(preview.storageURL, destination)
        XCTAssertNil(preview.fallbackData)
        try FileManager.default.removeItem(at: cached)
        XCTAssertEqual(try preview.loadData(), data, "History no longer depends on the temporary cache")
        XCTAssertNil(try preview.loadPresentation().pendingData)
    }

    @MainActor
    func testCompletingSaveAfterSwitchingPreservesOtherResultsPendingData() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = StoryboardViewModel()
        let firstData = try imageData(red: 0.3)
        let firstID = try await appendUnsaved(firstData, to: model, directory: directory, index: 0)
        let secondData = try imageData(red: 0.8)
        _ = try await appendUnsaved(secondData, to: model, directory: directory, index: 1)
        let description = model.outputDescription
        let destination = directory.appendingPathComponent("first-saved.jpg")
        try firstData.write(to: destination, options: .atomic)

        model.completeManualSave(to: destination, targetPreviewID: firstID)

        XCTAssertEqual(model.selectedPreviewIndex, 1)
        XCTAssertEqual(model.pendingData, secondData)
        XCTAssertNil(model.lastSavedURL)
        XCTAssertEqual(model.outputDescription, description)
        XCTAssertEqual(model.completedPreviews[0].storageURL, destination)
        XCTAssertNil(model.completedPreviews[1].savedURL)
    }

    @MainActor
    func testSavingWhileReturningToResultDoesNotRestoreStalePendingData() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = StoryboardViewModel()
        let data = try imageData(red: 0.3)
        let firstID = try await appendUnsaved(data, to: model, directory: directory, index: 0)
        _ = try await appendUnsaved(imageData(red: 0.8), to: model, directory: directory, index: 1)
        let destination = directory.appendingPathComponent("saved-during-load.jpg")
        try data.write(to: destination, options: .atomic)
        model.showPreviousPreview()
        XCTAssertTrue(model.isLoadingPreview)

        model.completeManualSave(to: destination, targetPreviewID: firstID)
        let deadline = ContinuousClock.now + .seconds(3)
        while model.isLoadingPreview, ContinuousClock.now < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertFalse(model.isLoadingPreview)
        XCTAssertNil(model.pendingData)
        XCTAssertEqual(model.lastSavedURL, destination)
        XCTAssertFalse(model.showError)
    }

    func testSavingFallbackRecordReleasesItsInMemoryExport() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try imageData(red: 0.3)
        let original = RenderedStoryboardPreview(
            id: UUID(), sourceURL: directory.appendingPathComponent("source.mp4"), duration: 2,
            frameCount: 9, settings: ExportSettings(format: .jpeg), savedURL: nil,
            storageURL: nil, fallbackData: data, jobIndex: 0, jobCount: 1
        )
        let destination = directory.appendingPathComponent("fallback-saved.jpg")
        try data.write(to: destination, options: .atomic)
        let saved = original.saved(at: destination)
        XCTAssertEqual(saved.id, original.id)
        XCTAssertEqual(saved.frameCount, original.frameCount)
        XCTAssertNil(saved.fallbackData)
        XCTAssertEqual(saved.storageURL, destination)
        XCTAssertEqual(try saved.loadData(), data)
    }

    @MainActor
    private func appendUnsaved(_ data: Data, to model: StoryboardViewModel, directory: URL, index: Int) async throws -> UUID {
        // This intentionally nonexistent child directory makes automatic export
        // fail without touching permissions or any real user video directory.
        let source = directory.appendingPathComponent("missing-\(index)/video.mp4")
        let result = StoryboardResult(frames: [], sourceURL: source, duration: 2)
        let canContinue = await model.completeJob(data: data, result: result,
                                                  settings: ExportSettings(format: .jpeg), index: index, total: 2)
        XCTAssertTrue(canContinue)
        let preview = try XCTUnwrap(model.completedPreviews.last)
        XCTAssertNil(preview.savedURL)
        return preview.id
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotMap-save-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func imageData(red: CGFloat) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 18, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
        return try XCTUnwrap(ImageCodec.jpegData(from: XCTUnwrap(context.makeImage()), compressionQuality: 0.8))
    }
}
