import AppKit
import Foundation

/// Rebrands an existing, approved workspace capture without changing its real
/// video content or interface layout. This is intentionally limited to the
/// header's product-name lockup so historical screenshots remain useful.

private func fail(_ message: String, code: Int32 = 64) -> Never {
    fputs("\\(message)\\n", stderr)
    exit(code)
}

private func topRect(
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    canvasHeight: CGFloat
) -> NSRect {
    NSRect(x: x, y: canvasHeight - y - height, width: width, height: height)
}

private func drawText(
    _ value: String,
    in rect: NSRect,
    size: CGFloat,
    color: NSColor
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byClipping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: .semibold),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    (value as NSString).draw(in: rect, withAttributes: attributes)
}

guard CommandLine.arguments.count == 3 else {
    fail("Usage: retitle_workspace_brand.swift <input.png> <output.png>")
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = NSImage(contentsOf: inputURL), let tiff = source.tiffRepresentation,
      let sourceBitmap = NSBitmapImageRep(data: tiff) else {
    fail("Could not read \\(inputURL.path)", code: 66)
}

let pixelWidth = sourceBitmap.pixelsWide
let pixelHeight = sourceBitmap.pixelsHigh
guard pixelWidth >= 1_200, pixelHeight >= 700 else {
    fail("The workspace capture is unexpectedly small: \\(pixelWidth)x\\(pixelHeight)", code: 65)
}

let canvasSize = NSSize(width: pixelWidth, height: pixelHeight)
let outputBitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelWidth,
    pixelsHigh: pixelHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

let context = NSGraphicsContext(bitmapImageRep: outputBitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
source.draw(in: NSRect(origin: .zero, size: canvasSize), from: .zero, operation: .copy, fraction: 1)

let scaleX = canvasSize.width / 1600
let scaleY = canvasSize.height / 900
let headerSample = sourceBitmap.colorAt(
    x: min(pixelWidth - 1, Int(80 * scaleX)),
    // NSBitmapImageRep pixel coordinates are top-left based for a bitmap
    // loaded from these captures. Sampling a bottom-row pixel produced a
    // visibly lighter patch on dark-mode headers.
    y: min(pixelHeight - 1, Int(18 * scaleY))
) ?? .black
let brightness = (headerSample.redComponent * 0.299)
    + (headerSample.greenComponent * 0.587)
    + (headerSample.blueComponent * 0.114)
let foreground = brightness < 0.45
    ? NSColor(calibratedWhite: 0.93, alpha: 1)
    : NSColor(calibratedWhite: 0.13, alpha: 1)

// Product mark. The old name is painted out using the exact header colour
// sampled from the screenshot before the shorter new name is drawn.
let productErase = topRect(
    x: 114 * scaleX,
    y: 8 * scaleY,
    width: 104 * scaleX,
    height: 26 * scaleY,
    canvasHeight: canvasSize.height
)
headerSample.setFill()
NSBezierPath(rect: productErase).fill()
drawText(
    "ShotMap",
    in: topRect(
        x: 120 * scaleX,
        y: 11 * scaleY,
        width: 94 * scaleX,
        height: 19 * scaleY,
        canvasHeight: canvasSize.height
    ),
    size: 14 * scaleX,
    color: foreground
)

// The legacy Chinese subtitle is visible in all three historical workspace
// captures. Keep the surrounding language-specific line below it intact.
let subtitleErase = topRect(
    x: 224 * scaleX,
    y: 7 * scaleY,
    width: 125 * scaleX,
    height: 17 * scaleY,
    canvasHeight: canvasSize.height
)
headerSample.setFill()
NSBezierPath(rect: subtitleErase).fill()
drawText(
    "视频一键拼图",
    in: topRect(
        x: 228 * scaleX,
        y: 8 * scaleY,
        width: 104 * scaleX,
        height: 16 * scaleY,
        canvasHeight: canvasSize.height
    ),
    size: 10 * scaleX,
    color: foreground
)

NSGraphicsContext.restoreGraphicsState()
guard let data = outputBitmap.representation(using: .png, properties: [:]) else {
    fail("Could not encode PNG", code: 70)
}
try data.write(to: outputURL, options: .atomic)
