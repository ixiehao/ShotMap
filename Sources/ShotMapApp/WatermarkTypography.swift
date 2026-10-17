import CoreText
import Foundation

/// Registers the bundled OFL font for export only. It is never installed into
/// the user's system font library and is available only for this process.
enum WatermarkTypography {
    static let postScriptName = "NotoSansCJKsc-Bold"

    static let isBundledFontAvailable: Bool = {
        guard let url = Bundle.module.url(
            forResource: "NotoSansCJKsc-Bold",
            withExtension: "otf"
        ) else { return false }

        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) { return true }
        let names = CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []
        return names.contains(postScriptName)
    }()

    static func titleFont(size: CGFloat) -> CTFont {
        guard isBundledFontAvailable else {
            // This only protects manually altered development bundles; all
            // release bundles include the checked-in OFL font resource.
            return CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        }
        return CTFontCreateWithName(postScriptName as CFString, size, nil)
    }
}
