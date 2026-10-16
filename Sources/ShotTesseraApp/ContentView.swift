import AppKit
@preconcurrency import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers

/// Shared, whole-point measurements for the three-column studio.
/// Keeping structural values here prevents subtle baseline drift between panels.
private enum StudioLayout {
    static let panelInset: CGFloat = 16
    static let panelTitleTop: CGFloat = 16
    static let titleSubtitleGap: CGFloat = 4
    static let panelHeaderHeight: CGFloat = 76
    static let toolbarHorizontalInset: CGFloat = 20
    static let controlHeight: CGFloat = 32
    static let toolbarControlHeight: CGFloat = 28
    static let primaryControlHeight: CGFloat = 36
    static let controlCornerRadius: CGFloat = 8
    static let panelCornerRadius: CGFloat = 12
}

/// Measurements for the dedicated manual editor.  Keep this separate from
/// Batch Studio: it is a dense editing desk with a fixed visual rhythm, not a
/// three-panel form.  Values are whole points so separators and baselines land
/// on physical pixels at the standard macOS scale.
private enum ManualEditorLayout {
    static let toolbarHeight: CGFloat = 54
    static let horizontalInset: CGFloat = 24
    static let workspaceVerticalInset: CGFloat = 12
    static let workspaceGap: CGFloat = 28
    static let mediaHeight: CGFloat = 238
    static let candidateGap: CGFloat = 12
    static let candidateHeaderTop: CGFloat = 15
    static let candidateHeaderBottom: CGFloat = 10
    static let candidateGridBottom: CGFloat = 16
    static let footerHeight: CGFloat = 62
    static let compactControlHeight: CGFloat = 34
    static let toolbarControlHeight: CGFloat = 32
}

private struct ManualFrameEditorRequest: Identifiable {
    let id = UUID()
    let previewID: RenderedStoryboardPreview.ID
    let sourceURL: URL
    let selectionLimit: Int
    let duration: Double
    let outputWidth: Int
}

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

