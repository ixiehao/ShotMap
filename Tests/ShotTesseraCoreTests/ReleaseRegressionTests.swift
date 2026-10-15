import AppKit
import AVFoundation
import XCTest
@testable import ShotTesseraApp

final class ReleaseRegressionTests: XCTestCase {
    func testDockReopenDependsOnMainWindowRatherThanOtherVisibleWindows() {
        // Help/About can be visible in all three cases. They must not suppress
        // recreation of a closed workspace or restoration of a minimized one.
        XCTAssertEqual(MainWindowReopenAction.resolve(hasMainWindow: false, isVisible: false, isMiniaturized: false), .create)
        XCTAssertEqual(MainWindowReopenAction.resolve(hasMainWindow: true, isVisible: false, isMiniaturized: false), .restore)
        XCTAssertEqual(MainWindowReopenAction.resolve(hasMainWindow: true, isVisible: true, isMiniaturized: true), .restore)
        XCTAssertEqual(MainWindowReopenAction.resolve(hasMainWindow: true, isVisible: true, isMiniaturized: false), .none)
    }

    func testOnlyNewStableReleasesFromTheProjectProduceAnUpdate() throws {
        let installed = try XCTUnwrap(ReleaseVersion(tag: "0.2.5"))
        func release(draft: Bool = false, prerelease: Bool = false, tag: String = "v0.2.6", url: String = "https://github.com/ixiehao/ShotTessera/releases/tag/v0.2.6") -> GitHubRelease {
            GitHubRelease(tagName: tag, htmlURL: URL(string: url)!, draft: draft, prerelease: prerelease)
        }
        XCTAssertNotNil(release().update(newerThan: installed))
        XCTAssertNil(release(draft: true).update(newerThan: installed))
        XCTAssertNil(release(prerelease: true).update(newerThan: installed))
        XCTAssertNil(release(tag: "v0.2.5").update(newerThan: installed))
        XCTAssertNil(release(tag: "v0.2.4").update(newerThan: installed))
        XCTAssertNil(release(url: "https://example.org/download").update(newerThan: installed))
    }

    func testCancelledPausedWorkerDoesNotNeedAnExplicitResume() async {
        let control = BatchRunControl()
        await control.requestPause()
        let released = expectation(description: "cancelled pause releases its continuation")
        let task = Task {
            await control.waitUntilResumed()
            released.fulfill()
        }
        await Task.yield()
        task.cancel()
        await fulfillment(of: [released], timeout: 2)
    }

    func testFinderDropsAcceptDataURLAndNSURLButRejectRemoteURLs() {
        let file = URL(fileURLWithPath: "/tmp/旅行 sample.mp4")
        XCTAssertEqual(DroppedVideoURL.decode(file), file)
        XCTAssertEqual(DroppedVideoURL.decode(file as NSURL), file)
        XCTAssertEqual(DroppedVideoURL.decode(file.dataRepresentation), file)
        XCTAssertNil(DroppedVideoURL.decode(URL(string: "https://example.org/movie.mp4")))
        XCTAssertNil(DroppedVideoURL.decode("not a file URL"))
    }

    func testConcurrentPauseCancellationNeverLeavesAWaiterBehind() async {
        let released = expectation(description: "all cancelled waiters released")
        released.expectedFulfillmentCount = 200
        for index in 0..<200 {
            let control = BatchRunControl()
            await control.requestPause()
            let task = Task {
                await control.waitUntilResumed()
                released.fulfill()
            }
            if index.isMultiple(of: 2) { await Task.yield() }
            task.cancel()
        }
        await fulfillment(of: [released], timeout: 3)
    }

    func testLongUnicodeExportNamesFitFilesystemLimit() {
        let filename = ExportDestination.filename(baseName: String(repeating: "旅行🎥", count: 80), format: .jpeg, sequence: 12)
        XCTAssertLessThanOrEqual(filename.utf8.count, 255)
        XCTAssertTrue(filename.hasSuffix("-shot-012.jpg"))
        XCTAssertFalse(filename.isEmpty)
    }

    func testBatchFilenameAllocationChecksEachNewCandidateOnlyOnce() {
        let source = URL(fileURLWithPath: "/tmp/ShotTessera-sequence-test/video.mp4")
        var allocator = ExportSequenceAllocator()
        var existing = Set<String>()
        var checks = 0
        for sequence in 1...957 {
            let destination = allocator.nextURL(for: source, format: .jpeg) { path in
                checks += 1
                return existing.contains(path)
            }
            XCTAssertEqual(destination.lastPathComponent, ExportDestination.filename(baseName: "video", format: .jpeg, sequence: sequence))
            existing.insert(destination.path)
        }
        XCTAssertEqual(checks, 957, "A long batch must not rescan 001 through every prior output")
    }

