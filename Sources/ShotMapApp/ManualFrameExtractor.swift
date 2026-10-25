import AVFoundation
import CoreGraphics
import Foundation
import OSLog

/// OSSignposter predates Swift's Sendable annotations. Its methods are used
/// only for diagnostic intervals, and Apple's signposting API is designed for
/// concurrent producers; keep that boundary explicit for the Swift 5.10 CI
/// compiler without making the extraction pipeline main-actor-bound.
private final class FrameExtractionSignposter: @unchecked Sendable {
    let value: OSSignposter

    init(category: String) {
        value = OSSignposter(
            subsystem: Bundle.main.bundleIdentifier ?? "com.ixiehao.shotmap",
            category: category
        )
    }
}

/// A compact candidate sampler used only after a person opens the manual
/// adjuster. The normal storyboard path remains a single, fast analysis pass.
enum ManualFrameExtractor {
    private static let candidateBatchSignposter = FrameExtractionSignposter(category: "CandidateSampling")
    private static let sharpnessBatchSignposter = FrameExtractionSignposter(category: "FrameRefinement")

    /// Around a proposed moment, compare the surrounding decoded frames and
    /// retain the one with the strongest fine detail. Three frames on each side
    /// is short enough to preserve the intended moment, while being wide enough
    /// to escape motion blur from a pan, a step, or a fast subject.
    static func captureSharpestFrame(
        from asset: AVURLAsset,
        duration: Double,
        at requestedTime: Double,
        identifier: Int,
        maximumEdge: CGFloat,
        compressionQuality: CGFloat
    ) async throws -> CapturedFrame {
        try Task.checkCancellation()
        let boundedDuration = max(0, duration - 0.001)
        let centre = min(max(0, requestedTime), boundedDuration)
        let frameRate = await nominalFrameRate(for: asset)
        // Decoding every comparison image at export resolution made a seven-frame
        // check substantially more expensive than the actual final decode. Fine
        // detail scoring operates on a compact luminance grid, so cap this first
        // pass and decode only the winning timestamp at the requested resolution.
        let analysisGenerator = AVAssetImageGenerator(asset: asset)
        analysisGenerator.appliesPreferredTrackTransform = true
        analysisGenerator.maximumSize = CGSize(
            width: sharpnessAnalysisMaximumEdge(for: maximumEdge),
            height: sharpnessAnalysisMaximumEdge(for: maximumEdge)
        )
        // This pass intentionally uses exact seeking. The earlier, tolerant
        // sampling pass stays fast; only the small +/- 3-frame neighbourhood
        // needs frame-level precision.
        analysisGenerator.requestedTimeToleranceBefore = .zero
        analysisGenerator.requestedTimeToleranceAfter = .zero

        defer { analysisGenerator.cancelAllCGImageGeneration() }

        // Adding one manually positioned frame still compares the complete
        // seven-frame neighbourhood. Submit it as one async decoder batch so
        // the cooperative worker is not blocked by seven synchronous seeks.
        let plans = [SharpnessPlan(
            index: 0,
            identifier: identifier,
            centre: centre,
            primaryTimes: sharpnessComparisonTimes(
                around: centre,
                duration: duration,
                frameRate: frameRate
            ),
            localRecoveryTimes: []
        )]
        let comparisonRequests = sharpnessRequestBatch(plans: plans, planIndices: [0]) { _, plan in
            plan.primaryTimes
        }
        let bestByPlan = try await scoreSharpnessBatch(
            using: analysisGenerator,
            requestBatch: comparisonRequests,
            plans: plans,
            existingBest: [nil]
        )
        guard let best = bestByPlan[0] else {
            throw StoryboardError.noUsableFrames
        }
        try Task.checkCancellation()

        // One full-resolution, exact decode preserves final export quality while
        // keeping the seven-frame comparison cheap. Retain the scored thumbnail
        // as a graceful fallback for damaged/VFR media whose second seek fails.
        let finalGenerator = AVAssetImageGenerator(asset: asset)
        finalGenerator.appliesPreferredTrackTransform = true
        finalGenerator.maximumSize = CGSize(width: maximumEdge, height: maximumEdge)
        finalGenerator.requestedTimeToleranceBefore = .zero
        finalGenerator.requestedTimeToleranceAfter = .zero
        defer { finalGenerator.cancelAllCGImageGeneration() }
        let finalRequests = sharpnessRequestBatch(plans: plans, planIndices: [0]) { _, _ in [best.time] }
        let finalImages = try await decodeFinalSharpnessBatch(
            using: finalGenerator,
            requestBatch: finalRequests,
            planCount: 1,
            compressionQuality: compressionQuality
        )
        try Task.checkCancellation()
        let final = finalImages[0]
        guard let jpegData = final?.jpegData ?? ImageCodec.jpegData(
            from: best.image,
            compressionQuality: compressionQuality
        ) else {
            throw StoryboardError.noUsableFrames
        }
        let resolvedTime = final?.time ?? best.time
        let aspectRatio = final?.aspectRatio ?? (best.image.height > 0
            ? Double(best.image.width) / Double(best.image.height)
            : 16.0 / 9.0)
        return CapturedFrame(id: identifier, time: resolvedTime, jpegData: jpegData, aspectRatio: aspectRatio)
    }

