import AppKit

/// Batch history stores paths and the settings used for each result. Keeping
/// every decoded image, encoded export and source frame in memory is unbounded
/// for the thousand-video queues this app supports.
struct RenderedStoryboardPreview: Identifiable, Sendable {
    let id: UUID
    let sourceURL: URL
    let duration: Double
    let frameCount: Int
    let settings: ExportSettings
    var savedURL: URL?
    let storageURL: URL?
    let fallbackData: Data?
    let jobIndex: Int
    let jobCount: Int

    var format: ExportFormat { settings.format }

    func saved(at destination: URL) -> RenderedStoryboardPreview {
        RenderedStoryboardPreview(
            id: id, sourceURL: sourceURL, duration: duration, frameCount: frameCount,
            settings: settings, savedURL: destination, storageURL: destination,
            fallbackData: nil, jobIndex: jobIndex, jobCount: jobCount
        )
    }

    func loadData() throws -> Data {
        if let fallbackData { return fallbackData }
        guard let storageURL else { throw StoryboardError.noExportData }
        return try Data(contentsOf: storageURL, options: .mappedIfSafe)
    }

    func thumbnail(from data: Data) -> CGImage? {
        ImageCodec.thumbnail(from: data)
    }

    func loadPresentation() throws -> PreparedPreviewPresentation {
        try Task.checkCancellation()
        if savedURL != nil, fallbackData == nil, let storageURL {
            // Saved results need only a display-sized bitmap. Let ImageIO read
            // the file directly instead of mapping the full export into Data.
            guard let image = ImageCodec.thumbnail(at: storageURL) else {
                throw StoryboardError.noExportData
            }
            try Task.checkCancellation()
            return PreparedPreviewPresentation(image: image, pendingData: nil)
        }
        let data = try loadData()
        guard let image = thumbnail(from: data) else { throw StoryboardError.noExportData }
        try Task.checkCancellation()
        return PreparedPreviewPresentation(image: image, pendingData: savedURL == nil ? data : nil)
    }
}

struct PreparedPreviewPresentation: Sendable {
    let image: CGImage
    let pendingData: Data?
}

struct PreparedStoryboardOutput: Sendable {
    let preview: RenderedStoryboardPreview
    let presentation: PreparedPreviewPresentation
    let saveFailure: String?
}

/// This actor serializes filename allocation and atomic writes off MainActor,
/// including a manual export racing with a cancelled batch's final write.
actor StoryboardOutputWriter {
    static let shared = StoryboardOutputWriter()
    private let writeFile: @Sendable (Data, URL) throws -> Void
    private var destinations = ExportSequenceAllocator()

    init(writeFile: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
        try data.write(to: url, options: .atomic)
    }) {
        self.writeFile = writeFile
    }

    func prepare(
        data: Data, result: StoryboardResult, settings: ExportSettings,
        jobIndex: Int, jobCount: Int, id: UUID = UUID(),
        previewStore: PreviewImageStore
    ) throws -> PreparedStoryboardOutput {
        try Task.checkCancellation()
        // Validate before allocating a filename or writing a file: a failed
        // decode must not leave an unreadable export beside the source video.
        guard let image = ImageCodec.thumbnail(from: data) else { throw StoryboardError.noExportData }
        try Task.checkCancellation()
        var savedURL: URL?
        var saveFailure: String?
        do {
            let destination = destinations.nextURL(for: result.sourceURL, format: settings.format)
            try writeFile(data, destination)
            savedURL = destination
        } catch let error as CancellationError {
            throw error
        } catch {
            saveFailure = error.localizedDescription
        }
        let storageURL = savedURL ?? (try? previewStore.store(data, format: settings.format))
        let preview = RenderedStoryboardPreview(
            id: id, sourceURL: result.sourceURL, duration: result.duration,
            frameCount: result.frames.count, settings: settings, savedURL: savedURL,
            storageURL: storageURL, fallbackData: storageURL == nil ? data : nil,
            jobIndex: jobIndex, jobCount: jobCount
        )
        return PreparedStoryboardOutput(
            preview: preview,
            presentation: PreparedPreviewPresentation(image: image, pendingData: savedURL == nil ? data : nil),
            saveFailure: saveFailure
        )
    }

    func save(_ data: Data, to destination: URL) throws {
        try Task.checkCancellation()
        try writeFile(data, destination)
    }
}

/// Used only when the video's folder rejects automatic export. These images
/// remain available for Save As without retaining an entire failed batch in RAM.
final class PreviewImageStore: @unchecked Sendable {
    private let directory: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? fileManager.temporaryDirectory
            .appendingPathComponent("ShotMap-previews-\(UUID().uuidString)", isDirectory: true)
    }

    func store(_ data: Data, format: ExportFormat) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).\(format.fileExtension)")
        try data.write(to: url, options: .atomic)
        return url
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: directory)
    }

    deinit {
        let directory = directory
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

enum DroppedVideoURL {
    static func decode(_ item: Any?) -> URL? {
        let url: URL?
        if let item = item as? URL {
            url = item
        } else if let data = item as? Data {
            url = URL(dataRepresentation: data, relativeTo: nil)
        } else {
            url = nil
        }
        return url?.isFileURL == true ? url : nil
    }
}
