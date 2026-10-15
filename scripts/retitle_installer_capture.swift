import AppKit
import Foundation

/// Updates only the product lettering inside the approved Finder/DMG capture.
/// The original icons, Finder chrome, and installation composition are kept.

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
    weight: NSFont.Weight,
    color: NSColor,
    alignment: NSTextAlignment = .left
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    (value as NSString).draw(in: rect, withAttributes: attributes)
}

private func sample(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) -> NSColor {
    bitmap.colorAt(x: min(max(0, x), bitmap.pixelsWide - 1), y: min(max(0, y), bitmap.pixelsHigh - 1)) ?? .white
}

guard CommandLine.arguments.count == 4 else {
    fail("Usage: retitle_installer_capture.swift <input.png> <background.png> <output.png>")
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let backgroundURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])
guard let source = NSImage(contentsOf: inputURL), let tiff = source.tiffRepresentation,
      let sourceBitmap = NSBitmapImageRep(data: tiff),
      let background = NSImage(contentsOf: backgroundURL) else {
    fail("Could not read an input image", code: 66)
}

let width = sourceBitmap.pixelsWide
let height = sourceBitmap.pixelsHigh
guard width >= 1_600, height >= 1_000 else {
    fail("The Finder capture is unexpectedly small: \\(width)x\\(height)", code: 65)
}

let outputBitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
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
source.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)

let scaleX = CGFloat(width) / 1920
let scaleY = CGFloat(height) / 1200
let canvasHeight = CGFloat(height)

// The legacy capture is a Finder window displayed over our generated DMG
// background. Replacing the complete client area is cleaner than trying to
// paint over individual glyphs on a non-uniform gradient.
let clientTop: CGFloat = 62 * scaleY
let clientRect = NSRect(x: 0, y: -clientTop, width: CGFloat(width), height: CGFloat(height))
background.draw(in: clientRect, from: .zero, operation: .copy, fraction: 1)

func copyFinderArtwork(topX: CGFloat, topY: CGFloat, width: CGFloat, height: CGFloat) {
    let sourceRect = topRect(x: topX, y: topY, width: width, height: height, canvasHeight: canvasHeight)
    source.draw(in: sourceRect, from: sourceRect, operation: .sourceOver, fraction: 1)
}

// Preserve the real Finder icon and Applications alias from the approved
// screenshot. Their labels are re-drawn separately below.
copyFinderArtwork(topX: 400 * scaleX, topY: 550 * scaleY, width: 250 * scaleX, height: 245 * scaleY)
copyFinderArtwork(topX: 1_260 * scaleX, topY: 550 * scaleY, width: 300 * scaleX, height: 245 * scaleY)

// Finder window title.
let windowBackground = sample(sourceBitmap, Int(500 * scaleX), Int(30 * scaleY))
windowBackground.setFill()
NSBezierPath(rect: topRect(x: 195 * scaleX, y: 12 * scaleY, width: 188 * scaleX, height: 41 * scaleY, canvasHeight: canvasHeight)).fill()
drawText(
    "ShotMap",
    in: topRect(x: 204 * scaleX, y: 16 * scaleY, width: 180 * scaleX, height: 34 * scaleY, canvasHeight: canvasHeight),
    size: 28 * scaleX,
    weight: .bold,
    color: NSColor(calibratedWhite: 0.30, alpha: 1)
)

// The centre background has a gentle horizontal gradient. Sampling both
// sides prevents a visible flat patch behind the updated title.
drawText(
    "ShotMap.app",
    in: topRect(x: 340 * scaleX, y: 810 * scaleY, width: 400 * scaleX, height: 36 * scaleY, canvasHeight: canvasHeight),
    size: 26 * scaleX,
    weight: .medium,
    color: NSColor(calibratedWhite: 0.15, alpha: 1),
    alignment: .center
)

NSGraphicsContext.restoreGraphicsState()
guard let data = outputBitmap.representation(using: .png, properties: [:]) else {
    fail("Could not encode PNG", code: 70)
}
try data.write(to: outputURL, options: .atomic)
