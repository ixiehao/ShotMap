import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model: StoryboardViewModel
    @EnvironmentObject private var updateChecker: UpdateChecker
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("appLanguage") private var languageCode = AppLanguage.chinese.rawValue
    @AppStorage("appAppearance") private var appearanceCode = AppAppearance.system.rawValue
    @State private var isLanguagePickerPresented = false
    @State private var isAppearancePickerPresented = false
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
        AppLanguage(rawValue: languageCode) ?? .chinese
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceCode) ?? .system
    }

    private var resolvedAppearance: AppAppearance {
        appearance == .system ? (systemColorScheme == .light ? .light : .dark) : appearance
    }

    private var isLightAppearance: Bool { resolvedAppearance == .light }

    // Frame Desk is intentionally quiet: neutral surfaces make video frames,
    // selection state, and one primary action easier to scan at a glance.
    // Values are paired for light and dark appearances instead of relying on
    // the system control palette, which also keeps the three panes cohesive.
    private var appBackground: Color {
        isLightAppearance
            ? Color(red: 0.969, green: 0.973, blue: 0.980) // #F7F8FA
            : Color(red: 0.063, green: 0.075, blue: 0.090) // #101317
    }

    private var sidebarFill: Color {
        isLightAppearance
            ? Color(red: 0.945, green: 0.961, blue: 0.976) // #F1F5F9
            : Color(red: 0.082, green: 0.102, blue: 0.129) // #151A21
    }

    private var stageFill: Color {
        isLightAppearance
            ? Color.white
            : Color(red: 0.090, green: 0.106, blue: 0.133) // #171B22
    }

    private var workspaceDivider: Color {
        isLightAppearance
            ? Color(red: 0.843, green: 0.871, blue: 0.910) // #D7DEE8
            : Color(red: 0.224, green: 0.271, blue: 0.329) // #394554
    }

    private var studioAccent: Color {
        isLightAppearance
            ? Color(red: 0.039, green: 0.400, blue: 0.851) // #0A66D9
            : Color(red: 0.353, green: 0.655, blue: 1.0) // #5AA7FF
    }

    private var inlineControlFill: Color {
        isLightAppearance
            ? Color.white
            : Color(red: 0.114, green: 0.137, blue: 0.173) // #1D232C
    }

    private func t(_ key: String, _ arguments: CVarArg...) -> String {
        language.text(key, arguments: arguments)
    }

    var body: some View {
        GeometryReader { geometry in
            let isCompactHeight = geometry.size.height < 700
            let isNarrow = geometry.size.width < 1_090
            let queueWidth: CGFloat = isNarrow ? 250 : 266
            let inspectorWidth: CGFloat = isNarrow ? 250 : 270

            VStack(spacing: 0) {
                studioToolbar(queueWidth: queueWidth)
                    // The brand block is already offset for the traffic lights;
                    // keep the toolbar in the native title-bar rhythm instead
                    // of reserving a second, empty title-bar-height strip.
                    .padding(.top, 8)
                    .padding(.horizontal, StudioLayout.toolbarHorizontalInset)
                    .padding(.bottom, 10)

                if updateChecker.hasUpdate {
                    UpdateAvailableBanner(checker: updateChecker, language: language)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                }

                Rectangle()
                    .fill(workspaceDivider)
                    .frame(height: 1)

                HStack(spacing: 0) {
                    queuePanel(compact: isCompactHeight, isNarrow: isNarrow)
                        .frame(width: queueWidth)
                        .frame(maxHeight: .infinity)

                    Rectangle()
                        .fill(workspaceDivider)
                        .frame(width: 1)

                    previewPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Rectangle()
                        .fill(workspaceDivider)
                        .frame(width: 1)

                    controlPanel(compact: isCompactHeight, isNarrow: isNarrow)
                        .frame(width: inspectorWidth)
                        .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if model.isProcessing || model.hasFailedJobs {
                    Rectangle()
                        .fill(workspaceDivider)
                        .frame(height: 1)
                    batchStatusBar
                }
            }
            .background(appBackground)
        }
        .environment(\.locale, language.locale)
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
            model.language = AppLanguage(rawValue: newValue) ?? .chinese
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
            Button(t("button.cancelGenerationConfirm"), role: .destructive) { model.cancelGeneration() }
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
                onApply: { request, frames in
                    model.applyManuallySelectedFrames(
                        frames,
                        targetPreviewID: request.previewID,
                        sourceURL: request.sourceURL,
                        duration: request.duration
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

    private func studioToolbar(queueWidth: CGFloat) -> some View {
        // This surface uses the exact same x-coordinate as the first column
        // divider below. It must not depend on the natural width of the brand.
        let queueBoundary = queueWidth - StudioLayout.toolbarHorizontalInset

        return ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    ShotMapMark(language: language, size: 28)
                    Text("ShotMap")
                        .font(.system(size: 18, weight: .semibold))
                }
                // The left inset leaves macOS traffic lights unobstructed in the
                // hidden-title-bar window. The frame ends at the column boundary.
                .padding(.leading, 88)
                .frame(width: queueBoundary, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    Text(t("app.productName"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(t("app.tagline"))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .padding(.leading, 10)
            }

            HStack(spacing: 8) {
                appearanceMenu
                languageMenu
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            Rectangle()
                .fill(workspaceDivider)
                .frame(width: 1, height: 26)
                .offset(x: queueBoundary)
        }
    }

    private func headerControlLabel(symbol: ProjectIcon.Symbol, title: String) -> some View {
        HStack(spacing: 6) {
            ProjectIcon(symbol: symbol, size: 15)
                .foregroundStyle(studioAccent)
            Text(title)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            ProjectIcon(symbol: .disclosure, size: 8)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .medium))
        .frame(width: 98, height: StudioLayout.toolbarControlHeight)
        .contentShape(RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
        .background(inlineControlFill.opacity(isLightAppearance ? 0.68 : 0.84), in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous).strokeBorder(workspaceDivider.opacity(0.82)) }
    }

    private var appearanceMenu: some View {
        Button {
            isAppearancePickerPresented.toggle()
        } label: {
            headerControlLabel(symbol: appearanceSymbol, title: appearance.displayName(in: language))
        }
        .buttonStyle(.plain)
        .frame(width: 98, height: StudioLayout.toolbarControlHeight)
        .accessibilityLabel(t("app.appearance"))
        // Open beneath the top toolbar. An upward popover is clipped whenever
        // the window sits against the top edge of the display.
        .popover(isPresented: $isAppearancePickerPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t("app.appearance"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)

                ForEach(AppAppearance.allCases) { choice in
                    Button {
                        appearanceCode = choice.rawValue
                        isAppearancePickerPresented = false
                    } label: {
                        HStack {
                            Text(choice.displayName(in: language))
                            Spacer()
                            if choice == appearance {
                                ProjectIcon(symbol: .check, size: 14)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(choice == appearance ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .contentShape(Rectangle())
                }
            }
            .padding(8)
            .frame(width: 156)
        }
    }

    private var appearanceSymbol: ProjectIcon.Symbol {
        resolvedAppearance == .dark ? .moon : .appearance
    }

    private var languageMenu: some View {
        Button {
            isLanguagePickerPresented.toggle()
        } label: {
            headerControlLabel(symbol: .language, title: language.displayName)
        }
        .buttonStyle(.plain)
        .frame(width: 98, height: StudioLayout.toolbarControlHeight)
        .accessibilityLabel(t("app.language"))
        .popover(isPresented: $isLanguagePickerPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t("app.language"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)

                ForEach(AppLanguage.allCases) { choice in
                    Button {
                        languageCode = choice.rawValue
                        isLanguagePickerPresented = false
                    } label: {
                        HStack {
                            Text(choice.displayName)
                            Spacer()
                            if choice == language {
                                ProjectIcon(symbol: .check, size: 14)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(choice == language ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .contentShape(Rectangle())
                }
            }
            .padding(8)
            .frame(width: 156)
        }
    }

    private var aspectSelector: some View {
        Button {
            isAspectPickerPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(t("section.aspect"))
                    .font(.system(size: 11, weight: .medium))
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
                .frame(width: 154, height: StudioLayout.controlHeight)
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
                Text(t("export.width"))
                    .font(.system(size: 11, weight: .medium))
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
                .frame(width: 154, height: StudioLayout.controlHeight)
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
        // Keep this row intrinsically smaller than the narrowest inspector.
        // The English label used to sit beside six 28 pt targets, giving the
        // row a wider minimum than its 250 pt inspector and letting the final
        // swatch render past the window edge.
        HStack(spacing: 8) {
            Text(t("export.background"))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                ForEach(StoryboardBackground.allCases) { background in
                    let isSelected = model.background == background
                    Button {
                        model.background = background
                    } label: {
                        StoryboardBackgroundSwatch(
                            color: storyboardBackgroundColor(background),
                            isSelected: isSelected,
                            accent: studioAccent
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSettingsLocked)
                    .help(background.label(in: language))
                    .accessibilityLabel(background.label(in: language))
                    .accessibilityValue(isSelected ? t("accessibility.selected") : "")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("export.background"))
    }

    private func storyboardBackgroundColor(_ background: StoryboardBackground) -> Color {
        let rgb = background.rgb
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// Keep the visible colour chip separate from its selected ring. The old
    /// heavy outline sat on top of the chip, which made compact palette edges
    /// look uneven. This gives the ring a small, intentional breathing space.
    private struct StoryboardBackgroundSwatch: View {
        let color: Color
        let isSelected: Bool
        let accent: Color

        var body: some View {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(accent.opacity(0.10))
                        .frame(width: 26, height: 26)
                    Circle()
                        .strokeBorder(accent, lineWidth: 1.5)
                        .frame(width: 26, height: 26)
                }

                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.75)
                    }
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
            .shadow(color: .black.opacity(isSelected ? 0.15 : 0.10), radius: isSelected ? 2 : 1, y: 1)
        }
    }

    private func queuePanel(compact: Bool, isNarrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 9) {
                    ProjectIcon(symbol: .videoImport, size: 16)
                        .foregroundStyle(studioAccent)
                        .frame(width: 30, height: 30)
                        .background(studioAccent.opacity(isLightAppearance ? 0.12 : 0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: StudioLayout.titleSubtitleGap) {
                        Text(t("queue.title"))
                            .font(.system(size: 17, weight: .semibold))
                        Text(t("queue.count", model.videoJobs.count))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Button(action: model.chooseVideo) {
                    ProjectIcon(symbol: .plus, size: 15)
                        .foregroundStyle(.white)
                        .frame(width: StudioLayout.primaryControlHeight, height: StudioLayout.primaryControlHeight)
                        .background(studioAccent, in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.isQueueLocked)
                .accessibilityLabel(t("queue.addAction"))
                .help(t("queue.addAction"))
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

            VStack(alignment: .leading, spacing: 5) {
                GlyphLabel(title: t("queue.localTitle"), glyph: .privacy, glyphSize: 17)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, StudioLayout.panelInset)
        .padding(.vertical, compact ? 12 : StudioLayout.panelTitleTop)
        .background(sidebarFill)
    }

    private func controlPanel(compact: Bool, isNarrow _: Bool) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                ProjectIcon(symbol: .sliders, size: 16)
                    .foregroundStyle(studioAccent)
                    .frame(width: 30, height: 30)
                .background(studioAccent.opacity(isLightAppearance ? 0.12 : 0.18), in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
                Text(t("inspector.title"))
                    .font(.system(size: 17, weight: .semibold))
            }
                .padding(.horizontal, StudioLayout.panelInset)
                .padding(.top, compact ? 12 : StudioLayout.panelTitleTop)
                .padding(.bottom, compact ? 8 : 12)

            ScrollView(showsIndicators: false) {
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
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
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

            Rectangle()
                .fill(workspaceDivider)
                .frame(height: 1)

            VStack(spacing: 8) {
                if !model.isProcessing {
                    Button(action: model.generate) {
                        GlyphLabel(title: model.primaryButtonTitle, glyph: .filmStack, glyphSize: 18)
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!model.hasVideos || model.isBusy)
                    .accessibilityLabel(t("accessibility.generate"))
                } else {
                    GlyphLabel(title: model.processingLabel, glyph: .refreshCandidates, glyphSize: 15)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

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
            .padding(.vertical, compact ? 12 : 16)
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
                .frame(height: 1)
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
            HStack(spacing: 7) {
                ProjectIcon(symbol: glyph, size: 14)
                    .foregroundStyle(studioAccent)
                    .frame(width: 24, height: 24)
                    .background(studioAccent.opacity(isLightAppearance ? 0.11 : 0.17), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            content()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(workspaceDivider.opacity(0.72))
                    .frame(height: 1)
            }
        }
    }

    private func inlineToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
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

    private func previewNavigationButton(
        symbol: ProjectIcon.Symbol,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ProjectIcon(symbol: symbol, size: 20)
                .frame(width: 36, height: 44)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(navigationForeground(enabled: enabled))
        .background(
            isLightAppearance
                ? Color.white.opacity(enabled ? 0.98 : 0.76)
                : Color(red: 0.094, green: 0.157, blue: 0.224).opacity(enabled ? 0.98 : 0.72),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(
                isLightAppearance
                    ? Color(red: 0.71, green: 0.81, blue: 0.85).opacity(enabled ? 1 : 0.62)
                    : Color(red: 0.29, green: 0.38, blue: 0.46).opacity(enabled ? 1 : 0.6)
            )
        }
        .shadow(color: isLightAppearance && enabled ? Color.black.opacity(0.10) : .clear, radius: 4, y: 2)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func navigationForeground(enabled: Bool) -> Color {
        guard enabled else {
            return isLightAppearance
                ? Color(red: 0.47, green: 0.55, blue: 0.59)
                : Color(red: 0.43, green: 0.51, blue: 0.58)
        }
        return isLightAppearance
            ? Color(red: 0.14, green: 0.35, blue: 0.42)
            : Color(red: 0.95, green: 0.98, blue: 1.0)
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
        .frame(height: 54)
        .background(sidebarFill)
    }

    private var previewPanel: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                HStack(alignment: .top, spacing: 9) {
                    ProjectIcon(symbol: .filmStack, size: 16)
                        .foregroundStyle(studioAccent)
                        .frame(width: 30, height: 30)
                        .background(studioAccent.opacity(isLightAppearance ? 0.12 : 0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: StudioLayout.titleSubtitleGap) {
                        Text(t("preview.title"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(PreviewText.primary)
                        Text(model.previewStatus)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(PreviewText.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .help(model.previewStatus)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, StudioLayout.panelInset)
            .padding(.top, StudioLayout.panelTitleTop)
            .padding(.bottom, 10)
            .frame(height: StudioLayout.panelHeaderHeight, alignment: .topLeading)

            Rectangle()
                .fill(workspaceDivider)
                .frame(height: 1)

            Group {
                if model.isProcessing {
                    ProgressiveStoryboardPreview(
                        gridSide: model.activeGridSide,
                        cardAspectRatio: model.activeCardAspectRatio,
                        language: language,
                        frames: model.livePreviewFrames,
                        isLightAppearance: isLightAppearance
                    )
                } else if let image = model.previewImage {
                    VStack(spacing: 14) {
                        ZStack {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 560)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .shadow(color: .black.opacity(0.28), radius: 24, y: 12)

                            if model.canBrowseCompletedPreviews {
                                HStack {
                                    previewNavigationButton(
                                        symbol: .previous,
                                        label: t("button.previousResult"),
                                        enabled: model.canShowPreviousPreview && !model.isApplyingFrameAdjustments,
                                        action: model.showPreviousPreview
                                    )
                                    Spacer(minLength: 0)
                                    previewNavigationButton(
                                        symbol: .next,
                                        label: t("button.nextResult"),
                                        enabled: model.canShowNextPreview && !model.isApplyingFrameAdjustments,
                                        action: model.showNextPreview
                                    )
                                }
                                .padding(.horizontal, 12)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        if model.canBrowseCompletedPreviews {
                            Text(t("preview.position", model.selectedPreviewNumber, model.completedPreviews.count))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(PreviewText.secondary)
                        }

                        HStack(spacing: 10) {
                            if model.lastSavedURL != nil {
                                Button(action: model.revealLastSavedResult) {
                                    GlyphLabel(title: t("button.openSaved"), glyph: .folderCheck)
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .frame(height: 38)
                                }
                                .buttonStyle(SavedResultButtonStyle())
                                .help(t("button.openSaved.hint"))
                            } else {
                                Button(action: model.exportCurrentResult) {
                                    GlyphLabel(title: t("button.saveas", (model.renderedFormat ?? model.format).rawValue), glyph: .save)
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .frame(height: 38)
                                }
                                .buttonStyle(ExportButtonStyle())
                                .disabled(model.isLoadingPreview)
                            }

                            if let request = model.manualEditorRequest {
                                Button {
                                    manualFrameEditorRequest = request
                                } label: {
                                    GlyphLabel(title: t("button.adjustFrames"), glyph: .frameSelect)
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(.horizontal, 16)
                                        .frame(minWidth: 202, minHeight: 38, maxHeight: 38)
                                }
                                .buttonStyle(ManualAdjustmentButtonStyle())
                                .help(t("button.adjustFrames.hint"))
                                .accessibilityIdentifier("manual-frame-selection")
                            }
                        }
                    }
                } else {
                    EmptyPreview(language: language, isLightAppearance: isLightAppearance)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(18)
        }
        .background(stageFill)
    }
}
