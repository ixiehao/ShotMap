import AppKit
import SwiftUI

/// Show the complete exported image. The enclosing window adapts to its
/// aspect ratio; no inspection controls take space away from the result.
@MainActor
struct StoryboardCanvas: View {
    let image: NSImage
    let isLightAppearance: Bool
    let language: AppLanguage
    var savedURL: URL? = nil

    var body: some View {
        StoryboardCanvasPresentation(image: image, isLightAppearance: isLightAppearance,
                                     language: language, savedURL: savedURL)
            .id(ObjectIdentifier(image))
    }
}

@MainActor
private struct StoryboardCanvasPresentation: View {
    let image: NSImage
    let isLightAppearance: Bool
    let language: AppLanguage
    let savedURL: URL?
    @StateObject private var detailLoader = StoryboardCanvasImageLoader()

    var body: some View {
        let request = StoryboardCanvasImageRequest(sourceURL: savedURL, previewIdentity: ObjectIdentifier(image))
        StoryboardCanvasSurface(image: image, detail: detailLoader.detail,
                                isLightAppearance: isLightAppearance, label: language.text("preview.title"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("storyboard-canvas")
            .task(id: request) { await detailLoader.load(request) }
            .onDisappear { detailLoader.clear() }
    }
}

private struct StoryboardCanvasSurface: NSViewRepresentable {
    let image: NSImage
    let detail: StoryboardCanvasDetailImage?
    let isLightAppearance: Bool
    let label: String

    func makeNSView(context: Context) -> StoryboardCanvasScrollView {
        StoryboardCanvasScrollView(frame: .zero)
    }

    func updateNSView(_ nsView: StoryboardCanvasScrollView, context: Context) {
        nsView.configure(image: image, isLightAppearance: isLightAppearance, label: label, detail: detail)
    }

    static func dismantleNSView(_ nsView: StoryboardCanvasScrollView, coordinator: ()) {
        nsView.releasePresentation()
        nsView.documentView = nil
    }
}

/// Native image presentation keeps a single bounded high-resolution backing.
/// Magnification is only used internally to fit the whole image to the viewport.
@MainActor
final class StoryboardCanvasScrollView: NSScrollView {
    private let imageView = CanvasImageView(frame: .zero)
    private var configuredImage: NSImage?
    private var configuredDetail: CGImage?
    private var previousViewportSize = CGSize.zero
    private var isUpdatingCanvas = false
    private(set) var fitMagnification: CGFloat = 1

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        borderType = .noBorder
        contentView = CenteredCanvasClipView(frame: .zero)
        contentView.drawsBackground = false
        automaticallyAdjustsContentInsets = false
        hasHorizontalScroller = false
        hasVerticalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        usesPredominantAxisScrolling = false
        horizontalScrollElasticity = .automatic
        verticalScrollElasticity = .automatic
        allowsMagnification = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.isEditable = false
        imageView.setAccessibilityIdentifier("storyboard-canvas-image")
        documentView = imageView
    }

    required init?(coder: NSCoder) { nil }

    func configure(image: NSImage, isLightAppearance: Bool, label: String,
                   detail: StoryboardCanvasDetailImage? = nil) {
        backgroundColor = isLightAppearance
            ? NSColor(calibratedRed: 0.937, green: 0.949, blue: 0.965, alpha: 1)
            : NSColor(calibratedRed: 0.071, green: 0.086, blue: 0.110, alpha: 1)
        drawsBackground = true
        imageView.setAccessibilityLabel(label)
        let changedImage = configuredImage !== image
        if changedImage {
            configuredImage = image
            configuredDetail = nil
            imageView.image = image
            imageView.frame = CGRect(origin: .zero, size: validImageSize(image.size))
            previousViewportSize = .zero
        }
        let acceptedDetail = detail?.previewIdentity == ObjectIdentifier(image) ? detail?.image : nil
        if configuredDetail !== acceptedDetail {
            configuredDetail = acceptedDetail
            if let acceptedDetail {
                // Preserve the original document coordinates. The
                // extra pixels change rendering detail, not image geometry.
                imageView.image = NSImage(cgImage: acceptedDetail, size: validImageSize(image.size))
            } else {
                imageView.image = image
            }
            imageView.needsDisplay = true
        }
        updateCanvas()
    }

    func releasePresentation() {
        configuredDetail = nil
        configuredImage = nil
        imageView.image = nil
    }

    override func layout() {
        super.layout()
        updateCanvas()
    }

    private func validImageSize(_ size: CGSize) -> CGSize {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return CGSize(width: 1, height: 1)
        }
        return size
    }

    private func updateCanvas() {
        guard !isUpdatingCanvas, configuredImage != nil,
              contentSize.width > 0, contentSize.height > 0 else { return }
        isUpdatingCanvas = true
        defer { isUpdatingCanvas = false }
        let viewport = contentSize
        let newFit = PreviewCanvasLayout.fitScale(imageSize: imageView.frame.size, viewportSize: viewport)
        let target = newFit
        let changedViewport = viewport != previousViewportSize
        previousViewportSize = viewport
        fitMagnification = newFit
        let newMaximum = newFit
        // Set the larger bound first so a tiny image can also fill a large pane.
        maxMagnification = max(minMagnification, newMaximum)
        minMagnification = newFit
        maxMagnification = newMaximum
        if abs(magnification - target) > 0.0001 || changedViewport {
            let visible = documentVisibleRect
            let center = CGPoint(x: visible.midX, y: visible.midY)
            setMagnification(target, centeredAt: center)
        }
        let visible = contentView.bounds.size
        let point = CGPoint(x: (imageView.frame.width - visible.width) / 2,
                            y: (imageView.frame.height - visible.height) / 2)
        contentView.scroll(to: point)
        reflectScrolledClipView(contentView)
    }
}

@MainActor
private final class CanvasImageView: NSImageView {
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(enclosingScrollView)
        super.mouseDown(with: event)
    }
}

@MainActor
private final class CenteredCanvasClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return constrained }
        let document = documentView.frame
        if document.width < proposedBounds.width {
            constrained.origin.x = document.minX - (proposedBounds.width - document.width) / 2
        }
        if document.height < proposedBounds.height {
            constrained.origin.y = document.minY - (proposedBounds.height - document.height) / 2
        }
        return constrained
    }
}
