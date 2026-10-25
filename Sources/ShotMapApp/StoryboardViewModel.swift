import AppKit
@preconcurrency import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Stable, index-addressable storage for a storyboard that is still being
/// built. Keeping empty slots (instead of appending images) makes a 4 × 4
/// preview stay in reading order while later, sharper versions replace the
/// same card.
struct ProgressivePreviewSlots<Frame> {
    private(set) var slots: [Frame?] = []

    var filledCount: Int { slots.reduce(into: 0) { if $1 != nil { $0 += 1 } } }

    mutating func reset(total: Int) {
        slots = Array(repeating: nil, count: max(0, total))
    }

    @discardableResult
    mutating func replace(_ frame: Frame, at index: Int, total: Int) -> Bool {
        let safeTotal = max(0, total)
        guard index >= 0, index < safeTotal else { return false }
        if slots.count != safeTotal {
            reset(total: safeTotal)
        }
        slots[index] = frame
        return true
    }
}

struct LivePreviewFrame: Identifiable {
    let id = UUID()
    let image: NSImage
}

@MainActor
final class StoryboardViewModel: ObservableObject {
    @Published private(set) var videoJobs: [VideoJob] = []
    @Published var language: AppLanguage = .systemDefault
    @Published var gridSide = 4
    @Published var layoutAspect: StoryboardAspect = .source
    @Published var format: ExportFormat = .png
    @Published var width = 2560
    @Published var background: StoryboardBackground = .cinema
    @Published var showTimestamps = false
    @Published var showTitleWatermark = false
    @Published var previewImage: NSImage?
    @Published private(set) var livePreviewSlots = ProgressivePreviewSlots<LivePreviewFrame>()
    @Published private(set) var activeGridSide = 4
    @Published private(set) var activeCardAspectRatio = 16.0 / 9.0
    @Published private(set) var activeJobIndex = 0
    @Published private(set) var activeJobCount = 0
    @Published private(set) var activeJobName = ""
    @Published var isProcessing = false
    @Published private(set) var isPauseRequested = false
    @Published private(set) var isPaused = false
    @Published var progress = 0.0
    @Published var isDropTargeted = false
    @Published private(set) var isImportingVideos = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published private var outputStatus: OutputStatus = .empty
    private var completedBatchCounts: (completed: Int, failed: Int)?
    @Published var renderedFormat: ExportFormat?
    @Published private(set) var lastSavedURL: URL?
    @Published private(set) var isApplyingFrameAdjustments = false
    @Published private(set) var completedPreviews: [RenderedStoryboardPreview] = []
    @Published private(set) var selectedPreviewIndex = 0
    @Published private(set) var isLoadingPreview = false
    private var generationTask: Task<Void, Never>?
    private var frameAdjustmentTask: Task<Void, Never>?
    private var previewLoadingTask: Task<Void, Never>?
    private var generationRunID = UUID()
    private var generationControl: BatchRunControl?
    private(set) var pendingData: Data?
    private var pendingSource: URL?
    private var pendingFormat: ExportFormat?
    private var previewImageStore = PreviewImageStore()
    private var previewLoadID = UUID()
    private var pendingDrops = OrderedVideoDrops()
    private struct DropLoading: Sendable {
        let timeout: Task<Void, Never>
        var progress: [Progress] = []
    }
    private var dropLoading: [UUID: DropLoading] = [:]
    private let dropTimeoutNanoseconds: UInt64
    private var displayedPreview: (id: UUID, presentation: PreparedPreviewPresentation)?
    private let previewLoader: @Sendable (RenderedStoryboardPreview) throws -> PreparedPreviewPresentation

    init(dropTimeoutNanoseconds: UInt64 = 30_000_000_000,
         previewLoader: @escaping @Sendable (RenderedStoryboardPreview) throws -> PreparedPreviewPresentation = {
        try $0.loadPresentation()
    }) {
        self.dropTimeoutNanoseconds = dropTimeoutNanoseconds
        self.previewLoader = previewLoader
    }

    deinit {
        generationTask?.cancel()
        frameAdjustmentTask?.cancel()
        previewLoadingTask?.cancel()
        for loading in dropLoading.values {
            loading.timeout.cancel()
            loading.progress.forEach { $0.cancel() }
        }
    }

    private func t(_ key: String, _ arguments: CVarArg...) -> String {
        language.text(key, arguments: arguments)
    }

