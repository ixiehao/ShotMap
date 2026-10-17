import SwiftUI

struct BatchFailureReport: View {
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

struct TranscodingGuide: View {
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
