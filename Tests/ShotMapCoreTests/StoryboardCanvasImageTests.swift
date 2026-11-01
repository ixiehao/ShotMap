import AppKit
import XCTest
@testable import ShotMapApp

final class StoryboardCanvasImageTests: XCTestCase {
    func testFileBackedDecodeLimitsRealLargeImageAndKeepsAspect() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotMap-canvas-image-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("wide.png")
        let source = try image(width: 4_096, height: 1_024)
        try XCTUnwrap(ImageCodec.data(from: source, format: .png)).write(to: url)
        let owner = NSObject()
        let request = try XCTUnwrap(StoryboardCanvasImageRequest(sourceURL: url, previewIdentity: ObjectIdentifier(owner)))
        let result = try await StoryboardCanvasImageDecoder.shared.decode(request)
        let decoded = try XCTUnwrap(result)
        XCTAssertEqual(decoded.width, 2_560)
        XCTAssertEqual(decoded.height, 640)
        XCTAssertLessThanOrEqual(decoded.bytesPerRow * decoded.height, 32 * 1_024 * 1_024)
    }

    @MainActor
    func testUnchangedResultDoesNotDecodeOnRepeatedPresentationUpdates() async throws {
        let loader = StoryboardCanvasImageLoader()
        let probe = CanvasDetailDecodeProbe()
        let owner = NSImage(size: CGSize(width: 1_280, height: 720))
        let request = try XCTUnwrap(StoryboardCanvasImageRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/unchanged-canvas-result.png"), previewIdentity: ObjectIdentifier(owner)))
        let decode: @Sendable (StoryboardCanvasImageRequest) async throws -> CGImage? = { request in
            try await probe.decode(request)
        }
        for _ in 0..<20 { await loader.load(request, decode: decode) }
        let count = await probe.count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(loader.detail?.previewIdentity, ObjectIdentifier(owner))
        XCTAssertEqual(loader.detail?.image.width, 96)
    }

    @MainActor
    func testLateResultAtSameURLCannotReplaceNewPreviewOrRepopulateClosedCanvas() async throws {
        let loader = StoryboardCanvasImageLoader()
        let url = URL(fileURLWithPath: "/tmp/reused-canvas-path.png")
        let oldOwner = NSImage(size: CGSize(width: 1_280, height: 720))
        let newOwner = NSImage(size: CGSize(width: 1_280, height: 720))
        let oldRequest = try XCTUnwrap(StoryboardCanvasImageRequest(sourceURL: url, previewIdentity: ObjectIdentifier(oldOwner)))
        let currentRequest = try XCTUnwrap(StoryboardCanvasImageRequest(sourceURL: url, previewIdentity: ObjectIdentifier(newOwner)))
        let oldImage = try image(width: 32, height: 18)
        let currentImage = try image(width: 96, height: 54)
        let gate = CanvasDetailDecodeGate()
        let old = Task {
            await loader.load(oldRequest) { _ in
                await gate.wait()
                return oldImage
            }
        }
        try await waitForGate(gate)
        await loader.load(currentRequest) { _ in currentImage }
        await gate.resume()
        await old.value
        XCTAssertEqual(loader.detail?.image.width, 96)
        XCTAssertEqual(loader.detail?.previewIdentity, ObjectIdentifier(newOwner))

        let closingGate = CanvasDetailDecodeGate()
        let closing = Task {
            await loader.load(oldRequest) { _ in
                await closingGate.wait()
                return oldImage
            }
        }
        try await waitForGate(closingGate)
        loader.clear()
        await closingGate.resume()
        await closing.value
        XCTAssertNil(loader.detail)
    }

    func testCancelledRequestStopsBeforeFileDecoding() async throws {
        let owner = NSObject()
        let request = try XCTUnwrap(StoryboardCanvasImageRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/cancelled-canvas-result.png"), previewIdentity: ObjectIdentifier(owner)))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await StoryboardCanvasImageDecoder.shared.decode(request)
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

    @MainActor
    func testDetailUpgradeKeepsWholeImageGeometryAndFit() throws {
        let view = StoryboardCanvasScrollView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        let original = NSImage(size: CGSize(width: 1_280, height: 720))
        view.configure(image: original, isLightAppearance: true, label: "Preview")
        view.layoutSubtreeIfNeeded()
        let oldFrame = try XCTUnwrap(view.documentView).frame
        let oldVisible = view.documentVisibleRect
        let oldMagnification = view.magnification
        let detail = StoryboardCanvasDetailImage(image: try image(width: 2_560, height: 1_440), previewIdentity: ObjectIdentifier(original))
        view.configure(image: original, isLightAppearance: true, label: "Preview", detail: detail)
        view.layoutSubtreeIfNeeded()

        let document = try XCTUnwrap(view.documentView as? NSImageView)
        XCTAssertEqual(document.frame, oldFrame)
        XCTAssertEqual(document.image?.size, original.size)
        XCTAssertEqual(document.image?.representations.first?.pixelsWide, 2_560)
        XCTAssertTrue(view.documentVisibleRect.contains(document.bounds))
        XCTAssertEqual(view.magnification, oldMagnification, accuracy: 0.001)
        XCTAssertEqual(view.documentVisibleRect.minX, oldVisible.minX, accuracy: 0.01)
        XCTAssertEqual(view.documentVisibleRect.minY, oldVisible.minY, accuracy: 0.01)
    }

    @MainActor
    func testFailedOrMismatchedDetailRetainsOriginalAndCloseReleasesBacking() async throws {
        let view = StoryboardCanvasScrollView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        let original = NSImage(size: CGSize(width: 1_280, height: 720))
        view.configure(image: original, isLightAppearance: true, label: "Preview")
        let loader = StoryboardCanvasImageLoader()
        let missing = try XCTUnwrap(StoryboardCanvasImageRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/ShotMap-missing-\(UUID()).jpg"), previewIdentity: ObjectIdentifier(original)))
        await loader.load(missing)
        view.configure(image: original, isLightAppearance: true, label: "Preview", detail: loader.detail)
        let document = try XCTUnwrap(view.documentView as? NSImageView)
        XCTAssertTrue(document.image === original)

        let differentOwner = NSImage(size: original.size)
        let wrong = StoryboardCanvasDetailImage(image: try image(width: 64, height: 36), previewIdentity: ObjectIdentifier(differentOwner))
        view.configure(image: original, isLightAppearance: true, label: "Preview", detail: wrong)
        XCTAssertTrue(document.image === original)
        view.releasePresentation()
        XCTAssertNil(document.image)
    }

    private func waitForGate(_ gate: CanvasDetailDecodeGate) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await gate.isWaiting), ContinuousClock.now < deadline { await Task.yield() }
        let waiting = await gate.isWaiting
        XCTAssertTrue(waiting)
    }

    private func image(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                            bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}

private actor CanvasDetailDecodeProbe {
    private(set) var count = 0

    func decode(_ request: StoryboardCanvasImageRequest) throws -> CGImage? {
        count += 1
        return CGContext(data: nil, width: 96, height: 54, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }
}

private actor CanvasDetailDecodeGate {
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
