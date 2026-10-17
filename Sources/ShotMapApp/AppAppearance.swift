import SwiftUI

/// A persisted appearance preference. `system` deliberately uses a nil
/// preferred scheme so macOS remains the source of truth.
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var localizationKey: String {
        switch self {
        case .system: "appearance.system"
        case .light: "appearance.light"
        case .dark: "appearance.dark"
        }
    }

    func displayName(in language: AppLanguage) -> String {
        language.text(localizationKey)
    }
}
