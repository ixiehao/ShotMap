import CoreText
import Foundation
import XCTest
@testable import ShotMapApp

final class LanguageSupportTests: XCTestCase {
    func testSupportedLanguagesAndSystemPreferenceMatching() {
        XCTAssertEqual(AppLanguage.allCases.map(\.rawValue), ["en", "zh-Hans", "fr", "ru", "es", "ja", "ko"])
        for (identifier, expected) in [
            ("en-GB", AppLanguage.english), ("zh-Hant-TW", .chinese),
            ("fr_CA", .french), ("ru-RU", .russian), ("es-419", .spanish),
            ("ja-JP", .japanese), ("ko-KR", .korean)
        ] {
            XCTAssertEqual(AppLanguage.preferred(from: [identifier]), expected)
        }
        XCTAssertEqual(AppLanguage.preferred(from: ["de-DE", "fr-CH", "en"]), .french)
        XCTAssertEqual(AppLanguage.preferred(from: ["ar-SA"]), .english)
        XCTAssertEqual(AppLanguage.preferred(from: []), .english)
    }

    func testAllResourcesHaveIdenticalKeysAndFormatArguments() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let resources = root.appendingPathComponent("Sources/ShotMapApp/Resources")
        let expression = try NSRegularExpression(pattern: "%([0-9]+\\$)?[-+0 #]*[0-9]*(?:\\.[0-9]+)?(?:ll|l|z)?[@diufgs]")
        func placeholders(_ value: String) -> [String] {
            expression.matches(in: value, range: NSRange(value.startIndex..., in: value))
                .map { (value as NSString).substring(with: $0.range) }
        }
        let required = Set(AppLanguage.requiredLocalizationKeys)
        XCTAssertEqual(required.count, AppLanguage.requiredLocalizationKeys.count)
        for language in AppLanguage.allCases {
            let path = resources.appendingPathComponent("\(language.rawValue).lproj/Localizable.strings")
            let strings = try XCTUnwrap(PropertyListSerialization.propertyList(
                from: Data(contentsOf: path), options: [], format: nil
            ) as? [String: String])
            XCTAssertEqual(Set(strings.keys), required, language.rawValue)
            for key in required {
                let translated = try XCTUnwrap(strings[key])
                XCTAssertFalse(translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertEqual(language.text(key), translated, "Bundled resource mismatch: \(language.rawValue)/\(key)")
                XCTAssertEqual(placeholders(translated), placeholders(AppLanguage.english.text(key)), "Unsafe format arguments: \(language.rawValue)/\(key)")
            }
        }
    }

    func testNewLanguageBundlesDoNotSilentlyFallBackToEnglish() {
        XCTAssertEqual(AppLanguage.french.text("app.language"), "Langue")
        XCTAssertEqual(AppLanguage.spanish.text("app.language"), "Idioma")
        XCTAssertEqual(AppLanguage.russian.text("app.language"), "Язык")
        XCTAssertEqual(AppLanguage.korean.text("app.language"), "언어")
    }

    func testWatermarkShapingCoversFilenamesInEverySupportedLanguage() {
        let font = WatermarkTypography.titleFont(size: 36)
        for title in ["Family trip", "家庭回忆", "Vacances d’été", "Семейная поездка", "Viaje de verano", "家族の旅行", "가족 여행"] {
            let string = NSAttributedString(string: title, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font
            ])
            let line = CTLineCreateWithAttributedString(string)
            let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
            XCTAssertFalse(runs.isEmpty, title)
            for run in runs {
                var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                XCTAssertFalse(glyphs.contains(0), "Missing shaped filename glyph: \(title)")
            }
        }
    }
}