    /// Refines a selected manual set in decoder batches. Every chosen moment is
    /// first sampled exactly at its centre; only a low-clarity centre receives
    /// the same +/- 3-frame neighbourhood used by `captureSharpestFrame`.
    /// Finally, the winning moment is decoded at export size. Applying a 6 × 6
    /// grid therefore avoids spending seven exact seeks on an already crisp
    /// card, while motion blur, dissolves, and failed centre decodes keep the
    /// full sharpness recovery path.
    static func captureSharpestFrames(
        from asset: AVURLAsset,
        duration: Double,
        frames: [CapturedFrame],
        maximumEdge: CGFloat,
        compressionQuality: CGFloat
    ) async throws -> [CapturedFrame] {
        try Task.checkCancellation()
        guard !frames.isEmpty else { return [] }
        let batchInterval = sharpnessBatchSignposter.value.beginInterval("selectedFrameRefinement")
        defer {
            sharpnessBatchSignposter.value.endInterval("selectedFrameRefinement", batchInterval)
        }

        let frameRate = await nominalFrameRate(for: asset)
        let plans = frames.enumerated().map { offset, frame in
            let centre = min(max(0, frame.time), max(0, duration - 0.001))
            return SharpnessPlan(
                index: offset,
                identifier: frame.id,
                centre: centre,
                primaryTimes: [centre],
                localRecoveryTimes: sharpnessRecoveryTimes(
                    around: centre,
                    duration: duration,
                    frameRate: frameRate
                )
            )
        }

        let analysisGenerator = AVAssetImageGenerator(asset: asset)
        analysisGenerator.appliesPreferredTrackTransform = true
        let analysisEdge = sharpnessAnalysisMaximumEdge(for: maximumEdge)
        analysisGenerator.maximumSize = CGSize(width: analysisEdge, height: analysisEdge)
        analysisGenerator.requestedTimeToleranceBefore = .zero
        analysisGenerator.requestedTimeToleranceAfter = .zero
        defer { analysisGenerator.cancelAllCGImageGeneration() }

        let primaryRequests = sharpnessRequestBatch(
            plans: plans,
            planIndices: Array(plans.indices)
        ) { _, plan in plan.primaryTimes }
        let primaryInterval = sharpnessBatchSignposter.value.beginInterval("selectedFramePrimaryDecode")
        var bestByPlan = Array<SharpnessProbe?>(repeating: nil, count: plans.count)
        do {
            defer {
                sharpnessBatchSignposter.value.endInterval("selectedFramePrimaryDecode", primaryInterval)
            }
            bestByPlan = try await scoreSharpnessBatch(
                using: analysisGenerator,
                requestBatch: primaryRequests,
                plans: plans,
                existingBest: bestByPlan
            )
        }

        // A clear central frame is already the most faithful representation of
        // the moment the person selected. Fast movement, cross-dissolves, and
        // damaged samples are the exceptions: they get the exact same local
        // neighbourhood as before, so the optimization never intentionally
        // trades away an action peak for fewer decodes.
        let recoveryPlanIndices = plans.indices.filter {
            bestByPlan[$0].map { candidateNeedsRecovery($0.metrics) } ?? true
        }
        let localRecoveryRequests = sharpnessRequestBatch(
            plans: plans,
            planIndices: recoveryPlanIndices
        ) { _, plan in plan.localRecoveryTimes }
        if !localRecoveryRequests.requestedTimes.isEmpty {
            let recoveryInterval = sharpnessBatchSignposter.value.beginInterval("selectedFrameRecoveryDecode")
            defer {
                sharpnessBatchSignposter.value.endInterval("selectedFrameRecoveryDecode", recoveryInterval)
            }
            bestByPlan = try await scoreSharpnessBatch(
                using: analysisGenerator,
                requestBatch: localRecoveryRequests,
                plans: plans,
                existingBest: bestByPlan
            )
        }

        let finalGenerator = AVAssetImageGenerator(asset: asset)
        finalGenerator.appliesPreferredTrackTransform = true
        finalGenerator.maximumSize = CGSize(width: maximumEdge, height: maximumEdge)
        finalGenerator.requestedTimeToleranceBefore = .zero
        finalGenerator.requestedTimeToleranceAfter = .zero
        defer { finalGenerator.cancelAllCGImageGeneration() }

        let finalRequests = sharpnessRequestBatch(
            plans: plans,
            planIndices: plans.indices.filter { bestByPlan[$0] != nil }
        ) { index, _ in bestByPlan[index].map { [$0.time] } ?? [] }
        let finalInterval = sharpnessBatchSignposter.value.beginInterval("selectedFrameFinalDecode")
        let finalImages: [FinalSharpnessImage?]
        do {
            defer {
                sharpnessBatchSignposter.value.endInterval("selectedFrameFinalDecode", finalInterval)
            }
            finalImages = try await decodeFinalSharpnessBatch(
                using: finalGenerator,
                requestBatch: finalRequests,
                planCount: plans.count,
                compressionQuality: compressionQuality
            )
        }

        // This is intentionally a local, ephemeral accounting value. It is
        // exercised by tests to keep the decoder budget honest; it is neither
        // persisted nor reported outside the process.
        _ = selectedRefinementDiagnostics(
            itemCount: plans.count,
            primaryRequests: primaryRequests.requestedTimes.count,
            localRecoveryRequests: localRecoveryRequests.requestedTimes.count,
            finalRequests: finalRequests.requestedTimes.count
        )

        var output: [CapturedFrame] = []
        output.reserveCapacity(plans.count)
        for (index, plan) in plans.enumerated() {
            try Task.checkCancellation()
            guard let best = bestByPlan[index] else { continue }
            let final = finalImages[index]
            guard let jpegData = final?.jpegData ?? ImageCodec.jpegData(
                from: best.image,
                compressionQuality: compressionQuality
            ) else {
                continue
            }
            let capturedTime = final?.time ?? best.time
            let aspectRatio = final?.aspectRatio ?? (best.image.height > 0
                ? Double(best.image.width) / Double(best.image.height)
                : 16.0 / 9.0)
            output.append(CapturedFrame(
                id: plan.identifier,
                time: capturedTime,
                jpegData: jpegData,
                aspectRatio: aspectRatio
            ))
        }
        return output
    }

