import AVFoundation
import Foundation

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case png = "PNG"
    case jpeg = "JPG"

    var id: String { rawValue }
    var fileExtension: String { self == .png ? "png" : "jpg" }
}

/// Purposeful, low-saturation canvases for a contact sheet. These colors keep
/// a visual boundary around film frames without competing with the footage.
enum StoryboardBackground: String, CaseIterable, Identifiable, Sendable {
    case cinema
    case ivory
    case navy
    case mist
    case evergreen
    case rose

    var id: Self { self }

    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .cinema: (0.055, 0.063, 0.086)
        case .ivory: (0.945, 0.922, 0.879)
        case .navy: (0.055, 0.145, 0.255)
        case .mist: (0.824, 0.890, 0.945)
        case .evergreen: (0.094, 0.275, 0.224)
        case .rose: (0.925, 0.796, 0.800)
        }
    }

    func label(in language: AppLanguage) -> String {
        language.text("background.\(rawValue)")
    }
}

enum StoryboardGrid {
    /// Six options keep the controls to two compact rows.
    static let availableSides = Array(3...8)
}

/// The card ratio also determines the exported contact-sheet direction because
/// every supported storyboard grid has the same number of rows and columns.
/// `source` is deliberately the default: it preserves a vertical, square, or
/// horizontal video's composition instead of forcing every frame into 16:9.
enum StoryboardAspect: CaseIterable, Identifiable, Sendable {
    case source
    case landscape
    case standard
    case square
    case vertical
    case portrait
    case ultraWide

    var id: Self { self }

    func label(in language: AppLanguage) -> String {
        language.text(localizationKey)
    }

    private var localizationKey: String {
        switch self {
        case .source: "aspect.source"
        case .landscape: "aspect.landscape"
        case .standard: "aspect.standard"
        case .square: "aspect.square"
        case .vertical: "aspect.vertical"
        case .portrait: "aspect.portrait"
        case .ultraWide: "aspect.ultraWide"
        }
    }

    private var fixedCardAspectRatio: Double? {
        switch self {
        case .source: nil
        case .landscape: 16.0 / 9.0
        case .standard: 4.0 / 3.0
        case .square: 1
        case .vertical: 3.0 / 4.0
        case .portrait: 9.0 / 16.0
        case .ultraWide: 21.0 / 9.0
        }
    }

    /// A guard rail for damaged metadata and unusually shaped image decodes.
    /// It still accommodates all common phone, square, film, and ultrawide ratios.
    func resolvedCardAspectRatio(sourceAspectRatio: Double?) -> Double {
        let candidate = fixedCardAspectRatio ?? sourceAspectRatio ?? (16.0 / 9.0)
        guard candidate.isFinite, candidate > 0 else { return 16.0 / 9.0 }
        return min(3, max(1.0 / 3.0, candidate))
    }
}

struct ExportSettings: Sendable {
    var gridSide: Int = 4
    var layoutAspect: StoryboardAspect = .source
    var language: AppLanguage = .chinese
    var format: ExportFormat = .png
    var width: Int = 2560
    var background: StoryboardBackground = .cinema
    var showTimestamps = false
    var showTitleWatermark = false

    var frameCount: Int { gridSide * gridSide }
    var safeWidth: Int { max(1920, min(width, 12_000)) }

    func resolvedCardAspectRatio(for frames: [CapturedFrame]) -> Double {
        layoutAspect.resolvedCardAspectRatio(sourceAspectRatio: frames.first?.aspectRatio)
    }

    func titleWatermark(for sourceURL: URL) -> String? {
        guard showTitleWatermark else { return nil }
        let title = sourceURL
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        // File names can be unexpectedly long; preserve a useful title without
        // allowing it to obscure the entire storyboard.
        return String(title.prefix(72))
    }
}

