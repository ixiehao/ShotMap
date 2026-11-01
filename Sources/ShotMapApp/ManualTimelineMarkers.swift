import SwiftUI

struct ManualTimelineSelection: Identifiable, Equatable {
    let id: Int
    let number: Int
    let time: Double
}

struct ManualTimelineMarkerGroup: Identifiable {
    var id: Int { selections[0].id }
    let selections: [ManualTimelineSelection]
    let center: CGFloat

    var label: String {
        guard let first = selections.first, let last = selections.last else { return "" }
        return first.number == last.number ? "\(first.number)" : "\(first.number)–\(last.number)"
    }
}

/// Selection pins, the playhead and scrubbing share the same time coordinate.
/// Only badge heads are grouped when crowded; each exact timestamp keeps its
/// own stem and remains individually reachable through the group's popover.
enum ManualTimelineGeometry {
    static func center(time: Double, duration: Double, width: CGFloat) -> CGFloat {
        let safeWidth = width.isFinite ? max(0, width) : 0
        let first = min(6, safeWidth / 2)
        let last = max(first, safeWidth - 6)
        let progress = time.isFinite && duration.isFinite && duration > 0
            ? min(1, max(0, time / duration)) : 0
        return first + (last - first) * progress
    }

    static func time(at x: CGFloat, duration: Double, width: CGFloat) -> Double {
        let start = center(time: 0, duration: duration, width: width)
        let end = center(time: duration, duration: duration, width: width)
        guard x.isFinite, duration.isFinite, duration > 0, end > start else { return 0 }
        return Double(min(1, max(0, (x - start) / (end - start)))) * duration
    }

    static func insertionOrigin(time: Double, duration: Double, width: CGFloat, buttonWidth: CGFloat, endpointWidth: CGFloat) -> CGFloat {
        let available = max(0, width - buttonWidth)
        let edge = min(max(0, endpointWidth), available / 2)
        let preferred = center(time: time, duration: duration, width: width) - buttonWidth / 2
        return min(available - edge, max(edge, preferred))
    }

    static func groups(
        for selections: [ManualTimelineSelection], duration: Double, width: CGFloat
    ) -> [ManualTimelineMarkerGroup] {
        guard width.isFinite, width > 0 else { return [] }
        let slotCount = max(1, Int(width / 36))
        let slotWidth = width / CGFloat(slotCount)
        var slots: [Int: [ManualTimelineSelection]] = [:]
        for selection in selections {
            let x = center(time: selection.time, duration: duration, width: width)
            let slot = min(slotCount - 1, Int(x / slotWidth))
            slots[slot, default: []].append(selection)
        }
        return slots.keys.sorted().map { slot in
            let entries = slots[slot]!.sorted { $0.number < $1.number }
            let mean = entries.reduce(CGFloat.zero) {
                $0 + center(time: $1.time, duration: duration, width: width)
            } / CGFloat(entries.count)
            let inset = min(16, slotWidth / 2)
            let left = CGFloat(slot) * slotWidth + inset
            let right = CGFloat(slot + 1) * slotWidth - inset
            return ManualTimelineMarkerGroup(selections: entries, center: min(right, max(left, mean)))
        }
    }
}

struct ManualTimelineMarkerButton: View {
    let group: ManualTimelineMarkerGroup
    let accent: Color
    let description: String
    let selectionDescription: (ManualTimelineSelection) -> String
    let onSeek: (ManualTimelineSelection) -> Void
    @State private var showsSelections = false

    var body: some View {
        Button {
            if group.selections.count == 1, let selection = group.selections.first {
                onSeek(selection)
            } else {
                showsSelections = true
            }
        } label: {
            Text(group.label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: group.selections.count == 1 ? 20 : 30, height: 18)
                .background(accent, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.white.opacity(0.85), lineWidth: 0.5)
                }
                .frame(width: 32, height: 24, alignment: .top)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(description)
        .accessibilityLabel(description)
        .accessibilityIdentifier("manual-frame-timeline-marker-\(group.id)")
        .popover(isPresented: $showsSelections, arrowEdge: .bottom) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(group.selections) { selection in
                        Button {
                            showsSelections = false
                            onSeek(selection)
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(selection.number)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(accent)
                                    .frame(width: 24)
                                Text(TimestampFormatter.editableString(for: selection.time))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                            }
                            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(selectionDescription(selection))
                    }
                }
                .padding(6)
            }
            .frame(width: 180, height: min(240, CGFloat(group.selections.count) * 32 + 10))
        }
    }
}
