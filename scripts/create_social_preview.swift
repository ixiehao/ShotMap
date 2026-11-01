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

private func render(caseStudy: NSImage) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw SocialPreviewError.unableToCreateBitmap
    }
    bitmap.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high
    defer { NSGraphicsContext.restoreGraphicsState() }

    color(0.95, 0.97, 0.99).setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: canvas)).fill()
    let navy = color(20 / 255, 37 / 255, 61 / 255)
    let blue = color(18 / 255, 102 / 255, 232 / 255)
    let muted = color(0.36, 0.43, 0.53)
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    guard let brand = NSImage(contentsOf: project.appendingPathComponent("website/assets/app-icon.png")) else {
        throw SocialPreviewError.unreadableImage("app-icon.png")
    }
    drawImage(brand, in: NSRect(x: 43, y: 527, width: 72, height: 72))
    drawText("ShotMap", in: NSRect(x: 127, y: 543, width: 260, height: 45), size: 37,
             weight: .bold, color: navy)
    drawText("Your videos,\neasier to find.", in: NSRect(x: 48, y: 368, width: 365, height: 115),
             size: 42, weight: .bold, color: navy)
    drawText("Turn a video into one storyboard.\nChoose frames. Save locally.",
             in: NSRect(x: 48, y: 282, width: 365, height: 65),
             size: 19, weight: .regular, color: muted)
    drawText("macOS 13+ · Apple Silicon & Intel", in: NSRect(x: 48, y: 184, width: 365, height: 24),
             size: 14, weight: .medium, color: muted)
    drawText("Free & open source · 7 languages", in: NSRect(x: 48, y: 151, width: 365, height: 24),
             size: 14, weight: .medium, color: muted)
    drawText("ixiehao.github.io/ShotMap", in: NSRect(x: 48, y: 64, width: 365, height: 25),
             size: 16, weight: .semibold, color: blue)

    let caseRect = NSRect(x: 438, y: 115, width: 798, height: 500)
    fill(caseRect, color: .white, radius: 17)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: caseRect, xRadius: 17, yRadius: 17).addClip()
    drawImage(caseStudy, in: caseRect)
    NSGraphicsContext.restoreGraphicsState()
    stroke(caseRect, color: color(0.84, 0.88, 0.93), radius: 17)
    drawText("Demo: Tears of Steel (2012) · © Blender Foundation / Blender Institute · CC BY 3.0",
             in: NSRect(x: 438, y: 70, width: 798, height: 22),
             size: 11, weight: .regular, color: muted)

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
let preview = try render(caseStudy: caseStudy)
try preview.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
try preview.write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
