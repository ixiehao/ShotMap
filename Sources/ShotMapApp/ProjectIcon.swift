import AppKit
import SwiftUI

/// Tabler Icons Outline, v3.49.0, rendered from the original bundled SVGs.
///
/// The Tabler project designs each icon on a 24-point grid with a 2 pt outline.
/// Keeping its source SVGs in the app bundle gives ShotMap a consistent,
/// recognisable visual language without adding a network dependency or an icon
/// font. The originals and their MIT licence are documented in `NOTICE.md`.
@MainActor
struct ProjectIcon: View {
    enum Symbol {
        case language, appearance, moon, disclosure, check, selector
        case grid, frame, layers, export, privacy, videoImport
        case wand, smartSelect, refreshCandidates, previous, next, skipPrevious, skipNext, folder, folderCheck, save, sliders, frameSelect
        case film, selected, eye, filmStack, plus, trash, refresh, pause, play, ellipsis

        fileprivate var tablerAsset: String {
            switch self {
            case .language: "language"
            case .appearance: "sun"
            case .moon: "moon"
            case .disclosure: "chevron-down"
            case .check: "check"
            case .selector: "selector"
            case .grid: "layout-grid"
            case .frame: "photo"
            case .layers: "stack-2"
            case .export: "download"
            case .privacy: "shield-check"
            case .videoImport: "video-plus"
            case .wand: "wand"
            case .smartSelect: "photo-spark"
            case .refreshCandidates, .refresh: "refresh"
            case .previous: "chevron-left"
            case .next: "chevron-right"
            case .skipPrevious: "player-skip-back"
            case .skipNext: "player-skip-forward"
            case .folder: "folder"
            case .folderCheck: "folder-check"
            case .save: "device-floppy"
            case .sliders: "adjustments-horizontal"
            case .frameSelect: "scan"
            case .film: "movie"
            case .selected: "circle-check"
            case .eye: "eye"
            case .filmStack: "stack-2"
            case .plus: "plus"
            case .trash: "trash"
            case .pause: "player-pause"
            case .play: "player-play"
            case .ellipsis: "dots"
            }
        }
    }

    let symbol: Symbol
    var size: CGFloat = 16

    var body: some View {
        Image(nsImage: TablerIconCatalog.image(named: symbol.tablerAsset))
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct GlyphLabel: View {
    let title: String
    let glyph: ProjectIcon.Symbol
    var glyphSize: CGFloat = 15

    var body: some View {
        Label {
            Text(title)
        } icon: {
            ProjectIcon(symbol: glyph, size: glyphSize)
        }
    }
}

/// AppKit is used only as a compact, native SVG renderer. The result is marked
/// as a template image, so the same Tabler stroke adopts the caller's semantic
/// foreground colour in both light and dark appearances.
@MainActor
private enum TablerIconCatalog {
    private static var cachedImages: [String: NSImage] = [:]

    static func image(named name: String) -> NSImage {
        if let cached = cachedImages[name] {
            return cached
        }

        let resourceName = "tabler-\(name)"
        let image: NSImage
        if let url = Bundle.module.url(forResource: resourceName, withExtension: "svg"),
           let loaded = NSImage(contentsOf: url) {
            image = loaded
        } else {
            image = NSImage(systemSymbolName: "questionmark.square.dashed", accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 24, height: 24))
        }
        image.isTemplate = true
        cachedImages[name] = image
        return image
    }
}
