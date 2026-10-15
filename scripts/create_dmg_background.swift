import AppKit
import Foundation

enum InstallerBackgroundError: Error {
    case invalidArguments
    case missingGraphicsContext
    case unableToWrite(String)
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    throw InstallerBackgroundError.invalidArguments
}

let outputURL = URL(fileURLWithPath: arguments[1])
let canvasSize = NSSize(width: 960, height: 600)
let canvasRect = NSRect(origin: .zero, size: canvasSize)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    throw InstallerBackgroundError.missingGraphicsContext
}

bitmap.size = canvasSize
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
graphics.imageInterpolation = .high

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func drawText(
    _ value: String,
    in rect: NSRect,
    font: NSFont,
    color textColor: NSColor,
    alignment: NSTextAlignment = .center
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    NSAttributedString(
        string: value,
        attributes: [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
    ).draw(in: rect)
}

// A quiet, original surface keeps Finder's real app and Applications icons as
// the visual focus. It follows the familiar drag-to-install hierarchy without
// copying third-party artwork or typography.
color(0.965, 0.973, 0.988).setFill()
NSBezierPath(rect: canvasRect).fill()

let topGlow = NSGradient(colors: [
    color(0.77, 0.91, 1.00, 0.48),
    color(0.91, 0.82, 1.00, 0.28),
    color(1.00, 1.00, 1.00, 0)
])!
topGlow.draw(
    fromCenter: NSPoint(x: 480, y: 505),
    radius: 0,
    toCenter: NSPoint(x: 480, y: 505),
    radius: 430,
    options: [.drawsAfterEndingLocation]
)

let floorGlow = NSGradient(colors: [
    color(0.48, 0.86, 0.94, 0.12),
    color(0.52, 0.46, 0.96, 0.06),
    .clear
])!
floorGlow.draw(
    fromCenter: NSPoint(x: 480, y: 265),
    radius: 0,
    toCenter: NSPoint(x: 480, y: 265),
    radius: 370,
    options: [.drawsAfterEndingLocation]
)

let accent = NSGradient(colors: [
    color(0.30, 0.82, 0.88),
    color(0.55, 0.47, 0.96)
])!
accent.draw(
    in: NSBezierPath(roundedRect: NSRect(x: 410, y: 554, width: 140, height: 4), xRadius: 2, yRadius: 2),
    angle: 0
)

drawText(
    "ShotMap",
    in: NSRect(x: 100, y: 506, width: 760, height: 42),
    font: .systemFont(ofSize: 30, weight: .semibold),
    color: color(0.10, 0.14, 0.22)
)
drawText(
    "视频一键拼图 · macOS",
    in: NSRect(x: 100, y: 474, width: 760, height: 24),
    font: .systemFont(ofSize: 15, weight: .medium),
    color: color(0.31, 0.37, 0.48, 0.82)
)

// Finder places the two real icons at x=260 and x=700. The arrow is the only
// instructional graphic in the center, so the installation gesture reads at a
// glance even before the user reads the footer.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 443, y: 302))
arrow.line(to: NSPoint(x: 517, y: 302))
arrow.lineWidth = 4
arrow.lineCapStyle = .round
color(0.18, 0.22, 0.29, 0.90).setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 500, y: 319))
arrowHead.line(to: NSPoint(x: 517, y: 302))
arrowHead.line(to: NSPoint(x: 500, y: 285))
arrowHead.lineWidth = 4
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
color(0.18, 0.22, 0.29, 0.90).setStroke()
arrowHead.stroke()

drawText(
    "拖动左侧应用到右侧“应用程序”即可安装",
    in: NSRect(x: 120, y: 119, width: 720, height: 24),
    font: .systemFont(ofSize: 15, weight: .medium),
    color: color(0.28, 0.33, 0.42, 0.86)
)
drawText(
    "适用于 Apple Silicon 与 Intel Mac · 需要 macOS 13 或更高版本",
    in: NSRect(x: 120, y: 85, width: 720, height: 20),
    font: .systemFont(ofSize: 12, weight: .regular),
    color: color(0.43, 0.47, 0.55, 0.68)
)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    throw InstallerBackgroundError.unableToWrite(outputURL.path)
}
try pngData.write(to: outputURL, options: .atomic)
