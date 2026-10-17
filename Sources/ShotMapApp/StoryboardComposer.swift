import CoreGraphics
import CoreText
import Foundation

enum StoryboardComposer {
    static func render(result: StoryboardResult, settings: ExportSettings) throws -> Data {
        try Task.checkCancellation()
        let layout = makeLayout(
            requestedWidth: settings.safeWidth,
            gridSide: settings.gridSide,
            cardAspectRatio: settings.resolvedCardAspectRatio(for: result.frames)
        )
        let width = layout.width
        let height = layout.height
        let side = settings.gridSide

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw StoryboardError.noExportData }

        let background = settings.background.rgb
        context.setFillColor(
            CGColor(
                red: background.red,
                green: background.green,
                blue: background.blue,
                alpha: 1
            )
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for cellIndex in 0..<(side * side) {
            // Rendering a large 8 × 8 export can take noticeable time on an
            // Intel Mac. Let a cancelled batch stop between cards instead of
            // always completing a now-unneeded bitmap and encoder pass.
            try Task.checkCancellation()
            let column = cellIndex % side
            let row = side - 1 - cellIndex / side
            let x = layout.margin + column * (layout.cellWidth + layout.gap)
            let y = layout.margin + row * (layout.cellHeight + layout.gap)
            let rect = CGRect(x: x, y: y, width: layout.cellWidth, height: layout.cellHeight)
            let frame = result.frames[safe: cellIndex] ?? result.frames.last
            drawCard(
                in: context,
                rect: rect,
                imageData: frame?.jpegData,
                timestamp: frame?.time,
                showsTimestamp: settings.showTimestamps
            )
        }

        if let title = settings.titleWatermark(for: result.sourceURL) {
            drawTitleWatermark(title, canvasSize: CGSize(width: width, height: height), context: context)
        }

        try Task.checkCancellation()
        guard let image = context.makeImage() else { throw StoryboardError.noExportData }
        try Task.checkCancellation()
        guard let data = ImageCodec.data(from: image, format: settings.format, jpegCompressionQuality: 0.94) else {
            throw StoryboardError.noExportData
        }
        return data
    }

    /// Keeps a high requested width for ordinary exports while putting a hard
    /// ceiling on memory use for a very tall 8×8 phone-video contact sheet.
    /// The normal 2560 px portrait case remains untouched; only exceptional
    /// 12,000 px requests are scaled down before allocating a bitmap context.
    static func canvasSize(result: StoryboardResult, settings: ExportSettings) -> CGSize {
        let layout = makeLayout(
            requestedWidth: settings.safeWidth,
            gridSide: settings.gridSide,
            cardAspectRatio: settings.resolvedCardAspectRatio(for: result.frames)
        )
        return CGSize(width: layout.width, height: layout.height)
    }

    private static func makeLayout(
        requestedWidth: Int,
        gridSide: Int,
        cardAspectRatio: Double
    ) -> StoryboardLayout {
        let safeSide = max(1, gridSide)
        let safeRatio = max(1.0 / 3.0, min(3, cardAspectRatio))
        // A bitmap context needs four bytes per pixel before ImageIO creates its
        // encoded data. 64 MP keeps the working bitmap near 244 MiB rather than
        // allowing a 12,000 px portrait contact sheet to exceed 400 MiB. This is
        // especially important on 8 GB Intel Macs where the image, JPEG buffers
        // and Vision thumbnails may coexist.
        let maxDimension = 16_384.0
        let maxPixels = 64_000_000.0
        var width = requestedWidth

        // Margins and integer cell sizes are recalculated after scaling, so one
        // pass can land fractionally over the budget. Re-evaluate the resulting
        // layout to keep the advertised dimension and memory limits real.
        for _ in 0..<8 {
            let layout = StoryboardLayout(width: width, gridSide: safeSide, cardAspectRatio: safeRatio)
            let pixelCount = Double(layout.width) * Double(layout.height)
            let scale = min(
                1,
                maxDimension / Double(max(layout.width, layout.height)),
                sqrt(maxPixels / max(1, pixelCount))
            )
            // Any overage, however small, matters for a hard bitmap-memory cap.
            guard scale < 1 else { return layout }

            // Force at least a one-pixel reduction while above budget. Without
            // this, a near-1 scale can round back to the same width forever.
            let scaledWidth = Int((Double(width) * scale).rounded(.down))
            let nextWidth = max(1_920, min(width - 1, scaledWidth))
            guard nextWidth < width else { return layout }
            width = nextWidth
        }
        return StoryboardLayout(width: width, gridSide: safeSide, cardAspectRatio: safeRatio)
    }