fileprivate struct LivePreviewFrame: Identifiable {
    let id = UUID()
    let image: NSImage
}

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
        HStack(spacing: 7) {
            Text(t("export.background"))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                ForEach(StoryboardBackground.allCases) { background in
                    let isSelected = model.background == background
                    Button {
                        model.background = background
                    } label: {
                        Circle()
                            .fill(storyboardBackgroundColor(background))
                            .frame(width: 20, height: 20)
                            .overlay {
                                Circle().strokeBorder(
                                    isSelected ? studioAccent : Color.primary.opacity(0.22),
                                    lineWidth: isSelected ? 3 : 1
                                )
                            }
                            .shadow(
                                color: .black.opacity(0.20),
                                radius: isSelected ? 3 : 1,
                                y: 1
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSettingsLocked)
                    .help(background.label(in: language))
                    .accessibilityLabel(background.label(in: language))
                    .accessibilityValue(isSelected ? t("accessibility.selected") : "")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("export.background"))
    }

    private func storyboardBackgroundColor(_ background: StoryboardBackground) -> Color {
        let rgb = background.rgb
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
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

@MainActor
final class StoryboardViewModel: ObservableObject {
    @Published private(set) var videoJobs: [VideoJob] = []
    @Published var language: AppLanguage = .chinese
    @Published var gridSide = 4
    @Published var layoutAspect: StoryboardAspect = .source
    @Published var format: ExportFormat = .png
    @Published var width = 2560
    @Published var background: StoryboardBackground = .cinema
    @Published var showTimestamps = false
    @Published var showTitleWatermark = false
    @Published var previewImage: NSImage?
    @Published fileprivate private(set) var livePreviewSlots = ProgressivePreviewSlots<LivePreviewFrame>()
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
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var outputDescription = ""
    private var completedBatchDescription: String?
    private var completedBatchCounts: (completed: Int, failed: Int)?
    @Published var renderedFormat: ExportFormat?
    @Published private(set) var lastSavedURL: URL?
    @Published private(set) var isApplyingFrameAdjustments = false
    @Published private(set) var completedPreviews: [RenderedStoryboardPreview] = []
    @Published private(set) var selectedPreviewIndex = 0
    @Published private(set) var isLoadingPreview = false
    fileprivate var generationTask: Task<Void, Never>?
    private var generationRunID = UUID()
    private var generationControl: BatchRunControl?
    private var pendingData: Data?
    private var pendingSource: URL?
    private var pendingFormat: ExportFormat?
    private var previewImageStore = PreviewImageStore()
    private var previewLoadID = UUID()

    private func t(_ key: String, _ arguments: CVarArg...) -> String {
        language.text(key, arguments: arguments)
    }

    var hasVideos: Bool { !videoJobs.isEmpty }
    fileprivate var livePreviewFrames: [LivePreviewFrame?] { livePreviewSlots.slots }
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
    fileprivate var manualEditorRequest: ManualFrameEditorRequest? {
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
        if let completedBatchCounts, outputDescription == completedBatchDescription {
            return completedBatchCounts.failed > 0
                ? t("status.batchCompletedWithFailures", completedBatchCounts.completed, completedBatchCounts.failed)
                : t("status.batchCompleted", completedBatchCounts.completed)
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
        videoJobs.append(contentsOf: additions)
        if supported.count < candidates.count {
            errorMessage = t("error.unsupportedInput")
            showError = true
        }
    }

    func clearVideos() {
        guard !isBusy else { return }
        videoJobs.removeAll()
        previewImage = nil
        livePreviewSlots.reset(total: 0)
        outputDescription = ""
        completedBatchDescription = nil
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
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                guard let url = DroppedVideoURL.decode(item) else { return }
                Task { @MainActor [weak self] in
                    self?.addVideos([url])
                }
            }
        }
        return true
    }

    func generate() {
        guard !videoJobs.isEmpty, !isBusy else { return }
        startGeneration(indices: Array(videoJobs.indices), resetPreviews: true)
    }

    func retryFailedJobs() {
        guard !isBusy else { return }
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
        let runID = UUID()
        generationRunID = runID
        isProcessing = true
        isPauseRequested = false
        isPaused = false
        progress = 0
        completedBatchDescription = nil
        completedBatchCounts = nil
        // Present the live grid immediately. This replaces a stale completed
        // image or a blank stage before the first AVFoundation decode returns.
        activeGridSide = gridSide
        activeUsesSourceAspect = layoutAspect == .source
        activeCardAspectRatio = layoutAspect.resolvedCardAspectRatio(sourceAspectRatio: nil)
        livePreviewSlots.reset(total: gridSide * gridSide)
        lastSavedURL = nil
        pendingData = nil
        pendingSource = nil
        pendingFormat = nil
        showError = false
        errorMessage = ""
        if resetPreviews {
            completedPreviews = []
            previewImageStore = PreviewImageStore()
            previewLoadID = UUID()
            isLoadingPreview = false
            selectedPreviewIndex = 0
            previewImage = nil
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
        outputDescription = t("status.cancelled")
        completedBatchDescription = nil
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

    fileprivate func markPausedAtCheckpoint() {
        isPaused = true
        isPauseRequested = false
        livePreviewSlots.reset(total: 0)
        outputDescription = t("status.paused")
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
        activeGridSide = gridSide
        activeUsesSourceAspect = layoutAspect == .source
        activeCardAspectRatio = layoutAspect.resolvedCardAspectRatio(sourceAspectRatio: nil)
        livePreviewSlots.reset(total: gridSide * gridSide)
        progress = 0
        if videoJobs.indices.contains(jobIndex) { videoJobs[jobIndex].state = .processing }
        outputDescription = t("status.nowProcessing", source.lastPathComponent)
    }

    func appendPreview(_ frame: CapturedFrame, index: Int, total: Int) {
        guard let image = NSImage(data: frame.jpegData) else { return }
        if activeUsesSourceAspect {
            activeCardAspectRatio = StoryboardAspect.source.resolvedCardAspectRatio(sourceAspectRatio: frame.aspectRatio)
        }
        var slots = livePreviewSlots
        guard slots.replace(LivePreviewFrame(image: image), at: index, total: total) else { return }
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
            outputDescription = t("status.generatedNotSaved", index + 1, total)
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
        outputDescription = t("status.failedContinue", index + 1)
    }

    func showSourceFiles(for jobs: [VideoJob]) {
        guard !jobs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(jobs.map(\.url))
    }

    func finishBatch() {
        isProcessing = false
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
        let description = failed > 0
            ? t("status.batchCompletedWithFailures", completed, failed)
            : t("status.batchCompleted", completed)
        completedBatchCounts = (completed, failed)
        completedBatchDescription = description
        outputDescription = description
    }

    func markCancelled() {
        isProcessing = false
        generationTask = nil
        generationControl = nil
        isPauseRequested = false
        isPaused = false
        livePreviewSlots.reset(total: 0)
        outputDescription = t("status.cancelled")
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
                    if let index = self.completedPreviews.firstIndex(where: { $0.id == targetPreviewID }) {
                        self.completedPreviews[index].savedURL = destination
                        let jobIndex = self.completedPreviews[index].jobIndex
                        if self.videoJobs.indices.contains(jobIndex) {
                            self.videoJobs[jobIndex].state = .completed(destination.lastPathComponent)
                        }
                        if index == self.selectedPreviewIndex {
                            self.lastSavedURL = destination
                            self.outputDescription = self.t("status.manualSaved", destination.lastPathComponent)
                        }
                    }
                } catch {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
        }
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

        Task.detached(priority: .userInitiated) {
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
        defer { isApplyingFrameAdjustments = false }
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
                outputDescription = t("status.manualSaved", savedURL.lastPathComponent)
            } else {
                outputDescription = t("status.generatedNotSaved", 1, 1)
            }
        }
    }

    fileprivate func markFrameEditFailed(_ message: String) {
        isApplyingFrameAdjustments = false
        errorMessage = message
        showError = true
    }

    private func selectPreview(at index: Int, presentation: PreparedPreviewPresentation? = nil) {
        guard completedPreviews.indices.contains(index) else { return }
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
            outputDescription = t("status.saved", preview.jobIndex + 1, preview.jobCount, savedURL.lastPathComponent)
        } else {
            outputDescription = t("status.generatedNotSaved", preview.jobIndex + 1, preview.jobCount)
        }
        if let presentation {
            applyPreviewPresentation(presentation)
            return
        }
        isLoadingPreview = true
        Task { @MainActor [weak self] in
            do {
                let presentation = try await Task.detached(priority: .userInitiated) {
                    try preview.loadPresentation()
                }.value
                guard let self, self.previewLoadID == loadID else { return }
                self.applyPreviewPresentation(presentation)
            } catch {
                guard let self, self.previewLoadID == loadID else { return }
                self.isLoadingPreview = false
                self.errorMessage = error.localizedDescription
                self.showError = true
            }
        }
    }

    private func applyPreviewPresentation(_ presentation: PreparedPreviewPresentation) {
        previewImage = NSImage(cgImage: presentation.image, size: .zero)
        pendingData = presentation.pendingData
        isLoadingPreview = false
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
        await MainActor.run { [weak self] in
            guard let self, let model = self.model, self.acceptsCurrentGeneration(model) else { return }
            model.appendPreview(frame, index: index, total: total)
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
            self?.model?.language ?? .chinese
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

/// Presents manual frame selection as a normal, movable and resizable macOS
/// window. A sheet is attached to the parent window and cannot be repositioned;
/// this small AppKit bridge keeps the editor independent without changing its
/// SwiftUI content or selection workflow.
private struct ManualFrameEditorWindowPresenter: NSViewRepresentable {
    @Binding var request: ManualFrameEditorRequest?
    @ObservedObject var model: StoryboardViewModel
    let language: AppLanguage
    let colorScheme: ColorScheme
    let onApply: (ManualFrameEditorRequest, [CapturedFrame]) -> Void

    func makeNSView(context: Context) -> HostView {
        HostView()
    }

    func updateNSView(_ nsView: HostView, context: Context) {
        nsView.update(
            request: $request,
            model: model,
            language: language,
            colorScheme: colorScheme,
            onApply: onApply
        )
    }

    final class HostView: NSView, NSWindowDelegate {
        private var currentRequestID: UUID?
        private weak var editorWindow: NSWindow?
        private var requestBinding: Binding<ManualFrameEditorRequest?>?
        private var editorConfiguration: ManualFrameEditorConfiguration?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(
            request: Binding<ManualFrameEditorRequest?>,
            model: StoryboardViewModel,
            language: AppLanguage,
            colorScheme: ColorScheme,
            onApply: @escaping (ManualFrameEditorRequest, [CapturedFrame]) -> Void
        ) {
            requestBinding = request
            guard let requestValue = request.wrappedValue else {
                closeEditor()
                return
            }
            guard currentRequestID != requestValue.id || editorWindow == nil else {
                editorWindow?.appearance = Self.appKitAppearance(for: colorScheme)
                editorWindow?.title = language.text("editor.title")
                editorConfiguration?.colorScheme = colorScheme
                editorConfiguration?.language = language
                if editorWindow?.isMiniaturized == true {
                    editorWindow?.deminiaturize(nil)
                }
                NSApplication.shared.activate(ignoringOtherApps: true)
                editorWindow?.makeKeyAndOrderFront(nil)
                return
            }

            closeEditor()
            currentRequestID = requestValue.id
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1_280, height: 800),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = language.text("editor.title")
            // This is a separate NSWindow, so it does not automatically inherit
            // ContentView's preferredColorScheme. Set its AppKit appearance as
            // well as the hosted SwiftUI preference to keep the entire editor—
            // title bar, surfaces and controls—in sync with Batch Studio.
            window.appearance = Self.appKitAppearance(for: colorScheme)
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.minSize = NSSize(width: 1_000, height: 680)
            window.contentMinSize = NSSize(width: 1_000, height: 680)
            window.maxSize = NSSize(width: 16_384, height: 16_384)
            // Keep a deliberately resized/repositioned editor where the person
            // left it.  Falling back to the centre only on a first launch also
            // prevents a manual editor from reopening partly off-screen.
            let autosaveName = "ShotTesseraManualFrameEditor"
            window.setFrameAutosaveName(autosaveName)
            if !window.setFrameUsingName(autosaveName) {
                window.center()
            }
            window.delegate = self
            let configuration = ManualFrameEditorConfiguration(
                colorScheme: colorScheme,
                language: language
            )
            editorConfiguration = configuration
            window.contentView = NSHostingView(
                rootView: ManualFrameEditor(
                    model: model,
                    sourceURL: requestValue.sourceURL,
                    selectionLimit: requestValue.selectionLimit,
                    duration: requestValue.duration,
                    outputWidth: requestValue.outputWidth,
                    configuration: configuration,
                    onClose: { [weak self] in self?.closeEditor() }
                ) { [weak self] frames in
                    onApply(requestValue, frames)
                    self?.closeEditor()
                }
            )
            editorWindow = window
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        private static func appKitAppearance(for colorScheme: ColorScheme) -> NSAppearance? {
            NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        }

        func windowWillClose(_ notification: Notification) {
            currentRequestID = nil
            editorWindow = nil
            editorConfiguration = nil
            requestBinding?.wrappedValue = nil
        }

        fileprivate func closeEditor() {
            guard let window = editorWindow else {
                currentRequestID = nil
                requestBinding?.wrappedValue = nil
                return
            }
            editorWindow = nil
            currentRequestID = nil
            editorConfiguration = nil
            window.delegate = nil
            window.close()
            requestBinding?.wrappedValue = nil
        }
    }
}

/// A hosted editor window does not automatically receive the parent SwiftUI
/// environment after it has been created. Keep the dynamic preferences in an
/// observable value so an open editor updates without rebuilding the view and
/// losing a person's in-progress selection.
@MainActor
private final class ManualFrameEditorConfiguration: ObservableObject {
    @Published var colorScheme: ColorScheme
    @Published var language: AppLanguage

    init(colorScheme: ColorScheme, language: AppLanguage) {
        self.colorScheme = colorScheme
        self.language = language
    }
}

private struct ManualFrameEditor: View {
    @Environment(\.colorScheme) private var colorScheme
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
    @State private var previewTime = 0.0
    @State private var previewTimeText = "00:00:00.000"
    @State private var previewFrame: CapturedFrame?
    @State private var isLoadingPreviewFrame = false
    @State private var isRefiningCurrentFrame = false
    @State private var isRefiningSelectedFrames = false
    @State private var previewCaptureTask: Task<Void, Never>?
    @State private var selectedFrameRefinementTask: Task<[CapturedFrame], Error>?
    @State private var applyPresentationTask: Task<Void, Never>?
    @State private var selectedFrameRefinementToken: UUID?
    @State private var operationError = ""
    @State private var player: AVPlayer?
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
        // The observable configuration keeps this independent AppKit window in
        // sync with the parent workspace even while it remains open.
        .environment(\.colorScheme, configuration.colorScheme)
        .preferredColorScheme(configuration.colorScheme)
        .onAppear {
            loadCandidates()
            prepareVideoPreview()
        }
        .onDisappear(perform: cancelBackgroundWork)
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
            .disabled(isLoadingCandidates || candidates.isEmpty || isSmartSelecting)
            .accessibilityIdentifier("manual-frame-smart-select")

            Button(action: regenerateCandidates) {
                GlyphLabel(title: t("editor.regenerate"), glyph: .refreshCandidates, glyphSize: 16)
                    .font(.system(size: 13, weight: .medium))
                    .frame(height: ManualEditorLayout.toolbarControlHeight)
                    .padding(.horizontal, 9)
            }
            .buttonStyle(ManualFrameEditorActionButtonStyle(role: .toolbarSecondary))
            .disabled(isLoadingCandidates || isSmartSelecting)
            .accessibilityIdentifier("manual-frame-regenerate")
        }
        .padding(.horizontal, ManualEditorLayout.horizontalInset)
        .frame(height: ManualEditorLayout.toolbarHeight)
    }

    private var candidateBrowser: some View {
        VStack(spacing: 0) {
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
                        ForEach(candidates) { candidate in
                            candidateTile(candidate)
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

    private func candidateTile(_ candidate: CapturedFrame) -> some View {
        let isSelected = selectedIDs.contains(candidate.id)
        // The badge is the final storyboard position, so a newly selected
        // earlier frame immediately renumbers every later selected frame.
        let selectionNumber = selectedFrames.firstIndex(where: { $0.id == candidate.id }).map { $0 + 1 }
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
        .disabled(!isSelected && selectedIDs.count >= selectionLimit)
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
                .frame(width: 156, height: ManualEditorLayout.compactControlHeight)
            }
            .buttonStyle(ManualFrameEditorActionButtonStyle(role: .primary))
            .disabled(selectedIDs.count != selectionLimit || model.isApplyingFrameAdjustments || isRefiningSelectedFrames)
            .keyboardShortcut(.return, modifiers: [.command])
            .accessibilityIdentifier("manual-frame-apply")
        }
        .padding(.horizontal, ManualEditorLayout.horizontalInset)
        .frame(height: ManualEditorLayout.footerHeight)
        .background(editorCanvas)
    }

    @ViewBuilder
    private func frameImage(_ frame: CapturedFrame) -> some View {
        if let image = NSImage(data: frame.jpegData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .background(.black.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.quaternary)
                .aspectRatio(frame.aspectRatio, contentMode: .fit)
        }
    }

    private var manualVideoPreview: some View {
        GeometryReader { proxy in
            let monitorWidth = min(max(proxy.size.width * 0.42, 360), 548)
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
            ManualVideoPlayerView(player: player)

            // A decoded still remains on top while scrubbing has stopped: it is
            // substantially clearer than the player surface for fast movement.
            if let previewFrame, !isScrubbingPreview {
                previewStill(previewFrame)
            } else if isLoadingPreviewFrame {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }

            HStack(spacing: 10) {
                ProjectIcon(symbol: .play, size: 16)
                    .foregroundStyle(.white)
                Text("\(TimestampFormatter.string(for: previewTime))  /  \(TimestampFormatter.string(for: safeDuration))")
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

    @ViewBuilder
    private func previewStill(_ frame: CapturedFrame) -> some View {
        if let image = NSImage(data: frame.jpegData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
    }

    private var timelineControlDeck: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(t("editor.timelineHint"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(controlText)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text("\(TimestampFormatter.string(for: previewTime))  /  \(TimestampFormatter.string(for: safeDuration))")
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

                TextField("00:00:00.000", text: $previewTimeText)
                    .textFieldStyle(ManualFrameEditorTextFieldStyle())
                    .frame(minWidth: 176, maxWidth: .infinity)
                    .onChange(of: previewTimeText, perform: updateTimelineFromCompleteTimeText)
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
                .disabled(previewFrame == nil || isLoadingPreviewFrame || isRefiningCurrentFrame)
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
                            filmstripImage(frame)
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
        .accessibilityValue(previewTimeText)
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
        previewTime = target
        scrubVideoPreview(to: target)
    }

    private func finishTimelineScrub() {
        guard isScrubbingPreview else { return }
        isScrubbingPreview = false
        seekVideoPreview(to: previewTime)
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
        let progress = max(0, min(1, previewTime / safeDuration))
        let firstCenter = min(thumbRadius, max(0, width / 2))
        let lastCenter = max(firstCenter, width - thumbRadius)
        let center = firstCenter + (lastCenter - firstCenter) * progress
        return max(0, min(width - markerWidth, center - markerWidth / 2))
    }

    @ViewBuilder
    private func filmstripImage(_ frame: CapturedFrame) -> some View {
        if let image = NSImage(data: frame.jpegData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color.black.opacity(0.08)
        }
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
        .disabled((offset < 0 && previewTime <= 0.000_01) || (offset > 0 && previewTime >= safeDuration - 0.000_01))
        .help(label)
        .accessibilityLabel(label)
    }

    private func prepareVideoPreview() {
        guard player == nil else { return }
        let newPlayer = AVPlayer(url: sourceURL)
        newPlayer.actionAtItemEnd = .pause
        player = newPlayer
        loadPreviewFrameStep()
        seekVideoPreview(to: 0)
    }

    private func loadPreviewFrameStep() {
        let source = sourceURL
        Task {
            let asset = AVURLAsset(url: source)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let nominalRate = try? await track.load(.nominalFrameRate),
                  nominalRate.isFinite, nominalRate > 1 else { return }
            previewFrameStep = 1.0 / Double(nominalRate)
        }
    }

    private func nudgePreview(by offset: Double) {
        let target = min(max(0, previewTime + offset), safeDuration)
        if abs(target - previewTime) < 0.000_01 { return }
        seekVideoPreview(to: target)
    }

    private func seekVideoPreview(to time: Double) {
        let clampedTime = min(max(0, time), safeDuration)
        previewTimeText = TimestampFormatter.editableString(for: clampedTime)
        isScrubbingPreview = false
        player?.pause()
        player?.seek(to: CMTime(seconds: clampedTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        requestPreviewFrame(at: clampedTime)
    }

    /// While the thumb moves, let AVFoundation use a nearby decodable frame.
    /// The expensive exact still-image decode is deferred until release.
    private func scrubVideoPreview(to time: Double) {
        let clampedTime = min(max(0, time), safeDuration)
        previewTimeText = TimestampFormatter.editableString(for: clampedTime)
        previewCaptureTask?.cancel()
        isLoadingPreviewFrame = false
        player?.pause()
        let tolerance = CMTime(seconds: 0.16, preferredTimescale: 600)
        player?.seek(
            to: CMTime(seconds: clampedTime, preferredTimescale: 600),
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        )
    }

    private func finishPreviewScrub(_ isEditing: Bool) {
        if isEditing {
            isScrubbingPreview = true
            previewCaptureTask?.cancel()
        } else {
            guard isScrubbingPreview else { return }
            isScrubbingPreview = false
            // One exact seek and one still decode after the drag—not dozens.
            seekVideoPreview(to: previewTime)
        }
    }

    private func applyEditablePreviewTime() {
        guard let requestedTime = TimestampFormatter.editableSeconds(from: previewTimeText) else {
            previewTimeText = TimestampFormatter.editableString(for: previewTime)
            return
        }
        let clampedTime = min(max(0, requestedTime), safeDuration)
        seekVideoPreview(to: clampedTime)
    }

    private func updateTimelineFromCompleteTimeText(_ text: String) {
        // Ignore the canonical value written by the slider itself. Partial text
        // edits are intentionally left alone until they form HH:MM:SS.mmm.
        guard text != TimestampFormatter.editableString(for: previewTime),
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

    private func requestPreviewFrame(at time: Double) {
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
                let frame = try await capture.value
                guard !Task.isCancelled else { return }
                previewFrame = frame
            } catch {
                guard !Task.isCancelled else { return }
                previewFrame = nil
            }
            guard !Task.isCancelled else { return }
            isLoadingPreviewFrame = false
        }
    }

    private func addCurrentFrame() {
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
        Task {
            defer { isRefiningCurrentFrame = false }
            // If refinement fails for an unusual codec, preserving the exact
            // preview still lets the user finish the manual edit.
            let refined = (try? await refinement.value) ?? previewFrame
            let isAlreadyPresent = candidates.contains { abs($0.time - refined.time) < 0.04 }
            guard !isAlreadyPresent else { return }
            manuallyAddedCandidates.append(refined)
        }
    }

    private func applySelectedFrames() {
        let framesToApply = selectedFrames
        guard framesToApply.count == selectionLimit, !isRefiningSelectedFrames else { return }
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
                let refinedFrames = try await refinement.value
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
        if selectedIDs.contains(candidate.id) {
            selectedIDs.remove(candidate.id)
        } else if selectedIDs.count < selectionLimit {
            selectedIDs.insert(candidate.id)
        }
    }

    private func regenerateCandidates() {
        candidateBatch += 1
        selectedIDs.removeAll()
        loadCandidates()
    }

    private func smartSelectCandidates() {
        guard !candidates.isEmpty, !isSmartSelecting else { return }
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
                let frames = try await samplingTask.value
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
        selectedFrameRefinementToken = nil
        selectedFrameRefinementTask?.cancel()
        applyPresentationTask?.cancel()
        player?.pause()
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

private struct ShotMapMark: View {
    let language: AppLanguage
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let image = ShotMapIconAsset.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .accessibilityLabel(language.text("app.icon.accessibility"))
            } else {
                ProjectIcon(symbol: .eye, size: 22)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(width: size, height: size)
    }
}

private enum ShotMapIconAsset {
    static let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

private struct ProcessingControlButtonStyle: ButtonStyle {
    enum Tone {
        case primary
        case secondary
        case destructive
    }

    let tone: Tone

    func makeBody(configuration: Configuration) -> some View {
        let colors: (fill: Color, stroke: Color, text: Color) = switch tone {
        case .primary:
            (SelectionPalette.active, .white.opacity(0.18), .white)
        case .secondary:
            (Color(nsColor: .controlBackgroundColor), Color.primary.opacity(0.14), PreviewText.primary)
        case .destructive:
            (Color(red: 0.788, green: 0.208, blue: 0.310), .white.opacity(0.22), .white)
        }
        return configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(colors.text)
            .background(colors.fill.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous)
                    .strokeBorder(colors.stroke)
            }
            .contentShape(RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
    }
}

private struct BatchFailureReport: View {
    let jobs: [VideoJob]
    let language: AppLanguage
    let retry: () -> Void
    let showSources: () -> Void
    let showTranscodingGuide: () -> Void
    @Environment(\.dismiss) private var dismiss

    private func t(_ key: String, _ arguments: CVarArg...) -> String {
        language.text(key, arguments: arguments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(t("failureReport.title"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(t("failureReport.detail", jobs.count))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            List(jobs) { job in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(job.url.lastPathComponent)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if job.state.needsTranscoding {
                            Text(t("failureReport.transcoding.badge"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(job.state.failureMessage ?? t("failureReport.unknown"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 3)
            }
            .frame(minHeight: 180, idealHeight: 300)

            HStack {
                Button(t("button.close")) { dismiss() }
                Spacer()
                if !jobs.isEmpty {
                    Button(action: showSources) {
                        GlyphLabel(title: t("failureReport.showSources"), glyph: .folder)
                    }
                }
                if jobs.contains(where: { $0.state.needsTranscoding }) {
                    Button(action: showTranscodingGuide) {
                        GlyphLabel(title: t("failureReport.transcodingGuide"), glyph: .eye)
                    }
                }
                let retryableCount = jobs.filter { $0.state.canRetry }.count
                if retryableCount > 0 {
                    Button(action: retry) {
                        GlyphLabel(title: t("button.retryFailed", retryableCount), glyph: .refresh)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(22)
        .frame(width: 560, height: 450)
    }
}

private struct TranscodingGuide: View {
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss

    private func t(_ key: String, _ arguments: CVarArg...) -> String {
        language.text(key, arguments: arguments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("transcoding.title"))
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(t("transcoding.intro"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 11) {
                TranscodingStep(index: "1", text: t("transcoding.step.one"))
                TranscodingStep(index: "2", text: t("transcoding.step.two"))
                TranscodingStep(index: "3", text: t("transcoding.step.three"))
            }

            Text(t("transcoding.tip"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(t("button.close")) { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}

private struct TranscodingStep: View {
    let index: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(index)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct VideoBatchCard: View {
    let jobs: [VideoJob]
    let language: AppLanguage
    let isTargeted: Bool
    let isLocked: Bool
    let isLightAppearance: Bool
    let isCompact: Bool
    let choose: () -> Void
    let clear: () -> Void

    var body: some View {
        Group {
            if jobs.isEmpty {
                emptyQueueTarget
            } else {
                VStack(spacing: 10) {
                    QueueVideoList(
                        jobs: jobs,
                        isCompact: isCompact,
                        isLightAppearance: isLightAppearance
                    )
                    .frame(maxHeight: .infinity)

                    HStack {
                        clearQueueButton
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var emptyQueueTarget: some View {
        Button(action: choose) {
            // The queue heading already identifies this as video import.  A
            // text-only empty state keeps the drop zone calm and gives the
            // filename support text more room in narrow windows.
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(isCompact ? 12 : 15)
            .background(
                isLightAppearance
                    ? Color.white.opacity(isTargeted ? 0.94 : 0.74)
                    : Color(red: 0.09, green: 0.14, blue: 0.20).opacity(isTargeted ? 1 : 0.88),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isTargeted
                            ? Color(red: 0.42, green: 0.85, blue: 0.91)
                            : .clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }

    private var clearQueueButton: some View {
        Button(action: clear) {
            GlyphLabel(title: language.text("queue.clear"), glyph: .trash)
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Color(red: 0.80, green: 0.18, blue: 0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22))
        }
        .help(language.text("queue.clear.hint"))
        .disabled(isLocked)
    }

    private var title: String {
        switch jobs.count {
        case 0: language.text("video.add")
        case 1: jobs[0].url.lastPathComponent
        default: language.text("video.added", jobs.count)
        }
    }

    private var subtitle: String {
        jobs.isEmpty ? language.text("video.support") : language.text("video.queueHint")
    }

}

private struct QueueVideoList: View {
    let jobs: [VideoJob]
    let isCompact: Bool
    let isLightAppearance: Bool

    @State private var contentHeight: CGFloat = 1
    @State private var contentOffset: CGFloat = 0

    private static let coordinateSpaceName = "shotTesseraQueueList"
    private var indexColumnWidth: CGFloat {
        switch String(max(1, jobs.count)).count {
        case 1, 2: 24
        case 3: 28
        default: 36
        }
    }

    var body: some View {
        GeometryReader { viewport in
            ZStack(alignment: .trailing) {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: isCompact ? 8 : 10) {
                        ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                            QueueVideoRow(
                                index: index + 1,
                                job: job,
                                isLightAppearance: isLightAppearance,
                                indexColumnWidth: indexColumnWidth
                            )
                        }
                    }
                    .padding(.vertical, 1)
                    .padding(.trailing, 10)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: QueueContentHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                        }
                    }
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: QueueScrollOffsetPreferenceKey.self,
                                value: proxy.frame(in: .named(Self.coordinateSpaceName)).minY
                            )
                        }
                    }
                }
                .coordinateSpace(name: Self.coordinateSpaceName)

                QueueScrollIndicator(
                    viewportHeight: viewport.size.height,
                    contentHeight: contentHeight,
                    contentOffset: contentOffset,
                    isLightAppearance: isLightAppearance
                )
                .padding(.trailing, 2)
                .allowsHitTesting(false)
            }
        }
        .onPreferenceChange(QueueContentHeightPreferenceKey.self) { contentHeight = $0 }
        .onPreferenceChange(QueueScrollOffsetPreferenceKey.self) { contentOffset = $0 }
    }
}

private struct QueueScrollIndicator: View {
    let viewportHeight: CGFloat
    let contentHeight: CGFloat
    let contentOffset: CGFloat
    let isLightAppearance: Bool

    private var isScrollable: Bool { contentHeight > viewportHeight + 1 }
    private var thumbHeight: CGFloat {
        guard isScrollable else { return 0 }
        return min(viewportHeight, max(34, viewportHeight * viewportHeight / contentHeight))
    }
    private var thumbOffset: CGFloat {
        guard isScrollable else { return 0 }
        let progress = min(1, max(0, -contentOffset / max(1, contentHeight - viewportHeight)))
        return progress * max(0, viewportHeight - thumbHeight)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(isLightAppearance ? Color.primary.opacity(0.045) : Color.white.opacity(0.055))
                .frame(width: 4, height: viewportHeight)
            Capsule()
                .fill(
                    isLightAppearance
                        ? SelectionPalette.active.opacity(0.56)
                        : Color(red: 0.353, green: 0.655, blue: 1.0).opacity(0.62)
                )
                .frame(width: 4, height: thumbHeight)
                .shadow(color: isLightAppearance ? Color.black.opacity(0.08) : Color.black.opacity(0.18), radius: 1, y: 1)
                .offset(y: thumbOffset)
        }
        .frame(width: 4, height: viewportHeight, alignment: .top)
        .opacity(isScrollable ? 1 : 0)
    }
}

private struct QueueContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct QueueScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct QueueVideoRow: View {
    let index: Int
    let job: VideoJob
    let isLightAppearance: Bool
    let indexColumnWidth: CGFloat

    var body: some View {
        HStack(spacing: 9) {
            Text("\(index)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: indexColumnWidth, alignment: .trailing)

            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(thumbnailFill)
                ProjectIcon(symbol: .film, size: 17)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 42, height: 38)

            Text(job.url.lastPathComponent)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(7)
        .frame(minHeight: 52)
        .background(rowFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var rowFill: Color {
        switch job.state {
        case .processing:
            return isLightAppearance ? Color(red: 0.86, green: 0.94, blue: 0.97) : Color(red: 0.10, green: 0.17, blue: 0.27)
        default:
            return isLightAppearance ? Color.white.opacity(0.52) : Color.clear
        }
    }

    private var thumbnailFill: LinearGradient {
        switch job.state {
        case .failed:
            return LinearGradient(colors: [Color(red: 0.47, green: 0.20, blue: 0.15), Color(red: 0.22, green: 0.11, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .processing:
            return LinearGradient(colors: [Color(red: 0.13, green: 0.34, blue: 0.54), Color(red: 0.07, green: 0.14, blue: 0.29)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [Color(red: 0.20, green: 0.33, blue: 0.49), Color(red: 0.07, green: 0.14, blue: 0.26)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

}

private struct ProgressiveStoryboardPreview: View {
    let gridSide: Int
    let cardAspectRatio: Double
    let language: AppLanguage
    let frames: [LivePreviewFrame?]
    let isLightAppearance: Bool

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: gridSide)
        let safeAspectRatio = min(3, max(1.0 / 3.0, cardAspectRatio))
        let total = gridSide * gridSide
        let filledCount = frames.reduce(into: 0) { if $1 != nil { $0 += 1 } }
        let activePlaceholderIndex = frames.firstIndex { $0 == nil }
        VStack(spacing: 12) {
            Text(language.text("preview.live", filledCount, total))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<total, id: \.self) { index in
                    ZStack {
                        if let frame = frames.indices.contains(index) ? frames[index] : nil {
                            Image(nsImage: frame.image)
                                .resizable()
                                .scaledToFill()
                                .id(frame.id)
                                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        } else {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(index == activePlaceholderIndex ? 0.12 : 0.045))
                            if index == activePlaceholderIndex {
                                ProgressView().controlSize(.mini)
                            }
                        }
                    }
                    .aspectRatio(safeAspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .aspectRatio(safeAspectRatio, contentMode: .fit)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if !isLightAppearance {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.14))
            }
        }
        .animation(.easeOut(duration: 0.18), value: filledCount)
    }
}

private struct EmptyPreview: View {
    let language: AppLanguage
    let isLightAppearance: Bool

    var body: some View {
        VStack(spacing: 18) {
            ShotMapMark(language: language, size: 72)
            Text(language.text("preview.empty.title"))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(PreviewText.primary)
            Text(language.text("preview.empty.description"))
                .font(.system(size: 13))
                .foregroundStyle(PreviewText.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 310)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if !isLightAppearance {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.14))
            }
        }
    }
}

private enum PreviewText {
    /// Semantic colors stay legible in each user-selected appearance.
    static let primary = Color.primary
    static let secondary = Color.secondary
}

private enum SelectionPalette {
    /// The single active-state color used by grid, format, and switch controls.
    static let active = Color(red: 0.039, green: 0.400, blue: 0.851) // #0A66D9
}

/// A compact visual preview makes the effect of each grid choice clear before
/// export. The real size remains in the label; very dense choices are capped
/// visually so their tiny cells stay legible in the narrow inspector.
private struct StoryboardGridChoiceLabel: View {
    let side: Int
    let isSelected: Bool

    private var visualSide: Int { min(5, max(2, side)) }

    var body: some View {
        VStack(spacing: 4) {
            VStack(spacing: 2.5) {
                ForEach(0..<visualSide, id: \.self) { _ in
                    HStack(spacing: 2.5) {
                        ForEach(0..<visualSide, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                                .fill(isSelected ? SelectionPalette.active : Color.secondary.opacity(0.72))
                                .frame(width: 4.5, height: 4.5)
                        }
                    }
                }
            }
            // Do not constrain this to a synthetic, one-size-fits-all height:
            // a 5 × 5 pictogram is taller than a 4 × 4 one.  Giving the
            // pictogram its real height lets the surrounding stack centre the
            // icon-and-label pair as one unit inside each option.

            Text("\(side) × \(side)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        // Keep the icon/label pair centred within every tap target.  This is
        // particularly noticeable for the active tile, whose outline makes
        // even a one-pixel vertical drift look unintentional.
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .center)
        .contentShape(Rectangle())
    }
}

/// A grid selector should read as a set of pictograms first, then as a value.
/// It intentionally differs from generic segmented controls used for formats.
private struct StoryboardGridChoiceStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(labelColor)
            .background {
                // Inactive choices deliberately have no card chrome.  The
                // controls read as a quiet set of options until a choice is
                // made; only the active value earns a surface and outline.
                if isSelected || configuration.isPressed {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(fillColor(isPressed: configuration.isPressed))
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1.5)
                }
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }

    private var labelColor: Color {
        guard isSelected else { return .primary }
        return SelectionPalette.active
    }

    private var borderColor: Color {
        if isSelected {
            return colorScheme == .light
                ? Color(red: 0.30, green: 0.56, blue: 1.0)
                : Color(red: 0.36, green: 0.65, blue: 1.0)
        }
        return colorScheme == .light
            ? Color.black.opacity(0.045)
            : Color.white.opacity(0.08)
    }

    private func fillColor(isPressed: Bool) -> Color {
        let base: Color
        if isSelected {
            base = colorScheme == .light
                ? Color(red: 0.91, green: 0.95, blue: 1.0)
                : Color(red: 0.09, green: 0.20, blue: 0.36)
        } else {
            base = colorScheme == .light
                ? Color.black.opacity(0.055)
                : Color.white.opacity(0.10)
        }
        return base.opacity(isPressed ? 0.78 : 1)
    }
}

private struct GridChoiceStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                isSelected ? SelectionPalette.active : idleFill(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.18) : Color.primary.opacity(0.08))
            }
    }

    private func idleFill(isPressed: Bool) -> Color {
        guard colorScheme == .light else {
            return Color(red: 0.114, green: 0.137, blue: 0.173).opacity(isPressed ? 0.84 : 1)
        }
        return isPressed
            ? Color(red: 0.910, green: 0.945, blue: 0.992)
            : Color.white
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(SelectionPalette.active, in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous).strokeBorder(.white.opacity(0.18)) }
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct ExportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous).strokeBorder(Color.primary.opacity(0.14)) }
    }
}

private struct SavedResultButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(SelectionPalette.active, in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.28)) }
            .shadow(color: Color(red: 0.30, green: 0.75, blue: 0.94).opacity(0.24), radius: 10, y: 4)
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct ManualAdjustmentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(Color(red: 0.071, green: 0.125, blue: 0.200), in: Capsule())
            .overlay { Capsule().strokeBorder(Color(red: 0.290, green: 0.510, blue: 0.820).opacity(0.72)) }
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.08 : 0.18), radius: 8, y: 3)
            .opacity(configuration.isPressed ? 0.80 : 1)
    }
}

/// Purpose-built action controls for the manual candidate editor.  These are
/// intentionally separate from the global button styles: one commits an
/// intelligent selection, while the other safely asks for a new candidate set.
private struct ManualFrameEditorTextFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) private var colorScheme

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .semibold, design: .monospaced))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .frame(height: ManualEditorLayout.compactControlHeight)
            .background(
                colorScheme == .dark
                    ? Color(red: 0.114, green: 0.133, blue: 0.157)
                    : Color.white.opacity(0.84),
                in: RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark ? .white.opacity(0.18) : Color(red: 0.805, green: 0.816, blue: 0.824),
                        lineWidth: 1
                    )
            }
    }
}

private struct ManualFrameEditorActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    enum Role {
        case primary
        case secondary
        case toolbarPrimary
        case toolbarSecondary
    }

    let role: Role
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: StudioLayout.controlCornerRadius, style: .continuous)
        let pressedOpacity = configuration.isPressed ? 0.80 : 1.0

        switch role {
        case .primary:
            configuration.label
                .foregroundStyle(Color.white)
                .background(
                    SelectionPalette.active,
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.34), lineWidth: 1)
                }
                .opacity(pressedOpacity)

        case .secondary:
            configuration.label
                .foregroundStyle(.primary)
                .background(
                    colorScheme == .dark
                        ? Color(red: 0.114, green: 0.133, blue: 0.157)
                        : Color.white.opacity(0.84),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(
                        colorScheme == .dark ? .white.opacity(0.18) : Color(red: 0.805, green: 0.816, blue: 0.824),
                        lineWidth: 1
                    )
                }
                .opacity(pressedOpacity)

        case .toolbarPrimary:
            configuration.label
                .foregroundStyle(SelectionPalette.active)
                .background(Color.clear, in: shape)
                .overlay { shape.strokeBorder(Color.clear, lineWidth: 1) }
                .opacity(pressedOpacity)

        case .toolbarSecondary:
            configuration.label
                .foregroundStyle(.primary)
                .background(Color.clear, in: shape)
                .overlay { shape.strokeBorder(Color.clear, lineWidth: 1) }
                .opacity(pressedOpacity)
        }
    }
}
