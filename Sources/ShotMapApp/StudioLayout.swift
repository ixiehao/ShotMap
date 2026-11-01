import SwiftUI

/// A compact media workspace gives its centre canvas most of the window.
/// These measurements are points; separators use the current display scale.
enum StudioLayout {
    static let panelInset: CGFloat = 12
    static let panelTitleTop: CGFloat = 12
    static let titleSubtitleGap: CGFloat = 4
    static let panelHeaderHeight: CGFloat = 40
    static let toolbarHorizontalInset: CGFloat = 12
    static let toolbarHeight: CGFloat = 48
    static let previewHeaderHeight: CGFloat = 40
    static let previewActionHeight: CGFloat = 48
    static let resultPagerWidth: CGFloat = 152
    static let inspectorWidth: CGFloat = 216
    static let controlHeight: CGFloat = 30
    static let toolbarControlHeight: CGFloat = 28
    static let primaryControlHeight: CGFloat = 30
    static let controlCornerRadius: CGFloat = 8
    static let panelCornerRadius: CGFloat = 8

    static func queueWidth(availableWidth: CGFloat) -> CGFloat {
        190
    }
}

/// Measurements for the dedicated manual editor.  Keep this separate from
/// Batch Studio: it is a dense editing desk with a fixed visual rhythm, not a
/// three-panel form.  Values are whole points so separators and baselines land
/// on physical pixels at the standard macOS scale.
enum ManualEditorLayout {
    static let horizontalInset: CGFloat = 16
    static let workspaceVerticalInset: CGFloat = 12
    static let workspaceGap: CGFloat = 16
    static func mediaHeight(availableHeight: CGFloat) -> CGFloat {
        min(320, max(298, (availableHeight * 0.4 - 22).rounded(.down)))
    }

    static func workspaceHeight(mediaHeight: CGFloat) -> CGFloat {
        mediaHeight + workspaceVerticalInset * 2
    }
    static let candidateGap: CGFloat = 12
    static let candidateGridBottom: CGFloat = 16
    static let candidateGridTop: CGFloat = 12
    static let compactControlHeight: CGFloat = 30
    static let controlDeckInset: CGFloat = 12
    static let toolbarHeight: CGFloat = 36
    static let toolbarGap: CGFloat = 6
    static let toolbarCommitGap: CGFloat = 8
    static let toolbarTimelineGap: CGFloat = 8
    static let playbackButtonWidth: CGFloat = 28
    static let actionHorizontalInset: CGFloat = 10
    static let selectionCountFontSize: CGFloat = 28
    static let selectionMarkerHeight: CGFloat = 24
    static let filmstripScrubberGap: CGFloat = 6
    static let scrubberHeight: CGFloat = 18
    static let rulerTopGap: CGFloat = 1
    static let rulerHeight: CGFloat = 6
    static let endpointTopGap: CGFloat = 1
    static let endpointHeight: CGFloat = 12
    static let navigationBottomInset: CGFloat = 8
    static let floatingAddHeight: CGFloat = 26
    static let commandsTopGap: CGFloat = 8

    static var navigationHeight: CGFloat {
        scrubberHeight + rulerTopGap + rulerHeight + endpointTopGap + endpointHeight + navigationBottomInset
    }

    // Keep the floating button completely inside the navigation hit area,
    // including the eight points before the command divider.
    static var floatingAddTop: CGFloat { navigationHeight - floatingAddHeight }

    static var selectionCountFont: NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: selectionCountFontSize, weight: .bold)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        return NSFont(descriptor: descriptor, size: selectionCountFontSize) ?? base
    }

    struct ToolbarMetrics {
        let countWidth: CGFloat
        let smartSelectionWidth: CGFloat
        let newCandidatesWidth: CGFloat
        let cancelWidth: CGFloat
        let applyWidth: CGFloat

        var workingWidth: CGFloat {
            playbackButtonWidth + countWidth + smartSelectionWidth + newCandidatesWidth + toolbarGap * 3
        }

        var commitWidth: CGFloat { cancelWidth + applyWidth + toolbarGap }

        var singleRowWidth: CGFloat {
            workingWidth + commitWidth + toolbarGap * 2 + toolbarCommitGap
        }

        func stacksCommitButtons(availableWidth: CGFloat) -> Bool {
            availableWidth < singleRowWidth
        }

        func height(availableWidth: CGFloat) -> CGFloat {
            stacksCommitButtons(availableWidth: availableWidth)
                ? toolbarHeight + toolbarGap + compactControlHeight
                : toolbarHeight
        }
    }

    static func toolbarMetrics(language: AppLanguage, selectionLimit: Int) -> ToolbarMetrics {
        func buttonWidth(_ key: String, minimum: CGFloat = 0, weight: NSFont.Weight = .medium) -> CGFloat {
            let title = language.text(key)
            let font = NSFont.systemFont(ofSize: 12, weight: weight)
            return max(minimum, ceil((title as NSString).size(withAttributes: [.font: font]).width) + actionHorizontalInset * 2)
        }
        let limit = max(1, selectionLimit)
        let maximumCount = "\(limit) / \(limit)"
        let countWidth = ceil((maximumCount as NSString).size(withAttributes: [.font: selectionCountFont]).width) + 4
        return ToolbarMetrics(
            countWidth: countWidth,
            smartSelectionWidth: buttonWidth("editor.smartSelect.short"),
            newCandidatesWidth: buttonWidth("editor.regenerate.short"),
            cancelWidth: buttonWidth("editor.cancel", minimum: 64),
            applyWidth: buttonWidth("editor.apply.short", minimum: 76, weight: .semibold)
        )
    }

    static func timelineFilmstripHeight(
        mediaHeight: CGFloat, toolbarHeight: CGFloat, hasSelections: Bool, hairline: CGFloat
    ) -> CGFloat {
        let markersHeight = hasSelections ? selectionMarkerHeight : 0
        let fixedHeight = controlDeckInset * 2 + toolbarHeight + toolbarTimelineGap + markersHeight
            + filmstripScrubberGap + navigationHeight + hairline + commandsTopGap + compactControlHeight
        return max(62, floor(mediaHeight - fixedHeight))
    }

    static func timeFieldWidth(duration: Double) -> CGFloat {
        let text = TimestampFormatter.editableString(for: duration)
        let font = NSFont.monospacedSystemFont(ofSize: 18, weight: .semibold)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width) + 16
    }

    static func candidateColumnCount(availableWidth: CGFloat, sourceAspectRatio: Double) -> Int {
        let width = max(0, availableWidth - horizontalInset * 2)
        if sourceAspectRatio.isFinite, sourceAspectRatio > 0, sourceAspectRatio < 0.85 {
            // At the supported 1000pt minimum width, five full portrait cards
            // fit vertically; normal 1280pt windows show six.
            return min(6, max(5, Int((width + candidateGap) / (180 + candidateGap))))
        }
        return max(1, Int((width + candidateGap) / (260 + candidateGap)))
    }

    static func candidateTileWidth(availableWidth: CGFloat, columns: Int) -> CGFloat {
        let count = max(1, columns)
        return max(1, (availableWidth - horizontalInset * 2 - CGFloat(count - 1) * candidateGap) / CGFloat(count))
    }
}