enum TimestampFormatter {
    static func string(for seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00:00" }
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainder = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainder)
    }

    /// A stable, editable representation for manual timeline positioning.
    /// Keep this separate from the short timestamp burned into thumbnails.
    static func editableString(for seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00:00.000" }
        let milliseconds = max(0, Int((seconds * 1_000).rounded()))
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds % 3_600_000) / 60_000
        let remainderSeconds = (milliseconds % 60_000) / 1_000
        let remainderMilliseconds = milliseconds % 1_000
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, remainderSeconds, remainderMilliseconds)
    }

    /// Accepts `SS.mmm`, `MM:SS.mmm`, or `HH:MM:SS.mmm` so people can enter a
    /// precise moment without having to fill leading units. The canonical
    /// display is always `HH:MM:SS.mmm`.
    static func editableSeconds(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty else { return nil }
        let pieces = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(pieces.count), !pieces.contains(where: { $0.isEmpty }) else { return nil }
        guard let last = Double(pieces[pieces.count - 1]), last.isFinite, last >= 0, last < 60 else { return nil }

        switch pieces.count {
        case 1:
            return last
        case 2:
            guard let minutes = Int(pieces[0]), minutes >= 0 else { return nil }
            // Do the conversion before multiplication. A pasted, pathological
            // minute value must be rejected or clamped by the caller, never
            // overflow an Int and terminate the app.
            let seconds = Double(minutes) * 60 + last
            return seconds.isFinite ? seconds : nil
        case 3:
            guard let hours = Int(pieces[0]), hours >= 0,
                  let minutes = Int(pieces[1]), (0..<60).contains(minutes) else { return nil }
            let seconds = Double(hours) * 3_600 + Double(minutes) * 60 + last
            return seconds.isFinite ? seconds : nil
        default:
            return nil
        }
    }
}

enum ExportDestination {
    static func filename(baseName: String, format: ExportFormat, sequence: Int) -> String {
        let suffix = String(format: "%03d", max(1, sequence))
        let ending = "-shot-\(suffix).\(format.fileExtension)"
        // macOS permits 255 UTF-8 bytes per filename, not 255 characters. Leave
        // space for the generated suffix without splitting a Unicode character.
        var safeBaseName = baseName.isEmpty ? "video" : baseName
        while safeBaseName.utf8.count + ending.utf8.count > 255 {
            safeBaseName.removeLast()
        }
        return "\(safeBaseName)\(ending)"
    }

    static func nextURL(for source: URL, format: ExportFormat, fileManager: FileManager = .default) -> URL {
        let folder = source.deletingLastPathComponent()
        let baseName = source.deletingPathExtension().lastPathComponent
        var sequence = 1
        while true {
            let candidate = folder.appendingPathComponent(filename(baseName: baseName, format: format, sequence: sequence))
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            sequence += 1
        }
    }
}

/// A hint avoids rescanning all earlier outputs for every image in a batch.
/// The candidate is still checked on disk because another app may have created
/// it since the previous write. The writer actor owns and serializes this value.
struct ExportSequenceAllocator {
    private struct Key: Hashable {
        let folder: String
        let baseName: String
        let fileExtension: String
    }

    private var nextSequences: [Key: Int] = [:]

    mutating func nextURL(
        for source: URL,
        format: ExportFormat,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        let folder = source.deletingLastPathComponent().standardizedFileURL
        let baseName = source.deletingPathExtension().lastPathComponent
        let key = Key(folder: folder.path, baseName: baseName, fileExtension: format.fileExtension)
        var sequence = nextSequences[key] ?? 1
        while true {
            let candidate = folder.appendingPathComponent(
                ExportDestination.filename(baseName: baseName, format: format, sequence: sequence)
            )
            if !fileExists(candidate.path) {
                nextSequences[key] = sequence + 1
                return candidate
            }
            sequence += 1
        }
    }
}

enum VideoJobState: Equatable {
    case queued
    case processing
    case completed(String)
    case failed(VideoFailure)

    func label(in language: AppLanguage) -> String {
        switch self {
        case .queued: language.text("job.queued")
        case .processing: language.text("job.processing")
        case .completed: language.text("job.completed")
        case .failed: language.text("job.failed")
        }
    }

    var failureMessage: String? {
        guard case let .failed(failure) = self else { return nil }
        return failure.message
    }