    private enum OutputStatus {
        case empty, paused, cancelled, batchCompleted
        case processing(String)
        case generatedNotSaved(index: Int, total: Int)
        case failedContinue(index: Int)
        case manualSaved(String)
        case saved(index: Int, total: Int, filename: String)
    }

    /// Store the event and its values, not translated prose. Switching the app
    /// language then updates an existing result without rerunning any work.
    var outputDescription: String {
        switch outputStatus {
        case .empty: return ""
        case .paused: return t("status.paused")
        case .cancelled: return t("status.cancelled")
        case .processing(let filename): return t("status.nowProcessing", filename)
        case .generatedNotSaved(let index, let total): return t("status.generatedNotSaved", index, total)
        case .failedContinue(let index): return t("status.failedContinue", index)
        case .manualSaved(let filename): return t("status.manualSaved", filename)
        case .saved(let index, let total, let filename): return t("status.saved", index, total, filename)
        case .batchCompleted:
            guard let counts = completedBatchCounts else { return "" }
            return counts.failed > 0
                ? t("status.batchCompletedWithFailures", counts.completed, counts.failed)
                : t("status.batchCompleted", counts.completed)
        }
    }

    var hasVideos: Bool { !videoJobs.isEmpty }
    var livePreviewFrames: [LivePreviewFrame?] { livePreviewSlots.slots }
    var livePreviewFrameCount: Int { livePreviewSlots.filledCount }
    var isBusy: Bool { isProcessing || isApplyingFrameAdjustments }
    var isSettingsLocked: Bool { (isProcessing && !isPaused) || isApplyingFrameAdjustments }
    var isQueueLocked: Bool { isProcessing || isApplyingFrameAdjustments }
    var failedJobs: [VideoJob] { videoJobs.filter { $0.state.failureMessage != nil } }
    var retryableFailedJobs: [VideoJob] { failedJobs.filter { $0.state.canRetry } }
    var transcodingJobs: [VideoJob] { failedJobs.filter { $0.state.needsTranscoding } }
    var failedJobCount: Int { failedJobs.count }
    var retryableFailedJobCount: Int { retryableFailedJobs.count }
    var hasRetryableFailedJobs: Bool { !retryableFailedJobs.isEmpty }
    var hasFailedJobs: Bool { !failedJobs.isEmpty }
    var manualEditorRequest: ManualFrameEditorRequest? {
        guard !isBusy, !isLoadingPreview, completedPreviews.indices.contains(selectedPreviewIndex) else { return nil }
        let preview = completedPreviews[selectedPreviewIndex]
        return ManualFrameEditorRequest(
            previewID: preview.id,
            sourceURL: preview.sourceURL,
            selectionLimit: max(1, preview.frameCount),
            duration: preview.duration,
            outputWidth: preview.settings.safeWidth
        )
    }
    var canBrowseCompletedPreviews: Bool { completedPreviews.count > 1 }
    var canShowPreviousPreview: Bool { selectedPreviewIndex > 0 }
    var canShowNextPreview: Bool { selectedPreviewIndex + 1 < completedPreviews.count }
    var selectedPreviewNumber: Int { completedPreviews.isEmpty ? 0 : selectedPreviewIndex + 1 }
    var primaryButtonTitle: String {
        videoJobs.count > 1 ? t("button.generate.batch", videoJobs.count) : t("button.generate.single")
    }

    var previewStatus: String {
        if isPaused { return outputDescription }
        if isPauseRequested { return t("status.pausePending") }
        if isProcessing {
            let totalFrames = activeGridSide * activeGridSide
            let name = activeJobName.isEmpty ? t("default.video") : activeJobName
            return t("status.processing", activeJobIndex + 1, max(1, activeJobCount), name, livePreviewFrameCount, totalFrames)
        }
        if case .batchCompleted = outputStatus {
            return outputDescription
        }
        return previewImage == nil ? t("status.empty") : outputDescription
    }

    var processingLabel: String {
        if isPaused { return t("processing.paused") }
        if isPauseRequested { return t("processing.pausePending") }
        let batchPrefix = activeJobCount > 1 ? "\(activeJobIndex + 1)/\(activeJobCount) · " : ""
        return switch progress {
        case ..<0.58: t("processing.fast", batchPrefix)
        case ..<0.72: t("processing.people", batchPrefix)
        default: t("processing.assembling", batchPrefix)
        }
    }

