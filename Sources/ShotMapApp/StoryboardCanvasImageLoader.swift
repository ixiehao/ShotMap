import CoreGraphics
import Combine
import Foundation

/// Metadata only: no NSImage or unbounded export data crosses executors.
struct StoryboardCanvasImageRequest: Equatable, Sendable {
    let sourceURL: URL
    let previewIdentity: ObjectIdentifier

    init?(sourceURL: URL?, previewIdentity: ObjectIdentifier) {
        guard let sourceURL, sourceURL.isFileURL else { return nil }
        self.sourceURL = sourceURL.standardizedFileURL
        self.previewIdentity = previewIdentity
    }
}

struct StoryboardCanvasDetailImage {
    let image: CGImage
    let previewIdentity: ObjectIdentifier
}

/// This is a display enhancement for one current result, not an export cache.
/// A 2560² 8-bit RGBA image uses about 25 MiB; unusual higher-stride images are
/// rejected above 32 MiB of retained pixel storage. ImageIO's transient buffers
/// and GPU/WindowServer allocations are not covered by this retained-byte cap.
actor StoryboardCanvasImageDecoder {
    static let shared = StoryboardCanvasImageDecoder()
    static let maximumPixelSize = 2_560
    static let maximumRetainedBytes = 32 * 1_024 * 1_024

    func decode(_ request: StoryboardCanvasImageRequest) throws -> CGImage? {
        try Task.checkCancellation()
        let image = autoreleasepool {
            ImageCodec.thumbnail(at: request.sourceURL, maximumPixelSize: Self.maximumPixelSize)
        }
        try Task.checkCancellation()
        guard let image, Self.isBounded(image) else { return nil }
        return image
    }

    static func isBounded(_ image: CGImage) -> Bool {
        image.width > 0 && image.height > 0
            && image.width <= maximumPixelSize && image.height <= maximumPixelSize
            && image.bytesPerRow <= maximumRetainedBytes / image.height
    }
}

@MainActor
final class StoryboardCanvasImageLoader: ObservableObject {
    @Published private(set) var detail: StoryboardCanvasDetailImage?
    private var request: StoryboardCanvasImageRequest?
    private var loadID = UUID()

    func load(_ request: StoryboardCanvasImageRequest?) async {
        await load(request) { request in
            try await StoryboardCanvasImageDecoder.shared.decode(request)
        }
    }

    func load(
        _ request: StoryboardCanvasImageRequest?,
        decode: @Sendable (StoryboardCanvasImageRequest) async throws -> CGImage?
    ) async {
        guard self.request != request else { return }
        let id = UUID()
        loadID = id
        self.request = request
        detail = nil
        guard let request else { return }
        do {
            let image = try await decode(request)
            try Task.checkCancellation()
            guard loadID == id, self.request == request else { return }
            if let image, StoryboardCanvasImageDecoder.isBounded(image) {
                detail = StoryboardCanvasDetailImage(image: image, previewIdentity: request.previewIdentity)
            }
        } catch {
            // The low-resolution presentation remains visible on any failure.
            // A cancelled predecessor must not clear a newer result's detail.
            guard loadID == id else { return }
            detail = nil
        }
    }

    func clear() {
        loadID = UUID()
        request = nil
        detail = nil
    }
}
