import CoreGraphics
import SwiftUI

/// Comparing the immutable JPEG payload also catches a higher-quality image
/// replacing a frame with the same ID. Data keeps its shared backing storage;
/// no image is decoded while SwiftUI compares or rebuilds this request.
struct FrameThumbnailRequest: Equatable, Sendable {
    let data: Data
    let maximumPixelSize: Int

    init(data: Data, maximumPixelSize: Int) {
        self.data = data
        self.maximumPixelSize = min(1_280, max(1, maximumPixelSize))
    }
}

enum FrameThumbnailSizing {
    static func maximumPixelSize(for size: CGSize, aspectRatio: Double, scale: CGFloat, fills: Bool) -> Int {
        guard size.width.isFinite, size.height.isFinite, scale.isFinite else { return 1 }
        let aspect = StoryboardAspect.source.resolvedCardAspectRatio(sourceAspectRatio: aspectRatio)
        let width = max(1, Double(size.width))
        let height = max(1, Double(size.height))
        let imageWidth = fills ? max(width, height * aspect) : min(width, height * aspect)
        let longestEdge = max(imageWidth, imageWidth / aspect) * max(1, Double(scale))
        return Int(min(1_280, max(1, longestEdge.rounded(.up))))
    }
}

/// ImageIO decoding is serialized away from MainActor. A newly visible gallery
/// must not start dozens of full-size decodes concurrently, and cancelled cells
/// are skipped before their queued work allocates a bitmap.
actor FrameThumbnailDecoder {
    static let shared = FrameThumbnailDecoder()

    func decode(_ request: FrameThumbnailRequest) throws -> CGImage? {
        try Task.checkCancellation()
        let image = autoreleasepool {
            ImageCodec.thumbnail(from: request.data, maximumPixelSize: request.maximumPixelSize)
        }
        try Task.checkCancellation()
        return image
    }
}

@MainActor
final class FrameThumbnailLoader: ObservableObject {
    @Published private(set) var image: CGImage?
    private var request: FrameThumbnailRequest?
    private var loadID = UUID()

    func load(_ request: FrameThumbnailRequest) async {
        await load(request) { request in
            try await FrameThumbnailDecoder.shared.decode(request)
        }
    }

    func load(
        _ request: FrameThumbnailRequest,
        decode: @Sendable (FrameThumbnailRequest) async throws -> CGImage?
    ) async {
        guard self.request != request || image == nil else { return }
        let id = UUID()
        loadID = id
        self.request = request
        image = nil
        do {
            let decoded = try await decode(request)
            try Task.checkCancellation()
            guard loadID == id else { return }
            image = decoded
        } catch {
            // A cancelled old request must not erase the next frame's image.
            guard loadID == id else { return }
            image = nil
        }
    }

    func clear() {
        loadID = UUID()
        request = nil
        image = nil
    }
}

/// A cell owns only its display-sized bitmap. Selection changes and playhead
/// updates reuse it; scrolling it away or closing the editor releases it.
@MainActor
struct FrameThumbnailImage: View {
    let frame: CapturedFrame
    let maximumPixelSize: Int
    var contentMode: ContentMode = .fit
    @StateObject private var loader = FrameThumbnailLoader()

    var body: some View {
        let request = FrameThumbnailRequest(data: frame.jpegData, maximumPixelSize: maximumPixelSize)
        Group {
            if let image = loader.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.black.opacity(0.08)
            }
        }
        .task(id: request) { await loader.load(request) }
        .onDisappear { loader.clear() }
    }
}
