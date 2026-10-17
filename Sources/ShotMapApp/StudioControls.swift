import AppKit
import SwiftUI

struct ShotMapMark: View {
    let language: AppLanguage
    var size: CGFloat = 44

    var body: some View {
        // The application bundle keeps the full-resolution PNG / ICNS for the
        // Dock and Finder. In workspace chrome native shapes retain softer,
        // cleaner corners than a very small raster rendition.
        ShotMapMarkGlyph(size: size)
            .accessibilityLabel(language.text("app.icon.accessibility"))
        .frame(width: size, height: size)
    }
}

/// Compact vector form of the ShotMap mark used inside the app chrome. Whole
/// point measurements keep the tile edges clean at standard and Retina scales.
private struct ShotMapMarkGlyph: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var outerCornerRadius: CGFloat { max(7, size * 0.27) }
    private var tileCornerRadius: CGFloat { max(2, size * 0.105) }
    private var tileInset: CGFloat { size * 0.19 }
    private var tileGap: CGFloat { size * 0.075 }

    var body: some View {
        let tileSize = (size - tileInset * 2 - tileGap) / 2
        let outer = RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
        let tile = RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous)

        ZStack {
            outer.fill(Color(red: 0.067, green: 0.137, blue: 0.239))
            outer.strokeBorder(
                colorScheme == .light ? Color.white.opacity(0.38) : Color.white.opacity(0.16),
                lineWidth: 1
            )
            VStack(spacing: tileGap) {
                HStack(spacing: tileGap) {
                    tile.fill(Color(red: 0.965, green: 0.970, blue: 0.978))
                    tile.fill(SelectionPalette.active)
                }
                HStack(spacing: tileGap) {
                    tile.fill(SelectionPalette.active)
                    tile.fill(Color(red: 0.965, green: 0.970, blue: 0.978))
                }
            }
            .frame(width: tileSize * 2 + tileGap, height: tileSize * 2 + tileGap)
        }
        .compositingGroup()
        .shadow(
            color: Color.black.opacity(colorScheme == .light ? 0.12 : 0.30),
            radius: size > 40 ? 5 : 2,
            y: size > 40 ? 3 : 1
        )
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

/// A compact visual preview makes the effect of each grid choice clear before
/// export. The real size remains in the label; very dense choices are capped
/// visually so their tiny cells stay legible in the narrow inspector.
struct StoryboardGridChoiceLabel: View {
    let side: Int
    let isSelected: Bool

    private var visualSide: Int { min(5, max(2, side)) }
    private var dotSize: CGFloat { visualSide >= 5 ? 4 : 5 }
    private var dotSpacing: CGFloat { visualSide >= 5 ? 2 : 3 }

    var body: some View {
        VStack(spacing: 3) {
            VStack(spacing: dotSpacing) {
                ForEach(0..<visualSide, id: \.self) { _ in
                    HStack(spacing: dotSpacing) {
                        ForEach(0..<visualSide, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(isSelected ? SelectionPalette.active : Color.secondary.opacity(0.72))
                                .frame(width: dotSize, height: dotSize)
                        }
                    }
                }
            }
            .frame(height: 29, alignment: .center)

            Text("\(side) × \(side)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .frame(height: 14)
        }
        // Every option uses the same icon and label lanes. This prevents the
        // 5 × 5 glyph from shifting its label by a visible pixel.
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
        .contentShape(Rectangle())
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
