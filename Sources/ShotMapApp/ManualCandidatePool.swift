import Foundation

/// Enlarging the grid must not swap existing IDs onto newly sampled moments.
/// Keep the old pool and append distinct moments from the additional batch.
enum ManualCandidatePool {
    static func appending(
        _ incoming: [CapturedFrame], to existing: [CapturedFrame], excluding manual: [CapturedFrame]
    ) -> [CapturedFrame] {
        var result = existing
        var knownIDs = Set((existing + manual).map(\.id))
        var times = (existing + manual).map(\.time)
        for frame in incoming {
            guard !knownIDs.contains(frame.id), !times.contains(where: { abs($0 - frame.time) < 0.04 }) else { continue }
            result.append(frame)
            knownIDs.insert(frame.id)
            times.append(frame.time)
        }
        return result
    }
}