    func testFilenameHintsScanExistingFilesAndStillSkipNewExternalConflicts() {
        let folder = URL(fileURLWithPath: "/tmp/ShotTessera-sequence-test")
        let source = folder.appendingPathComponent("video.mp4")
        var allocator = ExportSequenceAllocator()
        var existing = Set(["video-shot-001.jpg", "video-shot-002.jpg"].map { folder.appendingPathComponent($0).path })
        var checked: [String] = []
        func exists(_ path: String) -> Bool {
            checked.append(URL(fileURLWithPath: path).lastPathComponent)
            return existing.contains(path)
        }
        XCTAssertEqual(allocator.nextURL(for: source, format: .jpeg, fileExists: exists).lastPathComponent, "video-shot-003.jpg")
        XCTAssertEqual(checked, ["video-shot-001.jpg", "video-shot-002.jpg", "video-shot-003.jpg"])
        existing.insert(folder.appendingPathComponent("video-shot-004.jpg").path)
        checked.removeAll()
        XCTAssertEqual(allocator.nextURL(for: source, format: .jpeg, fileExists: exists).lastPathComponent, "video-shot-005.jpg")
        XCTAssertEqual(checked, ["video-shot-004.jpg", "video-shot-005.jpg"])
        XCTAssertEqual(allocator.nextURL(for: source, format: .png, fileExists: exists).lastPathComponent, "video-shot-001.png")
        XCTAssertEqual(allocator.nextURL(for: folder.appendingPathComponent("other.mp4"), format: .jpeg, fileExists: exists).lastPathComponent, "other-shot-001.jpg")
        XCTAssertEqual(allocator.nextURL(for: folder.appendingPathComponent("different/video.mp4"), format: .jpeg, fileExists: exists).lastPathComponent, "video-shot-001.jpg")
    }

    func testPermanentContentFailuresNeverBecomeRetryOrTranscodingActions() {
        for error in [StoryboardError.noUsableFrames, .unreadableVideo] {
            let failure = VideoFailure.classify(error, language: .english)
            XCTAssertEqual(failure.kind, .permanent)
            XCTAssertFalse(failure.isRetryable)
            XCTAssertFalse(failure.needsTranscoding)
        }
        XCTAssertEqual(VideoFailure.classify(StoryboardError.unsupportedCodec, language: .english).kind, .needsTranscoding)
        XCTAssertEqual(VideoFailure.classify(StoryboardError.noExportData, language: .english).kind, .retryable)
        XCTAssertEqual(VideoFailure.classify(CocoaError(.fileReadNoPermission), language: .english).kind, .retryable)
    }

    func testSystemMediaFailuresOfferOnlyUsefulRecoveryActions() {
        func avError(_ code: AVError.Code) -> NSError {
            NSError(domain: AVFoundationErrorDomain, code: code.rawValue)
        }

        XCTAssertEqual(
            VideoFailure.classify(avError(.decoderNotFound), language: .english).kind,
            .needsTranscoding
        )
        XCTAssertEqual(
            VideoFailure.classify(avError(.fileFormatNotRecognized), language: .english).kind,
            .needsTranscoding
        )
        for code in [AVError.Code.fileFailedToParse, .failedToLoadMediaData, .contentIsProtected] {
            let failure = VideoFailure.classify(avError(code), language: .english)
            XCTAssertEqual(failure.kind, .permanent)
            XCTAssertFalse(failure.isRetryable)
        }
        XCTAssertEqual(
            VideoFailure.classify(CocoaError(.fileReadCorruptFile), language: .english).kind,
            .permanent
        )
        // A mounted volume or granted permission can change after the first
        // attempt, so access failures intentionally retain the Retry action.
        XCTAssertEqual(
            VideoFailure.classify(CocoaError(.fileReadNoPermission), language: .english).kind,
            .retryable
        )
    }

