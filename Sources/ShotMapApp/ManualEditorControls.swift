import SwiftUI

/// Separate the value from its localized unit without parsing translated text.
/// Keep the same hit area and align the smaller, secondary unit to the baseline.
struct ManualFrameStepLabel: View {
    let frames: Int
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(frames > 0 ? "+\(frames)" : "−\(abs(frames))")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text(unit)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Manual controls use the same neutral surfaces, blue accent and corner
/// geometry as the main workspace. Apply remains the only solid primary action.
struct ManualFrameEditorTextFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    func _body(configuration: TextField<Self._Label>) -> some View {
        let palette = StudioPalette(isLight: colorScheme == .light)
        return configuration
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .semibold, design: .monospaced))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .frame(height: ManualEditorLayout.compactControlHeight)
            .background(
                palette.control,
                in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous)
                    .strokeBorder(palette.divider, lineWidth: 1 / max(1, displayScale))
            }
    }
}

struct ManualFrameEditorActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.displayScale) private var displayScale
    enum Role {
        case primary
        case secondary
        case toolbarPrimary
        case toolbarSecondary
    }

    let role: Role
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous)
        let palette = StudioPalette(isLight: colorScheme == .light)
        let pressedOpacity = (configuration.isPressed ? 0.80 : 1.0) * (isEnabled ? 1.0 : 0.45)

        switch role {
        case .primary:
            configuration.label
                .foregroundStyle(Color.white)
                .background(
                    SelectionPalette.active,
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1 / max(1, displayScale))
                }
                .opacity(pressedOpacity)

        case .secondary, .toolbarSecondary:
            configuration.label
                .foregroundStyle(.primary)
                .background(
                    palette.control,
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(palette.divider, lineWidth: 1 / max(1, displayScale))
                }
                .opacity(pressedOpacity)

        case .toolbarPrimary:
            configuration.label
                .foregroundStyle(palette.accent)
                .background(palette.accent.opacity(0.08), in: shape)
                .overlay { shape.strokeBorder(palette.accent.opacity(0.14), lineWidth: 1 / max(1, displayScale)) }
                .opacity(pressedOpacity)
        }
    }
}
