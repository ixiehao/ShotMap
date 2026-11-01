import Foundation

enum FrameSelection {
    static func histogramDistance(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 1 }
        return zip(lhs, rhs).reduce(0) { $0 + abs($1.0 - $1.1) } / 2
    }

    static func hammingDistance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }

    static func sceneRanges(in frames: [FrameDescriptor], threshold: Float = 0.22) -> [Range<Int>] {
        guard !frames.isEmpty else { return [] }
        var ranges: [Range<Int>] = []
        var start = 0

        for index in 1..<frames.count {
            let previous = frames[index - 1]
            let current = frames[index]
            let changedEnough = histogramDistance(previous.histogram, current.histogram) >= threshold
            let hasRoom = current.time - frames[start].time >= 0.7
            if changedEnough && hasRoom {
                ranges.append(start..<index)
                start = index
            }
        }
        ranges.append(start..<frames.count)
        return ranges
    }

    static func chooseFrames(from frames: [FrameDescriptor], count: Int) -> [FrameDescriptor] {
        guard count > 0, !frames.isEmpty else { return [] }
        let usablePool = frames.filter(\.isUsable)
        // A grid of black or excessively blurry cards is not a useful storyboard.
        // The analyzer turns this empty result into a clear user-facing error.
        guard !usablePool.isEmpty else { return [] }
        // Only a high-confidence text card is a hard rejection. Never make "no
        // detected person", a dark scene, or a sparse composition a hard rule:
        // Vision deliberately examines only a compact subset of a video, and an
        // absent signal is not proof of non-content. This keeps establishing shots
        // and action beats available while still removing real covers/warnings.
        // Quality exclusions are irreversible for this candidate. In particular,
        // an all-title clip must not restore its rejected pool just to fill tiles.
        let pool = usablePool
        let ranges = sceneRanges(in: pool)
        let sceneIndexByID = sceneIndexMap(ranges: ranges, frames: pool)

        // Pick representatives from stable shots first. This replaces the old
        // fixed time buckets: a weak intro, credit card, or empty landscape no
        // longer receives a tile solely because it occupies part of the runtime.
        var candidates: [FrameDescriptor] = []
        for range in ranges {
            let shot = Array(pool[range])
            guard !shot.isEmpty else { continue }
            let stable = stableCandidates(in: shot)
            candidates.append(contentsOf: stable.prefix(2))
        }

        // Preserve the useful narrative coverage of the V0.2.6 time buckets,
        // but use them as optional anchors rather than reserved slots. A weak
        // opening card is therefore available only as a last resort, while a
        // meaningful quiet or dark scene retains a route into the final sheet.
        candidates.append(contentsOf: temporalAnchors(in: pool, count: min(count * 2, pool.count)))
        candidates = uniqueCandidates(candidates)

        // Long, low-cut scenes need more than two options for a large grid. Add
        // the remaining video frames only as a candidate reservoir; the final
        // MMR pass below still rejects near-identical moments.
        if candidates.count < count * 2 {
            candidates.append(contentsOf: pool)
            candidates = uniqueCandidates(candidates)
        }

        let selected = selectStoryDiverse(
            from: candidates,
            sceneIndexByID: sceneIndexByID,
            count: count
        )
        let coverageAdjusted = improveTimelineCoverage(
            selected,
            candidates: candidates,
            count: count
        )
        // A very static clip can legitimately have few visually distinct frames.
        // Complete the requested grid without reintroducing unusable/title frames.
        let filled = coverageAdjusted.count < count
            ? coverageAdjusted + relaxedBucketFill(from: pool, current: coverageAdjusted, count: count)
            : coverageAdjusted
        var ids = Set<Int>()
        let distinctTimestamps = filled.filter { ids.insert($0.id).inserted }
        return improveVisualDiversity(Array(distinctTimestamps.prefix(count)), pool: pool, count: count)
            .sorted { $0.time < $1.time }
    }

    static func evenlySpaced(_ frames: [FrameDescriptor], count: Int) -> [FrameDescriptor] {
        guard count > 0 else { return [] }
        guard frames.count > count else { return frames }
        if count == 1 {
            return [frames[frames.count / 2]]
        }
        return (0..<count).map { slot in
            let position = Double(slot) * Double(frames.count - 1) / Double(count - 1)
            return frames[Int(position.rounded())]
        }
    }

    private static func isVisualDuplicate(_ lhs: FrameDescriptor, _ rhs: FrameDescriptor, strict: Bool) -> Bool {
        if abs(lhs.time - rhs.time) < (strict ? 0.35 : 0.08) { return true }
        let hamming = hammingDistance(lhs.fingerprint, rhs.fingerprint)
        if hamming < (strict ? 7 : 3) { return true }
        guard hamming < (strict ? 18 : 8) else { return false }
        let histDistance = histogramDistance(lhs.histogram, rhs.histogram)
        // Average hashes alone can miss same-stage frames with small motion. Combine
        // them with histogram distance for a less brittle near-duplicate signal.
        return histDistance < (strict ? 0.035 : 0.012)
    }

    private static func sceneIndexMap(
        ranges: [Range<Int>],
        frames: [FrameDescriptor]
    ) -> [Int: Int] {
        var output: [Int: Int] = [:]
        for (scene, range) in ranges.enumerated() {
            for frame in frames[range] { output[frame.id] = scene }
        }
        return output
    }

    private static func stableCandidates(in shot: [FrameDescriptor]) -> [FrameDescriptor] {
        guard shot.count > 2 else { return shot.sorted { $0.qualityScore > $1.qualityScore } }
        // Boundary samples frequently land on edits. Retain the entire shot when
        // it is short, otherwise prefer its interior while leaving a fallback.
        let inset = shot.count >= 5 ? 1 : 0
        let interior = Array(shot.dropFirst(inset).dropLast(inset))
        return interior.sorted { $0.qualityScore > $1.qualityScore }
    }

    private static func uniqueCandidates(_ candidates: [FrameDescriptor]) -> [FrameDescriptor] {
        var output: [FrameDescriptor] = []
        for candidate in candidates.sorted(by: { $0.qualityScore > $1.qualityScore }) {
            guard !output.contains(where: { $0.id == candidate.id }) else { continue }
            if !output.contains(where: { isVisualDuplicate($0, candidate, strict: true) }) {
                output.append(candidate)
            }
        }
        return output
    }

    private static func temporalAnchors(in pool: [FrameDescriptor], count: Int) -> [FrameDescriptor] {
        guard count > 0, let first = pool.first, let last = pool.last else { return [] }
        let span = max(0.001, last.time - first.time)

        return (0..<count).compactMap { bucket in
            let lower = first.time + span * Double(bucket) / Double(count)
            let upper = first.time + span * Double(bucket + 1) / Double(count)
            return pool
                .filter { $0.time >= lower && ($0.time < upper || bucket == count - 1) }
                .max { $0.qualityScore < $1.qualityScore }
        }
    }

    /// The first pass deliberately favors quality and visual novelty. If that
    /// produces a cluster of similarly timed frames, replace only the redundant
    /// member with a sufficiently good temporal anchor. This restores story
    /// coverage without returning to mandatory, low-quality time buckets.
    static func improveTimelineCoverage(
        _ selected: [FrameDescriptor],
        candidates: [FrameDescriptor],
        count: Int
    ) -> [FrameDescriptor] {
        guard selected.count > 1, count > 1 else { return selected }
        let orderedCandidates = candidates.sorted { $0.time < $1.time }
        guard let first = orderedCandidates.first, let last = orderedCandidates.last else { return selected }

        let desiredGap = max(0.001, (last.time - first.time) / Double(count))
        let qualityCeiling = max(0.001, candidates.map(\.qualityScore).max() ?? 0.001)
        var output = selected

        for anchor in temporalAnchors(in: orderedCandidates, count: count) {
            guard anchor.isUsable, !output.contains(where: { $0.id == anchor.id }) else { continue }

            let crowded = output.enumerated().compactMap { index, frame -> (index: Int, gap: Double)? in
                let nearestGap = output.enumerated()
                    .filter { $0.offset != index }
                    .map { abs(frame.time - $0.element.time) }
                    .min() ?? .infinity
                return nearestGap < desiredGap * 0.75 ? (index, nearestGap) : nil
            }
            let replacements = crowded.sorted(by: { lhs, rhs in
                if lhs.gap == rhs.gap {
                    return output[lhs.index].qualityScore < output[rhs.index].qualityScore
                }
                return lhs.gap < rhs.gap
            })
            for replacement in replacements {
                let original = output[replacement.index]
                // A well-exposed, readable establishing shot can score below
                // 70% of the best close-up and still improve a weak crowded
                // sample. Use direct observed evidence for that relative route;
                // legacy/manual descriptors retain the established threshold.
                let improvesObservedQuality: Bool
                if let anchorDetail = observedReadability(anchor),
                   let originalDetail = observedReadability(original) {
                    improvesObservedQuality = anchor.qualityScore >= original.qualityScore
                        && anchorDetail >= originalDetail
                } else {
                    improvesObservedQuality = false
                }
                guard anchor.qualityScore >= qualityCeiling * 0.70 || improvesObservedQuality else { continue }
                var comparison = output
                comparison.remove(at: replacement.index)
                guard !comparison.contains(where: { isVisualDuplicate(anchor, $0, strict: true) }) else { continue }
                let anchorGap = comparison.map { abs(anchor.time - $0.time) }.min() ?? .infinity
                guard anchorGap > replacement.gap else { continue }
                output[replacement.index] = anchor
                break
            }
        }
        return output
    }

    private static func observedReadability(_ frame: FrameDescriptor) -> Float? {
        guard let evidence = frame.qualityEvidence, evidence.state == .observed,
              evidence.rejection == nil else { return nil }
        return min(1, max(0, evidence.subjectDetailScore ?? evidence.focusScore))
    }

    /// A bright flash/pan can change its histogram while retaining the same
    /// composition. This is a soft, local duplicate signal, never an eligibility
    /// gate. It is applied only when an audited replacement actually exists.
    private static func isLocalNearDuplicate(_ lhs: FrameDescriptor, _ rhs: FrameDescriptor) -> Bool {
        if isVisualDuplicate(lhs, rhs, strict: true) { return true }
        guard lhs.qualityEvidence?.state == .observed, rhs.qualityEvidence?.state == .observed,
              abs(lhs.time - rhs.time) <= 2 else { return false }
        return hammingDistance(lhs.fingerprint, rhs.fingerprint) <= 10
            && histogramDistance(lhs.histogram, rhs.histogram) <= 0.30
    }

    static func improveVisualDiversity(_ selected: [FrameDescriptor], pool: [FrameDescriptor], count: Int) -> [FrameDescriptor] {
        guard selected.count == count, pool.count > count,
              selected.contains(where: { $0.qualityEvidence?.state == .observed }) else { return selected }
        var result = selected
        let first = pool.map(\.time).min() ?? 0
        let span = max(1, (pool.map(\.time).max() ?? first) - first)
        let desiredGap = span / Double(max(1, count))
        for _ in 0..<min(count, 8) {
            var duplicatePairs: [(Int, Int)] = []
            for left in result.indices {
                for right in result.indices where right > left {
                    if isLocalNearDuplicate(result[left], result[right]) { duplicatePairs.append((left, right)) }
                }
            }
            guard !duplicatePairs.isEmpty else { break }
            var replaced = false
            for (left, right) in duplicatePairs {
                let weaker = result[left].qualityScore < result[right].qualityScore ? left : right
                let original = result[weaker]
                let others = result.enumerated().filter { $0.offset != weaker }.map(\.element)
                let occupied = Set(result.map(\.id))
                let alternatives = pool.filter { candidate in
                    !occupied.contains(candidate.id) && candidate.qualityScore >= original.qualityScore * 0.70
                        && !others.contains(where: { isLocalNearDuplicate(candidate, $0) })
                }
                let replacement = alternatives.max { lhs, rhs in
                    let lhsUtility = lhs.qualityScore - Float(min(1, abs(lhs.time - original.time) / max(1, desiredGap))) * 0.12
                    let rhsUtility = rhs.qualityScore - Float(min(1, abs(rhs.time - original.time) / max(1, desiredGap))) * 0.12
                    return lhsUtility < rhsUtility
                }
                if let replacement {
                    result[weaker] = replacement
                    replaced = true
                    break
                }
            }
            if !replaced { break }
        }
        return result
    }

    static func selectStoryDiverse(
        from candidates: [FrameDescriptor],
        sceneIndexByID: [Int: Int],
        count: Int
    ) -> [FrameDescriptor] {
        guard count > 0 else { return [] }
        let maxQuality = max(0.001, candidates.map(\.qualityScore).max() ?? 0.001)
        var remaining = candidates.map { DiversityCandidate(frame: $0, quality: $0.qualityScore / maxQuality) }
        var selected: [FrameDescriptor] = []
        var sceneUseCount: [Int: Int] = [:]

        while selected.count < count, !remaining.isEmpty {
            // Novelty is the minimum distance to the selected set. Updating
            // that minimum once per winner avoids re-measuring every previous
            // winner inside every comparator, without changing the score.
            let winner = remaining.max { lhs, rhs in
                selectionUtility(lhs, hasSelection: !selected.isEmpty, sceneIndexByID: sceneIndexByID, sceneUseCount: sceneUseCount)
                    < selectionUtility(rhs, hasSelection: !selected.isEmpty, sceneIndexByID: sceneIndexByID, sceneUseCount: sceneUseCount)
            }!.frame
            selected.append(winner)
            if let scene = sceneIndexByID[winner.id] { sceneUseCount[scene, default: 0] += 1 }
            remaining.removeAll { $0.frame.id == winner.id || isVisualDuplicate($0.frame, winner, strict: true) }
            guard selected.count < count else { break }
            for index in remaining.indices {
                let frame = remaining[index].frame
                let histogram = histogramDistance(frame.histogram, winner.histogram)
                let hash = Float(hammingDistance(frame.fingerprint, winner.fingerprint)) / 64
                remaining[index].novelty = min(remaining[index].novelty, min(1, histogram * 1.8 + hash * 0.45))
            }
        }
        return selected
    }

    private struct DiversityCandidate {
        let frame: FrameDescriptor
        let quality: Float
        var novelty: Float = 1
    }

    private static func selectionUtility(
        _ candidate: DiversityCandidate,
        hasSelection: Bool,
        sceneIndexByID: [Int: Int],
        sceneUseCount: [Int: Int]
    ) -> Float {
        guard hasSelection else { return candidate.quality }
        let sameScenePenalty: Float
        if let scene = sceneIndexByID[candidate.frame.id] {
            switch sceneUseCount[scene, default: 0] {
            case 0: sameScenePenalty = 0
            case 1: sameScenePenalty = 0.10
            default: sameScenePenalty = 0.22
            }
        } else {
            sameScenePenalty = 0
        }
        return candidate.quality * 0.72 + candidate.novelty * 0.48 - sameScenePenalty
    }

    private static func relaxedBucketFill(
        from pool: [FrameDescriptor],
        current: [FrameDescriptor],
        count: Int
    ) -> [FrameDescriptor] {
        guard let first = pool.first, let last = pool.last else { return [] }
        let span = max(0.001, last.time - first.time)
        var output: [FrameDescriptor] = []
        var occupied = current

        for bucket in 0..<count where occupied.count < count {
            let lower = first.time + span * Double(bucket) / Double(count)
            let upper = first.time + span * Double(bucket + 1) / Double(count)
            let candidates = pool
                .filter { $0.time >= lower && ($0.time < upper || bucket == count - 1) }
                .sorted { $0.qualityScore > $1.qualityScore }
            if let choice = candidates.first(where: { candidate in
                !occupied.contains(where: { isVisualDuplicate($0, candidate, strict: false) })
            }) {
                if !occupied.contains(where: { $0.id == choice.id }) {
                    output.append(choice)
                    occupied.append(choice)
                }
            }
        }

        // A bucket with only duplicates must not take a slot before another
        // bucket's distinct content. Search the complete pool first.
        for candidate in pool.sorted(by: { $0.qualityScore > $1.qualityScore }) where occupied.count < count {
            if !occupied.contains(where: { isVisualDuplicate($0, candidate, strict: false) }) {
                output.append(candidate)
                occupied.append(candidate)
            }
        }
        // Static clips still need all their unique PTS. Only relax visual
        // similarity after all genuinely different alternatives are exhausted.
        var remaining = pool.filter { candidate in !occupied.contains(where: { $0.id == candidate.id }) }
        while occupied.count < count, !remaining.isEmpty {
            // Once visual alternatives are exhausted, spread the remaining
            // distinct timestamps instead of taking many adjacent copies of
            // whichever static scene happens to be marginally sharper.
            let winner = remaining.max { lhs, rhs in
                let leftGap = occupied.map { abs($0.time - lhs.time) }.min() ?? .infinity
                let rightGap = occupied.map { abs($0.time - rhs.time) }.min() ?? .infinity
                if leftGap != rightGap { return leftGap < rightGap }
                if lhs.qualityScore != rhs.qualityScore { return lhs.qualityScore < rhs.qualityScore }
                return lhs.time > rhs.time
            }!
            output.append(winner)
            occupied.append(winner)
            remaining.removeAll { $0.id == winner.id }
        }
        return output
    }
}
