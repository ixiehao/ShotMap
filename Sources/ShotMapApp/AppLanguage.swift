import Foundation

/// An in-app language choice. Keeping the selected language separate from the
/// macOS system language lets people use ShotMap in their preferred language
/// without restarting the application.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case chinese = "zh-Hans"
    case french = "fr"
    case russian = "ru"
    case spanish = "es"
    case japanese = "ja"
    case korean = "ko"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese: "中文"
        case .english: "English"
        case .french: "Français"
        case .russian: "Русский"
        case .spanish: "Español"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    /// Existing AppStorage choices take precedence. First launch follows the
    /// first supported system language, with English as the universal fallback.
    static var systemDefault: AppLanguage { preferred(from: Locale.preferredLanguages) }

    static func preferred(from identifiers: [String]) -> AppLanguage {
        for identifier in identifiers {
            let base = identifier.replacingOccurrences(of: "_", with: "-")
                .split(separator: "-").first.map(String.init)?.lowercased()
            if base == "zh" { return .chinese }
            if let language = allCases.first(where: { $0.rawValue == base }) { return language }
        }
        return .english
    }

    static let requiredLocalizationKeys = [
        "alert.generation.title", "button.ok", "app.tagline", "app.productName", "studio.title", "app.language", "app.appearance", "appearance.system", "appearance.light", "appearance.dark", "app.icon.accessibility",
        "section.grid", "section.frame", "section.aspect", "aspect.source", "aspect.landscape", "aspect.standard",
        "aspect.square", "aspect.vertical", "aspect.portrait", "aspect.ultraWide",
        "section.export", "export.autosave", "export.format", "export.width", "export.width.value", "export.background",
        "background.cinema", "background.ivory", "background.navy", "background.mist", "background.evergreen",
        "export.time", "export.title", "button.generate.single",
        "button.generate.batch", "button.cancel", "button.cancelGeneration", "button.cancelGenerationConfirm", "button.keepGenerating",
        "button.pauseGeneration", "button.pausePending", "button.pauseConfirm", "button.resumeGeneration", "button.resumeConfirm",
        "button.retryFailed", "button.failureDetails", "button.close", "accessibility.generating", "accessibility.generate", "accessibility.selected",
        "accessibility.analyzing", "preview.title", "preview.position", "button.saveas", "button.openSaved", "button.openSaved.hint",
        "button.adjustFrames", "button.adjustFrames.hint", "button.previousResult", "button.nextResult", "status.processing", "status.empty",
        "default.video", "processing.fast", "processing.people", "processing.assembling", "error.unsupportedInput", "error.videoImport", "queue.importing",
        "status.cancelled", "status.nowProcessing", "status.saved", "status.manualSaved", "status.generatedNotSaved", "status.failedContinue",
        "status.paused", "status.pausePending", "processing.paused", "processing.pausePending", "alert.pauseBatch.title", "alert.pauseBatch.message",
        "alert.resumeBatch.title", "alert.resumeBatch.message", "alert.cancelBatch.title", "alert.cancelBatch.message",
        "status.batchCompleted", "status.batchCompletedWithFailures", "job.queued", "job.processing", "job.completed",
        "job.failed", "queue.more", "queue.clear", "queue.clear.hint", "queue.title", "queue.count", "queue.addAction", "queue.localTitle",
        "inspector.title", "batch.failureSummary", "video.add", "video.added", "video.support",
        "video.queueHint", "preview.live", "preview.empty.title", "preview.empty.description", "error.unreadableVideo",
        "error.unsupportedCodec", "error.noUsableFrames", "error.noExportData", "error.previewStorage", "about.menu", "about.developer",
        "about.feedback", "about.privacy", "about.license", "help.menu", "help.title", "help.intro",
        "help.step.add.title", "help.step.add.detail", "help.step.settings.title", "help.step.settings.detail",
        "help.step.create.title", "help.step.create.detail", "help.troubleshoot.title", "help.troubleshoot.detail",
        "help.privacy", "help.project", "help.feedback", "update.available", "update.about.available", "update.menu.available",
        "update.menu.check", "button.downloadUpdate", "editor.title", "editor.detail", "editor.preview", "editor.timelineHint", "editor.loading",
        "editor.noPreview", "editor.apply",
        "editor.cancel", "editor.selectionCount", "editor.smartSelect", "editor.regenerate", "editor.videoPreview",
        "editor.videoPreviewDetail", "editor.playPreview", "editor.pausePreview", "editor.addCurrentFrame", "editor.candidates",
        "editor.timeField", "editor.backTenFrames", "editor.previousFrame", "editor.nextFrame", "editor.forwardTenFrames",
        "editor.backFiveFrames", "editor.backOneFrame", "editor.forwardOneFrame", "editor.forwardFiveFrames",
        "failureReport.title", "failureReport.detail", "failureReport.unknown", "failureReport.transcoding.badge",
        "failureReport.showSources", "failureReport.transcodingGuide", "transcoding.title", "transcoding.intro",
        "transcoding.step.one", "transcoding.step.two", "transcoding.step.three", "transcoding.tip"
    ]

    /// Resource-bundle lookup is immutable for the lifetime of the process.
    /// Resolve each `.lproj` directory from the resource root explicitly:
    /// `path(forResource:ofType:)` may fall back to the host language in an
    /// XCTest bundle, which would silently show English for another selection.
    /// Cache the exact bundles for SwiftUI's frequent label updates.
    private static let localizationBundles: [AppLanguage: Bundle] = Dictionary(
        uniqueKeysWithValues: allCases.compactMap { language in
            guard let resources = Bundle.module.resourceURL,
                  let bundle = Bundle(url: resources.appendingPathComponent("\(language.rawValue).lproj", isDirectory: true)) else { return nil }
            return (language, bundle)
        }
    )

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        text(key, arguments: arguments)
    }

    func text(_ key: String, arguments: [CVarArg]) -> String {
        let format = localizationBundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }

    private var localizationBundle: Bundle {
        Self.localizationBundles[self] ?? Self.localizationBundles[.english] ?? .module
    }
}