    func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { addVideos(panel.urls) }
    }

    func addVideos(_ urls: [URL]) {
        guard !isBusy else { return }
        var knownPaths = Set(videoJobs.map { $0.url.standardizedFileURL.path })
        let candidates = urls
            .map(\.standardizedFileURL)
        let supported = candidates.filter(SupportedVideoInput.accepts)
        let additions = supported
            .filter { knownPaths.insert($0.path).inserted }
            .map { VideoJob(url: $0) }
        if !additions.isEmpty { videoJobs.append(contentsOf: additions) }
        if supported.count < candidates.count {
            errorMessage = t("error.unsupportedInput")
            showError = true
        }
    }

    func clearVideos() {
        guard !isBusy else { return }
        cancelVideoImport()
        previewLoadingTask?.cancel()
        previewLoadingTask = nil
        videoJobs.removeAll()
        previewImage = nil
        displayedPreview = nil
        livePreviewSlots.reset(total: 0)
        outputStatus = .empty
        completedBatchCounts = nil
        lastSavedURL = nil
        pendingData = nil
        pendingSource = nil
        pendingFormat = nil
        completedPreviews = []
        previewImageStore = PreviewImageStore()
        previewLoadID = UUID()
        isLoadingPreview = false
        selectedPreviewIndex = 0
    }

    func acceptDrop(providers: [NSItemProvider]) -> Bool {
        guard !isBusy else { return false }
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard let batchID = pendingDrops.register(count: fileProviders.count) else { return false }
        if !isImportingVideos { isImportingVideos = true }
        let timeoutNanoseconds = dropTimeoutNanoseconds
        let timeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: timeoutNanoseconds) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.releaseDropLoading(batchID, cancelLoads: true)
            self.finishVideoDrop(self.pendingDrops.expire(batchID))
        }
        dropLoading[batchID] = DropLoading(timeout: timeout)
        for (index, provider) in fileProviders.enumerated() {
            let progress = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] data, _ in
                let url = DroppedVideoURL.decode(data)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let completion = self.pendingDrops.resolve(url, at: index, batchID: batchID)
                    if !self.pendingDrops.isPending(batchID) { self.releaseDropLoading(batchID, cancelLoads: false) }
                    self.finishVideoDrop(completion)
                }
            }
            dropLoading[batchID]?.progress.append(progress)
        }
        return true
    }

    func cancelVideoImport() {
        pendingDrops.cancelAll()
        let activeLoads = dropLoading.values
        dropLoading.removeAll()
        for loading in activeLoads {
            loading.timeout.cancel()
            loading.progress.forEach { $0.cancel() }
        }
        if isImportingVideos { isImportingVideos = false }
    }

    private func releaseDropLoading(_ id: UUID, cancelLoads: Bool) {
        guard let loading = dropLoading.removeValue(forKey: id) else { return }
        loading.timeout.cancel()
        if cancelLoads { loading.progress.forEach { $0.cancel() } }
    }

    private func finishVideoDrop(_ completion: OrderedVideoDrops.Completion?) {
        let hasPendingDrops = !pendingDrops.isEmpty
        if isImportingVideos != hasPendingDrops { isImportingVideos = hasPendingDrops }
        guard let completion else { return }
        addVideos(completion.urls)
        if completion.failedCount > 0 {
            errorMessage = t("error.videoImport", completion.failedCount)
            showError = true
        }
    }

    func generate() {
        guard !videoJobs.isEmpty, !isBusy, !isImportingVideos else { return }
        startGeneration(indices: Array(videoJobs.indices), resetPreviews: true)
    }

    func retryFailedJobs() {
        guard !isBusy, !isImportingVideos else { return }
        let indices = videoJobs.indices.filter { videoJobs[$0].state.canRetry }
        guard !indices.isEmpty else { return }
        for index in indices { videoJobs[index].state = .queued }
        startGeneration(indices: indices, resetPreviews: false)
    }

    func requestPause() {
        guard isProcessing, !isPauseRequested, !isPaused, let generationControl else { return }
        isPauseRequested = true
        Task { await generationControl.requestPause() }
    }

    func resumeGeneration() {
        guard isProcessing, isPaused, let generationControl else { return }
        isPaused = false
        isPauseRequested = false
        Task { await generationControl.resume() }
    }

    private func startGeneration(indices: [Int], resetPreviews: Bool) {
        guard !indices.isEmpty else { return }
        cancelVideoImport()
        let runID = UUID()
        generationRunID = runID
        isProcessing = true
        isPauseRequested = false
        isPaused = false
        progress = 0
        completedBatchCounts = nil
        // Present the live grid immediately. This replaces a stale completed
        // image or a blank stage before the first AVFoundation decode returns.
        activeGridSide = StoryboardGrid.boundedSide(gridSide)
        activeUsesSourceAspect = layoutAspect == .source
        activeCardAspectRatio = layoutAspect.resolvedCardAspectRatio(sourceAspectRatio: nil)
        livePreviewSlots.reset(total: activeGridSide * activeGridSide)
        lastSavedURL = nil
        pendingData = nil
        pendingSource = nil
        pendingFormat = nil
        showError = false
        errorMessage = ""
        if resetPreviews {
            previewLoadingTask?.cancel()
            previewLoadingTask = nil
            completedPreviews = []
            previewImageStore = PreviewImageStore()
            previewLoadID = UUID()
            isLoadingPreview = false
            selectedPreviewIndex = 0
            previewImage = nil
            displayedPreview = nil
            renderedFormat = nil
        }
        let analyzer = VideoStoryboardAnalyzer()
        let bridge = UIStateBridge(model: self, generationRunID: runID)
        let selectedJobs = indices.compactMap { index -> (index: Int, url: URL)? in
            guard videoJobs.indices.contains(index) else { return nil }
            return (index, videoJobs[index].url)
        }
        guard !selectedJobs.isEmpty else {
            isProcessing = false
            return
        }
        let control = BatchRunControl()
        generationControl = control
        for index in selectedJobs.map(\.index) { videoJobs[index].state = .queued }

        let task = Task.detached(priority: .userInitiated) {
            for (batchIndex, job) in selectedJobs.enumerated() {
                var settings: ExportSettings?
                do {
                    if await control.isPauseRequested() {
                        await bridge.pauseBatch()
                        await control.waitUntilResumed()
                        try Task.checkCancellation()
                        await bridge.resumeBatch()
                    }
                    try Task.checkCancellation()
                    guard let currentSettings = await bridge.currentGenerationSettings() else { return }
                    settings = currentSettings
                    await bridge.beginJob(
                        source: job.url,
                        jobIndex: job.index,
                        batchIndex: batchIndex,
                        total: selectedJobs.count,
                        gridSide: currentSettings.gridSide,
                        layoutAspect: currentSettings.layoutAspect
                    )
                    let result = try await analyzer.analyze(
                        videoURL: job.url,
                        gridSide: currentSettings.gridSide,
                        outputWidth: currentSettings.safeWidth,
                        progress: { value in
                            bridge.report(progress: value)
                        },
                        onPreviewFrame: { frame, frameIndex, totalFrames in
                            await bridge.appendPreview(frame, index: frameIndex, total: totalFrames)
                        }
                    )
                    let data = try StoryboardComposer.render(result: result, settings: currentSettings)
                    let canContinue = await bridge.finishJob(data: data, result: result, settings: currentSettings, index: job.index, total: selectedJobs.count)
                    if !canContinue { break }
                } catch is CancellationError {
                    await bridge.cancelled()
                    return
                } catch {
                    let language: AppLanguage
                    if let settings {
                        language = settings.language
                    } else {
                        language = await bridge.currentLanguage()
                    }
                    let failure = VideoFailure.classify(error, language: language)
                    await bridge.failJob(index: job.index, failure: failure)
                }
            }
            await bridge.finishBatch()
        }
        generationTask = task
    }

    func cancelGeneration() {
        let control = generationControl
        generationRunID = UUID()
        generationTask?.cancel()
        generationTask = nil
        generationControl = nil
        isProcessing = false
        isPauseRequested = false
        isPaused = false
        for index in videoJobs.indices where videoJobs[index].state == .processing {
            videoJobs[index].state = .queued
        }
        livePreviewSlots.reset(total: 0)
        outputStatus = .cancelled
        completedBatchCounts = nil
        Task { await control?.resume() }
    }

    fileprivate func generationSettings() -> ExportSettings {
        ExportSettings(
            gridSide: gridSide,
            layoutAspect: layoutAspect,
            language: language,
            format: format,
            width: width,
            background: background,
            showTimestamps: showTimestamps,
            showTitleWatermark: showTitleWatermark
        )
    }

    func markPausedAtCheckpoint() {
        isPaused = true
        isPauseRequested = false
        livePreviewSlots.reset(total: 0)
        outputStatus = .paused
    }

    fileprivate func markResumedAtCheckpoint() {
        isPaused = false
        isPauseRequested = false
    }

    private var activeUsesSourceAspect = true

    func beginJob(source: URL, jobIndex: Int, batchIndex: Int, total: Int, gridSide: Int, layoutAspect: StoryboardAspect) {
        activeJobIndex = batchIndex
        activeJobCount = total
        activeJobName = source.lastPathComponent
        activeGridSide = StoryboardGrid.boundedSide(gridSide)
        activeUsesSourceAspect = layoutAspect == .source
        activeCardAspectRatio = layoutAspect.resolvedCardAspectRatio(sourceAspectRatio: nil)
        livePreviewSlots.reset(total: activeGridSide * activeGridSide)
        progress = 0
        if videoJobs.indices.contains(jobIndex) { videoJobs[jobIndex].state = .processing }
        outputStatus = .processing(source.lastPathComponent)
    }

    func appendPreview(_ image: CGImage, aspectRatio: Double, index: Int, total: Int) {
        guard total > 0, total <= 64 else { return }
        if activeUsesSourceAspect {
            activeCardAspectRatio = StoryboardAspect.source.resolvedCardAspectRatio(sourceAspectRatio: aspectRatio)
        }
        var slots = livePreviewSlots
        guard slots.replace(LivePreviewFrame(image: NSImage(cgImage: image, size: .zero)), at: index, total: total) else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            livePreviewSlots = slots
        }
    }

    @discardableResult
    func completeJob(data: Data, result: StoryboardResult, settings: ExportSettings, index: Int, total: Int, runID: UUID? = nil) async -> Bool {
        let output: PreparedStoryboardOutput
        do {
            output = try await StoryboardOutputWriter.shared.prepare(
                data: data, result: result, settings: settings,
                jobIndex: index, jobCount: total, previewStore: previewImageStore
            )
        } catch is CancellationError {
            return false
        } catch {
            guard acceptsGenerationUpdate(for: runID) else { return false }
            markJobFailed(index: index, failure: VideoFailure.classify(error, language: settings.language))
            return true
        }
        guard acceptsGenerationUpdate(for: runID) else { return false }
        let preview = output.preview
        if videoJobs.indices.contains(index) {
            if let savedURL = preview.savedURL {
                videoJobs[index].state = .completed(savedURL.lastPathComponent)
            } else {
                videoJobs[index].state = .failed(.retryable(output.saveFailure ?? t("error.noExportData")))
            }
        }
        completedPreviews.append(preview)
        selectPreview(at: completedPreviews.count - 1, presentation: output.presentation)
        if preview.savedURL == nil {
            outputStatus = .generatedNotSaved(index: index + 1, total: total)
        }
        // If neither destination nor session cache can be written, keep this
        // one result in memory and stop before accumulating an unbounded batch.
        if preview.fallbackData != nil {
            errorMessage = t("error.previewStorage")
            showError = true
            return false
        }
        return true
    }

    func markJobFailed(index: Int, message: String) {
        markJobFailed(index: index, failure: .retryable(message))
    }

    func markJobFailed(index: Int, failure: VideoFailure) {
        if videoJobs.indices.contains(index) { videoJobs[index].state = .failed(failure) }
        outputStatus = .failedContinue(index: index + 1)
    }

    func showSourceFiles(for jobs: [VideoJob]) {
        guard !jobs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(jobs.map(\.url))
    }

    func finishBatch() {
        isProcessing = false
        // The completed, display-sized storyboard has replaced the live grid.
        // Release its individual decoded cards instead of keeping a second
        // full set of media alive for the rest of the app session.
        livePreviewSlots.reset(total: 0)
        generationTask = nil
        generationControl = nil
        isPauseRequested = false
        isPaused = false
        progress = 1
        let completed = videoJobs.filter {
            if case .completed = $0.state { return true }
            return false
        }.count
        let failed = videoJobs.filter {
            if case .failed = $0.state { return true }
            return false
        }.count
        completedBatchCounts = (completed, failed)
        outputStatus = .batchCompleted
    }

    func markCancelled() {
        isProcessing = false
        generationTask = nil
        generationControl = nil
        isPauseRequested = false
        isPaused = false
        livePreviewSlots.reset(total: 0)
        outputStatus = .cancelled
    }

    func exportCurrentResult() {
        guard let pendingData, let pendingSource, let pendingFormat else { return }
        save(data: pendingData, source: pendingSource, format: pendingFormat)
    }

    func save(data: Data, source: URL, format: ExportFormat) {
        let targetPreviewID = completedPreviews.indices.contains(selectedPreviewIndex)
            ? completedPreviews[selectedPreviewIndex].id : nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .png ? .png : .jpeg]
        panel.directoryURL = source.deletingLastPathComponent()
        panel.nameFieldStringValue = ExportDestination.nextURL(for: source, format: format).lastPathComponent
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            Task { @MainActor in
                do {
                    try await StoryboardOutputWriter.shared.save(data, to: destination)
                    self.completeManualSave(to: destination, targetPreviewID: targetPreviewID)
                } catch {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }

    /// The save panel can remain open while another result is selected. Update
    /// the saved record by ID and release only that result's encoded buffers.
    func completeManualSave(to destination: URL, targetPreviewID: UUID?) {
        guard let index = completedPreviews.firstIndex(where: { $0.id == targetPreviewID }) else { return }
        let saved = completedPreviews[index].saved(at: destination)
        completedPreviews[index] = saved
        if let displayed = displayedPreview, displayed.id == saved.id {
            displayedPreview = (saved.id, PreparedPreviewPresentation(image: displayed.presentation.image, pendingData: nil))
        }
        if videoJobs.indices.contains(saved.jobIndex) {
            videoJobs[saved.jobIndex].state = .completed(destination.lastPathComponent)
        }
        guard index == selectedPreviewIndex else { return }
        pendingData = nil
        lastSavedURL = destination
        if isLoadingPreview {
            // A load started before Save completed holds an unsaved snapshot.
            // Replace it so its late result cannot restore pending export data.
            selectPreview(at: index)
        }
        outputStatus = .manualSaved(destination.lastPathComponent)
    }

    func revealLastSavedResult() {
        guard let lastSavedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastSavedURL])
    }

    func showPreviousPreview() {
        selectPreview(at: selectedPreviewIndex - 1)
    }

    func showNextPreview() {
        selectPreview(at: selectedPreviewIndex + 1)
    }

    func applyManuallySelectedFrames(
        _ frames: [CapturedFrame],
        targetPreviewID: RenderedStoryboardPreview.ID,
        sourceURL: URL,
        duration: Double
    ) {
        guard !frames.isEmpty, !isBusy,
              let target = completedPreviews.first(where: { $0.id == targetPreviewID }),
              frames.count == target.frameCount else { return }
        let updatedResult = StoryboardResult(
            frames: frames,
            sourceURL: sourceURL,
            duration: duration
        )
        let settings = ExportSettings(
            gridSide: target.settings.gridSide,
            layoutAspect: target.settings.layoutAspect,
            language: language,
            format: target.settings.format,
            width: target.settings.width,
            background: target.settings.background,
            showTimestamps: target.settings.showTimestamps,
            showTitleWatermark: target.settings.showTitleWatermark
        )
        let settingsLanguage = settings.language
        isApplyingFrameAdjustments = true
        let bridge = UIStateBridge(model: self)

        frameAdjustmentTask = Task.detached(priority: .userInitiated) {
            do {
                let data = try StoryboardComposer.render(result: updatedResult, settings: settings)
                await bridge.finishEditedFrames(
                    data: data,
                    result: updatedResult,
                    settings: settings,
                    targetPreviewID: targetPreviewID
                )
            } catch {
                await bridge.failEditedFrames(
                    message: (error as? StoryboardError)?.message(in: settingsLanguage) ?? error.localizedDescription
                )
            }
        }
    }

    fileprivate func completeEditedFrames(
        data: Data,
        result: StoryboardResult,
        settings: ExportSettings,
        targetPreviewID: RenderedStoryboardPreview.ID
    ) async {
        defer {
            isApplyingFrameAdjustments = false
            frameAdjustmentTask = nil
        }
        guard let targetIndex = completedPreviews.firstIndex(where: { $0.id == targetPreviewID }) else {
            return
        }
        let existing = completedPreviews[targetIndex]
        let output: PreparedStoryboardOutput
        do {
            output = try await StoryboardOutputWriter.shared.prepare(
                data: data, result: result, settings: settings,
                jobIndex: existing.jobIndex, jobCount: existing.jobCount,
                id: existing.id, previewStore: previewImageStore
            )
        } catch {
            markFrameEditFailed((error as? StoryboardError)?.message(in: settings.language) ?? error.localizedDescription)
            return
        }
        let updated = output.preview
        completedPreviews[targetIndex] = updated
        if videoJobs.indices.contains(existing.jobIndex) {
            if let savedURL = updated.savedURL {
                videoJobs[existing.jobIndex].state = .completed(savedURL.lastPathComponent)
            } else {
                videoJobs[existing.jobIndex].state = .failed(.retryable(output.saveFailure ?? t("error.noExportData")))
            }
        }
        if selectedPreviewIndex == targetIndex {
            selectPreview(at: targetIndex, presentation: output.presentation)
            if let savedURL = updated.savedURL {
                outputStatus = .manualSaved(savedURL.lastPathComponent)
            } else {
                outputStatus = .generatedNotSaved(index: 1, total: 1)
            }
        }
    }

    fileprivate func markFrameEditFailed(_ message: String) {
        frameAdjustmentTask = nil
        isApplyingFrameAdjustments = false
        errorMessage = message
        showError = true
    }

    private func selectPreview(at index: Int, presentation: PreparedPreviewPresentation? = nil) {
        guard completedPreviews.indices.contains(index) else { return }
        previewLoadingTask?.cancel()
        previewLoadingTask = nil
        let preview = completedPreviews[index]
        selectedPreviewIndex = index
        let loadID = UUID()
        previewLoadID = loadID
        pendingData = nil
        pendingSource = preview.sourceURL
        pendingFormat = preview.format
        renderedFormat = preview.format
        lastSavedURL = preview.savedURL
        if let savedURL = preview.savedURL {
            outputStatus = .saved(index: preview.jobIndex + 1, total: preview.jobCount, filename: savedURL.lastPathComponent)
        } else {
            outputStatus = .generatedNotSaved(index: preview.jobIndex + 1, total: preview.jobCount)
        }
        if let presentation {
            applyPreviewPresentation(presentation, previewID: preview.id)
            return
        }
        isLoadingPreview = true
        let previewLoader = previewLoader
        previewLoadingTask = Task { @MainActor [weak self] in
            do {
                let loading = Task.detached(priority: .userInitiated) {
                    try previewLoader(preview)
                }
                let presentation = try await loading.valuePropagatingCancellation()
                guard !Task.isCancelled, let self, self.previewLoadID == loadID else { return }
                self.applyPreviewPresentation(presentation, previewID: preview.id)
            } catch {
                guard !Task.isCancelled, let self, self.previewLoadID == loadID else { return }
                self.isLoadingPreview = false
                self.previewLoadingTask = nil
                self.restoreDisplayedPreview()
                self.errorMessage = error.localizedDescription
                self.showError = true
            }
        }
    }

    private func applyPreviewPresentation(_ presentation: PreparedPreviewPresentation, previewID: UUID) {
        previewImage = NSImage(cgImage: presentation.image, size: .zero)
        displayedPreview = (previewID, presentation)
        pendingData = presentation.pendingData
        isLoadingPreview = false
        previewLoadingTask = nil
    }

    /// A deleted export or disconnected drive must not leave an earlier image
    /// labelled with the failed result's filename or attached to its editor.
    /// Resolve by stable ID because history can gain results while I/O waits.
    private func restoreDisplayedPreview() {
        guard let displayed = displayedPreview,
              let index = completedPreviews.firstIndex(where: { $0.id == displayed.id }) else { return }
        let preview = completedPreviews[index]
        selectedPreviewIndex = index
        pendingData = preview.savedURL == nil ? displayed.presentation.pendingData : nil
        pendingSource = preview.sourceURL
        pendingFormat = preview.format
        renderedFormat = preview.format
        lastSavedURL = preview.savedURL
        if let savedURL = preview.savedURL {
            outputStatus = .saved(index: preview.jobIndex + 1, total: preview.jobCount, filename: savedURL.lastPathComponent)
        } else {
            outputStatus = .generatedNotSaved(index: preview.jobIndex + 1, total: preview.jobCount)
        }
    }

    fileprivate func acceptsGenerationUpdate(for runID: UUID?) -> Bool {
        runID == nil || runID == generationRunID
    }
}

