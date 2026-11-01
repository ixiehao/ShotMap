import Foundation

/// Smart selection fills vacant slots; it never replaces a deliberate choice.
/// Freeze the current selection before background scoring and only admit new
/// IDs from the remaining candidate pool when presenting the result.
struct ManualSelectionFillPlan: Sendable {
    let preservedIDs: Set<Int>
    let candidates: [CapturedFrame]
    let additionalCount: Int

    init(candidates: [CapturedFrame], selectedIDs: Set<Int>, limit: Int) {
        let candidateIDs = Set(candidates.map(\.id))
        let preserved = selectedIDs.intersection(candidateIDs)
        preservedIDs = preserved
        self.candidates = candidates.filter { !preserved.contains($0.id) }
        additionalCount = min(self.candidates.count, max(0, limit - preserved.count))
    }

    func completing(with additionalIDs: [Int]) -> Set<Int> {
        let allowedIDs = Set(candidates.map(\.id))
        var result = preservedIDs
        var added = 0
        for id in additionalIDs where allowedIDs.contains(id) && !result.contains(id) {
            guard added < additionalCount else { break }
            result.insert(id)
            added += 1
        }
        return result
    }
}
