import AppKit
import SwiftUI

struct ShotMapMark: View {
    let language: AppLanguage
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let image = ShotMapIconAsset.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .accessibilityLabel(language.text("app.icon.accessibility"))
            } else {
                ProjectIcon(symbol: .eye, size: 22)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(width: size, height: size)
    }
}

private enum ShotMapIconAsset {
    static let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
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

    var body: some View {
        VStack(spacing: 4) {
            VStack(spacing: 2.5) {
                ForEach(0..<visualSide, id: \.self) { _ in
                    HStack(spacing: 2.5) {
                        ForEach(0..<visualSide, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                                .fill(isSelected ? SelectionPalette.active : Color.secondary.opacity(0.72))
                                .frame(width: 4.5, height: 4.5)
                        }
                    }
                }
            }
            // Do not constrain this to a synthetic, one-size-fits-all height:
            // a 5 × 5 pictogram is taller than a 4 × 4 one.  Giving the
            // pictogram its real height lets the surrounding stack centre the
            // icon-and-label pair as one unit inside each option.

            Text("\(side) × \(side)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        // Keep the icon/label pair centred within every tap target.  This is
        // particularly noticeable for the active tile, whose outline makes
        // even a one-pixel vertical drift look unintentional.
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .center)
        .contentShape(Rectangle())
    }
}

/// A grid selector should read as a set of pictograms first, then as a value.
/// It intentionally differs from generic segmented controls used for formats.
struct StoryboardGridChoiceStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(labelColor)
            .background {
                // Inactive choices deliberately have no card chrome.  The
                // controls read as a quiet set of options until a choice is
                // made; only the active value earns a surface and outline.
                if isSelected || configuration.isPressed {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(fillColor(isPressed: configuration.isPressed))
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1.5)
                }
            }
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
                ? Color(red: 0.91, green: 0.95, blue: 1.0)
                : Color(red: 0.09, green: 0.20, blue: 0.36)
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
