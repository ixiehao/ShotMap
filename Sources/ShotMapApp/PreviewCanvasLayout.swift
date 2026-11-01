import CoreGraphics

/// Preview scale is relative to a whole-image fit, not export pixel dimensions.
/// The supplied bitmap is intentionally display-sized to bound memory use.
enum PreviewCanvasLayout {
    static let inset: CGFloat = 12

    static func fitScale(imageSize: CGSize, viewportSize: CGSize, inset: CGFloat = PreviewCanvasLayout.inset) -> CGFloat {
        guard imageSize.width.isFinite, imageSize.height.isFinite,
              viewportSize.width.isFinite, viewportSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0 else { return 1 }
        let padding = max(0, inset)
        let availableWidth = max(1, viewportSize.width - padding * 2)
        let availableHeight = max(1, viewportSize.height - padding * 2)
        return max(0.0001, min(availableWidth / imageSize.width, availableHeight / imageSize.height))
    }

    struct GridMetrics {
        let tileSize: CGSize
        let gridSize: CGSize
    }

    /// Equal horizontal/vertical gaps mean the whole grid's aspect is not
    /// exactly the card's aspect. Fit actual row and column extents instead.
    static func gridMetrics(side: Int, cardAspect: Double, availableSize: CGSize, gap: CGFloat = 5) -> GridMetrics {
        let count = min(8, max(1, side))
        let aspect = cardAspect.isFinite && cardAspect > 0 ? CGFloat(cardAspect) : 16.0 / 9.0
        let spacing = max(0, gap) * CGFloat(count - 1)
        let widthLimit = max(1, availableSize.width - spacing) / CGFloat(count)
        let heightLimit = max(1, availableSize.height - spacing) / CGFloat(count)
        let tileWidth = max(1, min(widthLimit, heightLimit * aspect))
        let tileHeight = tileWidth / aspect
        return GridMetrics(
            tileSize: CGSize(width: tileWidth, height: tileHeight),
            gridSize: CGSize(width: tileWidth * CGFloat(count) + spacing,
                             height: tileHeight * CGFloat(count) + spacing)
        )
    }
}
