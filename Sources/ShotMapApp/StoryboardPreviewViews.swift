import SwiftUI

struct ProgressiveStoryboardPreview: View {
    let gridSide: Int
    let cardAspectRatio: Double
    let language: AppLanguage
    let frames: [LivePreviewFrame?]
    let processingLabel: String
    let isLightAppearance: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let side = min(8, max(1, gridSide))
        let total = side * side
        let filledCount = frames.reduce(into: 0) { if $1 != nil { $0 += 1 } }
        let activePlaceholderIndex = frames.firstIndex { $0 == nil }
        GeometryReader { geometry in
            let metrics = PreviewCanvasLayout.gridMetrics(
                side: side, cardAspect: cardAspectRatio,
                availableSize: CGSize(width: max(1, geometry.size.width - 24),
                                      height: max(1, geometry.size.height - 50))
            )
            let columns = Array(repeating: GridItem(.fixed(metrics.tileSize.width), spacing: 5), count: side)
            VStack(spacing: 8) {
                Text(filledCount == 0 ? processingLabel : language.text("preview.live", filledCount, total))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(height: 18)
                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach(0..<total, id: \.self) { index in
                        ZStack {
                            if let frame = frames.indices.contains(index) ? frames[index] : nil {
                                Image(nsImage: frame.image)
                                    .resizable()
                                    .scaledToFit()
                                    .id(frame.id)
                                    .transition(.opacity)
                            } else {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isLightAppearance
                                        ? Color(red: 0.86, green: 0.90, blue: 0.95).opacity(index == activePlaceholderIndex ? 1 : 0.6)
                                        : Color.white.opacity(index == activePlaceholderIndex ? 0.14 : 0.06))
                                if index == activePlaceholderIndex {
                                    ProgressView().controlSize(.mini)
                                }
                            }
                        }
                        .frame(width: metrics.tileSize.width, height: metrics.tileSize.height)
                    }
                }
                .frame(width: metrics.gridSize.width, height: metrics.gridSize.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: filledCount)
    }
}

struct EmptyPreview: View {
    let language: AppLanguage
    let isLightAppearance: Bool

    var body: some View {
        VStack(spacing: 12) {
            ShotMapMark(language: language, size: 44)
            Text(language.text("preview.empty.title"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PreviewText.primary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
