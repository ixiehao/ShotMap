import SwiftUI

struct ProgressiveStoryboardPreview: View {
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

struct EmptyPreview: View {
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
