import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model: StoryboardViewModel
    @StateObject private var previewAutoFitter = PreviewWindowAutoFitter()
    @EnvironmentObject private var updateChecker: UpdateChecker
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.displayScale) private var displayScale
    @AppStorage("appLanguage") private var languageCode = AppLanguage.systemDefault.rawValue
    @AppStorage("appAppearance") private var appearanceCode = AppAppearance.system.rawValue
    @State private var showsQueue = true
    @State private var showsInspector = true
    @State private var panelsBeforeFocus: (queue: Bool, inspector: Bool)?
    @State private var isAspectPickerPresented = false
    @State private var isWidthPickerPresented = false
    @State private var manualFrameEditorRequest: ManualFrameEditorRequest?
    @State private var isPauseConfirmationPresented = false
    @State private var isResumeConfirmationPresented = false
    @State private var isCancelConfirmationPresented = false
    @State private var isFailureReportPresented = false
    @State private var isTranscodingGuidePresented = false
    @State private var presentsTranscodingGuideAfterFailureReport = false

    @MainActor
    init(model: StoryboardViewModel? = nil) {
        _model = StateObject(wrappedValue: model ?? StoryboardViewModel())
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceCode) ?? .system
    }

    private var resolvedAppearance: AppAppearance {
        appearance == .system ? (systemColorScheme == .light ? .light : .dark) : appearance
    }

    private var isLightAppearance: Bool { resolvedAppearance == .light }

    private var workspacePalette: StudioPalette { StudioPalette(isLight: isLightAppearance) }
    private var appBackground: Color { workspacePalette.window }
    private var sidebarFill: Color { workspacePalette.panel }
    private var stageFill: Color { workspacePalette.canvas }
    private var workspaceDivider: Color { workspacePalette.divider }
    private var studioAccent: Color { workspacePalette.accent }
    private var inlineControlFill: Color { workspacePalette.control }

    private func t(_ key: String, _ arguments: CVarArg...) -> String {
        language.text(key, arguments: arguments)
    }

    var body: some View {
        GeometryReader { geometry in
            let isCompactHeight = geometry.size.height < 700
            let isNarrow = geometry.size.width < 1_090
            let queueWidth = StudioLayout.queueWidth(availableWidth: geometry.size.width)
            let inspectorWidth = StudioLayout.inspectorWidth

            VStack(spacing: 0) {
                studioToolbar(compact: geometry.size.width < 650)
                    .frame(height: StudioLayout.toolbarHeight)
                    .background(appBackground)

                if updateChecker.hasUpdate {
                    UpdateAvailableBanner(checker: updateChecker, language: language)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }

                workspaceRule

                HStack(spacing: 0) {
                    if showsQueue {
                        queuePanel(compact: isCompactHeight, isNarrow: isNarrow)
                            .frame(width: queueWidth)
                            .frame(maxHeight: .infinity)
                        Rectangle().fill(workspaceDivider).frame(width: hairline)
                    }

                    previewPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)

                    if showsInspector {
                        Rectangle().fill(workspaceDivider).frame(width: hairline)
                        controlPanel(compact: isCompactHeight, isNarrow: isNarrow)
                            .frame(width: inspectorWidth)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !model.isProcessing {
                    workspaceRule
                    Group {
                        if model.previewImage != nil {
                            previewActions
                        } else {
                            HStack {
                                localPrivacyCaption
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: StudioLayout.previewActionHeight)
                    .background(appBackground)
                }

                if model.isProcessing || model.hasFailedJobs {
                    workspaceRule
                    batchStatusBar
                }
            }
            .background(appBackground)
        }
        .frame(minWidth: showsQueue && showsInspector ? 720 : (showsQueue || showsInspector ? 600 : 480), minHeight: 480)
        .environment(\.locale, language.locale)
        .environment(\.layoutDirection, .leftToRight)
        // `preferredColorScheme` updates the hosting window, but its semantic
        // `Color.primary` / `Color.secondary` values can briefly keep the
        // previous system appearance when a user switches this in-app setting.
        // Supply the resolved scheme to the entire content tree as well, so
        // every label, picker and ButtonStyle changes foreground colour in the
        // same render pass as our custom light/dark surfaces.
        .environment(\.colorScheme, resolvedAppearance == .light ? .light : .dark)
        .preferredColorScheme(appearance.preferredColorScheme)
        .onAppear {
            model.language = language
            Task { await updateChecker.checkForUpdate() }
        }
        .onChange(of: languageCode) { newValue in
            model.language = AppLanguage(rawValue: newValue) ?? .english
        }
        .onChange(of: model.isProcessing) { isProcessing in
            guard !isProcessing else { return }
            // Processing can finish while a confirmation is open. Do not let
            // that stale dialog overwrite a completed result with Cancelled.
            isPauseConfirmationPresented = false
            isResumeConfirmationPresented = false
            isCancelConfirmationPresented = false
        }
        .onDrop(of: [.fileURL], isTargeted: $model.isDropTargeted, perform: model.acceptDrop)
        .alert(t("alert.generation.title"), isPresented: $model.showError) {
            Button(t("button.ok"), role: .cancel) { }
        } message: {
            Text(model.errorMessage)
        }
        .confirmationDialog(t("alert.pauseBatch.title"), isPresented: $isPauseConfirmationPresented, titleVisibility: .visible) {
            Button(t("button.pauseConfirm")) { model.requestPause() }
            Button(t("button.cancel"), role: .cancel) { }
        } message: {
            Text(t("alert.pauseBatch.message"))
        }
        .confirmationDialog(t("alert.resumeBatch.title"), isPresented: $isResumeConfirmationPresented, titleVisibility: .visible) {
            Button(t("button.resumeConfirm")) { model.resumeGeneration() }
            Button(t("button.cancel"), role: .cancel) { }
        } message: {
            Text(t("alert.resumeBatch.message"))
        }
        .confirmationDialog(t("alert.cancelBatch.title"), isPresented: $isCancelConfirmationPresented, titleVisibility: .visible) {
            Button(t("button.cancelGenerationConfirm"), role: .destructive) {
                if model.isProcessing { model.cancelGeneration() }
            }
            Button(t("button.keepGenerating"), role: .cancel) { }
        } message: {
            Text(t("alert.cancelBatch.message"))
        }
        .sheet(isPresented: $isFailureReportPresented, onDismiss: presentQueuedTranscodingGuide) {
            BatchFailureReport(
                jobs: model.failedJobs,
                language: language,
                retry: {
                    isFailureReportPresented = false
                    model.retryFailedJobs()
                },
                showSources: {
                    model.showSourceFiles(for: model.failedJobs)
                },
                showTranscodingGuide: {
                    // A sheet cannot reliably present another sheet while it is
                    // still dismissing. Queue the guide for the dismissal callback.
                    presentsTranscodingGuideAfterFailureReport = true
                    isFailureReportPresented = false
                }
            )
        }
        .sheet(isPresented: $isTranscodingGuidePresented) {
            TranscodingGuide(language: language)
        }
        .background {
            ManualFrameEditorWindowPresenter(
                request: $manualFrameEditorRequest,
                model: model,
                language: language,
                colorScheme: resolvedAppearance == .dark ? .dark : .light,
                onApply: { request, frames, settings in
                    model.applyManuallySelectedFrames(
                        frames,
                        targetPreviewID: request.previewID,
                        sourceURL: request.sourceURL,
                        duration: request.duration,
                        settings: settings
                    )
                }
            )
        }
    }

    private func presentQueuedTranscodingGuide() {
        guard presentsTranscodingGuideAfterFailureReport else { return }
        presentsTranscodingGuideAfterFailureReport = false
        isTranscodingGuidePresented = true
    }

    private var hairline: CGFloat { 1 / max(1, displayScale) }
    private var isPreviewFocused: Bool { !showsQueue && !showsInspector }

    private var workspaceRule: some View {
        Rectangle().fill(workspaceDivider).frame(height: hairline)
    }

    private func studioToolbar(compact: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    ShotMapMark(language: language, size: 22)
                    if !compact {
                        Text("ShotMap")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.leading, 76)
                .fixedSize()

                Spacer(minLength: 8)

                HStack(spacing: 3) {
                    panelToggle(symbol: .sidebarLeft, label: t("workspace.toggleQueue"), selected: showsQueue) {
                        panelsBeforeFocus = nil
                        showsQueue.toggle()
                    }
                    panelToggle(symbol: .sidebarRight, label: t("workspace.toggleInspector"), selected: showsInspector) {
                        panelsBeforeFocus = nil
                        showsInspector.toggle()
                    }
                    panelToggle(
                        symbol: isPreviewFocused ? .minimize : .maximize,
                        label: t(isPreviewFocused ? "workspace.restorePanels" : "workspace.focusPreview"),
                        selected: isPreviewFocused,
                        action: togglePreviewFocus
                    )
                }
            }
            .padding(.horizontal, StudioLayout.toolbarHorizontalInset)
            .frame(maxWidth: .infinity)

            if showsInspector {
                // This is the same width and separator as the settings pane
                // below, independent of the translated generation label.
                Rectangle().fill(workspaceDivider).frame(width: hairline, height: 18)
                generateButton
                    .padding(.horizontal, StudioLayout.panelInset)
                    .frame(width: StudioLayout.inspectorWidth)
            } else {
                generateButton
                    .padding(.leading, 10)
                    .padding(.trailing, StudioLayout.toolbarHorizontalInset)
            }
        }
    }

    private var generateButton: some View {
        Button(action: model.generate) {
            GlyphLabel(title: model.primaryButtonTitle, glyph: .filmStack, glyphSize: 14)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 12)
                .frame(maxWidth: showsInspector ? .infinity : nil)
                .frame(height: StudioLayout.primaryControlHeight)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!model.hasVideos || model.isBusy || model.isImportingVideos || model.isProcessing)
        .accessibilityLabel(t("accessibility.generate"))
    }

    private func panelToggle(symbol: ProjectIcon.Symbol, label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ProjectIcon(symbol: symbol, size: 16)
                .foregroundStyle(selected ? studioAccent : Color.secondary)
                .frame(width: 30, height: 28)
                .background(selected ? studioAccent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(selected ? t("accessibility.selected") : "")
    }

    private func togglePreviewFocus() {
        if isPreviewFocused {
            let restored = panelsBeforeFocus ?? (queue: true, inspector: true)
            showsQueue = restored.queue
            showsInspector = restored.inspector
            panelsBeforeFocus = nil
        } else {
            panelsBeforeFocus = (showsQueue, showsInspector)
            showsQueue = false
            showsInspector = false
        }
    }

    /// All three frame controls share one trailing column. Measure the
    /// longest localized label so translated captions cannot push one row out
    /// of alignment with the other two in the compact inspector.
    private var inspectorValueColumnWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let labelWidth = ["section.aspect", "export.width", "export.background"]
            .map { ceil((t($0) as NSString).size(withAttributes: [.font: font]).width) }
            .max() ?? 0
        let available = StudioLayout.inspectorWidth - StudioLayout.panelInset * 2
        return min(128, max(0, available - labelWidth - 16))
    }

    private var aspectSelector: some View {
        Button {
            isAspectPickerPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                inspectorFieldLabel(t("section.aspect"))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Spacer(minLength: 0)
                    Text(model.layoutAspect.label(in: language))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                    ProjectIcon(symbol: .selector, size: 11)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .frame(width: inspectorValueColumnWidth, height: StudioLayout.controlHeight)
                .background(inlineControlFill, in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous).strokeBorder(workspaceDivider) }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t("section.aspect"))
        // A pause is an intentional checkpoint between jobs. Keep this
        // setting editable there, so the user can adjust the next job before
        // resuming; an active render must still keep it stable.
        .disabled(model.isSettingsLocked)
        .popover(isPresented: $isAspectPickerPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t("section.aspect"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)

                ForEach(StoryboardAspect.allCases) { aspect in
                    Button {
                        model.layoutAspect = aspect
                        isAspectPickerPresented = false
                    } label: {
                        HStack {
                            Text(aspect.label(in: language))
                            Spacer()
                            if aspect == model.layoutAspect {
                                ProjectIcon(symbol: .check, size: 14)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(aspect == model.layoutAspect ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .contentShape(Rectangle())
                }
            }
            .padding(8)
            .frame(width: 178)
        }
    }

    private var widthSelector: some View {
        Button {
            isWidthPickerPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                inspectorFieldLabel(t("export.width"))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Spacer(minLength: 0)
                    Text(t("export.width.value", model.width))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                    ProjectIcon(symbol: .selector, size: 11)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .frame(width: inspectorValueColumnWidth, height: StudioLayout.controlHeight)
                .background(inlineControlFill, in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous).strokeBorder(workspaceDivider) }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t("export.width"))
        // Match the rest of the export controls: settings unlock only after
        // the batch reaches its pause checkpoint, never mid-render.
        .disabled(model.isSettingsLocked)
        .popover(isPresented: $isWidthPickerPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t("export.width"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)

                ForEach(outputWidthChoices, id: \.self) { width in
                    Button {
                        model.width = width
                        isWidthPickerPresented = false
                    } label: {
                        HStack {
                            Text(t("export.width.value", width))
                                .monospacedDigit()
                            Spacer()
                            if width == model.width {
                                ProjectIcon(symbol: .check, size: 14)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(width == model.width ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .contentShape(Rectangle())
                }
            }
            .padding(8)
            .frame(width: 148)
        }
    }

    private var outputWidthChoices: [Int] { [1920, 2560, 3840, 5120, 7680, 12_000] }

    private var backgroundPalette: some View {
        HStack(spacing: 8) {
            inspectorFieldLabel(t("export.background"))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                ForEach(StoryboardBackground.allCases) { background in
                    let isSelected = model.background == background
                    Button {
                        model.background = background
                    } label: {
                        StoryboardBackgroundSwatch(
                            color: storyboardBackgroundColor(background),
                            isSelected: isSelected,
                            accent: studioAccent,
                            checkColor: [.white, .ivory, .mist].contains(background) ? studioAccent : .white
                        )
                        .overlay(alignment: .trailing) {
                            if background != .cinema {
                                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: hairline)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.plain)
                    .disabled(model.isSettingsLocked)
                    .help(background.label(in: language))
                    .accessibilityLabel(background.label(in: language))
                    .accessibilityValue(isSelected ? t("accessibility.selected") : "")
                }
            }
            .frame(width: inspectorValueColumnWidth, height: StudioLayout.controlHeight)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: hairline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("export.background"))
    }

    private func storyboardBackgroundColor(_ background: StoryboardBackground) -> Color {
        let rgb = background.rgb
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// Equal-width connected chips keep all six canvases readable in the
    /// narrow inspector. The check and inset outline do not change geometry.
    private struct StoryboardBackgroundSwatch: View {
        let color: Color
        let isSelected: Bool
        let accent: Color
        let checkColor: Color

        var body: some View {
            Rectangle()
                .fill(color)
                .frame(maxWidth: .infinity)
                .frame(height: StudioLayout.controlHeight)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(accent, lineWidth: 2)
                            .padding(2)
                        ProjectIcon(symbol: .check, size: 12)
                            .foregroundStyle(checkColor)
                    }
                }
                .contentShape(Rectangle())
        }
    }

    private func queuePanel(compact: Bool, isNarrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                ProjectIcon(symbol: .videoImport, size: 13)
                    .foregroundStyle(studioAccent)
                Text(t("queue.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                Text("\(model.videoJobs.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button(action: model.chooseVideo) {
                    ProjectIcon(symbol: .plus, size: 14)
                        .foregroundStyle(studioAccent)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isQueueLocked)
                .accessibilityLabel(t("queue.addAction"))
                .help(t("queue.addAction"))
            }
            .frame(height: 32)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(t("queue.count", model.videoJobs.count))

            if model.isImportingVideos {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(t("queue.importing"))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(t("button.cancel"), action: model.cancelVideoImport)
                        .buttonStyle(.borderless)
                }
                .font(.system(size: 11))
                .accessibilityIdentifier("video-import-progress")
            }

            VideoBatchCard(
                jobs: model.videoJobs,
                language: language,
                isTargeted: model.isDropTargeted,
                isLocked: model.isQueueLocked,
                isLightAppearance: isLightAppearance,
                isCompact: compact || isNarrow,
                choose: model.chooseVideo,
                clear: model.clearVideos
            )
            .frame(maxHeight: .infinity, alignment: .top)

        }
        .padding(.horizontal, StudioLayout.panelInset)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(sidebarFill)
    }

    private func controlPanel(compact: Bool, isNarrow _: Bool) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            Text(t("inspector.title"))
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, StudioLayout.panelInset)
                .frame(height: 40, alignment: .leading)

            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    storyboardGridPicker(compact: compact)

                    inspectorSection(title: t("section.frame"), glyph: .frame, compact: compact) {
                        VStack(spacing: 8) {
                            aspectSelector
                            widthSelector
                            backgroundPalette
                            inlineToggle(t("export.time"), isOn: $model.showTimestamps)
                            inlineToggle(t("export.title"), isOn: $model.showTitleWatermark)
                        }
                    }

                    inspectorSection(title: t("section.export"), glyph: .export, compact: compact, showsDivider: false) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(t("export.autosave"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                ForEach(ExportFormat.allCases) { format in
                                    Button {
                                        model.format = format
                                    } label: {
                                        Text(format.rawValue)
                                            .font(.system(size: 12, weight: .semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, compact ? 6 : 8)
                                    }
                                    .buttonStyle(GridChoiceStyle(isSelected: model.format == format))
                                    .disabled(model.isSettingsLocked)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, StudioLayout.panelInset)
                .padding(.bottom, 12)
            }

            if model.hasFailedJobs && !model.isProcessing {
                workspaceRule
            }
            VStack(spacing: 8) {
                if model.hasFailedJobs && !model.isProcessing {
                    HStack(spacing: 8) {
                        if model.hasRetryableFailedJobs {
                            Button {
                                model.retryFailedJobs()
                            } label: {
                                GlyphLabel(title: t("button.retryFailed", model.retryableFailedJobCount), glyph: .refresh, glyphSize: 13)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(ProcessingControlButtonStyle(tone: .primary))
                        }

                        Button {
                            isFailureReportPresented = true
                        } label: {
                            GlyphLabel(title: t("button.failureDetails"), glyph: .eye, glyphSize: 13)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(ProcessingControlButtonStyle(tone: .secondary))
                    }
                }
            }
            .padding(.horizontal, StudioLayout.panelInset)
            .padding(.vertical, model.hasFailedJobs && !model.isProcessing ? 10 : 0)
        }
        .background(sidebarFill)
    }

    /// The panel heading already establishes this as storyboard settings, so a
    /// second "Storyboard grid" heading adds visual noise.  The picker itself
    /// communicates the setting through a compact visual preview instead.
    private func storyboardGridPicker(compact: Bool) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
        ) {
            ForEach(StoryboardGrid.availableSides, id: \.self) { side in
                Button {
                    model.gridSide = side
                } label: {
                    StoryboardGridChoiceLabel(
                        side: side,
                        isSelected: model.gridSide == side
                    )
                }
                .buttonStyle(StoryboardGridChoiceStyle(isSelected: model.gridSide == side))
                .disabled(model.isSettingsLocked)
                .accessibilityLabel("\(side) × \(side)")
            }
        }
        .padding(.top, compact ? 8 : 10)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(workspaceDivider.opacity(0.72))
                .frame(height: hairline)
        }
    }

    private func inspectorSection<SectionContent: View>(
        title: String,
        glyph: ProjectIcon.Symbol,
        compact: Bool,
        showsDivider: Bool = true,
        @ViewBuilder content: () -> SectionContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ProjectIcon(symbol: glyph, size: 13)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(workspaceDivider.opacity(0.72))
                    .frame(height: hairline)
            }
        }
    }

    private func inspectorFieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
    }

    private func inlineToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            inspectorFieldLabel(title)
                .lineLimit(2)
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(SelectionPalette.active)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .disabled(model.isSettingsLocked)
    }

    private var batchStatusBar: some View {
        HStack(spacing: 12) {
            if model.isProcessing {
                ProgressView(value: model.progress)
                    .tint(studioAccent)
                    .frame(width: 150)
                    .accessibilityLabel(t("accessibility.analyzing"))
                    .accessibilityValue("\(Int(model.progress * 100))%")
                Text(model.previewStatus)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    if model.isPaused {
                        isResumeConfirmationPresented = true
                    } else if !model.isPauseRequested {
                        isPauseConfirmationPresented = true
                    }
                } label: {
                    GlyphLabel(
                        title: model.isPaused ? t("button.resumeGeneration") : (model.isPauseRequested ? t("button.pausePending") : t("button.pauseGeneration")),
                        glyph: model.isPaused ? .play : .pause,
                        glyphSize: 13
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
                .buttonStyle(ProcessingControlButtonStyle(tone: .primary))
                .disabled(model.isPauseRequested && !model.isPaused)

                Button {
                    isCancelConfirmationPresented = true
                } label: {
                    GlyphLabel(title: t("button.cancelGeneration"), glyph: .trash, glyphSize: 13)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .buttonStyle(ProcessingControlButtonStyle(tone: .destructive))
            } else {
                GlyphLabel(title: t("batch.failureSummary", model.failedJobCount), glyph: .eye, glyphSize: 14)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    isFailureReportPresented = true
                } label: {
                    GlyphLabel(title: t("button.failureDetails"), glyph: .eye, glyphSize: 13)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .buttonStyle(ProcessingControlButtonStyle(tone: .secondary))
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .background(sidebarFill)
    }

    private var previewPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(t("preview.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PreviewText.primary)
                    .fixedSize()
                Spacer(minLength: 0)
                Text(model.previewStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(PreviewText.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(model.previewStatus)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .layoutPriority(-1)
                if !model.isProcessing && model.previewImage != nil {
                    fileActions
                        .fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .frame(height: StudioLayout.previewHeaderHeight)
            .background(appBackground)

            workspaceRule

            Group {
                if model.showsProgressivePreview {
                    ProgressiveStoryboardPreview(
                        gridSide: model.activeGridSide,
                        cardAspectRatio: model.activeCardAspectRatio,
                        language: language,
                        frames: model.livePreviewFrames,
                        processingLabel: model.processingLabel,
                        isLightAppearance: isLightAppearance
                    )
                } else if let image = model.previewImage {
                    StoryboardCanvas(image: image, isLightAppearance: isLightAppearance, language: language,
                                     savedURL: model.isLoadingPreview ? nil : model.lastSavedURL)
                } else {
                    EmptyPreview(language: language, isLightAppearance: isLightAppearance)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .background {
                // Keep the window bridge alive when the image disappears, so
                // clearing a result or an unprocessed queue can restore it.
                PreviewWindowAutoFitProbe(
                    fitter: previewAutoFitter,
                    request: previewWindowAutoFitRequest,
                    isEnabled: !model.isLoadingPreview && !model.isBusy,
                    queueResetID: model.queueResetID
                )
            }

        }
        .background(stageFill)
    }

    private var previewWindowAutoFitRequest: PreviewWindowAutoFitRequest? {
        guard !model.isProcessing, let image = model.previewImage,
              model.completedPreviews.indices.contains(model.selectedPreviewIndex) else { return nil }
        let preview = model.completedPreviews[model.selectedPreviewIndex]
        return PreviewWindowAutoFitRequest(
            sourceID: preview.id.uuidString,
            aspectRatio: Double(image.size.width / max(1, image.size.height)),
            layoutAspect: preview.settings.layoutAspect,
            panels: PreviewWindowPanelConfiguration(queueVisible: showsQueue, inspectorVisible: showsInspector)
        )
    }

    private var localPrivacyCaption: some View {
        GlyphLabel(title: t("queue.localTitle"), glyph: .privacy, glyphSize: 11)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(t("queue.localTitle"))
    }

    private var previewActions: some View {
        // Equal side columns keep the page controls at the window's actual
        // centre even when translated file actions have different lengths.
        GeometryReader { geometry in
            let sideWidth = max(0, (geometry.size.width - StudioLayout.resultPagerWidth) / 2)
            HStack(spacing: 0) {
                localPrivacyCaption
                    .frame(width: sideWidth, alignment: .leading)

                StoryboardResultPager(
                    position: model.selectedPreviewNumber, count: model.completedPreviews.count,
                    canGoBack: model.canShowPreviousPreview && !model.isApplyingFrameAdjustments,
                    canGoForward: model.canShowNextPreview && !model.isApplyingFrameAdjustments,
                    language: language,
                    previous: model.showPreviousPreview, next: model.showNextPreview
                )

                Button {
                    manualFrameEditorRequest = model.manualEditorRequest
                } label: {
                    GlyphLabel(title: t("button.adjustFrames.short"), glyph: .frameSelect, glyphSize: 15)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, geometry.size.width < 600 ? 8 : 14)
                        .frame(height: 34)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.manualEditorRequest == nil)
                .help(t("button.adjustFrames.hint"))
                .accessibilityLabel(t("button.adjustFrames"))
                .accessibilityIdentifier("manual-frame-selection")
                .frame(width: sideWidth, alignment: .trailing)
            }
            .frame(height: geometry.size.height)
        }
    }

    private var fileActions: some View {
        HStack(spacing: 0) {
            if model.lastSavedURL != nil {
                Button(action: model.revealLastSavedResult) {
                    GlyphLabel(title: t("button.openSaved"), glyph: .folderCheck, glyphSize: 13)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(studioAccent)
                }
                .buttonStyle(.borderless)
                .help(t("button.openSaved.hint"))
            } else {
                Button(action: model.exportCurrentResult) {
                    GlyphLabel(title: t("button.saveas", (model.renderedFormat ?? model.format).rawValue), glyph: .save, glyphSize: 13)
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(model.isLoadingPreview)
            }

        }
    }
}
