import AppKit
@preconcurrency import AVFoundation
import SwiftUI

/// A hosted editor window does not automatically receive the parent SwiftUI
/// environment after it has been created. Keep the dynamic preferences in an
/// observable value so an open editor updates without rebuilding the view and
/// losing a person's in-progress selection.
@MainActor
final class ManualFrameEditorConfiguration: ObservableObject {
    @Published var colorScheme: ColorScheme
    @Published var language: AppLanguage

    init(colorScheme: ColorScheme, language: AppLanguage) {
        self.colorScheme = colorScheme
        self.language = language
    }
}

struct ManualFrameEditor: View {
    private struct CandidateReveal: Equatable {
        let frameID: Int
        let token = UUID()
    }
    @Environment(\.displayScale) private var displayScale
    @ObservedObject var model: StoryboardViewModel
    let sourceURL: URL
    let duration: Double
    @ObservedObject var configuration: ManualFrameEditorConfiguration
    let onClose: () -> Void
    let onApply: ([CapturedFrame], ExportSettings) -> Void
    @State private var sampledCandidates: [CapturedFrame] = []
    @State private var manuallyAddedCandidates: [CapturedFrame] = []
    @State private var candidateReveal: CandidateReveal?
    @State private var selectedIDs = Set<Int>()
    @State private var candidateBatch = 0
    @State private var isLoadingCandidates = false
    @State private var isSmartSelecting = false
    @State private var captureToken = UUID()
    @State private var captureError = ""
    @State private var candidateSamplingTask: Task<[CapturedFrame], Error>?
    @State private var candidatePresentationTask: Task<Void, Never>?
    @State private var smartSelectionTask: Task<[Int], Never>?
    @State private var smartSelectionPresentationTask: Task<Void, Never>?
    @State private var timeline = ManualEditorTimeline()
    @State private var previewFrame: CapturedFrame?
    @State private var isLoadingPreviewFrame = false
    @State private var isRefiningCurrentFrame = false
    @State private var isRefiningSelectedFrames = false
    @State private var previewCaptureTask: Task<Void, Never>?
    @State private var currentFrameRefinementTask: Task<Void, Never>?
    @State private var frameRateTask: Task<Void, Never>?
    @State private var selectedFrameRefinementTask: Task<[CapturedFrame], Error>?
    @State private var applyPresentationTask: Task<Void, Never>?
    @State private var selectedFrameRefinementToken: UUID?
    @State private var operationError = ""
    @StateObject private var playback = ManualVideoPlayback()
    @State private var isScrubbingPreview = false
    @State private var nextManualFrameID = 1_000_000
    @State private var previewFrameStep = 1.0 / 30.0

    private func t(_ key: String, _ arguments: CVarArg...) -> String {
        language.text(key, arguments: arguments)
    }

    private var language: AppLanguage { configuration.language }
    private var selectionLimit: Int { model.currentExportSettings.frameCount }
    private var outputWidth: Int { model.currentExportSettings.safeWidth }

    private var selectedFrames: [CapturedFrame] {
        candidates
            .filter { selectedIDs.contains($0.id) }
    }

    private var candidates: [CapturedFrame] {
        (sampledCandidates + manuallyAddedCandidates).sorted {
            $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time
        }
    }

    private var safeDuration: Double { max(0.01, duration) }
    private var isApplyingSelection: Bool { isRefiningSelectedFrames || model.isApplyingFrameAdjustments }