    private struct SharpnessPlan {
        let index: Int
        let identifier: Int
        let centre: Double
        let primaryTimes: [Double]
        let localRecoveryTimes: [Double]
    }

    private struct SharpnessProbe {
        let image: CGImage
        let time: Double
        let metrics: PixelMetrics
        let score: Float
    }

    private struct FinalSharpnessImage {
        let jpegData: Data
        let time: Double
        let aspectRatio: Double
    }

    private static func sharpnessRequestBatch(
        plans: [SharpnessPlan],
        planIndices: [Int],
        selecting times: (Int, SharpnessPlan) -> [Double]
    ) -> FrameImageRequestBatch {
        FrameImageRequestBatch(
            planTimes: planIndices.map { (index: $0, times: times($0, plans[$0])) }
        )
    }

    private static func scoreSharpnessBatch(
        using generator: AVAssetImageGenerator,
        requestBatch: FrameImageRequestBatch,
        plans: [SharpnessPlan],
        existingBest: [SharpnessProbe?]
    ) async throws -> [SharpnessProbe?] {
        var bestByPlan = existingBest
        if bestByPlan.count != plans.count {
            bestByPlan = Array<SharpnessProbe?>(repeating: nil, count: plans.count)
        }
        guard !requestBatch.requestedTimes.isEmpty else { return bestByPlan }

        for await result in generator.images(for: requestBatch.requestedTimes) {
            try Task.checkCancellation()
            guard case let .success(requestedTime, image, actualTime) = result else { continue }
            let planIndices = requestBatch.planIndices(for: requestedTime)
            let resolvedTime = actualTime.isValid && actualTime.seconds.isFinite
                ? actualTime.seconds
                : requestedTime.seconds
            let metrics = autoreleasepool { PixelMetrics.make(from: image) }
            let score = visualClarityScore(metrics)
            for index in planIndices {
                let distancePenalty = Float(abs(resolvedTime - plans[index].centre)) * 0.0001
                let probe = SharpnessProbe(
                    image: image,
                    time: resolvedTime,
                    metrics: metrics,
                    score: score - distancePenalty
                )
                if probe.score > (bestByPlan[index]?.score ?? -.greatestFiniteMagnitude)
                    || (probe.score == bestByPlan[index]?.score && probe.time < bestByPlan[index]!.time) {
                    bestByPlan[index] = probe
                }
            }
        }
        try Task.checkCancellation()
        return bestByPlan
    }

    private static func decodeFinalSharpnessBatch(
        using generator: AVAssetImageGenerator,
        requestBatch: FrameImageRequestBatch,
        planCount: Int,
        compressionQuality: CGFloat
    ) async throws -> [FinalSharpnessImage?] {
        var results = Array<FinalSharpnessImage?>(repeating: nil, count: planCount)
        guard !requestBatch.requestedTimes.isEmpty else { return results }

        for await result in generator.images(for: requestBatch.requestedTimes) {
            try Task.checkCancellation()
            guard case let .success(requestedTime, image, actualTime) = result else { continue }
            let planIndices = requestBatch.planIndices(for: requestedTime)
            let resolvedTime = actualTime.isValid && actualTime.seconds.isFinite
                ? actualTime.seconds
                : requestedTime.seconds
            // Keep compressed results, not every export-sized bitmap. At 64
            // cards, retaining 1280px RGBA images can cost hundreds of MB. Each
            // shared request is encoded once and its Data reused by all plans.
            guard let jpegData = autoreleasepool(invoking: {
                ImageCodec.jpegData(from: image, compressionQuality: compressionQuality)
            }) else { continue }
            let captured = FinalSharpnessImage(
                jpegData: jpegData,
                time: resolvedTime,
                aspectRatio: image.height > 0 ? Double(image.width) / Double(image.height) : 16.0 / 9.0
            )
            for index in planIndices {
                results[index] = captured
            }
        }
        try Task.checkCancellation()
        return results
    }

    /// PixelMetrics reduces every image to 48 × 48 before scoring. Limiting the
    /// comparison decode to 480 px is therefore visually equivalent for this
    /// decision while sharply reducing decode, memory, and JPEG-buffer pressure.
    static func sharpnessAnalysisMaximumEdge(for requestedMaximumEdge: CGFloat) -> CGFloat {
        min(480, max(1, requestedMaximumEdge))
    }

