import Foundation

struct ManualFrameEditorRequest: Identifiable {
    let id = UUID()
    let previewID: RenderedStoryboardPreview.ID
    let sourceURL: URL
    let selectionLimit: Int
    let duration: Double
    let outputWidth: Int
}