private final class UIStateBridge: @unchecked Sendable {
    weak var model: StoryboardViewModel?
    private let generationRunID: UUID?

    init(model: StoryboardViewModel, generationRunID: UUID? = nil) {
        self.model = model
        self.generationRunID = generationRunID
    }

    @MainActor
    private func acceptsCurrentGeneration(_ model: StoryboardViewModel) -> Bool {
        model.acceptsGenerationUpdate(for: generationRunID)
    }

    func report(progress: Double) {
        Task { @MainActor [weak self] in
            guard let self, let model = self.model, self.acceptsCurrentGeneration(model) else { return }
            model.progress = progress
        }
    }

    func beginJob(
        source: URL,
        jobIndex: Int,
        batchIndex: Int,
        total: Int,
        gridSide: Int,
        layoutAspect: StoryboardAspect
    ) async {
        await MainActor.run { [weak self] in
            guard let self, let model = self.model, self.acceptsCurrentGeneration(model) else { return }
            model.beginJob(
                source: source,
                jobIndex: jobIndex,
                batchIndex: batchIndex,
                total: total,
                gridSide: gridSide,
                layoutAspect: layoutAspect
            )
        }
    }

    func appendPreview(_ frame: CapturedFrame, index: Int, total: Int) async {
        guard !Task.isCancelled else { return }
        let gridSide = max(1, Int(Double(max(1, total)).squareRoot().rounded(.up)))
        let request = FrameThumbnailRequest(data: frame.jpegData, maximumPixelSize: max(160, 1_280 / gridSide))
        guard let image = try? await FrameThumbnailDecoder.shared.decode(request), !Task.isCancelled else { return }
        await MainActor.run { [weak self] in
            guard let self, let model = self.model, self.acceptsCurrentGeneration(model) else { return }
            model.appendPreview(image, aspectRatio: frame.aspectRatio, index: index, total: total)
        }
    }

