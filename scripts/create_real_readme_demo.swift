import AppKit
import Foundation

enum DemoError: Error {
    case invalidArguments
    case missingImages
    case unreadableImage(String)
    case unableToCreateBitmap
    case unableToWrite(String)
}

private let canvas = NSSize(width: 960, height: 540)
private let outputPixelWidth = max(
    960,
    Int(ProcessInfo.processInfo.environment["SHOTMAP_DEMO_PIXEL_WIDTH"] ?? "960") ?? 960
)
private let outputPixelHeight = Int(
    (CGFloat(outputPixelWidth) * canvas.height / canvas.width).rounded()
)

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

private func fill(_ rect: NSRect, color fillColor: NSColor, radius: CGFloat = 0) {
    let path = radius > 0
        ? NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        : NSBezierPath(rect: rect)
    fillColor.setFill()
    path.fill()
}

private func stroke(_ rect: NSRect, color strokeColor: NSColor, width: CGFloat = 1, radius: CGFloat = 0) {
    let path = radius > 0
        ? NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        : NSBezierPath(rect: rect)
    strokeColor.setStroke()
    path.lineWidth = width
    path.stroke()
}

private func drawText(
    _ value: String,
    in rect: NSRect,
    size: CGFloat,
    weight: NSFont.Weight,
    color textColor: NSColor,
    alignment: NSTextAlignment = .left
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    NSAttributedString(
        string: value,
        attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
    ).draw(in: rect)
}

