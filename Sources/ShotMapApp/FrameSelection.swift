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
        let textFreePool = usablePool.filter { $0.textOverlayScore < 0.65 }
        let pool = textFreePool.isEmpty ? usablePool : textFreePool
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
        guard coverageAdjusted.count < count else { return coverageAdjusted.sorted { $0.time < $1.time } }

        // A very static clip can legitimately have few visually distinct frames.
        // Complete the requested grid without reintroducing unusable/title frames.
        let filled = coverageAdjusted + relaxedBucketFill(from: pool, current: coverageAdjusted, count: count)
        var ids = Set<Int>()
        let distinctTimestamps = filled.filter { ids.insert($0.id).inserted }
        return Array(distinctTimestamps.prefix(count)).sorted { $0.time < $1.time }
    }

    static func evenlySpaced(_ frames: [FrameDescriptor], count: Int) -> [FrameDescriptor] {
        guard count > 0, frames.count > count else { return frames }
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
        let histDistance = histogramDistance(lhs.histogram, rhs.histogram)
        if hamming < (strict ? 7 : 3) { return true }
        // Average hashes alone can miss same-stage frames with small motion. Combine
        // them with histogram distance for a less brittle near-duplicate signal.
        return hamming < (strict ? 18 : 8) && histDistance < (strict ? 0.035 : 0.012)
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
    private static func improveTimelineCoverage(
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
            guard !output.contains(where: { $0.id == anchor.id }),
                  anchor.qualityScore >= qualityCeiling * 0.70 else { continue }

            let crowded = output.enumerated().compactMap { index, frame -> (index: Int, gap: Double)? in
                let nearestGap = output.enumerated()
                    .filter { $0.offset != index }
                    .map { abs(frame.time - $0.element.time) }
                    .min() ?? .infinity
                return nearestGap < desiredGap * 0.75 ? (index, nearestGap) : nil
            }
            guard let replacement = crowded.min(by: { lhs, rhs in
                if lhs.gap == rhs.gap {
                    return output[lhs.index].qualityScore < output[rhs.index].qualityScore
                }
                return lhs.gap < rhs.gap
            }) else { continue }

            var comparison = output
            comparison.remove(at: replacement.index)
            let anchorGap = comparison.map { abs(anchor.time - $0.time) }.min() ?? .infinity
            guard anchorGap > replacement.gap else { continue }
            output[replacement.index] = anchor
        }
        return output
    }

    private static func selectStoryDiverse(
        from candidates: [FrameDescriptor],
        sceneIndexByID: [Int: Int],
        count: Int
    ) -> [FrameDescriptor] {
        guard count > 0 else { return [] }
        let maxQuality = max(0.001, candidates.map(\.qualityScore).max() ?? 0.001)
        var remaining = candidates
        var selected: [FrameDescriptor] = []
        var sceneUseCount: [Int: Int] = [:]

        while selected.count < count, !remaining.isEmpty {
            let winner = remaining.max { lhs, rhs in
                selectionUtility(lhs, selected: selected, sceneIndexByID: sceneIndexByID, sceneUseCount: sceneUseCount, maxQuality: maxQuality)
                    < selectionUtility(rhs, selected: selected, sceneIndexByID: sceneIndexByID, sceneUseCount: sceneUseCount, maxQuality: maxQuality)
            }!
            selected.append(winner)
            if let scene = sceneIndexByID[winner.id] { sceneUseCount[scene, default: 0] += 1 }
            remaining.removeAll { $0.id == winner.id || isVisualDuplicate($0, winner, strict: true) }
        }
        return selected
    }

    private static func selectionUtility(
        _ candidate: FrameDescriptor,
        selected: [FrameDescriptor],
        sceneIndexByID: [Int: Int],
        sceneUseCount: [Int: Int],
        maxQuality: Float
    ) -> Float {
        let quality = candidate.qualityScore / maxQuality
        guard !selected.isEmpty else { return quality }
        let novelty = selected.map { existing -> Float in
            let histogram = histogramDistance(candidate.histogram, existing.histogram)
            let hash = Float(hammingDistance(candidate.fingerprint, existing.fingerprint)) / 64
            return min(1, histogram * 1.8 + hash * 0.45)
        }.min() ?? 1
        let sameScenePenalty: Float
        if let scene = sceneIndexByID[candidate.id] {
            switch sceneUseCount[scene, default: 0] {
            case 0: sameScenePenalty = 0
            case 1: sameScenePenalty = 0.10
            default: sameScenePenalty = 0.22
            }
        } else {
            sameScenePenalty = 0
        }
        return quality * 0.72 + novelty * 0.48 - sameScenePenalty
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
            }) ?? candidates.first {
                if !occupied.contains(where: { $0.id == choice.id }) {
                    output.append(choice)
                    occupied.append(choice)
                }
            }
        }

        // In extremely short clips several buckets may map to the same sample. Use
        // the remaining usable timestamps before accepting any repeat.
        for candidate in pool.sorted(by: { $0.qualityScore > $1.qualityScore }) where occupied.count < count {
            if !occupied.contains(where: { $0.id == candidate.id }) {
                output.append(candidate)
                occupied.append(candidate)
            }
        }
        return output
    }
}