    @MainActor
    func testLargeBatchKeepsAllHistoryWithoutRetainingExportOrFrameData() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = StoryboardViewModel()
        let data = try smallImageData()
        let source = directory.appendingPathComponent("sample.mp4")
        let result = StoryboardResult(frames: [CapturedFrame(id: 0, time: 1, jpegData: data)], sourceURL: source, duration: 3)
        let settings = ExportSettings(gridSide: 3, format: .jpeg, width: 1920)
        for index in 0..<957 {
            let canContinue = await model.completeJob(data: data, result: result, settings: settings, index: index, total: 957)
            XCTAssertTrue(canContinue)
        }
        XCTAssertEqual(model.completedPreviews.count, 957)
        XCTAssertTrue(model.completedPreviews.allSatisfy { $0.fallbackData == nil && $0.storageURL != nil })
        XCTAssertEqual(model.selectedPreviewIndex, 956)
        XCTAssertEqual(try model.completedPreviews[0].loadData(), data)
        model.showPreviousPreview()
        XCTAssertEqual(model.selectedPreviewIndex, 955)
        XCTAssertEqual(model.lastSavedURL, model.completedPreviews[955].savedURL)
        model.showNextPreview()
        XCTAssertEqual(model.selectedPreviewIndex, 956)
        model.clearVideos()
        XCTAssertTrue(model.completedPreviews.isEmpty)
        XCTAssertNil(model.lastSavedURL)
        XCTAssertNil(model.previewImage)
    }

    @MainActor
    func testManualEditKeepsTheTargetResultsGridFormatAndDimensions() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = StoryboardViewModel()
        let source = directory.appendingPathComponent("original.mp4")
        model.addVideos([source])
        let data = try smallImageData()
        let frames = (0..<9).map { CapturedFrame(id: $0, time: Double($0), jpegData: data) }
        let result = StoryboardResult(frames: frames, sourceURL: source, duration: 10)
        let originalSettings = ExportSettings(gridSide: 3, layoutAspect: .portrait, format: .jpeg, width: 1920, showTimestamps: true)
        await model.completeJob(data: data, result: result, settings: originalSettings, index: 0, total: 1)
        let id = try XCTUnwrap(model.completedPreviews.first?.id)
        model.gridSide = 8
        model.format = .png
        model.width = 5120
        model.layoutAspect = .landscape
        model.showTimestamps = false
        model.applyManuallySelectedFrames(frames, targetPreviewID: id, sourceURL: source, duration: 10)
        let deadline = Date().addingTimeInterval(10)
        while model.isApplyingFrameAdjustments && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(model.isApplyingFrameAdjustments)
        let edited = try XCTUnwrap(model.completedPreviews.first)
        XCTAssertEqual(edited.id, id)
        XCTAssertEqual(edited.settings.gridSide, 3)
        XCTAssertEqual(edited.settings.layoutAspect, .portrait)
        XCTAssertEqual(edited.settings.width, 1920)
        XCTAssertTrue(edited.settings.showTimestamps)
        XCTAssertEqual(edited.format, .jpeg)
        let image = try XCTUnwrap(ImageCodec.cgImage(from: edited.loadData()))
        XCTAssertEqual(image.width, 1920)
        XCTAssertGreaterThan(image.height, image.width)
        let preview = try XCTUnwrap(model.previewImage)
        XCTAssertLessThanOrEqual(max(preview.size.width, preview.size.height), 1280)
    }

    func testTemporaryPreviewStoragePersistsAndCleansUpUnexportedResults() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PreviewImageStore(directory: directory.appendingPathComponent("preview-cache"))
        let data = Data([1, 2, 3])
        let url = try store.store(data, format: .png)
        XCTAssertEqual(try Data(contentsOf: url), data)
        store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testBackgroundWriterSerializesNamesAndNeverWritesOnMainThread() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = StoryboardOutputWriter { data, url in
            XCTAssertFalse(Thread.isMainThread, "Slow filesystem writes must not block AppKit")
            try data.write(to: url, options: .atomic)
        }
        let data = try smallImageData()
        let result = StoryboardResult(frames: [], sourceURL: directory.appendingPathComponent("same.mp4"))
        let store = PreviewImageStore()
        let outputs = try await withThrowingTaskGroup(of: URL.self) { group in
            for index in 0..<20 {
                group.addTask {
                    let output = try await writer.prepare(data: data, result: result, settings: ExportSettings(format: .jpeg), jobIndex: index, jobCount: 20, previewStore: store)
                    return try XCTUnwrap(output.preview.savedURL)
                }
            }
            var urls: [URL] = []
            for try await url in group { urls.append(url) }
            return urls
        }
        XCTAssertEqual(Set(outputs).count, 20)
        XCTAssertTrue(outputs.contains { $0.lastPathComponent == "same-shot-020.jpg" })
        try await writer.save(data, to: directory.appendingPathComponent("manual.jpg"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ShotTessera-regression-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func smallImageData() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 18, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
        return try XCTUnwrap(ImageCodec.jpegData(from: XCTUnwrap(context.makeImage()), compressionQuality: 0.8))
    }
}
