import AppKit
import SwiftUI

struct ShotMapMark: View {
    let language: AppLanguage
    var size: CGFloat = 44

    var body: some View {
        // Native vector rendering preserves the approved brand geometry at
        // small sizes and adapts the navy outer frame to a dark workspace.
        ShotMapMarkGlyph(size: size)
            .accessibilityLabel(language.text("app.icon.accessibility"))
        .frame(width: size, height: size)
    }
}

/// Native counterpart of Assets/Brand/mark.svg (viewBox 72 72 384 360).
/// Keep these coordinates in sync with the canonical vector, including the
/// optically centred playback triangle and the eight 56 × 32 frame tiles.
private struct ShotMapMarkGlyph: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, extent in
            let scale = min(extent.width / 384, extent.height / 360)
            context.translateBy(x: (extent.width - 384 * scale) / 2,
                                y: (extent.height - 360 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -72, y: -72)

            let frameColor = colorScheme == .light
                ? Color(red: 20 / 255, green: 37 / 255, blue: 61 / 255)
                : Color(red: 232 / 255, green: 242 / 255, blue: 1)
            let blue = colorScheme == .light
                ? Color(red: 18 / 255, green: 102 / 255, blue: 232 / 255)
                : Color(red: 85 / 255, green: 155 / 255, blue: 1)

            var outer = Path()
            outer.move(to: CGPoint(x: 272, y: 128))
            outer.addLine(to: CGPoint(x: 128, y: 128))
            outer.addQuadCurve(to: CGPoint(x: 96, y: 160), control: CGPoint(x: 96, y: 128))
            outer.addLine(to: CGPoint(x: 96, y: 384))
            outer.addQuadCurve(to: CGPoint(x: 128, y: 416), control: CGPoint(x: 96, y: 416))
            outer.addLine(to: CGPoint(x: 384, y: 416))
            outer.addQuadCurve(to: CGPoint(x: 416, y: 384), control: CGPoint(x: 416, y: 416))
            outer.addLine(to: CGPoint(x: 416, y: 248))
            context.stroke(outer, with: .color(frameColor),
                           style: StrokeStyle(lineWidth: 32, lineCap: .round, lineJoin: .round))
            for row in 0..<3 {
                for column in 0..<3 where !(row == 0 && column == 2) {
                    let rect = CGRect(x: 140 + column * 80, y: 184 + row * 72, width: 56, height: 32)
                    context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(frameColor))
                }
            }

            // Quadratic corners match the SVG rather than substituting a
            // differently rounded system rectangle at large sizes.
            var video = Path()
            video.move(to: CGPoint(x: 320, y: 88))
            video.addLine(to: CGPoint(x: 420, y: 88))
            video.addQuadCurve(to: CGPoint(x: 440, y: 108), control: CGPoint(x: 440, y: 88))
            video.addLine(to: CGPoint(x: 440, y: 172))
            video.addQuadCurve(to: CGPoint(x: 420, y: 192), control: CGPoint(x: 440, y: 192))
            video.addLine(to: CGPoint(x: 320, y: 192))
            video.addQuadCurve(to: CGPoint(x: 300, y: 172), control: CGPoint(x: 300, y: 192))
            video.addLine(to: CGPoint(x: 300, y: 108))
            video.addQuadCurve(to: CGPoint(x: 320, y: 88), control: CGPoint(x: 300, y: 88))
            video.closeSubpath()
            context.fill(video, with: .color(blue))

            var play = Path()
            play.move(to: CGPoint(x: 354, y: 112))
            play.addLine(to: CGPoint(x: 402, y: 140))
            play.addLine(to: CGPoint(x: 354, y: 168))
            play.closeSubpath()
            context.fill(play, with: .color(.white))
        }
        .frame(width: size, height: size)
    }
}

struct ProcessingControlButtonStyle: ButtonStyle {
    enum Tone {
        case primary
        case secondary
        case destructive
    }

    let tone: Tone

    func makeBody(configuration: Configuration) -> some View {
        let colors: (fill: Color, stroke: Color, text: Color) = switch tone {
        case .primary:
            (SelectionPalette.active, .white.opacity(0.18), .white)
        case .secondary:
            (Color(nsColor: .controlBackgroundColor), Color.primary.opacity(0.14), PreviewText.primary)
        case .destructive:
            (Color(red: 0.788, green: 0.208, blue: 0.310), .white.opacity(0.22), .white)
        }
        return configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(colors.text)
            .background(colors.fill.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous)
                    .strokeBorder(colors.stroke)
            }
            .contentShape(RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
    }
}

enum PreviewText {
    /// Semantic colors stay legible in each user-selected appearance.
    static let primary = Color.primary
    static let secondary = Color.secondary
}

enum SelectionPalette {
    /// The single active-state color used by grid, format, and switch controls.
    static let active = Color(red: 0.039, green: 0.400, blue: 0.851) // #0A66D9
}

struct StoryboardResultPager: View {
    let position: Int
    let count: Int
    let canGoBack: Bool
    let canGoForward: Bool
    let language: AppLanguage
    let previous: () -> Void
    let next: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private var palette: StudioPalette { StudioPalette(isLight: colorScheme == .light) }