    private static func drawCard(
        in context: CGContext,
        rect: CGRect,
        imageData: Data?,
        timestamp: Double?,
        showsTimestamp: Bool
    ) {
        let radius = min(rect.width, rect.height) * 0.055
        let cardPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.setFillColor(CGColor(red: 0.15, green: 0.17, blue: 0.22, alpha: 1))
        context.addPath(cardPath)
        context.fillPath()

        guard let imageData, let image = ImageCodec.cgImage(from: imageData) else { return }
        context.saveGState()
        context.addPath(cardPath)
        context.clip()
        drawAspectFill(image, in: rect, context: context)
        context.restoreGState()

        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
        context.setLineWidth(max(1, rect.width * 0.003))
        context.addPath(cardPath)
        context.strokePath()

        if showsTimestamp, let timestamp {
            drawTimestamp(timestamp, in: rect, context: context)
        }
    }

    private static func drawTimestamp(_ timestamp: Double, in rect: CGRect, context: CGContext) {
        let fontSize = max(10, rect.width * 0.043)
        let font = WatermarkTypography.titleFont(size: fontSize)
        let text = TimestampFormatter.string(for: timestamp) as CFString
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 0.96)
        ]
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text, attributes as CFDictionary))
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let horizontalPadding = fontSize * 0.52
        let verticalPadding = fontSize * 0.30
        let labelHeight = fontSize + verticalPadding * 2
        let labelRect = CGRect(
            x: rect.minX + fontSize * 0.42,
            y: rect.minY + fontSize * 0.42,
            width: textWidth + horizontalPadding * 2,
            height: labelHeight
        )

        context.saveGState()
        context.setFillColor(CGColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 0.72))
        context.addPath(CGPath(roundedRect: labelRect, cornerWidth: labelHeight * 0.36, cornerHeight: labelHeight * 0.36, transform: nil))
        context.fillPath()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: labelRect.minX + horizontalPadding, y: labelRect.minY + verticalPadding)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func drawTitleWatermark(_ title: String, canvasSize: CGSize, context: CGContext) {
        let fontSize = max(42, min(canvasSize.width * 0.065, canvasSize.height * 0.19))
        let font = WatermarkTypography.titleFont(size: fontSize)
        var alignment = CTTextAlignment.center
        var lineBreakMode = CTLineBreakMode.byCharWrapping
        let paragraph = withUnsafePointer(to: &alignment) { alignmentPointer in
            withUnsafePointer(to: &lineBreakMode) { lineBreakPointer in
                var settings = [
                    CTParagraphStyleSetting(
                        spec: .alignment,
                        valueSize: MemoryLayout<CTTextAlignment>.size,
                        value: alignmentPointer
                    ),
                    CTParagraphStyleSetting(
                        spec: .lineBreakMode,
                        valueSize: MemoryLayout<CTLineBreakMode>.size,
                        value: lineBreakPointer
                    )
                ]
                return CTParagraphStyleCreate(&settings, settings.count)
            }
        }
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTParagraphStyleAttributeName: paragraph,
            // The dark shadow preserves legibility without turning the title
            // into an opaque banner over the selected images.
            kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 0.68)
        ]
        guard let string = CFAttributedStringCreate(nil, title as CFString, attributes as CFDictionary) else { return }
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let maximumWidth = canvasSize.width * 0.82
        let maximumHeight = canvasSize.height * 0.38
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: maximumWidth, height: maximumHeight),
            nil
        )
        let textHeight = min(maximumHeight, max(fontSize * 1.25, ceil(suggestedSize.height)))
        let textRect = CGRect(
            x: (canvasSize.width - maximumWidth) / 2,
            y: (canvasSize.height - textHeight) / 2,
            width: maximumWidth,
            height: textHeight
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            CGPath(rect: textRect, transform: nil),
            nil
        )

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -fontSize * 0.035),
            blur: fontSize * 0.16,
            color: CGColor(red: 0, green: 0, blue: 0.02, alpha: 0.72)
        )
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private static func drawAspectFill(_ image: CGImage, in rect: CGRect, context: CGContext) {
        let sourceRatio = CGFloat(image.width) / CGFloat(image.height)
        let targetRatio = rect.width / rect.height
        let drawRect: CGRect
        if sourceRatio > targetRatio {
            let width = rect.height * sourceRatio
            drawRect = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
        } else {
            let height = rect.width / sourceRatio
            drawRect = CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        }
        context.interpolationQuality = .high
        context.draw(image, in: drawRect)
    }
}

private struct StoryboardLayout {
    let width: Int
    let height: Int
    let margin: Int
    let gap: Int
    let cellWidth: Int
    let cellHeight: Int

    init(width: Int, gridSide: Int, cardAspectRatio: Double) {
        self.width = width
        margin = max(28, width / 42)
        gap = max(10, width / 190)
        cellWidth = max(1, (width - margin * 2 - gap * (gridSide - 1)) / gridSide)
        cellHeight = max(1, Int((Double(cellWidth) / cardAspectRatio).rounded(.down)))
        height = margin * 2 + cellHeight * gridSide + gap * (gridSide - 1)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
