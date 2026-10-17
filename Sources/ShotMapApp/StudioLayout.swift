import SwiftUI

/// Shared, whole-point measurements for the three-column studio.
/// Keeping structural values here prevents subtle baseline drift between panels.
enum StudioLayout {
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
enum ManualEditorLayout {
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
