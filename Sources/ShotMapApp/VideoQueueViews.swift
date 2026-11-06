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
                        language: language,
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
            // Keep the drop target text-only: the heading already identifies
            // video import, while a soft card keeps the empty queue welcoming.
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(3)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                isLightAppearance
                    ? (isTargeted ? Color(red: 0.91, green: 0.95, blue: 1) : Color.white.opacity(0.88))
                    : Color.white.opacity(isTargeted ? 0.09 : 0.05),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isTargeted ? SelectionPalette.active.opacity(0.7) : Color.primary.opacity(0.055), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isLightAppearance ? 0.035 : 0.09), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }

    private var clearQueueButton: some View {
        Button(role: .destructive, action: clear) {
            GlyphLabel(title: language.text("queue.clear"), glyph: .trash, glyphSize: 12)
                .font(.system(size: 11, weight: .medium))
                .frame(height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.red.opacity(0.85))
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
    let language: AppLanguage
    let isCompact: Bool
    let isLightAppearance: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: isCompact ? 7 : 9) {
                ForEach(IndexedVideoJobs(jobs: jobs)) { entry in
                    QueueVideoRow(
                        index: entry.index + 1,
                        numberWidth: max(26, CGFloat(String(jobs.count).count) * 7.5 + 10),
                        job: entry.job,
                        language: language,
                        isLightAppearance: isLightAppearance
                    )
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 1)
        }
    }
}

/// A view over the array's existing storage. Progress updates must not allocate
/// a second copy of a large queue just to display row numbers. The job's ID,
/// rather than its current position, remains the SwiftUI identity.
struct IndexedVideoJobs: RandomAccessCollection {
    struct Element: Identifiable {
        let index: Int
        let job: VideoJob
        var id: UUID { job.id }
    }

    let jobs: [VideoJob]
    var startIndex: Int { jobs.startIndex }
    var endIndex: Int { jobs.endIndex }

    subscript(position: Int) -> Element {
        Element(index: position, job: jobs[position])
    }
}

private struct QueueVideoRow: View {
    let index: Int
    let numberWidth: CGFloat
    let job: VideoJob
    let language: AppLanguage
    let isLightAppearance: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Ordinals are identifiers, not locale-formatted quantities. Keep
            // four-digit queues readable and align all filenames to one edge.
            Text(verbatim: String(index))
                .font(.system(size: index < 100 ? 15 : 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(StudioPalette(isLight: isLightAppearance).accent)
                .frame(width: numberWidth, height: 30)
                .background(SelectionPalette.active.opacity(isLightAppearance ? 0.07 : 0.14),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(job.url.lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.leading)
                    .allowsTightening(true)
                Text(job.state.label(in: language))
                    .foregroundStyle(stateColor)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(rowFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(rowBorder, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(isLightAppearance ? 0.035 : 0.08), radius: 2, y: 1)
        .accessibilityElement(children: .combine)
        .help(job.url.lastPathComponent + " — " + job.state.label(in: language))
    }

    private var rowFill: Color {
        switch job.state {
        case .processing:
            return isLightAppearance ? Color(red: 0.89, green: 0.94, blue: 1) : Color(red: 0.10, green: 0.17, blue: 0.27)
        case .failed:
            return isLightAppearance ? Color(red: 1, green: 0.965, blue: 0.955) : Color(red: 0.20, green: 0.13, blue: 0.14)
        default:
            return isLightAppearance ? Color.white.opacity(0.9) : Color.white.opacity(0.05)
        }
    }

    private var rowBorder: Color {
        switch job.state {
        case .processing: return SelectionPalette.active.opacity(isLightAppearance ? 0.17 : 0.26)
        case .failed: return Color.red.opacity(0.12)
        default: return Color.primary.opacity(isLightAppearance ? 0.055 : 0.07)
        }
    }

    private var stateColor: Color {
        switch job.state {
        case .failed: return .red
        case .processing: return SelectionPalette.active
        case .completed: return isLightAppearance ? Color(red: 0.18, green: 0.43, blue: 0.31) : Color(red: 0.43, green: 0.73, blue: 0.56)
        case .queued: return .secondary
        }
    }
}
