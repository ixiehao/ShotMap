import AppKit
import XCTest
@testable import ShotMapApp

final class PreviewResponsivenessTests: XCTestCase {
    @MainActor
    func testUnchangedThumbnailReusesBitmapButChangedPayloadRefreshesIt() async throws {
        let loader = FrameThumbnailLoader()
        let probe = ThumbnailDecodeProbe()
        let first = FrameThumbnailRequest(data: try imageData(width: 160), maximumPixelSize: 80)
        let decode: @Sendable (FrameThumbnailRequest) async throws -> CGImage? = {
            try await probe.decode($0)
        }
        for _ in 0..<100 {
            await loader.load(first, decode: decode)
        }
        let firstDecodeCount = await probe.count
        XCTAssertEqual(firstDecodeCount, 1, "Selection and playhead redraws must reuse an unchanged bitmap")
        XCTAssertEqual(loader.image?.width, 80)

        // Frame IDs can remain unchanged after refinement; the new payload
        // still needs a fresh image even if its maximum display size is equal.
        let replacement = FrameThumbnailRequest(data: try imageData(width: 48), maximumPixelSize: 80)
        await loader.load(replacement, decode: decode)
        let finalDecodeCount = await probe.count
        XCTAssertEqual(finalDecodeCount, 2)
        XCTAssertEqual(loader.image?.width, 48)
        let mainThreadDecodes = await probe.mainThreadDecodes
        XCTAssertEqual(mainThreadDecodes, 0)
    }

    @MainActor
    func testLateThumbnailCannotReplaceNewerFrameOrRepopulateClosedCell() async throws {
        let loader = FrameThumbnailLoader()
        let delayed = ThumbnailDecodeGate()
        let oldRequest = FrameThumbnailRequest(data: try imageData(width: 32), maximumPixelSize: 160)
        let currentRequest = FrameThumbnailRequest(data: try imageData(width: 96), maximumPixelSize: 160)
        let old = Task {
            await loader.load(oldRequest) { request in
                await delayed.wait()
                return try await FrameThumbnailDecoder.shared.decode(request)
            }
        }
        try await waitForGate(delayed)
        await loader.load(currentRequest)
        XCTAssertEqual(loader.image?.width, 96)
        await delayed.resume()
        await old.value
        XCTAssertEqual(loader.image?.width, 96, "A previous decode must not flash over the current frame")

        let closingGate = ThumbnailDecodeGate()
        let closing = Task {
            await loader.load(oldRequest) { request in
                await closingGate.wait()
                return try await FrameThumbnailDecoder.shared.decode(request)
            }
        }
        try await waitForGate(closingGate)
        loader.clear()
        await closingGate.resume()
        await closing.value
        XCTAssertNil(loader.image, "Offscreen/closed cells release their image even if work finishes late")
    }

    func testCancelledThumbnailStopsBeforeDecoding() async throws {
        let request = FrameThumbnailRequest(data: try imageData(width: 160), maximumPixelSize: 80)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await FrameThumbnailDecoder.shared.decode(request)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
    }

    func testPortraitThumbnailsPreserveRetinaWidthAndFilmstripCropDetail() {
        XCTAssertEqual(FrameThumbnailSizing.maximumPixelSize(
            for: CGSize(width: 340, height: 340 * 9 / 16),
            aspectRatio: 16.0 / 9, scale: 2, fills: false
        ), 680)
        XCTAssertEqual(FrameThumbnailSizing.maximumPixelSize(
            for: CGSize(width: 340, height: CGFloat(340) / (9.0 / 16)),
            aspectRatio: 9.0 / 16, scale: 2, fills: false
        ), 1_209)
        XCTAssertEqual(FrameThumbnailSizing.maximumPixelSize(
            for: CGSize(width: 140, height: 62),
            aspectRatio: 9.0 / 16, scale: 2, fills: true
        ), 498)
        XCTAssertEqual(FrameThumbnailSizing.maximumPixelSize(
            for: CGSize(width: 16_384, height: 16_384),
            aspectRatio: 1, scale: 2, fills: true
        ), 1_280, "Resizing must keep each decoded display bitmap bounded")
    }

