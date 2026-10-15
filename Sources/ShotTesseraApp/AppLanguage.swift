import Foundation

/// An in-app language choice. Keeping the selected language separate from the
/// macOS system language lets people use ShotMap in their preferred language
/// without restarting the application.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese: "中文"
        case .english: "English"
        case .japanese: "日本語"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    static let requiredLocalizationKeys = [
        "alert.generation.title", "button.ok", "app.tagline", "app.language", "app.appearance", "appearance.system", "appearance.light", "appearance.dark", "app.icon.accessibility",
        "section.grid", "section.frame", "section.aspect", "aspect.source", "aspect.landscape", "aspect.standard",
        "aspect.square", "aspect.vertical", "aspect.portrait", "aspect.ultraWide",
        "section.export", "export.autosave", "export.format", "export.width", "export.width.value", "export.background",
        "background.cinema", "background.ivory", "background.navy", "background.mist", "background.evergreen", "background.rose",
        "export.time", "export.title", "button.generate.single",
        "button.generate.batch", "button.cancel", "button.cancelGeneration", "button.cancelGenerationConfirm", "button.keepGenerating",
        "button.pauseGeneration", "button.pausePending", "button.pauseConfirm", "button.resumeGeneration", "button.resumeConfirm",
        "button.retryFailed", "button.failureDetails", "button.close", "accessibility.generating", "accessibility.generate", "accessibility.selected",
        "accessibility.analyzing", "preview.title", "preview.position", "button.saveas", "button.openSaved", "button.openSaved.hint",
        "button.adjustFrames", "button.adjustFrames.hint", "button.previousResult", "button.nextResult", "status.processing", "status.empty",
        "default.video", "processing.fast", "processing.people", "processing.assembling", "error.unsupportedInput",
        "status.cancelled", "status.nowProcessing", "status.saved", "status.manualSaved", "status.generatedNotSaved", "status.failedContinue",
        "status.paused", "status.pausePending", "processing.paused", "processing.pausePending", "alert.pauseBatch.title", "alert.pauseBatch.message",
        "alert.resumeBatch.title", "alert.resumeBatch.message", "alert.cancelBatch.title", "alert.cancelBatch.message",
        "status.batchCompleted", "status.batchCompletedWithFailures", "job.queued", "job.processing", "job.completed",
        "job.failed", "queue.more", "queue.clear", "queue.clear.hint", "video.add", "video.added", "video.support",
        "video.queueHint", "preview.live", "preview.empty.title", "preview.empty.description", "error.unreadableVideo",
        "error.unsupportedCodec", "error.noUsableFrames", "error.noExportData", "error.previewStorage", "about.menu", "about.developer",
        "about.feedback", "about.privacy", "about.license", "help.menu", "help.title", "help.intro",
        "help.step.add.title", "help.step.add.detail", "help.step.settings.title", "help.step.settings.detail",
        "help.step.create.title", "help.step.create.detail", "help.troubleshoot.title", "help.troubleshoot.detail",
        "help.privacy", "help.project", "help.feedback", "update.available", "update.about.available", "update.menu.available",
        "update.menu.check", "button.downloadUpdate", "editor.title", "editor.detail", "editor.loading",
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
    /// Cache it once per language instead of rebuilding a Bundle for every
    /// localized label during each SwiftUI body update.
    private static let localizationBundles: [AppLanguage: Bundle] = Dictionary(
        uniqueKeysWithValues: allCases.compactMap { language in
            guard let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { return nil }
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
        Self.localizationBundles[self] ?? .module
    }
}
