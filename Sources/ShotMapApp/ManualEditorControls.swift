import SwiftUI

/// Purpose-built action controls for the manual candidate editor.  These are
/// intentionally separate from the global button styles: one commits an
/// intelligent selection, while the other safely asks for a new candidate set.
struct ManualFrameEditorTextFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) private var colorScheme

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .semibold, design: .monospaced))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .frame(height: ManualEditorLayout.compactControlHeight)
            .background(
                colorScheme == .dark
                    ? Color(red: 0.114, green: 0.133, blue: 0.157)
                    : Color.white.opacity(0.84),
                in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark ? .white.opacity(0.18) : Color(red: 0.805, green: 0.816, blue: 0.824),
                        lineWidth: 1
                    )
            }
    }
}

struct ManualFrameEditorActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    enum Role {
        case primary
        case secondary
        case toolbarPrimary
        case toolbarSecondary
    }

    let role: Role
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous)
        let pressedOpacity = configuration.isPressed ? 0.80 : 1.0

        switch role {
        case .primary:
            configuration.label
                .foregroundStyle(Color.white)
                .background(
                    SelectionPalette.active,
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.34), lineWidth: 1)
                }
                .opacity(pressedOpacity)

        case .secondary:
            configuration.label
                .foregroundStyle(.primary)
                .background(
                    colorScheme == .dark
                        ? Color(red: 0.114, green: 0.133, blue: 0.157)
                        : Color.white.opacity(0.84),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(
                        colorScheme == .dark ? .white.opacity(0.18) : Color(red: 0.805, green: 0.816, blue: 0.824),
                        lineWidth: 1
                    )
                }
                .opacity(pressedOpacity)

        case .toolbarPrimary:
            configuration.label
                .foregroundStyle(SelectionPalette.active)
                .background(Color.clear, in: shape)
                .overlay { shape.strokeBorder(Color.clear, lineWidth: 1) }
                .opacity(pressedOpacity)

        case .toolbarSecondary:
            configuration.label
                .foregroundStyle(.primary)
                .background(Color.clear, in: shape)
                .overlay { shape.strokeBorder(Color.clear, lineWidth: 1) }
                .opacity(pressedOpacity)
        }
    }
}