    @MainActor
    func finishJob(data: Data, result: StoryboardResult, settings: ExportSettings, index: Int, total: Int) async -> Bool {
        guard let model, acceptsCurrentGeneration(model) else { return false }
        return await model.completeJob(data: data, result: result, settings: settings, index: index, total: total, runID: generationRunID)
    }

    func failJob(index: Int, failure: VideoFailure) async {
        await MainActor.run { [weak self] in
            guard let self, let model = self.model, self.acceptsCurrentGeneration(model) else { return }
            model.markJobFailed(index: index, failure: failure)
        }
    }

    func currentGenerationSettings() async -> ExportSettings? {
        await MainActor.run { [weak self] in
            guard let self, let model = self.model, self.acceptsCurrentGeneration(model) else { return nil }
            return model.generationSettings()
        }
    }

    func currentLanguage() async -> AppLanguage {
        await MainActor.run { [weak self] in
            self?.model?.language ?? .english
        }
    }

    func pauseBatch() async {
        await MainActor.run { [weak self] in
            guard let self, let model = self.model, self.acceptsCurrentGeneration(model) else { return }
            model.markPausedAtCheckpoint()
        }
    }

    func resumeBatch() async {
        await MainActor.run { [weak self] in
            guard let self, let model = self.model, self.acceptsCurrentGeneration(model) else { return }
            model.markResumedAtCheckpoint()
        }
    }

    func finishBatch() async {
        await MainActor.run { [weak self] in
            guard let self, let model = self.model, self.acceptsCurrentGeneration(model) else { return }
            model.finishBatch()
        }
    }

    func cancelled() async {
        await MainActor.run { [weak self] in
            guard let self, let model = self.model, self.acceptsCurrentGeneration(model) else { return }
            model.markCancelled()
        }
    }

    @MainActor
    func finishEditedFrames(
        data: Data,
        result: StoryboardResult,
        settings: ExportSettings,
        targetPreviewID: RenderedStoryboardPreview.ID
    ) async {
        await model?.completeEditedFrames(
                data: data,
                result: result,
                settings: settings,
                targetPreviewID: targetPreviewID
            )
    }

    func failEditedFrames(message: String) async {
        await MainActor.run { [weak self] in
            self?.model?.markFrameEditFailed(message)
        }
    }
}
