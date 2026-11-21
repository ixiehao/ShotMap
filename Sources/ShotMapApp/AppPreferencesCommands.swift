import Foundation
import SwiftUI

/// Infrequent, app-wide choices belong in the macOS menu bar. These bindings
/// share the existing storage keys with the workspace and manual editor; moving
/// their controls does not migrate or replace a person's saved preferences.
struct AppPreferencesCommands: Commands {
    @AppStorage private var languageCode: String
    @AppStorage private var appearanceCode: String

    init(defaults: UserDefaults = .standard) {
        _languageCode = AppStorage(wrappedValue: AppLanguage.followSystem, "appLanguage", store: defaults)
        _appearanceCode = AppStorage(wrappedValue: AppAppearance.system.rawValue, "appAppearance", store: defaults)
    }

    var selectedLanguage: AppLanguage {
        AppLanguage.resolve(languageCode)
    }

    var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appearanceCode) ?? .system
    }

    // Resolve an unknown stored value for the checkmark without rewriting it
    // merely because the menu was opened. Only a user selection writes storage.
    var languageSelection: Binding<String> {
        Binding(get: {
            languageCode == AppLanguage.followSystem ? languageCode : selectedLanguage.rawValue
        }, set: { value in
            guard value == AppLanguage.followSystem || AppLanguage(rawValue: value) != nil else { return }
            languageCode = value
        })
    }

    var appearanceSelection: Binding<String> {
        Binding(get: { selectedAppearance.rawValue }, set: { value in
            guard let appearance = AppAppearance(rawValue: value) else { return }
            appearanceCode = appearance.rawValue
        })
    }

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Menu(selectedLanguage.text("app.appearance")) {
                Picker(selectedLanguage.text("app.appearance"), selection: appearanceSelection) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.displayName(in: selectedLanguage)).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        CommandMenu(selectedLanguage.text("app.language")) {
            Picker(selectedLanguage.text("app.language"), selection: languageSelection) {
                Text(selectedLanguage.text("language.followSystem")).tag(AppLanguage.followSystem)
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language.rawValue)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}