    @MainActor
    func testFinishingBatchReleasesLiveCardsAndKeepsCompletedPresentation() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = StoryboardViewModel()
        let source = directory.appendingPathComponent("video.mp4")
        let data = try imageData(width: 160)
        let image = try XCTUnwrap(ImageCodec.cgImage(from: data))
        model.beginJob(source: source, jobIndex: 0, batchIndex: 0, total: 1, gridSide: 8, layoutAspect: .source)
        for index in 0..<64 {
            model.appendPreview(image, aspectRatio: 16.0 / 9, index: index, total: 64)
        }
        let liveImage = WeakPreviewImage(model.livePreviewFrames[0]?.image)
        XCTAssertNotNil(liveImage.value)
        _ = await model.completeJob(data: data, result: StoryboardResult(frames: [], sourceURL: source),
                                    settings: ExportSettings(format: .jpeg), index: 0, total: 1)
        model.finishBatch()
        XCTAssertEqual(model.livePreviewFrameCount, 0)
        XCTAssertTrue(model.livePreviewFrames.isEmpty)
        XCTAssertNil(liveImage.value, "The completed grid no longer needs 64 individual display images")
        XCTAssertNotNil(model.previewImage)
        XCTAssertEqual(model.completedPreviews.count, 1)
    }

    @MainActor
    func testDeletedHistoryExportRestoresLastPresentedRecordAndActions() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = StoryboardViewModel()
        let previews = try await populateHistory(model, directory: directory)
        model.showPreviousPreview()
        try await waitForPreview(model)
        let visibleImage = model.previewImage
        try FileManager.default.removeItem(at: XCTUnwrap(previews[1].savedURL))

        model.showNextPreview()
        try await waitForPreview(model)

        XCTAssertTrue(model.showError)
        XCTAssertEqual(model.completedPreviews[model.selectedPreviewIndex].id, previews[0].id)
        XCTAssertTrue(model.previewImage === visibleImage)
        XCTAssertEqual(model.lastSavedURL, previews[0].savedURL)
        XCTAssertEqual(model.manualEditorRequest?.previewID, previews[0].id)
        XCTAssertNil(model.pendingData)
        XCTAssertEqual(model.outputDescription, model.language.text("status.saved", 1, 2, try XCTUnwrap(previews[0].savedURL).lastPathComponent))
    }

    @MainActor
    func testLateFailedHistoryLoadDoesNotUndoRapidReturnToCurrentResult() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let delayed = BlockingPreviewLoader(
            blockedSource: directory.appendingPathComponent("second.mp4"),
            started: expectation(description: "Second result is loading"),
            finished: expectation(description: "Obsolete load finishes")
        )
        defer { delayed.release() }
        let model = StoryboardViewModel(previewLoader: { try delayed.load($0) })
        let previews = try await populateHistory(model, directory: directory)
        model.showPreviousPreview()
        try await waitForPreview(model)
        model.showNextPreview()
        await fulfillment(of: [delayed.started], timeout: 3)
        model.showPreviousPreview()
        try await waitForPreview(model)
        delayed.release()
        await fulfillment(of: [delayed.finished], timeout: 3)
        for _ in 0..<10 { await Task.yield() }

        XCTAssertFalse(model.showError, "A cancelled, older request must not present a new error")
        XCTAssertEqual(model.completedPreviews[model.selectedPreviewIndex].id, previews[0].id)
        XCTAssertEqual(model.lastSavedURL, previews[0].savedURL)
        XCTAssertEqual(model.manualEditorRequest?.previewID, previews[0].id)
    }

    @MainActor
    private func populateHistory(_ model: StoryboardViewModel, directory: URL) async throws -> [RenderedStoryboardPreview] {
        for (index, name) in ["first", "second"].enumerated() {
            _ = await model.completeJob(
                data: try imageData(width: (index + 1) * 96),
                result: StoryboardResult(frames: [], sourceURL: directory.appendingPathComponent("\(name).mp4")),
                settings: ExportSettings(format: .jpeg), index: index, total: 2
            )
        }
        return model.completedPreviews
    }

    @MainActor
    private func waitForPreview(_ model: StoryboardViewModel) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while model.isLoadingPreview, ContinuousClock.now < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertFalse(model.isLoadingPreview)
    }

    private func waitForGate(_ gate: ThumbnailDecodeGate) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await gate.isWaiting), ContinuousClock.now < deadline {
            await Task.yield()
        }
        let waiting = await gate.isWaiting
        XCTAssertTrue(waiting)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotMap-preview-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func imageData(width: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: width * 9 / 16,
                                            bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: width * 9 / 16))
        return try XCTUnwrap(ImageCodec.jpegData(from: XCTUnwrap(context.makeImage()), compressionQuality: 0.8))
    }
}

private actor ThumbnailDecodeProbe {
    private(set) var count = 0
    private(set) var mainThreadDecodes = 0

    func decode(_ request: FrameThumbnailRequest) throws -> CGImage? {
        count += 1
        if Thread.isMainThread { mainThreadDecodes += 1 }
        return ImageCodec.thumbnail(from: request.data, maximumPixelSize: request.maximumPixelSize)
    }
}

private final class WeakPreviewImage {
    weak var value: NSImage?
    init(_ value: NSImage?) { self.value = value }
}

private actor ThumbnailDecodeGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    var isWaiting: Bool { continuation != nil }

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private final class BlockingPreviewLoader: @unchecked Sendable {
    let blockedSource: URL
    let started: XCTestExpectation
    let finished: XCTestExpectation
    private let gate = DispatchSemaphore(value: 0)

    init(blockedSource: URL, started: XCTestExpectation, finished: XCTestExpectation) {
        self.blockedSource = blockedSource
        self.started = started
        self.finished = finished
    }

    func load(_ preview: RenderedStoryboardPreview) throws -> PreparedPreviewPresentation {
        guard preview.sourceURL == blockedSource else { return try preview.loadPresentation() }
        started.fulfill()
        _ = gate.wait(timeout: .now() + 5)
        defer { finished.fulfill() }
        throw CocoaError(.fileReadNoSuchFile)
    }

    func release() { gate.signal() }
}