    /// Kept deterministic and separately testable: a normal 30 fps moment has
    /// exactly 7 comparison points (the target plus three frames on either side).
    static func sharpnessComparisonTimes(
        around time: Double,
        duration: Double,
        frameRate: Double,
        neighbourhoodFrames: Int = 3
    ) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        let safeRate = frameRate.isFinite && frameRate > 1 ? frameRate : 30
        let centre = min(max(0, time), max(0, duration - 0.001))
        let step = 1.0 / safeRate
        var times: [Double] = []
        var seen = Set<Int64>()
        for offset in -max(0, neighbourhoodFrames)...max(0, neighbourhoodFrames) {
            let candidate = min(max(0, centre + Double(offset) * step), max(0, duration - 0.001))
            // At either end several offsets collapse to the same frame.
            let key = Int64((candidate * safeRate).rounded())
            if seen.insert(key).inserted {
                times.append(candidate)
            }
        }
        return times
    }

    /// The centre is always decoded in the primary batch. Recovery therefore
    /// requests only its neighbours, retaining the historical +/- 3-frame
    /// search window without duplicating the centre request.
    static func sharpnessRecoveryTimes(
        around time: Double,
        duration: Double,
        frameRate: Double,
        neighbourhoodFrames: Int = 3
    ) -> [Double] {
        let allTimes = sharpnessComparisonTimes(
            around: time,
            duration: duration,
            frameRate: frameRate,
            neighbourhoodFrames: neighbourhoodFrames
        )
        let safeRate = frameRate.isFinite && frameRate > 1 ? frameRate : 30
        let centre = min(max(0, time), max(0, duration - 0.001))
        let centreKey = candidateRequestKey(for: centre, frameRate: safeRate)
        return allTimes.filter { candidateRequestKey(for: $0, frameRate: safeRate) != centreKey }
    }

    /// Decodes one user-positioned frame for the manual editor's preview
    /// timeline. This is deliberately separate from candidate sampling: moving
    /// the scrubber must never replace, reorder, or otherwise disturb the
    /// existing automatic candidates.
    static func captureFrame(
        from videoURL: URL,
        at requestedTime: Double,
        identifier: Int,
        maximumEdge: CGFloat = 1_600
    ) async throws -> CapturedFrame {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: videoURL)
        guard try await asset.load(.isPlayable) else { throw StoryboardError.unsupportedCodec }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw StoryboardError.unreadableVideo }

        let time = min(max(0, requestedTime), max(0, duration - 0.01))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumEdge, height: maximumEdge)
        // A manual addition should represent the time the person chose, rather
        // than a nearby key frame as used by the fast gallery sampler.
        let tolerance = CMTime(seconds: 0.04, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        defer { generator.cancelAllCGImageGeneration() }
        try Task.checkCancellation()
        // Scrubbing frequently supersedes the previous request. Suspend while
        // AVFoundation decodes instead of occupying a cooperative Swift worker
        // with a synchronous seek, and never publish an obsolete result.
        for await result in generator.images(for: [CMTime(seconds: time, preferredTimescale: 600)]) {
            try Task.checkCancellation()
            guard case let .success(_, image, actualTime) = result,
                  let jpegData = ImageCodec.jpegData(from: image, compressionQuality: 0.92) else { continue }
            try Task.checkCancellation()
            let actualSeconds = actualTime.seconds
            let capturedTime = actualTime.isValid && actualSeconds.isFinite ? actualSeconds : time
            let aspectRatio = image.height > 0 ? Double(image.width) / Double(image.height) : 16.0 / 9.0
            return CapturedFrame(
                id: identifier,
                time: capturedTime,
                jpegData: jpegData,
                aspectRatio: aspectRatio
            )
        }
        try Task.checkCancellation()
        throw StoryboardError.noUsableFrames
    }

    /// Re-decodes only the final automatic tiles at presentation size after a
    /// lightweight broad scan. It uses the same tolerant seeking as the former
    /// broad pass, so this is a resolution upgrade rather than a new selection
    /// rule. Exact sharpness refinement, when needed, is applied separately.
    static func capturePresentationFrames(
        from asset: AVURLAsset,
        frames: [CapturedFrame],
        maximumEdge: CGFloat,
        compressionQuality: CGFloat
    ) async throws -> [CapturedFrame] {
        try Task.checkCancellation()
        guard !frames.isEmpty else { return [] }
        let interval = sharpnessBatchSignposter.value.beginInterval("presentationFrameDecode")
        defer {
            sharpnessBatchSignposter.value.endInterval("presentationFrameDecode", interval)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumEdge, height: maximumEdge)
        let tolerance = CMTime(seconds: 0.75, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        defer { generator.cancelAllCGImageGeneration() }

        let requests = FrameImageRequestBatch(
            planTimes: frames.enumerated().map { (index: $0.offset, times: [$0.element.time]) }
        )

        var capturedByID: [Int: CapturedFrame] = [:]
        for await result in generator.images(for: requests.requestedTimes) {
            try Task.checkCancellation()
            guard case let .success(requestedTime, image, actualTime) = result,
                  let jpegData = ImageCodec.jpegData(from: image, compressionQuality: compressionQuality) else {
                continue
            }
            let time = actualTime.isValid && actualTime.seconds.isFinite ? actualTime.seconds : requestedTime.seconds
            let aspectRatio = image.height > 0
                ? Double(image.width) / Double(image.height)
                : 16.0 / 9.0
            for index in requests.planIndices(for: requestedTime) {
                let identifier = frames[index].id
                capturedByID[identifier] = CapturedFrame(
                    id: identifier,
                    time: time,
                    jpegData: jpegData,
                    aspectRatio: aspectRatio
                )
            }
        }
        try Task.checkCancellation()
        return frames.compactMap { capturedByID[$0.id] }
    }

    static func captureCandidates(
        from videoURL: URL,
        gridSide: Int,
        outputWidth: Int,
        count: Int,
        batch: Int
    ) async throws -> [CapturedFrame] {
        try Task.checkCancellation()
        let wholeBatch = candidateBatchSignposter.value.beginInterval("manualCandidateBatch")
        defer {
            candidateBatchSignposter.value.endInterval("manualCandidateBatch", wholeBatch)
        }

        let asset = AVURLAsset(url: videoURL)
        guard try await asset.load(.isPlayable) else { throw StoryboardError.unsupportedCodec }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw StoryboardError.unreadableVideo }

        let frameRate = await nominalFrameRate(for: asset)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let estimatedCellWidth = Double(max(1_920, outputWidth)) / Double(max(1, gridSide))
        let maximumEdge = min(1_280, max(480, estimatedCellWidth * 1.15))
        // Gallery cards only need enough pixels for clear review. Limiting these
        // probes to 640px gives us room to inspect a tiny neighbourhood without
        // regressing the editor's perceived load time.
        let analysisEdge = min(640, maximumEdge)
        generator.maximumSize = CGSize(width: CGFloat(analysisEdge), height: CGFloat(analysisEdge))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        defer { generator.cancelAllCGImageGeneration() }

        let sampleCount = max(1, count)
        // A deterministic phase shift makes “regenerate” produce a visibly
        // different yet evenly distributed set of moments without random jitter.
        let phase = Double((batch * 37) % 97) / 97.0
        let plans = (0..<sampleCount).map { index -> CandidatePlan in
            let shiftedProgress = (Double(index) + 0.5 + phase) / Double(sampleCount)
            let progress = shiftedProgress >= 1 ? shiftedProgress - 1 : shiftedProgress
            let requestedTime = min(max(0, duration * progress), max(0, duration - 0.01))
            return CandidatePlan(
                identifier: -((batch + 1) * 10_000 + index + 1),
                requestedTime: requestedTime,
                primaryTimes: [requestedTime],
                localRecoveryTimes: candidateRecoveryTimes(
                    around: requestedTime,
                    duration: duration,
                    frameRate: frameRate
                ),
                wideRecoveryTimes: candidateWideRecoveryTimes(
                    around: requestedTime,
                    duration: duration,
                    frameRate: frameRate
                )
            )
        }

        // AVFoundation can decode a timeline of requested moments in one
        // stream. Start with the intended moment for every card, then spend
        // neighbouring seeks only where the centre is actually diffuse. That
        // keeps ordinary gallery loads light, while fast action, dissolves, and
        // missing centre decodes still receive the same two-stage recovery.
        let allPlanIndices = Array(plans.indices)
        let primaryBatch = candidateRequestBatch(
            plans: plans,
            planIndices: allPlanIndices,
            selecting: \.primaryTimes
        )
        var bestByPlan = Array<CandidateProbe?>(repeating: nil, count: plans.count)
        do {
            let primaryInterval = candidateBatchSignposter.value.beginInterval("manualCandidatePrimaryDecode")
            defer {
                candidateBatchSignposter.value.endInterval("manualCandidatePrimaryDecode", primaryInterval)
            }
            bestByPlan = try await scoreCandidateBatch(
                using: generator,
                requestBatch: primaryBatch,
                plans: plans,
                existingBest: bestByPlan
            )
        }

        // Only cards whose centre still looks diffuse receive the two nearby
        // probes, delivered as one decoder batch. A separate wide pass below
        // remains available when the nearby probe still lands in a dissolve.
        let recoveryPlanIndices = plans.indices.filter {
            bestByPlan[$0].map { candidateNeedsRecovery($0.metrics) } ?? true
        }
        var localRecoveryBatch = FrameImageRequestBatch.empty
        if !recoveryPlanIndices.isEmpty {
            localRecoveryBatch = candidateRequestBatch(
                plans: plans,
                planIndices: recoveryPlanIndices,
                selecting: \.localRecoveryTimes
            )
            if !localRecoveryBatch.requestedTimes.isEmpty {
                let recoveryInterval = candidateBatchSignposter.value.beginInterval("manualCandidateRecoveryDecode")
                do {
                    defer {
                        candidateBatchSignposter.value.endInterval("manualCandidateRecoveryDecode", recoveryInterval)
                    }
                    bestByPlan = try await scoreCandidateBatch(
                        using: generator,
                        requestBatch: localRecoveryBatch,
                        plans: plans,
                        existingBest: bestByPlan
                    )
                }
            }
        }

        // A short cross-dissolve can remain diffuse after the nearby 0.3–0.45s
        // probe. Retain the wider 10-frame escape hatch, but only for those
        // unresolved cards instead of applying it to a whole gallery.
        let wideRecoveryPlanIndices = plans.indices.filter {
            bestByPlan[$0].map { candidateNeedsRecovery($0.metrics) } ?? true
        }
        var wideRecoveryBatch = FrameImageRequestBatch.empty
        if !wideRecoveryPlanIndices.isEmpty {
            wideRecoveryBatch = candidateRequestBatch(
                plans: plans,
                planIndices: wideRecoveryPlanIndices,
                selecting: \.wideRecoveryTimes
            )
            if !wideRecoveryBatch.requestedTimes.isEmpty {
                let recoveryInterval = candidateBatchSignposter.value.beginInterval("manualCandidateWideRecoveryDecode")
                defer {
                    candidateBatchSignposter.value.endInterval("manualCandidateWideRecoveryDecode", recoveryInterval)
                }
                bestByPlan = try await scoreCandidateBatch(
                    using: generator,
                    requestBatch: wideRecoveryBatch,
                    plans: plans,
                    existingBest: bestByPlan
                )
            }
        }

        // The structure is intentionally not persisted or surfaced to users.
        // It gives tests a deterministic way to guard this decoder budget
        // without introducing telemetry into a local-first app.
        _ = candidateSamplingDiagnostics(
            itemCount: plans.count,
            primaryRequests: primaryBatch.requestedTimes.count,
            localRecoveryRequests: localRecoveryBatch.requestedTimes.count,
            wideRecoveryRequests: wideRecoveryBatch.requestedTimes.count
        )

        var frames: [CapturedFrame] = []
        frames.reserveCapacity(sampleCount)
        for (index, plan) in plans.enumerated() {
            try Task.checkCancellation()
            guard let best = bestByPlan[index],
                  let jpegData = ImageCodec.jpegData(from: best.image, compressionQuality: 0.90) else {
                continue
            }
            let aspectRatio = best.image.height > 0
                ? Double(best.image.width) / Double(best.image.height)
                : 16.0 / 9.0
            frames.append(CapturedFrame(
                id: plan.identifier,
                time: best.time,
                jpegData: jpegData,
                aspectRatio: aspectRatio
            ))
        }

        guard !frames.isEmpty else { throw StoryboardError.noUsableFrames }
        return frames.sorted { $0.time < $1.time }
    }

    private struct CandidatePlan {
        let identifier: Int
        let requestedTime: Double
        let primaryTimes: [Double]
        let localRecoveryTimes: [Double]
        let wideRecoveryTimes: [Double]
    }

    private struct CandidateProbe {
        let image: CGImage
        let time: Double
        let metrics: PixelMetrics
        let score: Float
    }

    private static func candidateRequestBatch(
        plans: [CandidatePlan],
        planIndices: [Int],
        selecting times: KeyPath<CandidatePlan, [Double]>
    ) -> FrameImageRequestBatch {
        FrameImageRequestBatch(
            planTimes: planIndices.map { (index: $0, times: plans[$0][keyPath: times]) }
        )
    }

    private static func scoreCandidateBatch(
        using generator: AVAssetImageGenerator,
        requestBatch: FrameImageRequestBatch,
        plans: [CandidatePlan],
        existingBest: [CandidateProbe?]
    ) async throws -> [CandidateProbe?] {
        guard !requestBatch.requestedTimes.isEmpty else { return existingBest }
        var bestByPlan = existingBest

        for await result in generator.images(for: requestBatch.requestedTimes) {
            try Task.checkCancellation()
            guard case let .success(requestedTime, image, actualTime) = result else { continue }
            let planIndices = requestBatch.planIndices(for: requestedTime)

            let resolvedTime = actualTime.isValid && actualTime.seconds.isFinite
                ? actualTime.seconds
                : requestedTime.seconds
            let metrics = autoreleasepool { PixelMetrics.make(from: image) }
            for index in planIndices {
                // Keep candidates close to their intended time, while allowing a
                // nearby clear frame to win over an obvious ghost frame.
                let distancePenalty = Float(abs(resolvedTime - plans[index].requestedTime)) * 0.025
                let probe = CandidateProbe(
                    image: image,
                    time: resolvedTime,
                    metrics: metrics,
                    score: visualClarityScore(metrics) - distancePenalty
                )
                if probe.score > (bestByPlan[index]?.score ?? -.greatestFiniteMagnitude) {
                    bestByPlan[index] = probe
                }
            }
        }
        return bestByPlan
    }

    private static func candidateRequestKey(for seconds: Double, frameRate: Double) -> Int64 {
        Int64((seconds * max(1, frameRate)).rounded())
    }

    /// A compact three-point probe is intentionally wider than the final
    /// export's +/- 3-frame refinement. A dissolve commonly lasts half a
    /// second or more; a 3-frame probe would keep all three samples inside the
    /// same ghost image. Candidate sampling now decodes its centre first and
    /// uses only the two outer probes for low-clarity cards.
    static func candidateComparisonTimes(
        around time: Double,
        duration: Double,
        frameRate: Double
    ) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        let safeRate = frameRate.isFinite && frameRate > 1 ? frameRate : 30
        let centre = min(max(0, time), max(0, duration - 0.001))
        let step = min(0.45, max(0.30, 15.0 / safeRate))
        var times: [Double] = []
        var seen = Set<Int64>()
        for offset in [-1.0, 0, 1.0] {
            let candidate = min(max(0, centre + offset * step), max(0, duration - 0.001))
            let key = Int64((candidate * safeRate).rounded())
            if seen.insert(key).inserted { times.append(candidate) }
        }
        return times
    }

    /// The centre has already been decoded by the primary candidate pass, so
    /// this helper returns just the outer sides of `candidateComparisonTimes`.
    /// Keeping it separately testable prevents a later optimization from
    /// accidentally reintroducing duplicate exact seeks for every card.
    static func candidateRecoveryTimes(
        around time: Double,
        duration: Double,
        frameRate: Double
    ) -> [Double] {
        let allTimes = candidateComparisonTimes(
            around: time,
            duration: duration,
            frameRate: frameRate
        )
        let safeRate = frameRate.isFinite && frameRate > 1 ? frameRate : 30
        let centre = min(max(0, time), max(0, duration - 0.001))
        let centreKey = candidateRequestKey(for: centre, frameRate: safeRate)
        return allTimes.filter { candidateRequestKey(for: $0, frameRate: safeRate) != centreKey }
    }

    /// Recovery probes are deliberately separate from the normal three-frame
    /// pass: they are evaluated only for a likely ghost frame. Keeping the
    /// offset at ten frames preserves the represented scene while reaching the
    /// stable side of a short cross-dissolve or a fast action blur.
    static func candidateWideRecoveryTimes(
        around time: Double,
        duration: Double,
        frameRate: Double
    ) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        let safeRate = frameRate.isFinite && frameRate > 1 ? frameRate : 30
        let centre = min(max(0, time), max(0, duration - 0.001))
        let step = 10.0 / safeRate
        var times: [Double] = []
        var seen = Set<Int64>()
        for offset in [-1.0, 1.0] {
            let candidate = min(max(0, centre + offset * step), max(0, duration - 0.001))
            let key = Int64((candidate * safeRate).rounded())
            if seen.insert(key).inserted { times.append(candidate) }
        }
        return times
    }

    /// A ghost image can carry plenty of weak edges, so it needs a stricter
    /// gate than simple sharpness. This only controls whether the two bounded
    /// recovery probes run; the highest visual-quality frame still wins.
    static func candidateNeedsRecovery(_ metrics: PixelMetrics) -> Bool {
        // This is intentionally a little conservative. It is cheaper to run
        // two neighbouring probes for a borderline action card than to let a
        // high-contrast motion trail look "sharp enough" at 48 × 48.
        visualClarityScore(metrics) < 0.55
            || metrics.focusedEdgeRatio < 0.45
            || (metrics.sharpness < 0.115 && metrics.contrast < 0.16)
    }

    private static func visualClarityScore(_ metrics: PixelMetrics) -> Float {
        let detail = min(1, metrics.sharpness / 0.18)
        let focusedEdges = min(1, metrics.focusedEdgeRatio / 0.62)
        let contrast = min(1, metrics.contrast / 0.24)
        let exposure = min(1, max(0, (metrics.luminance - 0.06) / 0.32))
        let clippingPenalty = max(0, metrics.brightRatio - 0.40) * 0.28
            + max(0, metrics.blackRatio - 0.68) * 0.10
        let diffuseEdgePenalty = max(0, 0.45 - metrics.focusedEdgeRatio) * 0.30
        let lowContrastPenalty = max(0, 0.10 - metrics.contrast) * 0.20
        return detail * 0.43 + focusedEdges * 0.39 + contrast * 0.14 + exposure * 0.04
            - clippingPenalty - diffuseEdgePenalty - lowContrastPenalty
    }

    private static func nominalFrameRate(for asset: AVURLAsset) async -> Double {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let rate = try? await track.load(.nominalFrameRate),
              rate.isFinite, rate > 1 else { return 30 }
        return Double(rate)
    }

    /// A deterministic accounting helper for tests and local profiling. It is
    /// not written to disk, included in exports, or sent anywhere.
    static func candidateSamplingDiagnostics(
        itemCount: Int,
        primaryRequests: Int,
        localRecoveryRequests: Int,
        wideRecoveryRequests: Int
    ) -> FrameDecodeDiagnostics {
        FrameDecodeDiagnostics(
            itemCount: itemCount,
            primaryRequests: primaryRequests,
            localRecoveryRequests: localRecoveryRequests,
            wideRecoveryRequests: wideRecoveryRequests,
            finalRequests: 0,
            // Before centre-first probing, every gallery card started with a
            // fixed three-point exact sweep. The optional wide recovery was
            // already conditional and is deliberately excluded from this
            // conservative baseline.
            fixedBaselineRequestsPerItem: 3
        )
    }

    /// A deterministic accounting helper for selected-frame apply. The prior
    /// batch path always decoded seven analysis probes plus one final image per
    /// selected frame; the new centre-first path should stay below that budget
    /// unless every card genuinely needs blur recovery.
    static func selectedRefinementDiagnostics(
        itemCount: Int,
        primaryRequests: Int,
        localRecoveryRequests: Int,
        finalRequests: Int
    ) -> FrameDecodeDiagnostics {
        FrameDecodeDiagnostics(
            itemCount: itemCount,
            primaryRequests: primaryRequests,
            localRecoveryRequests: localRecoveryRequests,
            wideRecoveryRequests: 0,
            finalRequests: finalRequests,
            fixedBaselineRequestsPerItem: 8
        )
    }
}

