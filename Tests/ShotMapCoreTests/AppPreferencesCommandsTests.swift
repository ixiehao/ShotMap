import Foundation
import XCTest
@testable import ShotMapApp

final class AppPreferencesCommandsTests: XCTestCase {
    @MainActor
    func testMenuBindingsPreserveExistingPreferencesAndPersistSelections() throws {
        let suite = "ShotMap.menu-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(AppLanguage.french.rawValue, forKey: "appLanguage")
        defaults.set(AppAppearance.dark.rawValue, forKey: "appAppearance")
        defaults.set(3, forKey: "gridSide")

        let commands = AppPreferencesCommands(defaults: defaults)
        XCTAssertEqual(commands.languageSelection.wrappedValue, AppLanguage.french.rawValue)
        XCTAssertEqual(commands.appearanceSelection.wrappedValue, AppAppearance.dark.rawValue)

        commands.languageSelection.wrappedValue = AppLanguage.japanese.rawValue
        XCTAssertEqual(defaults.string(forKey: "appLanguage"), AppLanguage.japanese.rawValue)
        XCTAssertEqual(defaults.string(forKey: "appAppearance"), AppAppearance.dark.rawValue)

        commands.appearanceSelection.wrappedValue = AppAppearance.light.rawValue
        XCTAssertEqual(defaults.string(forKey: "appAppearance"), AppAppearance.light.rawValue)
        XCTAssertEqual(defaults.integer(forKey: "gridSide"), 3)
        XCTAssertEqual(AppPreferencesCommands(defaults: defaults).languageSelection.wrappedValue, AppLanguage.japanese.rawValue)
    }

    @MainActor
    func testUnknownPreferencesHaveValidCheckmarksWithoutOpeningMenuOverwritingStorage() throws {
        let suite = "ShotMap.menu-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown-language", forKey: "appLanguage")
        defaults.set("unknown-appearance", forKey: "appAppearance")

        let commands = AppPreferencesCommands(defaults: defaults)
        XCTAssertEqual(commands.languageSelection.wrappedValue, AppLanguage.english.rawValue)
        XCTAssertEqual(commands.appearanceSelection.wrappedValue, AppAppearance.system.rawValue)
        XCTAssertEqual(defaults.string(forKey: "appLanguage"), "unknown-language")
        XCTAssertEqual(defaults.string(forKey: "appAppearance"), "unknown-appearance")

        commands.languageSelection.wrappedValue = "invalid"
        commands.appearanceSelection.wrappedValue = "invalid"
        XCTAssertEqual(defaults.string(forKey: "appLanguage"), "unknown-language")
        XCTAssertEqual(defaults.string(forKey: "appAppearance"), "unknown-appearance")
    }
}
