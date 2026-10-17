import SwiftUI

struct VideoBatchCard: View {
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

    private static let coordinateSpaceName = "shotMapQueueList"
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