/// Maps submitted decoder times back to their consumers. The key is derived
/// from the same CMTime that AVFoundation receives, rather than a rounded
/// nominal frame number: VFR timestamps can share a nominal frame bucket, and
/// converting seconds to CMTime can cross a rounding boundary in that bucket.
/// Identical requests still decode once and serve every interested plan.
struct FrameImageRequestBatch {
    private static let timescale: CMTimeScale = 60_000
    let requestedTimes: [CMTime]
    private let indicesByRequestKey: [Int64: [Int]]

    static let empty = FrameImageRequestBatch(planTimes: [])

    init(planTimes: [(index: Int, times: [Double])]) {
        var requestsByKey: [Int64: CMTime] = [:]
        var indicesByKey: [Int64: [Int]] = [:]
        for plan in planTimes {
            var keysForPlan = Set<Int64>()
            for seconds in plan.times {
                guard seconds.isFinite, seconds >= 0 else { continue }
                let time = CMTime(seconds: seconds, preferredTimescale: Self.timescale)
                guard let key = Self.requestKey(for: time), keysForPlan.insert(key).inserted else { continue }
                requestsByKey[key] = time
                indicesByKey[key, default: []].append(plan.index)
            }
        }
        requestedTimes = requestsByKey.keys.sorted().compactMap { requestsByKey[$0] }
        indicesByRequestKey = indicesByKey
    }