private func drawImage(
    _ image: NSImage,
    in rect: NSRect,
    aspectFill: Bool,
    fraction: CGFloat = 1
) {
    let source = image.size
    guard source.width > 0, source.height > 0 else { return }
    let scale = aspectFill
        ? max(rect.width / source.width, rect.height / source.height)
        : min(rect.width / source.width, rect.height / source.height)
    let size = NSSize(width: source.width * scale, height: source.height * scale)
    let drawRect = NSRect(
        x: rect.midX - size.width / 2,
        y: rect.midY - size.height / 2,
        width: size.width,
        height: size.height
    )
    image.draw(
        in: drawRect,
        from: .zero,
        operation: .sourceOver,
        fraction: fraction,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
}

private func drawArrow(progress: CGFloat) {
    let start = NSPoint(x: 438, y: 278)
    let end = NSPoint(x: 522, y: 278)
    let visibleEnd = NSPoint(x: start.x + (end.x - start.x) * progress, y: start.y)
    let line = NSBezierPath()
    line.move(to: start)
    line.line(to: visibleEnd)
    line.lineWidth = 5
    line.lineCapStyle = .round
    color(0.35, 0.86, 0.92, 0.25 + progress * 0.75).setStroke()
    line.stroke()

    guard progress > 0.78 else { return }
    let head = NSBezierPath()
    head.move(to: NSPoint(x: visibleEnd.x - 16, y: visibleEnd.y + 13))
    head.line(to: visibleEnd)
    head.line(to: NSPoint(x: visibleEnd.x - 16, y: visibleEnd.y - 13))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    color(0.35, 0.86, 0.92, 1).setStroke()
    head.stroke()
}

private func renderFrame(
    sourceImage: NSImage,
    storyboardImage: NSImage,
    index: Int,
    count: Int
) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: outputPixelWidth,
        pixelsHigh: outputPixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw DemoError.unableToCreateBitmap
    }
    // Bind the dense backing pixels to the stable 960 × 540 point layout
    // before creating the graphics context. This produces a high-resolution
    // overview without scaling the layout into the lower-left corner.
    bitmap.size = canvas
    guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw DemoError.unableToCreateBitmap
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high

    let phase = CGFloat(index) / CGFloat(max(1, count - 1))
    let background = NSGradient(colors: [
        color(0.025, 0.040, 0.090),
        color(0.075, 0.055, 0.145)
    ])!
    background.draw(in: NSRect(origin: .zero, size: canvas), angle: -30)

    let glow = NSGradient(colors: [
        color(0.18, 0.68, 0.85, 0.15),
        color(0.48, 0.38, 0.92, 0.05),
        .clear
    ])!
    glow.draw(
        fromCenter: NSPoint(x: 480, y: 270),
        radius: 0,
        toCenter: NSPoint(x: 480, y: 270),
        radius: 370,
        options: [.drawsAfterEndingLocation]
    )

    drawText(
        "SHOT TESSERA",
        in: NSRect(x: 0, y: 489, width: canvas.width, height: 18),
        size: 12,
        weight: .bold,
        color: color(0.42, 0.88, 0.92),
        alignment: .center
    )
    drawText(
        "REAL VIDEO  →  SMART STORYBOARD",
        in: NSRect(x: 0, y: 444, width: canvas.width, height: 36),
        size: 27,
        weight: .bold,
        color: color(0.91, 0.96, 1),
        alignment: .center
    )
    drawText(
        "Smart selection first. Fine-tune any frame. Process locally.",
        in: NSRect(x: 0, y: 416, width: canvas.width, height: 18),
        size: 12,
        weight: .medium,
        color: color(0.60, 0.75, 0.92),
        alignment: .center
    )

    let leftPanel = NSRect(x: 42, y: 120, width: 368, height: 274)
    let rightPanel = NSRect(x: 550, y: 120, width: 368, height: 274)
    for panel in [leftPanel, rightPanel] {
        fill(panel, color: color(0.015, 0.025, 0.060, 0.88), radius: 20)
        stroke(panel, color: color(0.55, 0.78, 1, 0.22), width: 1, radius: 20)
    }

    drawText(
        "OWNER-SHOT VIDEO",
        in: NSRect(x: leftPanel.minX + 18, y: leftPanel.maxY - 34, width: leftPanel.width - 36, height: 15),
        size: 10,
        weight: .bold,
        color: color(0.62, 0.82, 0.96)
    )
    drawText(
        "SHOT TESSERA · 3 × 3",
        in: NSRect(x: rightPanel.minX + 18, y: rightPanel.maxY - 34, width: rightPanel.width - 36, height: 15),
        size: 10,
        weight: .bold,
        color: color(0.69, 0.82, 1)
    )

    let leftContent = NSRect(x: leftPanel.minX + 18, y: leftPanel.minY + 38, width: leftPanel.width - 36, height: 187)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: leftContent, xRadius: 12, yRadius: 12).addClip()
    drawImage(sourceImage, in: leftContent, aspectFill: true)
    NSGraphicsContext.restoreGraphicsState()
    stroke(leftContent, color: color(1, 1, 1, 0.16), width: 1, radius: 12)

    let rightContent = NSRect(x: rightPanel.minX + 18, y: rightPanel.minY + 31, width: rightPanel.width - 36, height: 194)
    fill(rightContent, color: color(0.04, 0.05, 0.08), radius: 12)
    let reveal = max(0, min(1, (phase - 0.22) / 0.55))
    if reveal > 0 {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rightContent, xRadius: 12, yRadius: 12).addClip()
        let revealRect = NSRect(
            x: rightContent.minX,
            y: rightContent.minY,
            width: rightContent.width * reveal,
            height: rightContent.height
        )
        NSBezierPath(rect: revealRect).addClip()
        drawImage(storyboardImage, in: rightContent, aspectFill: false, fraction: min(1, reveal * 1.45))
        NSGraphicsContext.restoreGraphicsState()
    }
    stroke(rightContent, color: color(1, 1, 1, 0.16), width: 1, radius: 12)

    let timeline = NSRect(x: leftContent.minX, y: leftPanel.minY + 19, width: leftContent.width, height: 4)
    fill(timeline, color: color(1, 1, 1, 0.14), radius: 2)
    fill(
        NSRect(x: timeline.minX, y: timeline.minY, width: timeline.width * max(0.08, phase), height: timeline.height),
        color: color(0.38, 0.88, 0.92),
        radius: 2
    )

    drawArrow(progress: min(1, phase * 1.55))
    drawText(
        "Project-owner footage · No cloud upload · Original video not distributed",
        in: NSRect(x: 50, y: 67, width: 860, height: 18),
        size: 11,
        weight: .medium,
        color: color(0.55, 0.66, 0.80),
        alignment: .center
    )

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw DemoError.unableToWrite("frame")
    }
    return data
}

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: create_real_readme_demo.swift <source-frames-directory> <storyboard-image> <output-directory>\n", stderr)
    throw DemoError.invalidArguments
}

let sourceDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let storyboardURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
let sourceURLs = try FileManager.default.contentsOfDirectory(
    at: sourceDirectory,
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles]
).filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

guard !sourceURLs.isEmpty else { throw DemoError.missingImages }
guard let storyboard = NSImage(contentsOf: storyboardURL) else {
    throw DemoError.unreadableImage(storyboardURL.path)
}
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for (index, sourceURL) in sourceURLs.enumerated() {
    guard let source = NSImage(contentsOf: sourceURL) else {
        throw DemoError.unreadableImage(sourceURL.path)
    }
    let outputURL = outputDirectory.appendingPathComponent(String(format: "frame-%02d.png", index))
    try renderFrame(
        sourceImage: source,
        storyboardImage: storyboard,
        index: index,
        count: sourceURLs.count
    ).write(to: outputURL, options: .atomic)
}