    private var palette: StudioPalette { StudioPalette(isLight: configuration.colorScheme == .light) }
    private var editorCanvas: Color { palette.canvas }
    private var editorControlSurface: Color { palette.control }
    private var editorDivider: Color { palette.divider }
    private var mediaWell: Color { palette.canvas }
    private var currentFrameAccent: Color { palette.accent }
    private var controlBorder: Color { palette.divider }
    private var controlText: Color { Color.primary }
    private var hairline: CGFloat { 1 / max(1, displayScale) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                manualVideoPreview(height: ManualEditorLayout.mediaHeight(availableHeight: geometry.size.height))
                candidateBrowser
            }
        }
        .background(palette.window)
        .frame(
            minWidth: 1_000,
            idealWidth: 1_280,
            maxWidth: .infinity,
            minHeight: 680,
            idealHeight: 800,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .accessibilityIdentifier("manual-frame-editor")
        .environment(\.locale, language.locale)
        .environment(\.layoutDirection, .leftToRight)
        // The observable configuration keeps this independent AppKit window in
        // sync with the parent workspace even while it remains open.
        .environment(\.colorScheme, configuration.colorScheme)
        .preferredColorScheme(configuration.colorScheme)
        .onAppear {
            loadCandidates()
            prepareVideoPreview()
        }
        .onDisappear(perform: cancelBackgroundWork)
        .onChange(of: model.gridSide) { _ in
            updateCandidateCapacityForCurrentGrid()
        }
        .onChange(of: playback.currentTime) { time in
            guard playback.isPlaying, !isScrubbingPreview else { return }
            timeline.seek(to: time, duration: safeDuration)
        }
        .onChange(of: playback.endCount) { _ in
            timeline.seek(to: playback.currentTime, duration: safeDuration)
            requestPreviewFrame(at: timeline.time)
        }
        .alert(t("alert.generation.title"), isPresented: Binding(
            get: { !operationError.isEmpty },
            set: { if !$0 { operationError = "" } }
        )) {
            Button(t("button.ok"), role: .cancel) { operationError = "" }
        } message: {
            Text(operationError)
        }
    }

    private var toolbarMetrics: ManualEditorLayout.ToolbarMetrics {
        ManualEditorLayout.toolbarMetrics(language: language, selectionLimit: max(selectionLimit, selectedIDs.count))
    }

    private func selectionCount(width: CGFloat) -> some View {
        Text("\(selectedIDs.count) / \(selectionLimit)")
            .font(.system(size: ManualEditorLayout.selectionCountFontSize, weight: .bold, design: .rounded))
            .foregroundStyle(palette.accent)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: width, height: ManualEditorLayout.toolbarHeight)
            .accessibilityLabel(t("editor.selectionCount", selectedIDs.count, selectionLimit))
            .accessibilityIdentifier("manual-frame-selection-count")
            .help(t("editor.selectionCount", selectedIDs.count, selectionLimit))
    }

    private var smartSelectionButton: some View {
        Button(action: smartSelectCandidates) {
            Group {
                if isSmartSelecting {
                    ProgressView().controlSize(.small)
                } else {
                    Text(t("editor.smartSelect.short"))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(width: toolbarMetrics.smartSelectionWidth, height: ManualEditorLayout.compactControlHeight)
        }
        .buttonStyle(ManualFrameEditorActionButtonStyle(role: .secondary))
        .disabled(isLoadingCandidates || candidates.isEmpty || isSmartSelecting || isApplyingSelection || selectedIDs.count >= selectionLimit)
        .help(t("editor.smartFill"))
        .accessibilityLabel(t("editor.smartSelect"))
        .accessibilityHint(t("editor.smartFill"))
        .accessibilityIdentifier("manual-frame-smart-select")
    }

    private var newCandidatesButton: some View {
        Button(action: regenerateCandidates) {
            Text(t("editor.regenerate.short"))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: toolbarMetrics.newCandidatesWidth, height: ManualEditorLayout.compactControlHeight)
        }
        .buttonStyle(ManualFrameEditorActionButtonStyle(role: .secondary))
        .disabled(isLoadingCandidates || isSmartSelecting || isApplyingSelection)
        .help(t("editor.regenerate"))
        .accessibilityLabel(t("editor.regenerate"))
        .accessibilityIdentifier("manual-frame-regenerate")
    }

    private var candidateBrowser: some View {
        let orderedCandidates = candidates
        let manualIDs = Set(manuallyAddedCandidates.map(\.id))
        let selectedPositions = Dictionary(uniqueKeysWithValues: orderedCandidates
            .filter { selectedIDs.contains($0.id) }
            .enumerated().map { ($0.element.id, $0.offset + 1) })
        return GeometryReader { proxy in
            let sourceAspect = orderedCandidates.first?.aspectRatio ?? (16.0 / 9.0)
            let columnCount = ManualEditorLayout.candidateColumnCount(
                availableWidth: proxy.size.width, sourceAspectRatio: sourceAspect
            )
            let tileWidth = ManualEditorLayout.candidateTileWidth(
                availableWidth: proxy.size.width, columns: columnCount
            )
            ScrollViewReader { scroller in
                ScrollView {
                    if isLoadingCandidates {
                        ProgressView(t("editor.loading"))
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else if orderedCandidates.isEmpty {
                        VStack(spacing: 8) {
                            ProjectIcon(symbol: .film, size: 28)
                                .foregroundStyle(.secondary)
                            Text(captureError.isEmpty ? t("editor.noPreview") : captureError)
                                .font(.system(size: 12))
                                .foregroundStyle(captureError.isEmpty ? Color.secondary : Color.red)
                        }
                        .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: ManualEditorLayout.candidateGap), count: columnCount),
                            spacing: ManualEditorLayout.candidateGap
                        ) {
                            ForEach(orderedCandidates) { candidate in
                                candidateTile(candidate, selectionNumber: selectedPositions[candidate.id], displayWidth: tileWidth, isManual: manualIDs.contains(candidate.id))
                                    .id(candidate.id)
                            }
                        }
                        .padding(.horizontal, ManualEditorLayout.horizontalInset)
                        .padding(.top, ManualEditorLayout.candidateGridTop)
                        .padding(.bottom, ManualEditorLayout.candidateGridBottom)
                    }
                }
                .onChange(of: candidateReveal) { reveal in
                    guard let reveal else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        scroller.scrollTo(reveal.frameID, anchor: .center)
                    }
                }
            }
        }
        .frame(minHeight: 220, maxHeight: .infinity)
        .layoutPriority(1)
        .background(editorCanvas)
        .overlay(alignment: .top) { Rectangle().fill(editorDivider).frame(height: hairline) }
        .accessibilityIdentifier("manual-frame-candidates")
    }

    private func candidateTile(_ candidate: CapturedFrame, selectionNumber: Int?, displayWidth: CGFloat, isManual: Bool) -> some View {
        let isSelected = selectedIDs.contains(candidate.id)
        // The badge is the final storyboard position, so a newly selected
        // earlier frame immediately renumbers every later selected frame.
        return Button {
            toggle(candidate)
        } label: {
            frameImage(candidate, displayWidth: displayWidth)
                .aspectRatio(candidate.aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottomLeading) {
                    Text(TimestampFormatter.string(for: candidate.time))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(6)
                }
                .overlay(alignment: .topLeading) {
                    ManualFrameSelectionBadge(isSelected: isSelected, number: selectionNumber)
                }
                .overlay(alignment: .topTrailing) {
                    if isManual {
                        Text(t("editor.manuallyAdded.short"))
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .foregroundStyle(configuration.colorScheme == .light
                                ? Color(red: 0.43, green: 0.27, blue: 0.03)
                                : Color(red: 1, green: 0.85, blue: 0.58))
                            .background(configuration.colorScheme == .light
                                ? Color(red: 1, green: 0.94, blue: 0.78)
                                : Color(red: 0.25, green: 0.19, blue: 0.10),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.5), lineWidth: hairline)
                            }
                            .padding(8)
                            .accessibilityHidden(true)
                    }
                }
                .overlay {
                    ManualFrameSelectionOutline(isSelected: isSelected, idleColor: controlBorder)
                }
        }
        .buttonStyle(.plain)
        .disabled(isSmartSelecting || isApplyingSelection || (!isSelected && selectedIDs.count >= selectionLimit))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(t(isManual ? "editor.manuallyAdded" : "editor.candidates")) · \(TimestampFormatter.string(for: candidate.time))")
        .accessibilityValue(
            isSelected
                ? "\(t("accessibility.selected")) \(selectionNumber ?? 0) / \(selectionLimit)"
                : "0 / \(selectionLimit)"
        )
    }

    private var cancelButton: some View {
        Button(role: .cancel, action: onClose) {
            Text(t("editor.cancel"))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: toolbarMetrics.cancelWidth, height: ManualEditorLayout.compactControlHeight)
        }
        .buttonStyle(ManualFrameEditorActionButtonStyle(role: .secondary))
        .keyboardShortcut(.escape, modifiers: [])
        .accessibilityIdentifier("manual-frame-cancel")
    }

    private var applyButton: some View {
        Button(action: applySelectedFrames) {
            Group {
                if isRefiningSelectedFrames {
                    ProgressView().controlSize(.small)
                } else {
                    Text(t("editor.apply.short"))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(width: toolbarMetrics.applyWidth, height: ManualEditorLayout.compactControlHeight)
        }
        .buttonStyle(ManualFrameEditorActionButtonStyle(role: .primary))
        .disabled(selectedIDs.count != selectionLimit || isLoadingCandidates || isSmartSelecting || isApplyingSelection)
        .keyboardShortcut(.return, modifiers: [.command])
        .help(t("editor.apply"))
        .accessibilityLabel(t("editor.apply"))
        .accessibilityIdentifier("manual-frame-apply")
    }

    private func frameImage(_ frame: CapturedFrame, displayWidth: CGFloat) -> some View {
        let aspect = StoryboardAspect.source.resolvedCardAspectRatio(sourceAspectRatio: frame.aspectRatio)
        let pixelSize = FrameThumbnailSizing.maximumPixelSize(
            for: CGSize(width: displayWidth, height: displayWidth / aspect),
            aspectRatio: aspect, scale: displayScale, fills: false
        )
        return FrameThumbnailImage(frame: frame, maximumPixelSize: pixelSize)
            .background(.black.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func manualVideoPreview(height: CGFloat) -> some View {
        GeometryReader { proxy in
            let aspect = previewFrame?.aspectRatio ?? candidates.first?.aspectRatio ?? (16.0 / 9)
            let desiredMonitorWidth = height * CGFloat(aspect)
            let availableMonitorWidth = proxy.size.width - ManualEditorLayout.workspaceGap - 544
            let monitorWidth = min(548, max(220, min(desiredMonitorWidth, availableMonitorWidth)))
            let controlsWidth = proxy.size.width - ManualEditorLayout.workspaceGap - monitorWidth
            HStack(alignment: .top, spacing: ManualEditorLayout.workspaceGap) {
                previewMonitor
                    .frame(width: monitorWidth, height: height)
                timelineControlDeck(mediaHeight: height, controlsWidth: controlsWidth)
                    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            }
        }
        .padding(.horizontal, ManualEditorLayout.horizontalInset)
        .padding(.vertical, ManualEditorLayout.workspaceVerticalInset)
        .frame(height: ManualEditorLayout.workspaceHeight(mediaHeight: height))
        .background(palette.panel)
    }

    private var previewMonitor: some View {
        ZStack {
            ManualVideoPlayerView(player: playback.player, fillColor: NSColor(mediaWell))
            if let previewFrame, !isScrubbingPreview, !playback.isPlaying {
                FrameThumbnailImage(frame: previewFrame, maximumPixelSize: 1_100)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(mediaWell)
            } else if isLoadingPreviewFrame {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(mediaWell)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(editorDivider, lineWidth: hairline)
        }
    }

    private func timelineControlDeck(mediaHeight: CGFloat, controlsWidth: CGFloat) -> some View {
        let metrics = toolbarMetrics
        let availableWidth = controlsWidth - ManualEditorLayout.controlDeckInset * 2
        let toolbarHeight = metrics.height(availableWidth: availableWidth)
        let hasSelections = !selectedIDs.isEmpty
        let stripHeight = ManualEditorLayout.timelineFilmstripHeight(
            mediaHeight: mediaHeight, toolbarHeight: toolbarHeight,
            hasSelections: hasSelections, hairline: hairline
        )
        return VStack(alignment: .leading, spacing: 0) {
            editorToolbar(metrics: metrics, availableWidth: availableWidth)
                .frame(height: toolbarHeight)
                .padding(.bottom, ManualEditorLayout.toolbarTimelineGap)

            if hasSelections {
                timelineSelectionMarkers
            }
            timelineFilmstrip(height: stripHeight)
            timelineNavigation.padding(.top, ManualEditorLayout.filmstripScrubberGap)

            Rectangle().fill(editorDivider).frame(height: hairline)
            editorCommands.padding(.top, ManualEditorLayout.commandsTopGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(ManualEditorLayout.controlDeckInset)
        .background(editorControlSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(editorDivider, lineWidth: hairline)
        }
    }

    @ViewBuilder
    private func editorToolbar(metrics: ManualEditorLayout.ToolbarMetrics, availableWidth: CGFloat) -> some View {
        if metrics.stacksCommitButtons(availableWidth: availableWidth) {
            VStack(alignment: .leading, spacing: ManualEditorLayout.toolbarGap) {
                editorWorkingControls(countWidth: metrics.countWidth)
                    .frame(maxWidth: .infinity, alignment: .leading)
                editorCommitControls
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            HStack(spacing: ManualEditorLayout.toolbarGap) {
                editorWorkingControls(countWidth: metrics.countWidth)
                Spacer(minLength: ManualEditorLayout.toolbarCommitGap)
                editorCommitControls
            }
        }
    }

    private func editorWorkingControls(countWidth: CGFloat) -> some View {
        HStack(spacing: ManualEditorLayout.toolbarGap) {
            Button(action: toggleVideoPlayback) {
                ProjectIcon(symbol: playback.isPlaying ? .pause : .play, size: 15)
                    .foregroundStyle(palette.accent)
                    .frame(width: ManualEditorLayout.playbackButtonWidth, height: ManualEditorLayout.compactControlHeight)
                    .background(palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(t(playback.isPlaying ? "editor.pausePreview" : "editor.playPreview"))
            .accessibilityLabel(t(playback.isPlaying ? "editor.pausePreview" : "editor.playPreview"))
            .accessibilityIdentifier("manual-frame-playback")
            selectionCount(width: countWidth)
            smartSelectionButton
            newCandidatesButton
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: ManualEditorLayout.toolbarHeight)
    }

    private var editorCommitControls: some View {
        HStack(spacing: ManualEditorLayout.toolbarGap) {
            cancelButton
            applyButton
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: ManualEditorLayout.compactControlHeight)
    }

    private var editorCommands: some View {
        frameStepControls
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: ManualEditorLayout.compactControlHeight)
    }

    private var timelineNavigation: some View {
        VStack(spacing: 0) {
            timelineScrubber
            timelineRuler.padding(.top, ManualEditorLayout.rulerTopGap)
            HStack {
                Text(TimestampFormatter.string(for: 0))
                Spacer()
                Text(TimestampFormatter.string(for: safeDuration))
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(height: ManualEditorLayout.endpointHeight)
            .padding(.top, ManualEditorLayout.endpointTopGap)
        }
        .padding(.bottom, ManualEditorLayout.navigationBottomInset)
        .frame(height: ManualEditorLayout.navigationHeight)
        .overlay(alignment: .topLeading) {
            floatingAddFrameControl
        }
    }

    private var frameStepControls: some View {
        HStack(spacing: 3) {
            frameNudgeButton(frames: -5, label: t("editor.backFiveFrames"))
            frameNudgeButton(frames: -1, label: t("editor.backOneFrame"))
            TextField("00:00:00.000", text: $timeline.editableText)
                .textFieldStyle(ManualFrameEditorTextFieldStyle())
                .frame(width: ManualEditorLayout.timeFieldWidth(duration: safeDuration))
                .onChange(of: timeline.editableText, perform: updateTimelineFromCompleteTimeText)
                .onSubmit(applyEditablePreviewTime)
                .accessibilityIdentifier("manual-frame-time-field")
                .accessibilityLabel(t("editor.timeField"))
            frameNudgeButton(frames: 1, label: t("editor.forwardOneFrame"))
            frameNudgeButton(frames: 5, label: t("editor.forwardFiveFrames"))
        }
    }

    private var addCurrentFrameButton: some View {
        Button(action: addCurrentFrame) {
            Text(t("editor.addCurrentFrame.short"))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(height: ManualEditorLayout.floatingAddHeight)
                .padding(.horizontal, 12)
        }
        .buttonStyle(ManualFrameEditorActionButtonStyle(role: .toolbarPrimary))
        .disabled((!playback.isPlaying && (previewFrame == nil || isLoadingPreviewFrame)) || isRefiningCurrentFrame || isApplyingSelection)
        .help(t("editor.addCurrentFrame"))
        .accessibilityLabel(t("editor.addCurrentFrame"))
        .accessibilityIdentifier("manual-frame-add-current")
        .background(editorControlSurface, in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(configuration.colorScheme == .light ? 0.10 : 0.25), radius: 4, y: 2)
    }

    private var floatingAddFrameControl: some View {
        let start = TimestampFormatter.string(for: 0)
        let end = TimestampFormatter.string(for: safeDuration)
        let timeFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        let endpointWidth = ceil(max(
            (start as NSString).size(withAttributes: [.font: timeFont]).width,
            (end as NSString).size(withAttributes: [.font: timeFont]).width
        )) + 8
        let title = t("editor.addCurrentFrame.short")
        let buttonWidth = ceil((title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
        ]).width) + 24
        return GeometryReader { proxy in
            let origin = ManualTimelineGeometry.insertionOrigin(
                time: timeline.time, duration: safeDuration, width: proxy.size.width,
                buttonWidth: buttonWidth, endpointWidth: endpointWidth
            )
            addCurrentFrameButton
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: origin, y: ManualEditorLayout.floatingAddTop)
        }
    }

    private var timelineSelectionMarkers: some View {
        let selections = selectedFrames.enumerated().map {
            ManualTimelineSelection(id: $0.element.id, number: $0.offset + 1, time: $0.element.time)
        }
        return GeometryReader { proxy in
            let groups = ManualTimelineGeometry.groups(for: selections, duration: safeDuration, width: proxy.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(groups) { group in
                    Path { path in
                        for selection in group.selections {
                            path.move(to: CGPoint(x: group.center, y: 17))
                            path.addLine(to: CGPoint(
                                x: ManualTimelineGeometry.center(time: selection.time, duration: safeDuration, width: proxy.size.width),
                                y: 24
                            ))
                        }
                    }
                    .stroke(palette.accent.opacity(0.65), lineWidth: 1)
                    .allowsHitTesting(false)
                    ManualTimelineMarkerButton(
                        group: group, accent: palette.accent,
                        description: timelineMarkerDescription(group),
                        selectionDescription: timelineSelectionDescription,
                        onSeek: { seekVideoPreview(to: $0.time) }
                    )
                    .offset(x: group.center - 16)
                    .disabled(isApplyingSelection)
                }
            }
        }
        .frame(height: ManualEditorLayout.selectionMarkerHeight)
    }

    private func timelineSelectionDescription(_ selection: ManualTimelineSelection) -> String {
        t("editor.selectedFrameMarker", selection.number, TimestampFormatter.editableString(for: selection.time))
    }

    private func timelineMarkerDescription(_ group: ManualTimelineMarkerGroup) -> String {
        guard let first = group.selections.first, let last = group.selections.last else { return "" }
        return group.selections.count == 1 ? timelineSelectionDescription(first)
            : t("editor.selectedFrameMarkers", first.number, last.number)
    }

    private func timelineFilmstrip(height: CGFloat) -> some View {
        let frames = timelineFrames
        return GeometryReader { proxy in
            if frames.isEmpty {
                Rectangle().fill(mediaWell.opacity(0.12))
            } else {
                let frameWidth = max(1, (proxy.size.width - CGFloat(max(0, frames.count - 1))) / CGFloat(frames.count))
                ZStack(alignment: .leading) {
                    HStack(spacing: 1) {
                        ForEach(frames) { frame in
                            filmstripImage(frame, size: CGSize(width: frameWidth, height: height))
                                .frame(width: frameWidth, height: height)
                                .clipped()
                        }
                    }

                    Rectangle()
                        .fill(currentFrameAccent)
                        .frame(width: 2, height: height)
                        .shadow(color: currentFrameAccent.opacity(0.32), radius: 2)
                        .offset(x: timelinePlayheadOffset(in: proxy.size.width))
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    /// A custom scrubber shares its exact coordinate system with the blue
    /// filmstrip marker above it.  Native `Slider` internally reserves thumb
    /// insets, which is what made the former blue line drift at either end.
    private var timelineScrubber: some View {
        GeometryReader { proxy in
            let thumbDiameter: CGFloat = 12
            let markerWidth: CGFloat = 2
            let markerX = timelinePlayheadOffset(in: proxy.size.width)
            let thumbX = max(0, min(proxy.size.width - thumbDiameter, markerX + markerWidth / 2 - thumbDiameter / 2))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(editorDivider.opacity(0.88))
                    .frame(height: 2)
                Capsule()
                    .fill(currentFrameAccent)
                    .frame(width: max(0, markerX + markerWidth / 2), height: 2)
                Circle()
                    .fill(editorControlSurface)
                    .overlay { Circle().strokeBorder(currentFrameAccent, lineWidth: 2) }
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .offset(x: thumbX)
                    .shadow(color: .black.opacity(0.14), radius: 1, y: 1)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateTimelineScrub(location: value.location.x, width: proxy.size.width)
                    }
                    .onEnded { _ in
                        finishTimelineScrub()
                    }
            )
        }
        .frame(height: ManualEditorLayout.scrubberHeight)
        .accessibilityIdentifier("manual-frame-timeline")
        .accessibilityLabel(t("editor.timelineHint"))
        .accessibilityValue(timeline.editableText)
        .accessibilityAdjustableAction { direction in
            nudgePreview(by: direction == .increment ? previewFrameStep : -previewFrameStep)
        }
    }

    private var timelineRuler: some View {
        HStack(spacing: 0) {
            ForEach(0..<9, id: \.self) { tick in
                Rectangle()
                    .fill(editorDivider)
                    .frame(width: 1, height: tick.isMultiple(of: 2) ? 6 : 4)
                    .frame(maxWidth: .infinity, alignment: tick == 0 ? .leading : .center)
            }
        }
        .frame(height: ManualEditorLayout.rulerHeight)
    }

    private func updateTimelineScrub(location: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let target = ManualTimelineGeometry.time(at: location, duration: safeDuration, width: width)
        if !isScrubbingPreview {
            isScrubbingPreview = true
            previewCaptureTask?.cancel()
        }
        timeline.seek(to: target, duration: safeDuration)
        scrubVideoPreview(to: target)
    }

    private func finishTimelineScrub() {
        guard isScrubbingPreview else { return }
        isScrubbingPreview = false
        seekVideoPreview(to: timeline.time)
    }

    /// Candidate ordering can change when a user manually adds a frame. The
    /// filmstrip must instead remain a truthful 0-to-duration map, so it takes
    /// evenly distributed samples from the original time-sorted candidate set.
    private var timelineFrames: [CapturedFrame] {
        let source = sampledCandidates.sorted { $0.time < $1.time }
        let displayCount = min(12, source.count)
        guard displayCount > 0, source.count > displayCount else { return source }

        var evenlyDistributedFrames: [CapturedFrame] = []
        evenlyDistributedFrames.reserveCapacity(displayCount)
        for position in 0..<displayCount {
            let sourceIndex = min(
                source.count - 1,
                Int((Double(position) + 0.5) * Double(source.count) / Double(displayCount))
            )
            evenlyDistributedFrames.append(source[sourceIndex])
        }
        return evenlyDistributedFrames
    }

    /// The custom scrubber and the filmstrip marker intentionally use the
    /// same 0...width coordinate space, so the playhead remains aligned at
    /// every timestamp—including both ends of the video.
    private func timelinePlayheadOffset(in width: CGFloat) -> CGFloat {
        let markerWidth: CGFloat = 2
        let center = ManualTimelineGeometry.center(time: timeline.time, duration: safeDuration, width: width)
        return max(0, min(width - markerWidth, center - markerWidth / 2))
    }

    private func filmstripImage(_ frame: CapturedFrame, size: CGSize) -> some View {
        FrameThumbnailImage(
            frame: frame,
            maximumPixelSize: FrameThumbnailSizing.maximumPixelSize(
                for: size, aspectRatio: frame.aspectRatio, scale: displayScale, fills: true
            ),
            contentMode: .fill
        )
    }

    private func frameNudgeButton(
        frames: Int,
        label: String
    ) -> some View {
        Button {
            nudgePreview(by: Double(frames) * previewFrameStep)
        } label: {
            ManualFrameStepLabel(frames: frames, unit: t("editor.frameUnit.short"))
                .frame(width: 44, height: ManualEditorLayout.compactControlHeight)
                .contentShape(RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
        }
        .buttonStyle(ManualFrameEditorActionButtonStyle(role: .secondary))
        .disabled((frames < 0 && timeline.time <= 0.000_01) || (frames > 0 && timeline.time >= safeDuration - 0.000_01))
        .help(label)
        .accessibilityLabel(label)
    }

    private func prepareVideoPreview() {
        guard !playback.hasObservers else { return }
        playback.prepare(url: sourceURL)
        loadPreviewFrameStep()
        seekVideoPreview(to: 0)
    }

    private func toggleVideoPlayback() {
        if playback.isPlaying {
            let time = playback.pause()
            timeline.seek(to: time, duration: safeDuration)
            requestPreviewFrame(at: timeline.time)
        } else {
            previewCaptureTask?.cancel()
            isLoadingPreviewFrame = false
            previewFrame = nil
            isScrubbingPreview = false
            let time = playback.play(from: timeline.time, duration: safeDuration)
            timeline.seek(to: time, duration: safeDuration)
        }
    }

    private func loadPreviewFrameStep() {
        let source = sourceURL
        frameRateTask?.cancel()
        frameRateTask = Task {
            let asset = AVURLAsset(url: source)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let nominalRate = try? await track.load(.nominalFrameRate),
                  nominalRate.isFinite, nominalRate > 1,
                  !Task.isCancelled else { return }
            previewFrameStep = 1.0 / Double(nominalRate)
        }
    }

    private func nudgePreview(by offset: Double) {
        let target = min(max(0, timeline.time + offset), safeDuration)
        if abs(target - timeline.time) < 0.000_01 { return }
        seekVideoPreview(to: target)
    }

    private func seekVideoPreview(to time: Double) {
        let clampedTime = timeline.seek(to: time, duration: safeDuration)
        isScrubbingPreview = false
        playback.seek(to: clampedTime)
        requestPreviewFrame(at: clampedTime)
    }

    /// While the thumb moves, let AVFoundation use a nearby decodable frame.
    /// The expensive exact still-image decode is deferred until release.
    private func scrubVideoPreview(to time: Double) {
        let clampedTime = min(max(0, time), safeDuration)
        timeline.editableText = TimestampFormatter.editableString(for: clampedTime)
        previewCaptureTask?.cancel()
        isLoadingPreviewFrame = false
        playback.seek(to: clampedTime, tolerance: 0.16)
    }

    private func finishPreviewScrub(_ isEditing: Bool) {
        if isEditing {
            isScrubbingPreview = true
            previewCaptureTask?.cancel()
        } else {
            guard isScrubbingPreview else { return }
            isScrubbingPreview = false
            // One exact seek and one still decode after the drag—not dozens.
            seekVideoPreview(to: timeline.time)
        }
    }

    private func applyEditablePreviewTime() {
        guard let requestedTime = TimestampFormatter.editableSeconds(from: timeline.editableText) else {
            timeline.editableText = TimestampFormatter.editableString(for: timeline.time)
            return
        }
        let clampedTime = min(max(0, requestedTime), safeDuration)
        seekVideoPreview(to: clampedTime)
    }

    private func updateTimelineFromCompleteTimeText(_ text: String) {
        // Ignore the canonical value written by the slider itself. Partial text
        // edits are intentionally left alone until they form HH:MM:SS.mmm.
        guard text != TimestampFormatter.editableString(for: timeline.time),
              let requestedTime = TimestampFormatter.editableSeconds(from: text),
              isCompleteTimestamp(text) else { return }
        seekVideoPreview(to: min(max(0, requestedTime), safeDuration))
    }

    private func isCompleteTimestamp(_ text: String) -> Bool {
        text.range(
            of: #"^\d{2}:\d{2}:\d{2}\.\d{3}$"#,
            options: .regularExpression
        ) != nil
    }

    private func requestPreviewFrame(at time: Double, addAfterCapture: Bool = false) {
        previewCaptureTask?.cancel()
        let identifier = nextManualFrameID
        nextManualFrameID += 1
        isLoadingPreviewFrame = true
        let source = sourceURL
        let capture = Task.detached(priority: .userInitiated) {
            try await ManualFrameExtractor.captureFrame(from: source, at: time, identifier: identifier)
        }
        previewCaptureTask = Task {
            do {
                let frame = try await capture.valuePropagatingCancellation()
                guard !Task.isCancelled else { return }
                previewFrame = frame
                isLoadingPreviewFrame = false
                if addAfterCapture { addCurrentFrame() }
            } catch {
                guard !Task.isCancelled else { return }
                previewFrame = nil
            }
            guard !Task.isCancelled else { return }
            isLoadingPreviewFrame = false
        }
    }

    private func addCurrentFrame() {
        guard !isRefiningCurrentFrame, !isApplyingSelection else { return }
        if playback.isPlaying {
            timeline.seek(to: playback.pause(), duration: safeDuration)
            requestPreviewFrame(at: timeline.time, addAfterCapture: true)
            return
        }
        guard let previewFrame else { return }
        let requestedTime = previewFrame.time
        let identifier = previewFrame.id
        let source = sourceURL
        let editorDuration = duration
        isRefiningCurrentFrame = true
        let refinement = Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: source)
            return try await ManualFrameExtractor.captureSharpestFrame(
                from: asset,
                duration: editorDuration,
                at: requestedTime,
                identifier: identifier,
                maximumEdge: 1_600,
                compressionQuality: 0.92
            )
        }
        currentFrameRefinementTask?.cancel()
        currentFrameRefinementTask = Task {
            defer { isRefiningCurrentFrame = false }
            // If refinement fails for an unusual codec, preserving the exact
            // preview still lets the user finish the manual edit.
            let refined = (try? await refinement.valuePropagatingCancellation()) ?? previewFrame
            guard !Task.isCancelled else { return }
            if let existing = candidates.first(where: { abs($0.time - refined.time) < 0.04 }) {
                candidateReveal = CandidateReveal(frameID: existing.id)
                return
            }
            manuallyAddedCandidates.append(refined)
            candidateReveal = CandidateReveal(frameID: refined.id)
        }
    }

    private func applySelectedFrames() {
        // Capture one current settings value at Save, before asynchronous
        // refinement. The same value drives final pixels, format and metadata.
        let settings = model.currentExportSettings
        let framesToApply = selectedFrames
        guard framesToApply.count == settings.frameCount, !isLoadingCandidates,
              !isSmartSelecting, !isApplyingSelection else { return }
        let source = sourceURL
        let editorDuration = duration
        let estimatedCellWidth = Double(settings.safeWidth) / Double(settings.gridSide)
        let maximumEdge = CGFloat(min(1_280, max(480, estimatedCellWidth * 1.15)))
        isRefiningSelectedFrames = true
        let token = UUID()
        selectedFrameRefinementToken = token

        let refinement = Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: source)
            let refined = try await ManualFrameExtractor.captureSharpestFrames(
                from: asset,
                duration: editorDuration,
                frames: framesToApply,
                maximumEdge: maximumEdge,
                compressionQuality: 0.92
            )
            let refinedByID = Dictionary(uniqueKeysWithValues: refined.map { ($0.id, $0) })
            // A damaged/VFR timestamp must not prevent a person from applying
            // the rest of a deliberate manual selection.
            return framesToApply.map { refinedByID[$0.id] ?? $0 }
        }
        selectedFrameRefinementTask = refinement
        applyPresentationTask?.cancel()
        applyPresentationTask = Task {
            defer {
                if selectedFrameRefinementToken == token {
                    isRefiningSelectedFrames = false
                    selectedFrameRefinementTask = nil
                    applyPresentationTask = nil
                    selectedFrameRefinementToken = nil
                }
            }
            do {
                let refinedFrames = try await refinement.valuePropagatingCancellation()
                // Closing the window or starting another operation invalidates
                // this result. Never apply frames after a user has cancelled.
                guard !Task.isCancelled, selectedFrameRefinementToken == token else { return }
                onApply(refinedFrames, settings)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, selectedFrameRefinementToken == token else { return }
                operationError = (error as? StoryboardError)?.message(in: language) ?? error.localizedDescription
            }
        }
    }

    private func toggle(_ candidate: CapturedFrame) {
        guard !isSmartSelecting, !isApplyingSelection else { return }
        if selectedIDs.contains(candidate.id) {
            selectedIDs.remove(candidate.id)
        } else if selectedIDs.count < selectionLimit {
            selectedIDs.insert(candidate.id)
        }
    }

    private func regenerateCandidates() {
        guard !isLoadingCandidates, !isSmartSelecting, !isApplyingSelection else { return }
        candidateBatch += 1
        selectedIDs.removeAll()
        loadCandidates()
    }

    private func smartSelectCandidates() {
        guard !candidates.isEmpty, !isLoadingCandidates, !isSmartSelecting, !isApplyingSelection else { return }
        let plan = ManualSelectionFillPlan(candidates: candidates, selectedIDs: selectedIDs, limit: selectionLimit)
        guard plan.additionalCount > 0 else { return }
        let token = captureToken
        isSmartSelecting = true

        smartSelectionTask?.cancel()
        smartSelectionPresentationTask?.cancel()
        let selectionTask = Task.detached(priority: .userInitiated) {
            ManualFrameSelector.selectIDs(from: plan.candidates, count: plan.additionalCount)
        }
        smartSelectionTask = selectionTask
        smartSelectionPresentationTask = Task {
            let ids = await selectionTask.value
            guard !Task.isCancelled, token == captureToken else { return }
            selectedIDs = plan.completing(with: ids)
            isSmartSelecting = false
            smartSelectionTask = nil
            smartSelectionPresentationTask = nil
        }
    }

    private func updateCandidateCapacityForCurrentGrid() {
        guard !isApplyingSelection else { return }
        smartSelectionTask?.cancel()
        smartSelectionPresentationTask?.cancel()
        smartSelectionTask = nil
        smartSelectionPresentationTask = nil
        isSmartSelecting = false
        // A larger grid may need more candidates. Append another uniquely
        // identified batch so existing choices keep their exact images/times.
        if candidates.count < selectionLimit {
            candidateBatch += 1
            loadCandidates(preservingExistingCandidates: true)
        }
    }

    private func loadCandidates(preservingExistingCandidates: Bool = false) {
        candidateSamplingTask?.cancel()
        candidatePresentationTask?.cancel()
        smartSelectionTask?.cancel()
        smartSelectionPresentationTask?.cancel()
        let token = UUID()
        captureToken = token
        captureError = ""
        isLoadingCandidates = true
        isSmartSelecting = false
        let outputWidth = outputWidth
        let gridSide = max(1, Int(Double(selectionLimit).squareRoot().rounded()))
        let requestedCount = min(72, max(24, selectionLimit * 3))
        let batch = candidateBatch
        let source = sourceURL

        // Sampling candidates may decode dozens of frames. Keep that work off the
        // main actor so scrolling, selection and the progress state stay responsive.
        let samplingTask = Task.detached(priority: .userInitiated) {
            try await ManualFrameExtractor.captureCandidates(
                from: source,
                gridSide: gridSide,
                outputWidth: outputWidth,
                count: requestedCount,
                batch: batch
            )
        }
        candidateSamplingTask = samplingTask

        candidatePresentationTask = Task {
            do {
                let frames = try await samplingTask.valuePropagatingCancellation()
                guard !Task.isCancelled, token == captureToken else { return }
                sampledCandidates = preservingExistingCandidates
                    ? ManualCandidatePool.appending(frames, to: sampledCandidates, excluding: manuallyAddedCandidates)
                    : frames
            } catch {
                guard !Task.isCancelled, token == captureToken else { return }
                captureError = (error as? StoryboardError)?.message(in: language) ?? error.localizedDescription
            }
            guard !Task.isCancelled, token == captureToken else { return }
            isLoadingCandidates = false
            candidateSamplingTask = nil
            candidatePresentationTask = nil
        }
    }

    private func cancelBackgroundWork() {
        captureToken = UUID()
        candidateSamplingTask?.cancel()
        candidatePresentationTask?.cancel()
        smartSelectionTask?.cancel()
        smartSelectionPresentationTask?.cancel()
        previewCaptureTask?.cancel()
        currentFrameRefinementTask?.cancel()
        frameRateTask?.cancel()
        selectedFrameRefinementToken = nil
        selectedFrameRefinementTask?.cancel()
        applyPresentationTask?.cancel()
        playback.stopAndRelease()
    }
}

/// A native AVPlayerLayer keeps letterboxing transparent to the editor's
/// theme-aware media well; AVPlayerView otherwise paints that space black.
private struct ManualVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer?
    let fillColor: NSColor

    func makeNSView(context: Context) -> ManualVideoSurface {
        ManualVideoSurface(player: player, fillColor: fillColor)
    }

    func updateNSView(_ view: ManualVideoSurface, context: Context) {
        view.update(player: player, fillColor: fillColor)
    }
}

final class ManualVideoSurface: NSView {
    override func makeBackingLayer() -> CALayer { AVPlayerLayer() }

    init(player: AVPlayer?, fillColor: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        update(player: player, fillColor: fillColor)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(player: AVPlayer?, fillColor: NSColor) {
        guard let playerLayer = layer as? AVPlayerLayer else { return }
        if playerLayer.player !== player { playerLayer.player = player }
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = fillColor.cgColor
    }
}
