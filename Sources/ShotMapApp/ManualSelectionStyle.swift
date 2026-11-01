import SwiftUI

/// One selection treatment for the manual gallery, sized for its 180–200 pt
/// portrait cards as well as the wider landscape cards. Selection order is
/// supplied by the editor; these views never keep a separate copy of it.
enum ManualFrameSelectionStyle {
    static let cornerRadius: CGFloat = 8
    static let borderWidth: CGFloat = 3
    static let innerKeylineWidth: CGFloat = 1
    static let badgeDiameter: CGFloat = 36
    static let idleBadgeDiameter: CGFloat = 24
    static let badgeInset: CGFloat = 8

    static func numberSize(_ number: Int) -> CGFloat {
        number >= 10 ? 18 : 20
    }
}

/// A solid blue disc and white rim remain legible over both pale and dark
/// footage. The fixed outer size keeps the disc centre still when selected.
struct ManualFrameSelectionBadge: View {
    let isSelected: Bool
    let number: Int?

    var body: some View {
        let diameter = isSelected
            ? ManualFrameSelectionStyle.badgeDiameter
            : ManualFrameSelectionStyle.idleBadgeDiameter
        ZStack {
            Circle()
                .fill(isSelected ? SelectionPalette.active : Color.black.opacity(0.20))
            Circle()
                .strokeBorder(.white.opacity(isSelected ? 1 : 0.92), lineWidth: isSelected ? 2 : 1.5)
            if isSelected, let number {
                Text("\(number)")
                    .font(.system(size: ManualFrameSelectionStyle.numberSize(number), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(isSelected ? 0.30 : 0.16), radius: isSelected ? 3 : 1, y: 1)
        .frame(width: ManualFrameSelectionStyle.badgeDiameter, height: ManualFrameSelectionStyle.badgeDiameter)
        .padding(ManualFrameSelectionStyle.badgeInset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The blue outer border identifies selection; its thin white inner keyline
/// preserves the shape on blue/dark footage without tinting or hiding the image.
struct ManualFrameSelectionOutline: View {
    let isSelected: Bool
    let idleColor: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ManualFrameSelectionStyle.cornerRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? SelectionPalette.active : idleColor,
                    lineWidth: isSelected ? ManualFrameSelectionStyle.borderWidth : 1
                )
            if isSelected {
                RoundedRectangle(
                    cornerRadius: ManualFrameSelectionStyle.cornerRadius - ManualFrameSelectionStyle.borderWidth,
                    style: .continuous
                )
                .strokeBorder(.white.opacity(0.92), lineWidth: ManualFrameSelectionStyle.innerKeylineWidth)
                .padding(ManualFrameSelectionStyle.borderWidth)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
