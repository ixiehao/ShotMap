import AppKit
import Foundation

enum SocialPreviewError: Error {
    case invalidArguments
    case unreadableImage(String)
    case unableToCreateBitmap
    case unableToWrite(String)
}

private let canvas = NSSize(width: 1280, height: 640)

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

private func drawImage(_ image: NSImage, in rect: NSRect) {
    let size = image.size
    guard size.width > 0, size.height > 0 else { return }
    let scale = min(rect.width / size.width, rect.height / size.height)
    let rendered = NSSize(width: size.width * scale, height: size.height * scale)
    image.draw(
        in: NSRect(
            x: rect.midX - rendered.width / 2,
            y: rect.midY - rendered.height / 2,
            width: rendered.width,
            height: rendered.height
        ),
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
}

private func render(caseStudy: NSImage, compact: Bool) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.width),
        pixelsHigh: Int(canvas.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { throw SocialPreviewError.unableToCreateBitmap }
    bitmap.size = canvas
    guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw SocialPreviewError.unableToCreateBitmap
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high

    NSGradient(colors: [color(0.018, 0.030, 0.075), color(0.070, 0.045, 0.145)])!
        .draw(in: NSRect(origin: .zero, size: canvas), angle: -24)
    let glow = NSGradient(colors: [color(0.24, 0.78, 0.90, 0.17), color(0.47, 0.38, 0.95, 0.10), .clear])!
    glow.draw(
        fromCenter: NSPoint(x: 875, y: 310), radius: 0,
        toCenter: NSPoint(x: 875, y: 310), radius: 620,
        options: [.drawsAfterEndingLocation]
    )

    fill(NSRect(x: 54, y: 88, width: 1172, height: 464), color: color(0.02, 0.04, 0.095, 0.75), radius: 28)
    stroke(NSRect(x: 54, y: 88, width: 1172, height: 464), color: color(0.48, 0.76, 1, 0.24), width: 1, radius: 28)

    fill(NSRect(x: 90, y: 474, width: 82, height: 27), color: color(0.13, 0.48, 0.66), radius: 13.5)
    drawText("macOS", in: NSRect(x: 90, y: 480, width: 82, height: 14), size: 12, weight: .bold, color: .white, alignment: .center)
    drawText("ShotMap", in: NSRect(x: 90, y: 410, width: 360, height: 48), size: 42, weight: .bold, color: color(0.93, 0.97, 1))
    drawText("Make every video easy to browse", in: NSRect(x: 90, y: 367, width: 390, height: 31), size: 22, weight: .semibold, color: color(0.72, 0.86, 1))
    drawText("Smart selection, precise control, local export.", in: NSRect(x: 90, y: 322, width: 390, height: 22), size: 16, weight: .medium, color: color(0.60, 0.76, 0.93))
    drawText("Native macOS · Your footage stays on your Mac", in: NSRect(x: 90, y: 293, width: 410, height: 18), size: 14, weight: .medium, color: color(0.40, 0.88, 0.91))

    let caseRect = NSRect(x: 490, y: compact ? 135 : 122, width: 690, height: compact ? 388 : 405)
    fill(caseRect, color: color(0, 0, 0, 0.30), radius: 20)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: caseRect, xRadius: 20, yRadius: 20).addClip()
    drawImage(caseStudy, in: caseRect.insetBy(dx: 8, dy: 8))
    NSGraphicsContext.restoreGraphicsState()
    stroke(caseRect, color: color(0.58, 0.87, 1, 0.35), width: 1.5, radius: 20)

    drawText(
        compact ? "Real workspace · manual control" : "A real ShotMap workspace",
        in: NSRect(x: 90, y: 154, width: 360, height: 44),
        size: compact ? 18 : 20,
        weight: .semibold,
        color: color(0.80, 0.90, 1)
    )
    fill(NSRect(x: 90, y: 119, width: 340, height: 5), color: color(0.34, 0.86, 0.91), radius: 2.5)
    drawText("Video stays on your Mac — no cloud upload.", in: NSRect(x: 90, y: 100, width: 360, height: 16), size: 13, weight: .medium, color: color(0.52, 0.65, 0.82))

    NSGraphicsContext.restoreGraphicsState()
    guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
        throw SocialPreviewError.unableToWrite("preview")
    }
    return jpeg
}

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: create_social_preview.swift <real-case-image> <social-preview.jpg> <social-preview-v2.jpg>\\n", stderr)
    throw SocialPreviewError.invalidArguments
}

let caseURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let caseStudy = NSImage(contentsOf: caseURL) else {
    throw SocialPreviewError.unreadableImage(caseURL.path)
}
try render(caseStudy: caseStudy, compact: false).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
try render(caseStudy: caseStudy, compact: true).write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