    var body: some View {
        HStack(spacing: 4) {
            navigationButton(.previous, enabled: canGoBack, label: language.text("button.previousResult"),
                             identifier: "preview-previous", action: previous)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(position)")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.accent)
                Text("/ \(count)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 60)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(language.text("preview.position", position, count))
            .accessibilityIdentifier("preview-page-position")
            navigationButton(.next, enabled: canGoForward, label: language.text("button.nextResult"),
                             identifier: "preview-next", action: next)
        }
        .padding(.horizontal, 8)
        .frame(width: StudioLayout.resultPagerWidth, height: 36)
        .background(palette.control, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(palette.divider, lineWidth: 1 / max(1, displayScale))
        }
        .shadow(color: .black.opacity(colorScheme == .light ? 0.035 : 0.12), radius: 2, y: 1)
        .accessibilityElement(children: .contain)
    }

    private func navigationButton(_ symbol: ProjectIcon.Symbol, enabled: Bool, label: String,
                                  identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ProjectIcon(symbol: symbol, size: 17)
                .foregroundStyle(enabled ? palette.accent : Color.secondary.opacity(0.35))
                .frame(width: 30, height: 28)
                .background(enabled ? palette.accent.opacity(0.09) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// A compact visual preview makes the effect of each grid choice clear before
/// export. The real size remains in the label; very dense choices are capped
/// visually so their tiny cells stay legible in the narrow inspector.
struct StoryboardGridChoiceLabel: View {
    let side: Int
    let isSelected: Bool
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 3) {
            Canvas { context, size in
                let color = isSelected ? SelectionPalette.active : Color.secondary.opacity(0.72)
                for rect in StoryboardGridGlyphLayout.cells(side: side, extent: size.width, displayScale: displayScale) {
                    let radius = min(1, rect.width / 4)
                    context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
                }
            }
            .frame(width: 30, height: 30)

            Text("\(side) × \(side)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .frame(height: 14)
        }
        // Both lanes stay fixed while the actual 3–8 row/column count changes.
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
        .contentShape(Rectangle())
    }
}

/// Draw the real grid, using equal cells on physical pixel boundaries.
/// A compact pictogram must not silently turn every dense grid into 5 × 5.
enum StoryboardGridGlyphLayout {
    static func cells(side: Int, extent: CGFloat, displayScale: CGFloat) -> [CGRect] {
        let count = min(8, max(3, side))
        let scale = displayScale.isFinite && displayScale > 0 ? displayScale : 1
        let pixels = max(count, Int((max(0, extent) * scale).rounded(.down)))
        let desiredGap: CGFloat = count == 3 ? 3 : (count == 6 ? 1 : (count == 7 ? 1.5 : 2))
        let gap = min(max(0, Int((desiredGap * scale).rounded())), max(0, (pixels - count) / (count - 1)))
        let cell = max(1, (pixels - gap * (count - 1)) / count)
        let used = cell * count + gap * (count - 1)
        let origin = (pixels - used) / 2
        return (0..<count).flatMap { row in
            (0..<count).map { column in
                CGRect(x: CGFloat(origin + column * (cell + gap)) / scale,
                       y: CGFloat(origin + row * (cell + gap)) / scale,
                       width: CGFloat(cell) / scale, height: CGFloat(cell) / scale)
            }
        }
    }
}

/// A grid selector should read as a set of pictograms first, then as a value.
/// It intentionally differs from generic segmented controls used for formats.
struct StoryboardGridChoiceStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        configuration.label
            .foregroundStyle(labelColor)
            .background {
                // Inactive choices deliberately have no card chrome.  The
                // controls read as a quiet set of options until a choice is
                // made; only the active value earns a surface and outline.
                if isSelected || configuration.isPressed {
                    shape
                        .fill(fillColor(isPressed: configuration.isPressed))
                }
            }
            .overlay {
                if isSelected {
                    shape.strokeBorder(borderColor, lineWidth: 1)
                    shape
                        .inset(by: 1)
                        .strokeBorder(Color.white.opacity(colorScheme == .light ? 0.72 : 0.16), lineWidth: 0.5)
                }
            }
            .shadow(color: isSelected ? borderColor.opacity(0.14) : .clear, radius: 3, y: 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }

    private var labelColor: Color {
        guard isSelected else { return .primary }
        return SelectionPalette.active
    }

    private var borderColor: Color {
        if isSelected {
            return colorScheme == .light
                ? Color(red: 0.30, green: 0.56, blue: 1.0)
                : Color(red: 0.36, green: 0.65, blue: 1.0)
        }
        return colorScheme == .light
            ? Color.black.opacity(0.045)
            : Color.white.opacity(0.08)
    }

    private func fillColor(isPressed: Bool) -> Color {
        let base: Color
        if isSelected {
            base = colorScheme == .light
                ? Color(red: 0.935, green: 0.962, blue: 1.0)
                : Color(red: 0.075, green: 0.172, blue: 0.310)
        } else {
            base = colorScheme == .light
                ? Color.black.opacity(0.055)
                : Color.white.opacity(0.10)
        }
        return base.opacity(isPressed ? 0.78 : 1)
    }
}

struct GridChoiceStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                isSelected ? SelectionPalette.active : idleFill(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.18) : Color.primary.opacity(0.08))
            }
    }

    private func idleFill(isPressed: Bool) -> Color {
        guard colorScheme == .light else {
            return Color(red: 0.114, green: 0.137, blue: 0.173).opacity(isPressed ? 0.84 : 1)
        }
        return isPressed
            ? Color(red: 0.910, green: 0.945, blue: 0.992)
            : Color.white
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(SelectionPalette.active, in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous).strokeBorder(.white.opacity(0.18)) }
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct ExportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous).strokeBorder(Color.primary.opacity(0.14)) }
    }
}

struct SavedResultButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(SelectionPalette.active, in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.28)) }
            .shadow(color: Color(red: 0.30, green: 0.75, blue: 0.94).opacity(0.24), radius: 10, y: 4)
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct ManualAdjustmentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(Color(red: 0.071, green: 0.125, blue: 0.200), in: Capsule())
            .overlay { Capsule().strokeBorder(Color(red: 0.290, green: 0.510, blue: 0.820).opacity(0.72)) }
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.08 : 0.18), radius: 8, y: 3)
            .opacity(configuration.isPressed ? 0.80 : 1)
    }
}
