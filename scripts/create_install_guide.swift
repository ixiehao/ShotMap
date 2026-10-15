import AppKit
import Foundation

/// Renders localized beginner-installation guides around approved, real
/// ShotMap installation and launch screenshots.

private enum Language: String {
    case english = "en"
    case chinese = "zh"
    case japanese = "ja"
}

private struct Copy {
    let kicker: String
    let title: String
    let subtitle: String
    let steps: [(title: String, body: String)]
    let safety: String
    let removeTitle: String
    let removeBody: String

    static func forLanguage(_ language: Language) -> Copy {
        switch language {
        case .english:
            return Copy(
                kicker: "SHOTMAP · BEGINNER INSTALL GUIDE",
                title: "Install safely in three steps",
                subtitle: "No Terminal. Do not disable macOS security.",
                steps: [
                    ("Open the DMG", "Download the release, then double-click the .dmg file."),
                    ("Drag to Applications", "Wait for the copy to finish. You may then eject or delete the DMG; it is only the installer."),
                    ("First launch", "If macOS cannot verify the developer, open Applications, Control-click the app, then choose Open once.")
                ],
                safety: "No system-wide security change is needed.",
                removeTitle: "Removing later",
                removeBody: "Quit the app, then move only the .app from Applications to Trash. Your exported images stay beside their source videos."
            )
        case .chinese:
            return Copy(
                kicker: "视频一键拼图（ShotMap）· 新手安装指引",
                title: "安全安装，只需三步",
                subtitle: "不需要终端，也不需要关闭 macOS 系统安全设置。",
                steps: [
                    ("打开 DMG", "从发布页下载后，双击 .dmg 文件打开安装窗口。"),
                    ("拖入“应用程序”", "等待复制完成；随后可推出或删除 DMG，它只是安装包。"),
                    ("首次打开", "若提示无法验证开发者，请在“应用程序”中按住 Control 点按应用，再选择“打开”。只需一次。")
                ],
                safety: "无需关闭系统安全功能，也无需输入命令。",
                removeTitle: "以后想删除？",
                removeBody: "先退出应用，再将“应用程序”中的 .app 移入废纸篓（回收站）。已经导出的图片仍在原视频文件夹，不会被删除。"
            )
        case .japanese:
            return Copy(
                kicker: "ShotMap · はじめてのインストール",
                title: "安全なインストールは 3 ステップ",
                subtitle: "ターミナルも macOS の安全設定変更も不要です。",
                steps: [
                    ("DMG を開く", "リリースからダウンロードし、.dmg ファイルをダブルクリックします。"),
                    ("アプリケーションへドラッグ", "コピー完了後、DMG は取り出しまたは削除できます。DMG はインストーラーです。"),
                    ("初回起動", "開発元を確認できない場合は、「アプリケーション」で Control-click して「開く」を一度選びます。")
                ],
                safety: "システム全体の安全設定は変更しません。",
                removeTitle: "あとで削除するには",
                removeBody: "アプリを終了し、「アプリケーション」の .app だけをゴミ箱へ移動します。書き出した画像は元動画の横に残ります。"
            )
        }
    }
}

private let canvas = NSSize(width: 1600, height: 1000)

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

private func rounded(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

private func fill(_ rect: NSRect, _ fillColor: NSColor, radius: CGFloat = 0) {
    let path = radius > 0 ? rounded(rect, radius: radius) : NSBezierPath(rect: rect)
    fillColor.setFill()
    path.fill()
}

private func stroke(_ rect: NSRect, _ strokeColor: NSColor, width: CGFloat = 1, radius: CGFloat = 0) {
    let path = radius > 0 ? rounded(rect, radius: radius) : NSBezierPath(rect: rect)
    strokeColor.setStroke()
    path.lineWidth = width
    path.stroke()
}

private func text(
    _ value: String,
    in rect: NSRect,
    size: CGFloat,
    weight: NSFont.Weight,
    color textColor: NSColor,
    alignment: NSTextAlignment = .left,
    lineBreak: NSLineBreakMode = .byWordWrapping
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = lineBreak
    paragraph.lineSpacing = size * 0.16
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: textColor,
        .paragraphStyle: paragraph
    ]
    (value as NSString).draw(in: rect, withAttributes: attributes)
}

