import AppKit
@preconcurrency import AVFoundation
import AVKit
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @ObservedObject var model: StoryboardViewModel
    let sourceURL: URL
    let selectionLimit: Int
    let duration: Double
    let outputWidth: Int
    @ObservedObject var configuration: ManualFrameEditorConfiguration
    let onClose: () -> Void
    let onApply: ([CapturedFrame]) -> Void
    @State private var sampledCandidates: [CapturedFrame] = []
    @State private var manuallyAddedCandidates: [CapturedFrame] = []
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

    private var selectedFrames: [CapturedFrame] {
        candidates
            .filter { selectedIDs.contains($0.id) }
            .sorted { $0.time < $1.time }
    }

    private var candidates: [CapturedFrame] {
        (sampledCandidates + manuallyAddedCandidates).sorted { $0.time < $1.time }
    }

    private var safeDuration: Double { max(0.01, duration) }
    private var isApplyingSelection: Bool { isRefiningSelectedFrames || model.isApplyingFrameAdjustments }
    private let manualPreviewHeight = ManualEditorLayout.mediaHeight

    // The editor has its own deliberately quiet, contact-sheet-like palette.
    // This makes the source media, selection order and current playhead the
    // visual anchors instead of surrounding every control with a card.
    private var editorCanvas: Color {
        colorScheme == .dark
            ? Color(red: 0.067, green: 0.078, blue: 0.094) // #111419
            : Color(red: 0.961, green: 0.959, blue: 0.945) // warm #F5F5F1
    }

    private var editorControlSurface: Color {
        colorScheme == .dark
            ? Color(red: 0.114, green: 0.133, blue: 0.157)
            : Color.white.opacity(0.84)
    }

    private var editorDivider: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.13)
            : Color(red: 0.805, green: 0.816, blue: 0.824)
    }

    private var mediaWell: Color {
        colorScheme == .dark
            ? Color(red: 0.012, green: 0.016, blue: 0.024)
            : Color(red: 0.067, green: 0.078, blue: 0.090)
    }

    private var currentFrameAccent: Color {
        colorScheme == .dark
            ? Color(red: 1.0, green: 0.68, blue: 0.20)
            : Color(red: 0.88, green: 0.52, blue: 0.035)
    }

    private var controlBorder: Color { editorDivider }

    private var controlText: Color {
        colorScheme == .dark
            ? Color(red: 0.949, green: 0.965, blue: 0.988)
            : Color(red: 0.071, green: 0.125, blue: 0.200)
    }

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            Rectangle().fill(editorDivider).frame(height: 1)
            manualVideoPreview
            candidateBrowser
            Rectangle().fill(editorDivider).frame(height: 1)
            editorFooter
        }
        .background(editorCanvas)
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

    private var editorToolbar: some View {
        HStack(spacing: 10) {
            GlyphLabel(title: t("editor.selectionCount", selectedIDs.count, selectionLimit), glyph: .layers, glyphSize: 18)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selectedIDs.count == selectionLimit ? Color.green : controlText)

            Spacer(minLength: 16)

            Button(action: smartSelectCandidates) {
                Group {
                    if isSmartSelecting {
                        ProgressView().controlSize(.small)
                    } else {
                        GlyphLabel(title: t("editor.smartSelect"), glyph: .smartSelect, glyphSize: 16)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .frame(height: ManualEditorLayout.toolbarControlHeight)
                .padding(.horizontal, 9)
            }
            .buttonStyle(ManualFrameEditorActionButtonStyle(role: .toolbarPrimary))
            .disabled(isLoadingCandidates || candidates.isEmpty || isSmartSelecting || isApplyingSelection)
            .accessibilityIdentifier("manual-frame-smart-select")

            Button(action: regenerateCandidates) {
                GlyphLabel(title: t("editor.regenerate"), glyph: .refreshCandidates, glyphSize: 16)
                    .font(.system(size: 13, weight: .medium))
                    .frame(height: ManualEditorLayout.toolbarControlHeight)
                    .padding(.horizontal, 9)
            }
            .buttonStyle(ManualFrameEditorActionButtonStyle(role: .toolbarSecondary))
            .disabled(isLoadingCandidates || isSmartSelecting || isApplyingSelection)
            .accessibilityIdentifier("manual-frame-regenerate")
        }
        .padding(.horizontal, ManualEditorLayout.horizontalInset)
        .frame(height: ManualEditorLayout.toolbarHeight)
    }

    private var candidateBrowser: some View {
        let orderedCandidates = candidates
        let selectedPositions = Dictionary(uniqueKeysWithValues: orderedCandidates
            .filter { selectedIDs.contains($0.id) }
            .enumerated().map { ($0.element.id, $0.offset + 1) })
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(t("editor.candidates"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(controlText)
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(selectedIDs.count) / \(selectionLimit)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                ProjectIcon(symbol: .grid, size: 17)
                    .foregroundStyle(SelectionPalette.active)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, ManualEditorLayout.horizontalInset)
            .padding(.top, ManualEditorLayout.candidateHeaderTop)
            .padding(.bottom, ManualEditorLayout.candidateHeaderBottom)

            ScrollView {
                if isLoadingCandidates {
                    ProgressView(t("editor.loading"))
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else if candidates.isEmpty {
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
                        columns: [GridItem(.adaptive(minimum: 238, maximum: 340), spacing: ManualEditorLayout.candidateGap)],
                        spacing: ManualEditorLayout.candidateGap
                    ) {
                        ForEach(orderedCandidates) { candidate in
                            candidateTile(candidate, selectionNumber: selectedPositions[candidate.id])
                        }
                    }
                    .padding(.horizontal, ManualEditorLayout.horizontalInset)
                    .padding(.bottom, ManualEditorLayout.candidateGridBottom)
                }
            }
        }
        .frame(minHeight: 220, maxHeight: .infinity)
        .layoutPriority(1)
        .accessibilityIdentifier("manual-frame-candidates")
    }

    private func candidateTile(_ candidate: CapturedFrame, selectionNumber: Int?) -> some View {
        let isSelected = selectedIDs.contains(candidate.id)
        // The badge is the final storyboard position, so a newly selected
        // earlier frame immediately renumbers every later selected frame.
        return Button {
            toggle(candidate)
        } label: {
            frameImage(candidate)
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
                    ZStack {
                        Circle().fill(isSelected ? SelectionPalette.active : .black.opacity(0.16))
                        Circle().strokeBorder(.white.opacity(0.92), lineWidth: 1.5)
                        if let selectionNumber {
                            Text("\(selectionNumber)")
                                .font(.system(size: selectionNumber >= 10 ? 9 : 11, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .padding(7)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(
                            isSelected ? SelectionPalette.active : controlBorder,
                            lineWidth: isSelected ? 2 : 1
                        )
                }
        }
        .buttonStyle(.plain)
        .disabled(isSmartSelecting || isApplyingSelection || (!isSelected && selectedIDs.count >= selectionLimit))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(t("editor.candidates")) · \(TimestampFormatter.string(for: candidate.time))")
        .accessibilityValue(
            isSelected
                ? "\(t("accessibility.selected")) \(selectionNumber ?? 0) / \(selectionLimit)"
                : "0 / \(selectionLimit)"
        )
    }

    private var editorFooter: some View {
        HStack {
            Button(role: .cancel, action: onClose) {
                Text(t("editor.cancel"))
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 128, height: ManualEditorLayout.compactControlHeight)
            }
            .buttonStyle(ManualFrameEditorActionButtonStyle(role: .secondary))
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Button(action: applySelectedFrames) {
                Group {
                    if isRefiningSelectedFrames {
                        ProgressView().controlSize(.small)
                    } else {
                        GlyphLabel(title: t("editor.apply"), glyph: .check)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .padding(.horizontal, 18)
                .frame(minWidth: 156, minHeight: ManualEditorLayout.compactControlHeight)
            }
            .buttonStyle(ManualFrameEditorActionButtonStyle(role: .primary))
            .disabled(selectedIDs.count != selectionLimit || isLoadingCandidates || isSmartSelecting || isApplyingSelection)
            .keyboardShortcut(.return, modifiers: [.command])
            .accessibilityIdentifier("manual-frame-apply")
        }
        .padding(.horizontal, ManualEditorLayout.horizontalInset)
        .frame(height: ManualEditorLayout.footerHeight)
        .background(editorCanvas)
    }

    private func frameImage(_ frame: CapturedFrame) -> some View {
        let aspect = StoryboardAspect.source.resolvedCardAspectRatio(sourceAspectRatio: frame.aspectRatio)
        let pixelSize = FrameThumbnailSizing.maximumPixelSize(
            for: CGSize(width: 340, height: 340 / aspect),
            aspectRatio: aspect, scale: displayScale, fills: false
        )
        return FrameThumbnailImage(frame: frame, maximumPixelSize: pixelSize)
            .background(.black.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var manualVideoPreview: some View {
        GeometryReader { proxy in
            // Reserve the controls' real minimum width before sizing the
            // monitor; the old percentage could push buttons off a 1000pt window.
            let controlsWidth: CGFloat = 612
            let availableMonitorWidth = proxy.size.width - ManualEditorLayout.workspaceGap - controlsWidth
            let monitorWidth = min(548, max(280, min(proxy.size.width * 0.42, availableMonitorWidth)))
            HStack(alignment: .top, spacing: ManualEditorLayout.workspaceGap) {
                previewMonitor
                    .frame(width: monitorWidth, height: manualPreviewHeight)
                timelineControlDeck
                    .frame(maxWidth: .infinity, minHeight: manualPreviewHeight, maxHeight: manualPreviewHeight)
            }
        }
        .padding(.horizontal, ManualEditorLayout.horizontalInset)
        .padding(.vertical, ManualEditorLayout.workspaceVerticalInset)
        .frame(height: manualPreviewHeight + ManualEditorLayout.workspaceVerticalInset * 2)
    }

    private var previewMonitor: some View {
        ZStack(alignment: .bottom) {
            ManualVideoPlayerView(player: playback.player)

            // A decoded still remains on top while scrubbing has stopped: it is
            // substantially clearer than the player surface for fast movement.
            if let previewFrame, !isScrubbingPreview, !playback.isPlaying {
                previewStill(previewFrame)
            } else if isLoadingPreviewFrame {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }

            HStack(spacing: 10) {
                Button(action: toggleVideoPlayback) {
                    ProjectIcon(symbol: playback.isPlaying ? .pause : .play, size: 16)
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t(playback.isPlaying ? "editor.pausePreview" : "editor.playPreview"))
                .accessibilityIdentifier("manual-frame-playback")
                Text("\(TimestampFormatter.string(for: timeline.time))  /  \(TimestampFormatter.string(for: safeDuration))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                ProjectIcon(symbol: .frame, size: 16)
                    .foregroundStyle(.white.opacity(0.90))
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(.black.opacity(0.54))
        }
        .background(mediaWell)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(colorScheme == .dark ? .white.opacity(0.16) : .black.opacity(0.22), lineWidth: 1)
        }
    }

    private func previewStill(_ frame: CapturedFrame) -> some View {
        FrameThumbnailImage(frame: frame, maximumPixelSize: 1_100)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }

    private var timelineControlDeck: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(t("editor.timelineHint"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(controlText)
                    .lineLimit(2)
                Spacer(minLength: 12)
                Text("\(TimestampFormatter.string(for: timeline.time))  /  \(TimestampFormatter.string(for: safeDuration))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            timelineFilmstrip
                .padding(.top, 13)

            timelineScrubber
                .padding(.top, 8)

            timelineRuler
                .padding(.top, 1)

            HStack {
                Text(TimestampFormatter.string(for: 0))
                Spacer()
                Text(TimestampFormatter.string(for: safeDuration))
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.top, 1)

            HStack(spacing: 8) {
                frameNudgeButton(
                    label: t("editor.backFiveFrames"),
                    offset: -5 * previewFrameStep
                )
                frameNudgeButton(
                    label: t("editor.backOneFrame"),
                    offset: -previewFrameStep
                )

                TextField("00:00:00.000", text: $timeline.editableText)
                    .textFieldStyle(ManualFrameEditorTextFieldStyle())
                    .frame(minWidth: 176, maxWidth: .infinity)
                    .onChange(of: timeline.editableText, perform: updateTimelineFromCompleteTimeText)
                    .onSubmit(applyEditablePreviewTime)
                    .accessibilityIdentifier("manual-frame-time-field")
                    .accessibilityLabel(t("editor.timeField"))

                frameNudgeButton(
                    label: t("editor.forwardOneFrame"),
                    offset: previewFrameStep
                )
                frameNudgeButton(
                    label: t("editor.forwardFiveFrames"),
                    offset: 5 * previewFrameStep
                )

                Button(action: addCurrentFrame) {
                    GlyphLabel(title: t("editor.addCurrentFrame"), glyph: .plus, glyphSize: 16)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .frame(width: 188, height: ManualEditorLayout.compactControlHeight)
                }
                .buttonStyle(ManualFrameEditorActionButtonStyle(role: .primary))
                .disabled((!playback.isPlaying && (previewFrame == nil || isLoadingPreviewFrame)) || isRefiningCurrentFrame || isApplyingSelection)
                .accessibilityIdentifier("manual-frame-add-current")
            }
            .padding(.top, 14)
            .frame(height: 48)
        }
    }

    private var timelineFilmstrip: some View {
        let frames = timelineFrames
        return GeometryReader { proxy in
            if frames.isEmpty {
                Rectangle().fill(mediaWell.opacity(0.12))
            } else {
                let frameWidth = max(1, (proxy.size.width - CGFloat(max(0, frames.count - 1))) / CGFloat(frames.count))
                ZStack(alignment: .leading) {
                    HStack(spacing: 1) {
                        ForEach(frames) { frame in
                            filmstripImage(frame, size: CGSize(width: frameWidth, height: 62))
                                .frame(width: frameWidth, height: 62)
                                .clipped()
                        }
                    }

                    Rectangle()
                        .fill(currentFrameAccent)
                        .frame(width: 2, height: 62)
                        .shadow(color: currentFrameAccent.opacity(0.32), radius: 2)
                        .offset(x: timelinePlayheadOffset(in: proxy.size.width))
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    /// A custom scrubber shares its exact coordinate system with the amber
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
                    .fill(SelectionPalette.active)
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
        .frame(height: 18)
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
        .frame(height: 6)
    }

    private func updateTimelineScrub(location: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let thumbRadius: CGFloat = 6
        let usableWidth = max(1, width - thumbRadius * 2)
        let progress = max(0, min(1, (location - thumbRadius) / usableWidth))
        let target = safeDuration * progress
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
        let thumbRadius: CGFloat = 6
        let progress = max(0, min(1, timeline.time / safeDuration))
        let firstCenter = min(thumbRadius, max(0, width / 2))
        let lastCenter = max(firstCenter, width - thumbRadius)
        let center = firstCenter + (lastCenter - firstCenter) * progress
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
        label: String,
        offset: Double
    ) -> some View {
        Button {
            nudgePreview(by: offset)
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 52, height: ManualEditorLayout.compactControlHeight)
                .contentShape(RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(controlText)
        .background(editorControlSurface, in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous)
                .strokeBorder(controlBorder, lineWidth: 1)
        }
        .disabled((offset < 0 && timeline.time <= 0.000_01) || (offset > 0 && timeline.time >= safeDuration - 0.000_01))
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
            let isAlreadyPresent = candidates.contains { abs($0.time - refined.time) < 0.04 }
            guard !isAlreadyPresent else { return }
            manuallyAddedCandidates.append(refined)
        }
    }

    private func applySelectedFrames() {
        let framesToApply = selectedFrames
        guard framesToApply.count == selectionLimit, !isLoadingCandidates,
              !isSmartSelecting, !isApplyingSelection else { return }
        let source = sourceURL
        let editorDuration = duration
        let gridSide = max(1, Int(Double(selectionLimit).squareRoot().rounded()))
        let estimatedCellWidth = Double(max(1_920, outputWidth)) / Double(gridSide)
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
                onApply(refinedFrames)
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
        let token = captureToken
        let source = candidates
        let targetCount = selectionLimit
        isSmartSelecting = true

        smartSelectionTask?.cancel()
        smartSelectionPresentationTask?.cancel()
        let selectionTask = Task.detached(priority: .userInitiated) {
            ManualFrameSelector.selectIDs(from: source, count: targetCount)
        }
        smartSelectionTask = selectionTask
        smartSelectionPresentationTask = Task {
            let ids = await selectionTask.value
            guard !Task.isCancelled, token == captureToken else { return }
            selectedIDs = Set(ids)
            isSmartSelecting = false
            smartSelectionTask = nil
            smartSelectionPresentationTask = nil
        }
    }

    private func loadCandidates() {
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
                sampledCandidates = frames
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

/// AppKit's AVPlayerView keeps the preview lifecycle stable inside a SwiftUI
/// sheet. The editor supplies its own timeline, so native transport controls
/// are intentionally hidden.
private struct ManualVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.allowsVideoFrameAnalysis = false
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }
}