    var canRetry: Bool {
        guard case let .failed(failure) = self else { return false }
        return failure.isRetryable
    }

    var needsTranscoding: Bool {
        guard case let .failed(failure) = self else { return false }
        return failure.needsTranscoding
    }
}

/// Only transient failures belong in the retry action. A decoder limitation is
/// deterministic, so sending it through the same batch again wastes time.
struct VideoFailure: Equatable {
    enum Kind: Equatable {
        case retryable, needsTranscoding, permanent
    }

    let message: String
    let kind: Kind

    var isRetryable: Bool { kind == .retryable }

    static func retryable(_ message: String) -> VideoFailure {
        VideoFailure(message: message, kind: .retryable)
    }

    static func needsTranscoding(_ message: String) -> VideoFailure {
        VideoFailure(message: message, kind: .needsTranscoding)
    }

    static func permanent(_ message: String) -> VideoFailure {
        VideoFailure(message: message, kind: .permanent)
    }

    static func classify(_ error: Error, language: AppLanguage) -> VideoFailure {
        if let error = error as? StoryboardError {
            let message = error.message(in: language)
            switch error {
            case .unsupportedCodec: return .needsTranscoding(message)
            case .unreadableVideo, .noUsableFrames: return .permanent(message)
            case .noExportData: return .retryable(message)
            }
        }

        // AVFoundation can fail after a container has already been accepted by
        // the file picker. Retrying a missing decoder or an unparseable movie
        // merely repeats the same work, so make the recovery path actionable:
        // offer transcoding for codec/container limits and do not offer a retry
        // for permanently unreadable or protected media. Transient I/O errors
        // remain retryable because an external drive, permission, or file copy
        // can change while the app is open.
        let nsError = error as NSError
        if nsError.domain == AVFoundationErrorDomain {
            switch AVError.Code(rawValue: nsError.code) {
            case .decoderNotFound, .fileFormatNotRecognized:
                return .needsTranscoding(language.text("error.unsupportedCodec"))
            case .fileFailedToParse, .failedToLoadMediaData, .contentIsProtected:
                return .permanent(language.text("error.unreadableVideo"))
            default:
                break
            }
        }
        if nsError.domain == NSCocoaErrorDomain,
           CocoaError.Code(rawValue: nsError.code) == .fileReadCorruptFile {
            return .permanent(language.text("error.unreadableVideo"))
        }
        return .retryable(error.localizedDescription)
    }

    var needsTranscoding: Bool { kind == .needsTranscoding }
}

struct VideoJob: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var state: VideoJobState

    init(url: URL, state: VideoJobState = .queued) {
        self.id = UUID()
        self.url = url
        self.state = state
    }
}

struct FrameDescriptor: Identifiable, Sendable {
    let id: Int
    let time: Double
    let histogram: [Float]
    let luminance: Float
    let blackRatio: Float
    var brightRatio: Float = 0
    var dominantToneRatio: Float = 0
    let sharpness: Float
    let fingerprint: UInt64
    let previewData: Data?
    /// Set from the same AVFoundation image used for metrics, so choosing a
    /// source-matched layout never needs another image decode.
    var aspectRatio: Double = 16.0 / 9.0
    var peopleScore: Float = 0
    /// Face and body signals are kept separately: dialogue scenes tend to have
    /// clear faces, while action scenes often need a readable full-body pose.
    var faceScore: Float = 0
    var bodyScore: Float = 0
    var faceCount: Int = 0
    /// Low-resolution temporal signal calculated from adjacent samples. It is
    /// deliberately modest in the final score: movement is useful only when a
    /// person or action is still visually readable.
    var motionScore: Float = 0
    /// A large jump on both sides is usually a cut, fade, or transition rather
    /// than a usable moment inside a shot.
    var transitionScore: Float = 0
    /// Derived locally with Vision from the lightweight analysis image. A high
    /// value usually indicates title cards, warning screens, or cover artwork.
    var textOverlayScore: Float = 0