private func drawScreenshot(_ image: NSImage, in rect: NSRect, source: NSRect? = nil) {
    let available = source ?? NSRect(origin: .zero, size: image.size)
    guard available.width > 0, available.height > 0 else { return }
    // Keep the real Finder/app capture intact.  A cover crop made the app
    // window drift to one side in the first-generation guide.  Fit it inside
    // the visual well instead, then centre the result on both axes.
    let scale = min(rect.width / available.width, rect.height / available.height)
    let fittedSize = NSSize(width: available.width * scale, height: available.height * scale)
    let fitted = NSRect(
        x: rect.midX - fittedSize.width / 2,
        y: rect.midY - fittedSize.height / 2,
        width: fittedSize.width,
        height: fittedSize.height
    )

    NSGraphicsContext.saveGraphicsState()
    rounded(rect, radius: 14).addClip()
    fill(rect, color(0.92, 0.96, 1, 0.96), radius: 14)
    image.draw(in: fitted, from: available, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    stroke(rect, color(0.71, 0.91, 1, 0.46), width: 1.3, radius: 14)
}

private func drawTrash(in rect: NSRect) {
    fill(NSRect(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.12, width: rect.width * 0.56, height: rect.height * 0.68), color(0.58, 0.67, 0.78), radius: 10)
    fill(NSRect(x: rect.minX + rect.width * 0.15, y: rect.maxY - rect.height * 0.25, width: rect.width * 0.70, height: rect.height * 0.10), color(0.72, 0.79, 0.87), radius: 5)
    fill(NSRect(x: rect.minX + rect.width * 0.40, y: rect.maxY - rect.height * 0.15, width: rect.width * 0.20, height: rect.height * 0.08), color(0.72, 0.79, 0.87), radius: 4)
    for column in 0..<3 {
        fill(NSRect(x: rect.minX + rect.width * (0.34 + CGFloat(column) * 0.14), y: rect.minY + rect.height * 0.24, width: rect.width * 0.06, height: rect.height * 0.40), color(0.35, 0.44, 0.56), radius: 2)
    }
}

private func drawStep(
    _ index: Int,
    in rect: NSRect,
    copy: (title: String, body: String),
    screenshot: NSImage
) {
    fill(rect, color(0.035, 0.07, 0.15, 0.88), radius: 24)
    stroke(rect, color(0.66, 0.88, 1, 0.22), width: 1.25, radius: 24)
    fill(NSRect(x: rect.minX + 25, y: rect.maxY - 56, width: 30, height: 30), color(0.38, 0.86, 0.91), radius: 15)
    text("\(index)", in: NSRect(x: rect.minX + 25, y: rect.maxY - 49, width: 30, height: 18), size: 13, weight: .bold, color: color(0.03, 0.08, 0.15), alignment: .center)
    text(copy.title, in: NSRect(x: rect.minX + 68, y: rect.maxY - 55, width: rect.width - 92, height: 28), size: 20, weight: .bold, color: color(0.91, 0.97, 1))

    let visual = NSRect(x: rect.minX + 25, y: rect.minY + 120, width: rect.width - 50, height: 184)
    let source: NSRect?
    switch index {
    case 1:
        // A centered close view of the real v0.2.7 mounted-app item.
        source = NSRect(x: 220, y: 310, width: 660, height: 520)
    case 2:
        // Keep the actual app, centered arrow, and Applications alias together.
        source = NSRect(x: 250, y: 270, width: 1_420, height: 560)
    default:
        source = nil
    }
    drawScreenshot(screenshot, in: visual, source: source)

    text(copy.body, in: NSRect(x: rect.minX + 25, y: rect.minY + 30, width: rect.width - 50, height: 78), size: 14, weight: .regular, color: color(0.70, 0.83, 0.95))
}

private func render(background: NSImage, copy: Copy, screenshots: [NSImage]) -> Data {
    let bitmap = NSBitmapImageRep(
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
    )!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    background.draw(in: NSRect(origin: .zero, size: canvas), from: .zero, operation: .sourceOver, fraction: 1)
    fill(NSRect(origin: .zero, size: canvas), color(0.015, 0.025, 0.07, 0.40))

    text(copy.kicker, in: NSRect(x: 0, y: 910, width: canvas.width, height: 22), size: 13, weight: .bold, color: color(0.44, 0.88, 0.94), alignment: .center)
    text(copy.title, in: NSRect(x: 0, y: 844, width: canvas.width, height: 48), size: 40, weight: .bold, color: color(0.94, 0.98, 1), alignment: .center)
    text(copy.subtitle, in: NSRect(x: 0, y: 806, width: canvas.width, height: 24), size: 17, weight: .medium, color: color(0.69, 0.83, 0.96), alignment: .center)

    let stepWidth: CGFloat = 455
    let stepHeight: CGFloat = 390
    let spacing: CGFloat = 34
    let originX = (canvas.width - stepWidth * 3 - spacing * 2) / 2
    let originY: CGFloat = 330
    for index in 0..<3 {
        let rect = NSRect(x: originX + CGFloat(index) * (stepWidth + spacing), y: originY, width: stepWidth, height: stepHeight)
        drawStep(index + 1, in: rect, copy: copy.steps[index], screenshot: screenshots[index])
    }

    let safety = NSRect(x: 496, y: 270, width: 608, height: 44)
    fill(safety, color(0.28, 0.84, 0.88, 0.16), radius: 22)
    stroke(safety, color(0.45, 0.91, 0.94, 0.38), width: 1, radius: 22)
    text(copy.safety, in: NSRect(x: safety.minX + 18, y: safety.minY + 12, width: safety.width - 36, height: 18), size: 14, weight: .semibold, color: color(0.76, 0.97, 0.98), alignment: .center)

    let removal = NSRect(x: 186, y: 88, width: 1228, height: 138)
    fill(removal, color(0.03, 0.055, 0.12, 0.82), radius: 24)
    stroke(removal, color(0.69, 0.83, 1, 0.22), width: 1.2, radius: 24)
    drawTrash(in: NSRect(x: removal.minX + 34, y: removal.minY + 24, width: 86, height: 86))
    text(copy.removeTitle, in: NSRect(x: removal.minX + 148, y: removal.maxY - 54, width: removal.width - 190, height: 27), size: 19, weight: .bold, color: color(0.92, 0.97, 1))
    text(copy.removeBody, in: NSRect(x: removal.minX + 148, y: removal.minY + 27, width: removal.width - 190, height: 53), size: 15, weight: .regular, color: color(0.70, 0.83, 0.95))

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.88])!
}

guard CommandLine.arguments.count == 6,
      let language = Language(rawValue: CommandLine.arguments[2]) else {
    fputs("Usage: create_install_guide.swift <background.png> <en|zh|ja> <dmg.png> <launch.png> <output.jpg>\n", stderr)
    exit(64)
}

let backgroundURL = URL(fileURLWithPath: CommandLine.arguments[1])
let dmgURL = URL(fileURLWithPath: CommandLine.arguments[3])
let launchURL = URL(fileURLWithPath: CommandLine.arguments[4])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[5])
guard let background = NSImage(contentsOf: backgroundURL),
      let dmg = NSImage(contentsOf: dmgURL),
      let launch = NSImage(contentsOf: launchURL) else {
    fputs("Could not read background or required screenshots.\n", stderr)
    exit(66)
}
try render(background: background, copy: .forLanguage(language), screenshots: [dmg, dmg, launch]).write(to: outputURL)