    func planIndices(for requestedTime: CMTime) -> [Int] {
        guard let key = Self.requestKey(for: requestedTime) else { return [] }
        return indicesByRequestKey[key] ?? []
    }

    private static func requestKey(for time: CMTime) -> Int64? {
        guard time.isValid, time.seconds.isFinite else { return nil }
        let normalized = CMTimeConvertScale(time, timescale: timescale, method: .roundHalfAwayFromZero)
        return normalized.isValid ? normalized.value : nil
    }
}

/// Pure in-memory decoder-budget accounting. This exists so performance
/// regressions can be caught in XCTest without collecting user activity or
/// introducing telemetry into ShotMap's local-first processing model.
struct FrameDecodeDiagnostics: Equatable, Sendable {
    let itemCount: Int
    let primaryRequests: Int
    let localRecoveryRequests: Int
    let wideRecoveryRequests: Int
    let finalRequests: Int
    let fixedBaselineRequestsPerItem: Int

    var totalRequests: Int {
        primaryRequests + localRecoveryRequests + wideRecoveryRequests + finalRequests
    }

    var fixedBaselineRequestCount: Int {
        max(0, itemCount) * max(0, fixedBaselineRequestsPerItem)
    }

    var avoidedRequests: Int {
        max(0, fixedBaselineRequestCount - totalRequests)
    }