    var isVisuallySparseCard: Bool {
        let mostlyWhite = brightRatio >= 0.58 && luminance >= 0.68
        let mostlyDark = blackRatio >= 0.58 && luminance <= 0.30
        return mostlyWhite || mostlyDark || dominantToneRatio >= 0.78
    }

    var isLikelyNonContentGraphic: Bool {
        guard peopleScore < 0.08 else { return false }
        // Sparse white/black slides often contain too little text for OCR to
        // cross the text-only threshold. Their overwhelmingly uniform luminance
        // still distinguishes them from a real bright or dark scene.
        // Normal subtitles and small watermarks are common in source material.
        // Only a genuinely dominant text screen is a hard rejection here;
        // temporal title-run filtering makes the complementary decision.
        let textHeavy = textOverlayScore >= 0.65
        return textHeavy || isVisuallySparseCard
    }

    var isUsable: Bool {
        blackRatio < 0.82 && luminance > 0.045 && sharpness > 0.012
    }

    var qualityScore: Float {
        let exposure = min(1, max(0, (luminance - 0.08) / 0.40))
        let detail = min(1, sharpness / 0.18)
        let darknessPenalty = blackRatio * 1.4
        let facePreference: Float = faceScore > 0.05 ? 0.42 + faceScore * 0.56 : 0
        let bodyPreference: Float = bodyScore > 0.05 ? 0.26 + bodyScore * 0.40 : 0
        // Manual selection and older cached descriptors only carry the combined
        // person signal, so preserve that useful fallback without double-counting
        // the richer Vision metrics above.
        let personFallback: Float = faceScore <= 0.05 && bodyScore <= 0.05 && peopleScore > 0.05
            ? 0.38 + peopleScore * 0.52
            : 0
        let interactionPreference: Float = faceCount >= 2 ? 0.20 : 0
        // A readable action pose receives a small bonus, but fast motion alone
        // never outranks a stable dramatic shot.
        let actionPreference = bodyScore * motionScore * 0.24
        let transitionPenalty = transitionScore * 0.34
        // OCR-confirmed title cards remain poor storyboard material. A dark or
        // minimalist cinematic shot, however, is not equivalent to a title card:
        // retain it as a slightly lower-priority option rather than effectively
        // removing it from automatic selection.
        let textPenalty: Float
        if textOverlayScore >= 0.65 {
            textPenalty = 0.55
        } else if isVisuallySparseCard && peopleScore < 0.08 {
            textPenalty = 0.18
        } else {
            textPenalty = 0
        }
        return max(0, exposure * 0.35 + detail * 0.55 + facePreference + bodyPreference + personFallback + interactionPreference + actionPreference - darknessPenalty - transitionPenalty - textPenalty)
    }
}

struct CapturedFrame: Sendable, Identifiable {
    let id: Int
    let time: Double
    let jpegData: Data
    /// Captured after AVFoundation applies the video's preferred track transform,
    /// so a phone video is reported as vertical rather than its encoded rotation.
    let aspectRatio: Double

    init(id: Int, time: Double, jpegData: Data, aspectRatio: Double = 16.0 / 9.0) {
        self.id = id
        self.time = time
        self.jpegData = jpegData
        self.aspectRatio = aspectRatio
    }
}

struct StoryboardResult: Sendable {
    let frames: [CapturedFrame]
    let sourceURL: URL
    /// Kept with the selected frames so the lightweight manual adjuster can seek
    /// to a user-chosen moment without rescanning the whole movie.
    let duration: Double

    init(frames: [CapturedFrame], sourceURL: URL, duration: Double = 0) {
        self.frames = frames
        self.sourceURL = sourceURL
        self.duration = duration
    }
}

enum StoryboardError: LocalizedError {
    case unreadableVideo
    case unsupportedCodec
    case noUsableFrames
    case noExportData

    func message(in language: AppLanguage) -> String {
        switch self {
        case .unreadableVideo: language.text("error.unreadableVideo")
        case .unsupportedCodec: language.text("error.unsupportedCodec")
        case .noUsableFrames: language.text("error.noUsableFrames")
        case .noExportData: language.text("error.noExportData")
        }
    }

    var errorDescription: String? { message(in: .chinese) }
}