    var avoidedRequestRatio: Double {
        guard fixedBaselineRequestCount > 0 else { return 0 }
        return Double(avoidedRequests) / Double(fixedBaselineRequestCount)
    }
}

/// Reuses the automatic path's visual quality and de-duplication rules for the
/// already-decoded candidate gallery. It intentionally skips a second Vision
/// pass, making the one-click suggestion nearly immediate.
enum ManualFrameSelector {
    static func selectIDs(from candidates: [CapturedFrame], count: Int) -> [Int] {
        let targetCount = min(max(0, count), candidates.count)
        guard targetCount > 0 else { return [] }

        let descriptors = candidates.compactMap { candidate -> FrameDescriptor? in
            guard let image = ImageCodec.cgImage(from: candidate.jpegData) else {
                return nil
            }
            let metrics = PixelMetrics.make(from: image)
            var descriptor = FrameDescriptor(
                id: candidate.id,
                time: candidate.time,
                histogram: metrics.histogram,
                luminance: metrics.luminance,
                blackRatio: metrics.blackRatio,
                sharpness: metrics.sharpness,
                fingerprint: metrics.fingerprint,
                previewData: candidate.jpegData
            )
            descriptor.aspectRatio = candidate.aspectRatio
            return descriptor
        }

        var selectedIDs = Set(FrameSelection.chooseFrames(from: descriptors, count: targetCount).map(\.id))
        if selectedIDs.count < targetCount {
            let remaining = candidates
                .filter { !selectedIDs.contains($0.id) }
                .sorted { $0.time < $1.time }
            selectedIDs.formUnion(evenlySpacedIDs(from: remaining, count: targetCount - selectedIDs.count))
        }

        // A damaged thumbnail should not make the manual editor impossible to
        // complete. Use any remaining candidate only after the visual rules and
        // distributed fallback have been exhausted.
        if selectedIDs.count < targetCount {
            for candidate in candidates where selectedIDs.count < targetCount {
                selectedIDs.insert(candidate.id)
            }
        }
        return candidates
            .filter { selectedIDs.contains($0.id) }
            .sorted { $0.time < $1.time }
            .prefix(targetCount)
            .map(\.id)
    }

    private static func evenlySpacedIDs(from candidates: [CapturedFrame], count: Int) -> [Int] {
        guard count > 0, !candidates.isEmpty else { return [] }
        guard candidates.count > count else { return candidates.map(\.id) }
        if count == 1 { return [candidates[candidates.count / 2].id] }
        return (0..<count).map { slot in
            let position = Double(slot) * Double(candidates.count - 1) / Double(count - 1)
            return candidates[Int(position.rounded())].id
        }
    }
}
