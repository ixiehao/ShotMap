import AVFoundation
import CoreGraphics
import Foundation
import OSLog
import Vision

/// A video-local, bounded pipeline. Evidence belongs to a particular decoded
/// PTS; changing the image means running the same quality gate again.
enum AutomaticFramePipeline {
    static func run(
        videoURL: URL,
        gridSide: Int,
        outputWidth: Int,
        progress: @escaping @Sendable (Double) -> Void,
        onPreviewFrame: @escaping @Sendable (CapturedFrame, Int, Int) async -> Void
    ) async throws -> StoryboardResult {
        let cancellation = AutomaticVisionCancellation()
        return try await withTaskCancellationHandler {
            try await execute(videoURL: videoURL, gridSide: gridSide, outputWidth: outputWidth,
                progress: progress, onPreviewFrame: onPreviewFrame, cancellation: cancellation)
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func execute(
        videoURL: URL, gridSide: Int, outputWidth: Int,
        progress: @escaping @Sendable (Double) -> Void,
        onPreviewFrame: @escaping @Sendable (CapturedFrame, Int, Int) async -> Void,
        cancellation: AutomaticVisionCancellation
    ) async throws -> StoryboardResult {
        let performance = AutomaticFramePerformance()
        defer { performance.emit() }
        try Task.checkCancellation()
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw StoryboardError.unreadableVideo }
        let playable = try await asset.load(.isPlayable)
        if !playable {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard !tracks.isEmpty else {
                throw StoryboardError.unreadableVideo
            }
            throw StoryboardError.unsupportedCodec
        }
        let side = StoryboardGrid.boundedSide(gridSide)
        let count = side * side
        let policy = AutomaticFrameSamplingPolicy(duration: duration, targetCount: count)
        var state = AutomaticFrameAnalysisState(policy: policy, cancellation: cancellation, performance: performance)
        let started = Date()
        let initial = state.makeRequests(policy.initialTimes)
        var initialDecoded = 0
        let initialDecodeStarted = performance.begin()
        try await ManualFrameExtractor.decodeAutomaticFrames(
            from: asset, requests: initial, maximumEdge: 480,
            tolerance: CMTime(seconds: min(0.25, duration / Double(policy.initialCount) * 0.2), preferredTimescale: 60_000),
            requireExactPTS: false
        ) { id, pts, image in
            initialDecoded += 1
            state.accept(id: id, pts: pts, image: image)
            progress(0.05 + 0.35 * Double(state.records.count) / Double(max(1, initial.count)))
        }
        performance.finish(.discoveryDecode, since: initialDecodeStarted, count: initial.count)
        performance.increment(.discoveryDecoded, by: initialDecoded)
        AutomaticFrameDiagnostics.write("discovery phase=initial requested=\(initial.count) decoded=\(initialDecoded) newUnique=\(state.records.count)")
        try Task.checkCancellation()
        guard !state.records.isEmpty else { throw StoryboardError.unreadableVideo }

        // Reserve semantic checks for terminal candidates; absence of a check
        // never becomes a fabricated zero-person or zero-text observation.
        progress(0.42)
        // Reserve the existing first-pass budget across the timeline before
        // appearance-based ranking. Repeated layouts otherwise spend the whole
        // semantic allowance on one end of a person-free video.
        let initialSemanticLimit = max(count * 2, count + 8)
        try state.auditCoverageCandidates(limit: count)
        try state.auditProvisionalSelection(limit: max(0, initialSemanticLimit - state.semanticChecks))
        progress(0.50)
        var additionalRequests = 0
        additionalRequests += try await reviewDetailedText(from: asset, state: &state,
            requestLimit: min(policy.additionalRequestLimit, max(4, count)))
        try state.auditProvisionalSelection(limit: count)
        progress(0.55)
        let initialSeconds = Date().timeIntervalSince(started)
        let recoveryDeadline = Date().addingTimeInterval(min(12, max(2, initialSeconds * 2)))
        for round in 0..<2 {
            try Task.checkCancellation()
            guard additionalRequests < policy.additionalRequestLimit else { break }
            // A decoded but unreviewed representative is cheaper than another
            // seek into the same interval. Coverage belongs to the whole verified
            // pool, not only the K thumbnails chosen for the current layout.
            try state.auditCoverageCandidates(limit: max(4, count / 4))
            additionalRequests += try await reviewDetailedText(from: asset, state: &state,
                requestLimit: policy.additionalRequestLimit - additionalRequests)
            try state.auditProvisionalSelection()
            let selected = state.verifiedSelection()
            let remaining = policy.additionalRequestLimit - additionalRequests
            let plan = state.recoveryPlan(selected: selected, round: round, remaining: remaining)
            if plan.centres.isEmpty && selected.count == count { break }
            // The deadline limits optional improvement, never discards the
            // remaining bounded recovery allowance while the result is short.
            if selected.count == count && Date() >= recoveryDeadline { break }
            let localTimes = plan.centres.flatMap { policy.localTimes(around: $0, expansion: round) }
            // Keep at least a quarter of recovery work distributed through the
            // video, including parts that never yielded a provisional winner.
            let coverageCount = max(4, min(plan.requestLimit / 4, policy.initialCount / 2))
            let coverageTimes = policy.coverageTimes(round: round, count: coverageCount * 2)
                .filter { !state.isConfirmedCardTime($0) }
            let batch = state.makeRecoveryRequests(localTimes: localTimes,
                coverageTimes: coverageTimes, limit: plan.requestLimit)
            guard !batch.isEmpty else { continue }
            state.recordRecoveryAttempt(plan: plan, requests: batch)
            additionalRequests += batch.count
            let previousUnique = state.records.count
            var recoveryDecoded = 0
            let recoveryDecodeStarted = performance.begin()
            try await ManualFrameExtractor.decodeAutomaticFrames(
                from: asset, requests: batch, maximumEdge: 480, tolerance: .zero, requireExactPTS: false
            ) { id, pts, image in
                recoveryDecoded += 1
                state.accept(id: id, pts: pts, image: image)
            }
            performance.finish(.discoveryDecode, since: recoveryDecodeStarted, count: batch.count)
            performance.increment(.discoveryDecoded, by: recoveryDecoded)
            AutomaticFrameDiagnostics.write("discovery phase=recovery requested=\(batch.count) decoded=\(recoveryDecoded) newUnique=\(state.records.count - previousUnique)")
            // New local alternatives must get their own subject evidence;
            // otherwise an old face bonus can prevent a sharper unknown frame
            // from ever entering the provisional set and being inspected.
            try state.auditRecoveredCandidates(batch.map(\.id), limit: max(count, policy.semanticRequestLimit / 4))
            try state.auditProvisionalSelection()
            additionalRequests += try await reviewDetailedText(from: asset, state: &state,
                requestLimit: policy.additionalRequestLimit - additionalRequests)
            try state.auditProvisionalSelection()
            progress(0.55 + 0.15 * Double(round + 1) / 2)
        }

        state.markRiskAroundConfirmedTerminalCard()
        try state.confirmTerminalCardRun()
        var selected = state.verifiedSelection()
        state.logSelection(selected)
        guard selected.count == count else {
            throw StoryboardError.insufficientUsableFrames(selected.count, count)
        }
        progress(0.72)
        selected.sort { $0.time < $1.time }
        // Show only semantically and visually audited candidates, before the
        // final-size decode. Exact PTS and chronological slots are frozen here.
        for (index, descriptor) in selected.enumerated() {
            try Task.checkCancellation()
            if let preview = state.preview(for: descriptor.id) {
                await onPreviewFrame(preview, index, count)
            }
            await Task.yield()
        }
        let finalEdge = min(1_280, max(480, CGFloat(Double(max(1_920, outputWidth)) / Double(side) * 1.15)))
        var finalByID: [Int: CapturedFrame] = [:]
        var rejectedFinalIDs = Set<Int>()
        var finalDecoded = 0
        var requests: [AutomaticFrameTimeRequest] = []
        for descriptor in selected {
            try Task.checkCancellation()
            guard let record = state.records[descriptor.id] else { continue }
            // The retained image is the original decoded CGImage at this exact
            // PTS and cap. A JPEG preview never qualifies for raw-image reuse.
            if let image = record.reusableFinalImage(maximumEdge: finalEdge) {
                performance.increment(.finalRawCacheHits)
                switch AutomaticFinalFrameRenderer.render(record: record, actualPTS: record.pts,
                    image: image, slotID: descriptor.id, performance: performance) {
                case let .accepted(frame): finalByID[descriptor.id] = frame
                case .rejected: rejectedFinalIDs.insert(descriptor.id)
                case .encodingFailed: break
                }
            } else { requests.append(AutomaticFrameTimeRequest(id: descriptor.id, time: record.pts)) }
        }
        let finalDecodeStarted = performance.begin()
        try await ManualFrameExtractor.decodeAutomaticFrames(
            from: asset, requests: requests, maximumEdge: finalEdge, tolerance: .zero, requireExactPTS: true
        ) { id, pts, image in
            finalDecoded += 1
            guard let original = state.records[id] else { return }
            switch AutomaticFinalFrameRenderer.render(record: original, actualPTS: pts,
                image: image, slotID: id, performance: performance) {
            case let .accepted(frame): finalByID[id] = frame
            case .rejected: rejectedFinalIDs.insert(id)
            case .encodingFailed: break
            }
        }
        performance.finish(.finalDecode, since: finalDecodeStarted, count: requests.count)
        performance.increment(.finalDecoded, by: finalDecoded)
        AutomaticFrameDiagnostics.write("samePTS phase=final requested=\(requests.count) decoded=\(finalDecoded) verified=\(finalByID.count) rejected=\(rejectedFinalIDs.count)")
        // A failed exact output decode may use an already audited analysis image
        // at the *same* PTS. It cannot substitute an unexamined neighbouring frame.
        for descriptor in selected where finalByID[descriptor.id] == nil && !rejectedFinalIDs.contains(descriptor.id) {
            if let record = state.records[descriptor.id], record.isExportVerified,
               let frame = state.preview(for: descriptor.id) {
                finalByID[descriptor.id] = frame
            }
        }
        // A final audit rejection is definitive for that PTS. Try an already
        // audited alternate inside the neighbouring chronological slots; do not
        // recover the rejected frame from its lower-resolution preview.
        var replacementByID: [Int: Int] = [:]
        var usedIDs = Set(selected.map(\.id))
        var plannedTimes = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0.time) })
        for (index, descriptor) in selected.enumerated() where finalByID[descriptor.id] == nil && replacementByID.count < policy.finalReplacementLimit {
            let lower = index > 0 ? (plannedTimes[selected[index - 1].id] ?? selected[index - 1].time) : 0
            let upper = index + 1 < selected.count ? selected[index + 1].time : duration
            let backup = state.records.values.filter {
                $0.isExportVerified && !usedIDs.contains($0.descriptor.id)
                    && $0.descriptor.time > lower && $0.descriptor.time < upper
            }.min { abs($0.descriptor.time - descriptor.time) < abs($1.descriptor.time - descriptor.time) }
            if let backup {
                replacementByID[backup.descriptor.id] = descriptor.id
                usedIDs.insert(backup.descriptor.id)
                plannedTimes[descriptor.id] = backup.descriptor.time
            }
        }
        let replacementRequests = replacementByID.keys.compactMap { id -> AutomaticFrameTimeRequest? in
            state.records[id].map { AutomaticFrameTimeRequest(id: id, time: $0.pts) }
        }
        var rejectedReplacementIDs = Set<Int>()
        let replacementDecodeStarted = performance.begin()
        try await ManualFrameExtractor.decodeAutomaticFrames(
            from: asset, requests: replacementRequests, maximumEdge: finalEdge, tolerance: .zero, requireExactPTS: true
        ) { id, pts, image in
            guard let slotID = replacementByID[id], let record = state.records[id] else { return }
            switch AutomaticFinalFrameRenderer.render(record: record, actualPTS: pts,
                image: image, slotID: slotID, performance: performance) {
            case let .accepted(frame): finalByID[slotID] = frame
            case .rejected: rejectedReplacementIDs.insert(id)
            case .encodingFailed: break
            }
        }
        performance.finish(.finalDecode, since: replacementDecodeStarted, count: replacementRequests.count)
        for (backupID, slotID) in replacementByID where finalByID[slotID] == nil && !rejectedReplacementIDs.contains(backupID) {
            if let backup = state.preview(for: backupID) {
                finalByID[slotID] = CapturedFrame(id: slotID, time: backup.time, jpegData: backup.jpegData, aspectRatio: backup.aspectRatio)
            }
        }
        let captured = selected.compactMap { finalByID[$0.id] }
        guard captured.count == count else {
            throw StoryboardError.insufficientUsableFrames(captured.count, count)
        }
        // Publish the accepted set in chronological slots. Delivering each card
        // separately still lets SwiftUI render immediately without artificial waits.
        for (index, frame) in captured.enumerated() {
            try Task.checkCancellation()
            await onPreviewFrame(frame, index, count)
            progress(0.75 + 0.24 * Double(index + 1) / Double(count))
            await Task.yield()
        }
        // Older SDKs do not mark Logger as Sendable. A local value avoids
        // shared static storage and needs no unchecked concurrency exemption.
        let logger = Logger(subsystem: "com.ixiehao.shotmap", category: "AutomaticFrameV2")
        logger.debug("V2 requests initial=\(initial.count) recovery=\(additionalRequests) final=\(requests.count + replacementRequests.count); semantic=\(state.semanticChecks); retained=\(state.cachedImageBytes) bytes")
        progress(1)
        return StoryboardResult(frames: captured, sourceURL: videoURL, duration: duration)
    }

    /// Small credit glyphs can be below both text detectors' resolution at
    /// 480 px. Only uncertain, person-free terminal candidates receive this
    /// same-PTS 1280 px accurate pass, charged to the shared recovery budget.
    private static func reviewDetailedText(
        from asset: AVURLAsset, state: inout AutomaticFrameAnalysisState, requestLimit: Int
    ) async throws -> Int {
        let openingRequests = try await reviewOpeningText(from: asset, state: &state, requestLimit: requestLimit)
        let tailRequestLimit = max(0, requestLimit - openingRequests)
        state.markRiskAroundConfirmedTerminalCard()
        try state.confirmTerminalCardRun()
        guard tailRequestLimit > 0, state.detailedTextChecks < state.policy.detailedTextRequestLimit else { return openingRequests }
        let eligible = state.semanticSelection().filter { descriptor in
            guard let record = state.records[descriptor.id], !record.detailedTextChecked else { return false }
            return record.needsDetailedTextCheck
        }.sorted { lhs, rhs in
            let leftBoundary = lhs.time / state.policy.duration > 0.65
            let rightBoundary = rhs.time / state.policy.duration > 0.65
            if leftBoundary != rightBoundary { return leftBoundary }
            if lhs.textOverlayScore != rhs.textOverlayScore { return lhs.textOverlayScore > rhs.textOverlayScore }
            return lhs.time < rhs.time
        }
        // Two nearly identical instants must not consume both detailed checks.
        // After one strong representative, inspect the farthest uncovered risk.
        var candidates: [FrameDescriptor] = []
        let allowed = min(tailRequestLimit, state.policy.detailedTextRequestLimit - state.detailedTextChecks)
        var coveredTimes = state.detailedTextTimes
        let firstIndependentSeed = state.records.values.filter { $0.independentTextScore >= 0.65
            && $0.descriptor.time > state.policy.duration * 0.5 }.map { $0.descriptor.time }.min()
        for _ in 0..<allowed {
            let available = eligible.filter { candidate in !candidates.contains(where: { $0.id == candidate.id }) }
            let choice: FrameDescriptor?
            var checkingPrecedingBoundary = false
            if coveredTimes.isEmpty { choice = available.first }
            else if let seed = firstIndependentSeed,
                    let precursor = available.filter({ $0.time < seed }).min(by: { $0.time < $1.time }) {
                // Close instants can straddle the actual credit boundary. A
                // precursor is reviewed, not suppressed as a near duplicate of
                // an already confirmed card; an ordinary scene can be cleared.
                choice = precursor
                checkingPrecedingBoundary = true
            }
            else {
                choice = available.max { lhs, rhs in
                    let left = coveredTimes.map { abs($0 - lhs.time) }.min() ?? 0
                    let right = coveredTimes.map { abs($0 - rhs.time) }.min() ?? 0
                    return left < right
                }
            }
            guard let choice else { break }
            if !checkingPrecedingBoundary,
               let distance = coveredTimes.map({ abs($0 - choice.time) }).min(), distance < min(15, max(1.5, state.policy.duration * 0.03)) { break }
            candidates.append(choice)
            coveredTimes.append(choice.time)
        }
        let requests = candidates.compactMap { descriptor -> AutomaticFrameTimeRequest? in
            state.records[descriptor.id].map { AutomaticFrameTimeRequest(id: descriptor.id, time: $0.pts) }
        }
        var completed = Set<Int>()
        state.detailedTextChecks += requests.count
        state.detailedTextTimes += requests.map { $0.time.seconds }
        let detailedDecodeStarted = state.performance.begin()
        try await ManualFrameExtractor.decodeAutomaticFrames(
            from: asset, requests: requests, maximumEdge: 1_280, tolerance: .zero, requireExactPTS: true
        ) { id, _, image in
            completed.insert(id)
            try state.auditDetailedText(id: id, image: image)
        }
        state.performance.finish(.detailedDecode, since: detailedDecodeStarted, count: requests.count)
        for request in requests where !completed.contains(request.id) {
            state.records[request.id]?.descriptor.textObservationState = .failed
        }
        AutomaticFrameDiagnostics.write("samePTS phase=HD requested=\(requests.count) decoded=\(completed.count)")
        state.markRiskAroundConfirmedTerminalCard()
        try state.confirmTerminalCardRun()
        return openingRequests + requests.count
    }

    /// An opening overlay is an optional, one-representative investigation.
    /// Other low-resolution layout hints never become globally pending OCR.
    private static func reviewOpeningText(from asset: AVURLAsset, state: inout AutomaticFrameAnalysisState,
                                          requestLimit: Int) async throws -> Int {
        guard requestLimit > 0, state.openingTextChecks == 0,
              state.records.values.contains(where: { $0.openingLayoutCandidate && !$0.detailedTextChecked }),
              let id = state.openingReviewCandidate(in: state.semanticSelection()),
              let record = state.records[id] else { return 0 }
        state.openingTextChecks += 1
        state.records[id]?.needsDetailedTextCheck = true
        let request = AutomaticFrameTimeRequest(id: id, time: record.pts)
        var completed = false
        let started = state.performance.begin()
        try await ManualFrameExtractor.decodeAutomaticFrames(from: asset, requests: [request],
            maximumEdge: 1_280, tolerance: .zero, requireExactPTS: true) { id, _, image in
            completed = true
            try state.auditDetailedText(id: id, image: image, forOpening: true)
        }
        state.performance.finish(.openingDecode, since: started)
        if !completed { state.records[id]?.descriptor.textObservationState = .failed }
        return 1
    }
}

struct AutomaticFrameRecord {
    var descriptor: FrameDescriptor
    let pts: CMTime
    var image: CGImage?
    var encodedPreview: Data?
    var subjectRegions: [CGRect] = []
    var detailedTextChecked = false
    var textRegions: [CGRect] = []
    var needsDetailedTextCheck = false
    /// Direct detector/OCR evidence only. Propagated run penalties must never
    /// become new anchors and recursively move the inferred boundary backwards.
    var independentTextScore: Float = 0
    var detailedTextObservedScore: Float?
    var detailedTextCoveredFullFrame = false
    /// A failed precise review gets at most one positive-evidence fallback at
    /// this PTS. Failed or negative results cannot restart it during recovery.
    var detailedTextFailureFallbackUsed = false
    var propagatedCreditRisk = false
    var openingLayoutCandidate = false
    let analysisMaximumEdge: CGFloat = 480

    func reusableFinalImage(maximumEdge: CGFloat) -> CGImage? {
        guard maximumEdge <= analysisMaximumEdge, isExportVerified else { return nil }
        return image
    }

    /// A review budget is not an eligibility quota. Product names, model years
    /// and small labels are ordinary content even when no human is present.
    /// Mandatory HD review requires a dense layout or several substantial text
    /// rows. Independently confirmed credit context can still add local risk.
    var hasIndependentDetailedTextRisk: Bool {
        descriptor.qualityEvidence?.denseTextLayout == true
            || (descriptor.faceScore < 0.05 && independentTextScore >= 0.35
                && AutomaticTextCardEvidence.lineCount(textRegions) >= 3)
    }

    var isTrustedContentBoundary: Bool {
        guard descriptor.personObservationState == .observed, descriptor.textObservationState == .observed,
              independentTextScore < 0.65,
              descriptor.qualityEvidence?.state == .observed, descriptor.qualityEvidence?.rejection == nil,
              descriptor.qualityEvidence?.denseTextLayout != true else { return false }
        if descriptor.faceScore >= 0.05 { return true }
        return detailedTextChecked && detailedTextCoveredFullFrame
            && descriptor.textObservationState == .observed && detailedTextObservedScore == 0
    }

    var isSemanticallyVerified: Bool {
        descriptor.personObservationState == .observed && descriptor.textObservationState == .observed
            && descriptor.qualityEvidence?.state == .observed && descriptor.isUsable
    }

    var isExportVerified: Bool {
        AutomaticFrameExportGate.allows(quality: descriptor.qualityEvidence?.state,
            person: descriptor.personObservationState, text: descriptor.textObservationState,
            usable: descriptor.isUsable, requiresDetailedText: needsDetailedTextCheck,
            detailedTextComplete: detailedTextChecked)
    }
}

enum AutomaticFinalFrameOutcome {
    case accepted(CapturedFrame)
    case rejected
    case encodingFailed
}

enum AutomaticFinalFrameRenderer {
    static func render(record: AutomaticFrameRecord, actualPTS: CMTime, image: CGImage,
                       slotID: Int, performance: AutomaticFramePerformance) -> AutomaticFinalFrameOutcome {
        guard record.isExportVerified, CMTimeCompare(record.pts, actualPTS) == 0 else { return .rejected }
        let evidence = performance.measure(.finalQuality) {
            FrameQualityAnalyzer.assess(image: image, subjectRegions: record.subjectRegions)
        }
        guard evidence.state == .observed, evidence.rejection == nil else { return .rejected }
        guard let data = performance.measure(.finalJPEG, { ImageCodec.jpegData(from: image, compressionQuality: 0.92) }) else { return .encodingFailed }
        return .accepted(CapturedFrame(id: slotID, time: actualPTS.seconds, jpegData: data,
            aspectRatio: Double(image.width) / Double(max(1, image.height))))
    }
}

struct AutomaticFrameAnalysisState {
    let policy: AutomaticFrameSamplingPolicy
    var cancellation = AutomaticVisionCancellation()
    var performance = AutomaticFramePerformance()
    var records: [Int: AutomaticFrameRecord] = [:]
    var requestedKeys = Set<AutomaticFrameTimeKey>()
    var actualKeys = Set<AutomaticFrameTimeKey>()
    var nextID = 0
    var semanticChecks = 0
    var detailedTextChecks = 0
    var openingTextChecks = 0
    var detailedTextTimes: [Double] = []
    var confirmedCardRanges: [Range<Double>] = []
    var searchedCoverageBuckets = Set<Int>()
    var searchedPersonBuckets = Set<Int>()
    var focusSearchesByBucket: [Int: Int] = [:]
    var didProbePersonFreeContent = false
    var cachedImageBytes = 0
    var cacheOrder: [Int] = []
    let imageCacheLimit = 64 * 1_024 * 1_024

    mutating func makeRequests(_ seconds: [Double], limit: Int = .max) -> [AutomaticFrameTimeRequest] {
        var result: [AutomaticFrameTimeRequest] = []
        for second in seconds where result.count < limit {
            let time = CMTime(seconds: second, preferredTimescale: 60_000)
            guard let key = AutomaticFrameTimeKey(time), !actualKeys.contains(key), requestedKeys.insert(key).inserted else { continue }
            result.append(AutomaticFrameTimeRequest(id: nextID, time: time))
            nextID += 1
        }
        return result.sorted { CMTimeCompare($0.time, $1.time) < 0 }
    }

    mutating func makeRecoveryRequests(localTimes: [Double], coverageTimes: [Double], limit: Int) -> [AutomaticFrameTimeRequest] {
        guard limit > 0 else { return [] }
        let quota = min(limit, max(1, (limit + 3) / 4))
        let orderedCoverage = coverageTimes.sorted()
        let reserveCount = min(quota, orderedCoverage.count)
        let spaced = (0..<reserveCount).map { index -> Double in
            if reserveCount == 1 { return orderedCoverage[orderedCoverage.count / 2] }
            let position = Double(index) * Double(max(0, orderedCoverage.count - 1)) / Double(reserveCount - 1)
            return orderedCoverage[Int(position.rounded())]
        }
        var coverage = makeRequests(spaced, limit: quota)
        if coverage.count < quota { coverage += makeRequests(orderedCoverage, limit: quota - coverage.count) }
        let local = makeRequests(localTimes, limit: limit - coverage.count)
        return (coverage + local).sorted { CMTimeCompare($0.time, $1.time) < 0 }
    }

    mutating func accept(id: Int, pts: CMTime, image: CGImage) {
        guard let key = AutomaticFrameTimeKey(pts), actualKeys.insert(key).inserted else { return }
        let metrics = performance.measure(.pixelMetrics) { PixelMetrics.make(from: image) }
        var descriptor = FrameDescriptor(id: id, time: pts.seconds,
            histogram: metrics.histogram, luminance: metrics.luminance, blackRatio: metrics.blackRatio,
            brightRatio: metrics.brightRatio, dominantToneRatio: metrics.dominantToneRatio,
            sharpness: metrics.sharpness, fingerprint: metrics.fingerprint, previewData: nil)
        descriptor.aspectRatio = Double(image.width) / Double(max(1, image.height))
        descriptor.qualityEvidence = performance.measure(.initialQuality) { FrameQualityAnalyzer.assess(image: image) }
        records[id] = AutomaticFrameRecord(descriptor: descriptor, pts: pts, image: image)
        performance.increment(.uniqueCandidates)
        cacheOrder.append(id)
        cachedImageBytes += image.bytesPerRow * image.height
        while cachedImageBytes > imageCacheLimit, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            guard var record = records[oldest], let cached = record.image else { continue }
            record.encodedPreview = performance.measure(.previewJPEG) { ImageCodec.jpegData(from: cached, compressionQuality: 0.9) }
            performance.increment(.rawCacheEvictions)
            record.image = nil
            cachedImageBytes -= cached.bytesPerRow * cached.height
            records[oldest] = record
        }
    }

    func image(for id: Int) -> CGImage? {
        guard let record = records[id] else { return nil }
        return record.image ?? record.encodedPreview.flatMap { ImageCodec.cgImage(from: $0) }
    }

    func preview(for id: Int) -> CapturedFrame? {
        guard let record = records[id], record.isExportVerified,
              let data = record.encodedPreview ?? record.image.flatMap({ image in performance.measure(.previewJPEG) { ImageCodec.jpegData(from: image, compressionQuality: 0.9) } }) else { return nil }
        return CapturedFrame(id: id, time: record.pts.seconds, jpegData: data, aspectRatio: record.descriptor.aspectRatio)
    }

    func verifiedSelection() -> [FrameDescriptor] {
        performance.measure(.verifiedSelection) {
            FrameSelection.chooseFrames(from: records.values.filter(\.isExportVerified).map(\.descriptor).sorted { $0.time < $1.time }, count: policy.targetCount)
        }
    }

    func semanticSelection() -> [FrameDescriptor] {
        performance.measure(.semanticSelection) {
            FrameSelection.chooseFrames(from: records.values.filter(\.isSemanticallyVerified).map(\.descriptor).sorted { $0.time < $1.time }, count: policy.targetCount)
        }
    }

    mutating func auditProvisionalSelection(limit: Int = .max) throws {
        let stopAt = policy.semanticStopCount(completed: semanticChecks, additionalLimit: limit)
        while semanticChecks < stopAt {
            try Task.checkCancellation()
            let pool = records.values.filter {
                $0.descriptor.isUsable && $0.descriptor.qualityEvidence?.state == .observed
                    && $0.descriptor.personObservationState != .failed && $0.descriptor.textObservationState != .failed
            }.map(\.descriptor).sorted { $0.time < $1.time }
            let provisional = performance.measure(.provisionalSelection) {
                FrameSelection.chooseFrames(from: pool, count: policy.targetCount)
            }
            let pending = provisional.filter { records[$0.id]?.isSemanticallyVerified == false }
            guard !pending.isEmpty else { break }
            for descriptor in pending where semanticChecks < stopAt {
                try Task.checkCancellation()
                semanticChecks += 1
                try autoreleasepool { try audit(id: descriptor.id) }
            }
            applyLocalFocusComparisons()
        }
    }

    mutating func auditRecoveredCandidates(_ ids: [Int], limit: Int) throws {
        var remaining = min(limit, policy.semanticRequestLimit - semanticChecks)
        for id in ids where remaining > 0 {
            try Task.checkCancellation()
            guard let record = records[id], record.descriptor.isUsable,
                  record.descriptor.personObservationState == .notEvaluated else { continue }
            try autoreleasepool { try audit(id: id) }
            semanticChecks += 1
            remaining -= 1
        }
        applyLocalFocusComparisons()
    }

    mutating func audit(id: Int) throws {
        guard var record = records[id] else { return }
        // A same-PTS candidate already audited once keeps its evidence. Images
        // rejected by the base gate cannot reach output and need no Vision work.
        if record.descriptor.personObservationState == .observed && record.descriptor.textObservationState == .observed {
            performance.increment(.semanticReuses)
            return
        }
        guard record.descriptor.qualityEvidence?.state == .observed,
              record.descriptor.qualityEvidence?.rejection == nil else {
            performance.increment(.semanticQualitySkips)
            return
        }
        let semanticStarted = performance.begin()
        defer { performance.finish(.semanticAudit, since: semanticStarted) }
        performance.increment(.semanticAudits)
        guard let image = image(for: id) else {
            record.descriptor.personObservationState = .failed
            record.descriptor.textObservationState = .failed
            records[id] = record
            return
        }
        let faces = VNDetectFaceRectanglesRequest()
        let bodies = VNDetectHumanRectanglesRequest()
        bodies.upperBodyOnly = true
        let text = VNDetectTextRectanglesRequest()
        text.reportCharacterBoxes = false
        do {
            try performance.measure(.personAndTextRegions) { try cancellation.perform([faces, bodies, text], using: VNImageRequestHandler(cgImage: image, options: [:])) }
            record.descriptor.personObservationState = .observed
            record.descriptor.textObservationState = .observed
            let faceObservations = (faces.results ?? []).filter { $0.confidence >= 0.4 }
            let bodyObservations = (bodies.results ?? []).filter { $0.confidence >= 0.45 }
            // A large body rectangle includes background. Judge the principal
            // face first so a sharp wall cannot hide an out-of-focus face.
            let primaryFace = faceObservations.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
            let primaryBody = bodyObservations.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
            record.subjectRegions = primaryFace.map { [$0.boundingBox] } ?? primaryBody.map { [$0.boundingBox] } ?? []
            let faceArea = faceObservations.map { Float($0.boundingBox.width * $0.boundingBox.height) }.max() ?? 0
            let bodyArea = bodyObservations.map { Float($0.boundingBox.width * $0.boundingBox.height) }.max() ?? 0
            record.descriptor.faceScore = min(1, faceArea * 11)
            record.descriptor.bodyScore = min(1, bodyArea * 4)
            record.descriptor.faceCount = faceObservations.count
            record.descriptor.peopleScore = max(record.descriptor.faceScore, record.descriptor.bodyScore)
            if record.subjectRegions.isEmpty {
                // The original image at this PTS already has full-frame quality
                // evidence. No new ROI means no second grayscale/statistics pass.
                performance.increment(.fullQualityReuses)
            } else {
                record.descriptor.qualityEvidence = performance.measure(.subjectQuality) { FrameQualityAnalyzer.assess(image: image, subjectRegions: record.subjectRegions) }
            }
            let regions = (text.results ?? []).map(\.boundingBox)
            record.textRegions = regions
            var textScore = AutomaticTextCardEvidence.score(
                regions: regions, sparse: record.descriptor.qualityEvidence?.isSparseGraphic ?? false,
                hasSubject: !record.subjectRegions.isEmpty)
            // Dense, small end-credit glyphs can yield zero text rectangles.
            // A negative region detector is not proof of absence: only this
            // person-free terminal shortlist receives lightweight OCR fallback.
            if record.subjectRegions.isEmpty && textScore < 0.65 {
                let recognition = VNRecognizeTextRequest()
                recognition.recognitionLevel = .fast
                recognition.usesLanguageCorrection = false
                recognition.minimumTextHeight = 0.008
                try performance.measure(.fastOCR) { try cancellation.perform([recognition], using: VNImageRequestHandler(cgImage: image, options: [:])) }
                let observations = (recognition.results ?? []).filter { !$0.topCandidates(1).isEmpty }
                let recognized = observations.map(\.boundingBox)
                record.textRegions += recognized
                textScore = max(textScore, AutomaticTextCardEvidence.score(
                    regions: recognized, sparse: record.descriptor.qualityEvidence?.isSparseGraphic ?? false,
                    hasSubject: false))
                let paidLines = observations.compactMap { observation -> String? in
                    guard observation.boundingBox.midY > 0.22,
                          let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.85 else { return nil }
                    return candidate.string
                }
                if AutomaticTextCardEvidence.hasProductionCreditPhrases(paidLines, hasSubject: false, layoutScore: textScore)
                    || AutomaticTextCardEvidence.hasExplicitFilmFundingSentence(paidLines) { textScore = max(textScore, 0.9) }
                record.openingLayoutCandidate = AutomaticOpeningOverlayEvidence.hasAlignedLowerLeftRows(image: image, regions: record.textRegions)
            }
            record.descriptor.textOverlayScore = textScore
            record.independentTextScore = max(record.independentTextScore, textScore)
            record.needsDetailedTextCheck = record.hasIndependentDetailedTextRisk
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AutomaticFrameDiagnostics.write("semantic-failure pts=\(record.pts.seconds) error=\(error)")
            record.descriptor.personObservationState = .failed
            record.descriptor.textObservationState = .failed
        }
        records[id] = record
    }

    mutating func auditDetailedText(id: Int, image: CGImage, forOpening: Bool = false,
        textReader: ((VNRequestTextRecognitionLevel, CGRect) throws -> [AutomaticRecognizedTextLine])? = nil
    ) throws {
        guard var record = records[id], !record.detailedTextFailureFallbackUsed else { return }
        record.detailedTextChecked = false
        record.detailedTextCoveredFullFrame = false
        let cancellation = self.cancellation, performance = self.performance
        performance.recordDetailedThread()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let workflowContext = hasIndependentCardContext(around: record.pts.seconds, excluding: id)
        let hasSubject = record.descriptor.faceScore >= 0.05
        let sparse = record.descriptor.qualityEvidence?.isSparseGraphic ?? false
        func read(_ level: VNRequestTextRecognitionLevel, roi: CGRect) throws -> [AutomaticRecognizedTextLine] {
            // Internal dependency boundary also permits deterministic failures
            // without swizzling Vision or changing global compute preferences.
            if let textReader { return try textReader(level, roi) }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.006
            request.regionOfInterest = roi
            try performance.measure(level == .accurate ? .accurateOCR : .fastOCR) {
                try cancellation.perform([request], using: handler)
            }
            return (request.results ?? []).compactMap { observation in
                guard let result = observation.topCandidates(1).first else { return nil }
                return AutomaticRecognizedTextLine(text: result.string, confidence: result.confidence,
                    region: AutomaticTextCardEvidence.fullImageRegion(observation.boundingBox, roi: roi))
            }
        }
        func textScore(_ lines: [AutomaticRecognizedTextLine]) -> Float {
            let regions = lines.map(\.region)
            var value = AutomaticTextCardEvidence.score(regions: regions, sparse: sparse, hasSubject: hasSubject)
            let central = lines.filter { $0.region.midY > 0.22 }
            if AutomaticTextCardEvidence.hasProductionCreditPhrases(central.map(\.text), hasSubject: hasSubject, layoutScore: value)
                || AutomaticTextCardEvidence.hasWorkflowCreditLayout(central, hasSubject: hasSubject, hasIndependentCardContext: workflowContext) {
                value = max(value, 0.9)
            }
            if forOpening && !hasSubject && AutomaticTextCardEvidence.hasExplicitFilmFundingSentence(
                lines.filter { $0.confidence >= 0.85 }.map(\.text)) { value = max(value, 0.9) }
            return value
        }
        var fullFastLines: [AutomaticRecognizedTextLine]?
        do {
            let started = performance.begin()
            let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
            let central = CGRect(x: 0.15, y: 0.35, width: 0.7, height: 0.3)
            let bounds = record.textRegions.reduce(CGRect.null) { $0.union($1) }
            let padded = bounds.isNull ? central : bounds.insetBy(dx: -0.05, dy: -0.12).intersection(unit)
            let roi: CGRect
            if forOpening { roi = CGRect(x: 0.03, y: 0.07, width: 0.55, height: 0.30) }
            else if hasSubject && record.descriptor.qualityEvidence?.denseTextLayout == true { roi = unit }
            else { roi = padded.width * padded.height <= 0.45 ? padded : central }
            var lines = try read(.accurate, roi: roi)
            var score = textScore(lines)
            var coveredFullFrame = roi == unit
            var fallbackROI: CGRect?
            // A local zero says nothing about text outside that region. Cover
            // the same image cheaply, then accurately read at most one bounded
            // region containing newly located text (or the independent centre).
            if !forOpening && score < 0.65 && !coveredFullFrame {
                let regions = VNDetectTextRectanglesRequest()
                regions.reportCharacterBoxes = false
                let fast = VNRecognizeTextRequest()
                fast.recognitionLevel = .fast
                fast.usesLanguageCorrection = false
                fast.minimumTextHeight = 0.006
                try performance.measure(.fullTextCoverage) {
                    try performance.measure(.fullTextRegions) { try cancellation.perform([regions], using: handler) }
                    try performance.measure(.fullFastOCR) { try cancellation.perform([fast], using: handler) }
                }
                let fullLines = (fast.results ?? []).compactMap { observation -> AutomaticRecognizedTextLine? in
                    guard let result = observation.topCandidates(1).first else { return nil }
                    return AutomaticRecognizedTextLine(text: result.string, confidence: result.confidence, region: observation.boundingBox)
                }
                fullFastLines = fullLines
                let fullRegions = (regions.results ?? []).map(\.boundingBox)
                score = max(score, textScore(fullLines), AutomaticTextCardEvidence.score(regions: fullRegions, sparse: sparse, hasSubject: hasSubject))
                coveredFullFrame = true
                let outside = (fullRegions + fullLines.map(\.region)).filter { region in
                    let area = region.width * region.height
                    let overlap = roi.intersection(region)
                    return area > 0 && (overlap.isNull || overlap.width * overlap.height < area * 0.8)
                }
                let newBounds = outside.reduce(CGRect.null) { $0.union($1) }
                let localized = newBounds.isNull ? central : newBounds.insetBy(dx: -0.035, dy: -0.05).intersection(unit)
                let alternate = localized.width * localized.height <= 0.45 ? localized : central
                if score < 0.65 && (alternate != roi || !outside.isEmpty) {
                    fallbackROI = alternate
                    let more = try read(.accurate, roi: alternate)
                    score = max(score, textScore(more))
                    lines += more
                }
                // Dense layout with no recognised text remains uncertain; do
                // not turn a detector miss into a trusted person-free boundary.
                if score == 0 && record.descriptor.qualityEvidence?.denseTextLayout == true { coveredFullFrame = false }
            }
            record.detailedTextChecked = score >= 0.65 || coveredFullFrame || forOpening
            record.detailedTextCoveredFullFrame = coveredFullFrame
            record.detailedTextObservedScore = score
            record.descriptor.textOverlayScore = max(record.descriptor.textOverlayScore, score)
            record.independentTextScore = max(record.independentTextScore, score)
            record.descriptor.textObservationState = .observed
            performance.finish(.detailedAudit, since: started)
            AutomaticFrameDiagnostics.write("detailed pts=\(record.pts.seconds) roi=\(roi) fallbackROI=\(String(describing: fallbackROI)) fullCoverage=\(coveredFullFrame) mainThread=\(Thread.isMainThread) boxes=\(lines.count) score=\(score)")
        } catch is CancellationError { throw CancellationError() }
        catch {
            record.descriptor.textObservationState = .failed
            record.detailedTextFailureFallbackUsed = true
            performance.increment(.detailedTextFailureFallbacks)
            // An unavailable precise OCR model must not erase positive credit
            // evidence obtainable by the cheaper model. Inspect the whole same
            // image once. A negative/failed fast read NEVER clears HD risk or
            // creates a trusted content boundary; only positive rejection is
            // accepted. Reuse an already observed full-frame fast read if the
            // later precise ROI request was the operation that failed.
            do {
                let lines = try cancellation.withActiveRequests([]) {
                    try fullFastLines ?? read(.fast, roi: CGRect(x: 0, y: 0, width: 1, height: 1))
                }
                let score = textScore(lines)
                if score >= 0.65 {
                    record.detailedTextChecked = true
                    record.detailedTextCoveredFullFrame = true
                    record.detailedTextObservedScore = score
                    record.descriptor.textOverlayScore = max(record.descriptor.textOverlayScore, score)
                    record.independentTextScore = max(record.independentTextScore, score)
                    record.descriptor.textObservationState = .observed
                    performance.increment(.detailedTextFallbackRejections)
                }
                AutomaticFrameDiagnostics.write("detailed-failure-fallback pts=\(record.pts.seconds) score=\(score) rejected=\(score >= 0.65)")
            } catch is CancellationError { throw CancellationError() }
            catch { AutomaticFrameDiagnostics.write("detailed-failure-fallback pts=\(record.pts.seconds) error=\(error)") }
        }
        records[id] = record
    }

    func hasIndependentCardContext(around time: Double, excluding id: Int) -> Bool {
        let anchors = records.values.filter { $0.descriptor.id != id && $0.independentTextScore >= 0.65 }
        guard let before = anchors.filter({ $0.pts.seconds < time }).map({ $0.pts.seconds }).max(),
              let after = anchors.filter({ $0.pts.seconds > time }).map({ $0.pts.seconds }).min() else { return false }
        return !records.values.contains { $0.descriptor.id != id && $0.pts.seconds > before
            && $0.pts.seconds < after && $0.isTrustedContentBoundary }
    }

    /// Independently observed text cards define runs only when no trusted
    /// ordinary scene separates them. A face cannot be called a credits portrait
    /// merely because two unrelated text cards happen to surround it.
    mutating func confirmTerminalCardRun() throws {
        confirmedCardRanges.removeAll(keepingCapacity: true)
        // Recompute propagation from independent evidence each time. Newly
        // audited content must be able to undo a former uncertain run.
        for id in Array(records.keys) where records[id]?.propagatedCreditRisk == true {
            guard var record = records[id] else { continue }
            record.descriptor.textOverlayScore = record.independentTextScore
            record.propagatedCreditRisk = false
            records[id] = record
        }
        var confirmed = records.values.filter {
            $0.independentTextScore >= 0.65 && $0.descriptor.time > policy.duration * 0.5
        }.sorted { $0.descriptor.time < $1.descriptor.time }
        guard confirmed.count >= 2, let first = confirmed.first else { return }
        let tailIDs = records.values.filter { $0.descriptor.time >= first.descriptor.time - 1.501 }
            .sorted { $0.descriptor.time < $1.descriptor.time }.map { $0.descriptor.id }
        for id in tailIDs {
            try Task.checkCancellation()
            if records[id]?.descriptor.personObservationState == .notEvaluated,
               records[id]?.descriptor.qualityEvidence?.state == .observed,
               records[id]?.descriptor.qualityEvidence?.rejection == nil,
               semanticChecks < policy.semanticRequestLimit {
                semanticChecks += 1
                try autoreleasepool { try audit(id: id) }
            }
        }
        confirmed = records.values.filter {
            $0.independentTextScore >= 0.65 && $0.descriptor.time > policy.duration * 0.5
        }.sorted { $0.descriptor.time < $1.descriptor.time }
        var groups: [[AutomaticFrameRecord]] = []
        for anchor in confirmed {
            if let previous = groups.last?.last,
               records.values.contains(where: { $0.pts.seconds > previous.pts.seconds
                   && $0.pts.seconds < anchor.pts.seconds && $0.isTrustedContentBoundary }) {
                groups.append([anchor])
            } else if groups.isEmpty { groups.append([anchor]) }
            else { groups[groups.count - 1].append(anchor) }
        }
        for group in groups where group.count >= 2 {
            guard let first = group.first, let last = group.last else { continue }
            let before = records.values.filter { $0.pts.seconds < first.pts.seconds && $0.isTrustedContentBoundary }
                .map { $0.pts.seconds }.max() ?? 0
            let start = max(first.pts.seconds - 1.501, before + 0.001)
            let end = records.values.filter { $0.pts.seconds > last.pts.seconds && $0.isTrustedContentBoundary }
                .map { $0.pts.seconds }.min() ?? policy.duration
            let observed = records.values.filter { $0.pts.seconds >= start && $0.pts.seconds < end }
            guard !observed.contains(where: { $0.descriptor.personObservationState != .observed
                && $0.descriptor.qualityEvidence?.rejection == nil }),
                observed.filter({ $0.independentTextScore >= 0.65 }).count >= 2 else { continue }
            confirmedCardRanges.append(start..<end)
            for record in observed where record.descriptor.personObservationState == .observed {
                records[record.descriptor.id]?.descriptor.textOverlayScore = max(0.75, record.independentTextScore)
                records[record.descriptor.id]?.propagatedCreditRisk = true
            }
            AutomaticFrameDiagnostics.write("terminal-card-run start=\(start) end=\(end) observed=\(observed.count) anchors=\(group.count)")
        }
    }

    /// One confirmed card schedules inspection of neighbouring uncertain
    /// content. Any actually observed ordinary scene bounds that inspection.
    mutating func markRiskAroundConfirmedTerminalCard() {
        for id in Array(records.keys) {
            guard let record = records[id] else { continue }
            records[id]?.needsDetailedTextCheck = record.hasIndependentDetailedTextRisk
        }
        let seeds = records.values.filter { $0.independentTextScore >= 0.65 && $0.pts.seconds > policy.duration * 0.5 }
        for seed in seeds {
            let start = precedingCreditReviewStart(seedTime: seed.pts.seconds)
            let end = records.values.filter { $0.pts.seconds > seed.pts.seconds && $0.isTrustedContentBoundary }
                .map { $0.pts.seconds }.min() ?? policy.duration
            for record in records.values where record.pts.seconds >= start && record.pts.seconds < end && !record.isTrustedContentBoundary {
                records[record.descriptor.id]?.needsDetailedTextCheck = true
            }
            AutomaticFrameDiagnostics.write("credit-review-risk seed=\(seed.pts.seconds) precedingStart=\(start) end=\(end)")
        }
    }

    /// Walk the already-decoded evidence back to observed content, rather than
    /// using a grid-dependent time window. This schedules review, never a fixed
    /// percentage or duration trim. Person-free media without a trusted content
    /// boundary retains only local/independent checks instead of blanket risk.
    func precedingCreditReviewStart(seedTime: Double) -> Double {
        let preceding = records.values.filter { $0.descriptor.time < seedTime }
        let strongScene = preceding.filter {
            $0.descriptor.personObservationState == .observed && $0.descriptor.faceScore >= 0.15
                && $0.independentTextScore < 0.1 && $0.descriptor.qualityEvidence?.denseTextLayout != true
        }.map { $0.descriptor.time }.max()
        guard let strongScene else {
            AutomaticFrameDiagnostics.write("preceding-credit-review-limited seed=\(seedTime) reason=no-observed-content-boundary")
            return max(0, seedTime - 3.001)
        }
        let earlierLayout = preceding.filter {
            $0.descriptor.time > strongScene && ($0.independentTextScore > 0.02
                || $0.descriptor.qualityEvidence?.denseTextLayout == true
                || $0.descriptor.qualityEvidence?.isSparseGraphic == true)
        }.map { $0.descriptor.time }.min()
        return min(max(0, seedTime - 3.001), earlierLayout ?? seedTime)
    }

    func logSelection(_ selected: [FrameDescriptor]) {
        let values = Array(records.values)
        AutomaticFrameDiagnostics.write("pool total=\(values.count) qualityUsable=\(values.filter { $0.descriptor.isUsable }.count) semanticsObserved=\(values.filter { $0.isSemanticallyVerified }.count) needsHDUnchecked=\(values.filter { $0.isSemanticallyVerified && $0.needsDetailedTextCheck && !$0.detailedTextChecked }.count) exportVerified=\(values.filter { $0.isExportVerified }.count)")
        for reason in [FrameQualityRejection.blank, .titleCard, .severelyBlurred] {
            AutomaticFrameDiagnostics.write("quality-rejections reason=\(reason.rawValue) count=\(values.filter { $0.descriptor.qualityEvidence?.rejection == reason }.count)")
        }
        for record in values.filter({ $0.independentTextScore >= 0.65 }).sorted(by: { $0.pts.seconds < $1.pts.seconds }) {
            AutomaticFrameDiagnostics.write("direct-anchor pts=\(record.pts.seconds) direct=\(record.independentTextScore) face=\(record.descriptor.faceScore) dense=\(record.descriptor.qualityEvidence?.denseTextLayout ?? false)")
        }
        for descriptor in selected {
            guard let record = records[descriptor.id] else { continue }
            AutomaticFrameDiagnostics.write("selected pts=\(descriptor.time) face=\(descriptor.faceScore) body=\(descriptor.bodyScore) text=\(descriptor.textOverlayScore) direct=\(record.independentTextScore) propagated=\(descriptor.textOverlayScore > record.independentTextScore) hd=\(record.detailedTextChecked) needsHD=\(record.needsDetailedTextCheck) dense=\(descriptor.qualityEvidence?.denseTextLayout ?? false) focus=\(descriptor.qualityEvidence?.focusScore ?? -1)")
        }
    }

    /// Only nearby, visually similar frames with corresponding subject regions
    /// are eligible references. Sparse all-video samples never create motion or
    /// transition scores. This comparison is conservative around genuine cuts.
    mutating func applyLocalFocusComparisons() {
        let checked = records.values.filter(\.isSemanticallyVerified)
        for record in checked {
            guard let evidence = record.descriptor.qualityEvidence else { continue }
            let references = checked.filter { reference in
                let delta = abs(reference.descriptor.time - record.descriptor.time)
                guard reference.descriptor.id != record.descriptor.id, delta <= 1.5,
                      FrameSelection.histogramDistance(record.descriptor.histogram, reference.descriptor.histogram) < 0.12,
                      FrameSelection.hammingDistance(record.descriptor.fingerprint, reference.descriptor.fingerprint) < 18 else { return false }
                if let lhs = record.subjectRegions.first, let rhs = reference.subjectRegions.first {
                    let intersection = lhs.intersection(rhs)
                    return !intersection.isNull && intersection.width * intersection.height / max(0.001, min(lhs.width * lhs.height, rhs.width * rhs.height)) >= 0.5
                }
                return record.subjectRegions.isEmpty && reference.subjectRegions.isEmpty
            }
            for reference in references {
                guard let comparison = reference.descriptor.qualityEvidence else { continue }
                let adjusted = evidence.rejectingSevereBlur(comparedWith: comparison)
                if adjusted.rejection != nil {
                    records[record.descriptor.id]?.descriptor.qualityEvidence = adjusted
                    break
                }
            }
        }
    }

    func openingReviewCandidate(in selected: [FrameDescriptor]) -> Int? {
        guard openingTextChecks == 0,
              let firstPerson = records.values.filter({ $0.descriptor.personObservationState == .observed
                && $0.descriptor.faceScore >= 0.15 && $0.independentTextScore < 0.1
                && $0.descriptor.qualityEvidence?.state == .observed && $0.descriptor.isUsable
              }).map({ $0.pts.seconds }).min() else { return nil }
        return selected.filter { descriptor in
            guard let record = records[descriptor.id] else { return false }
            return record.openingLayoutCandidate && !record.detailedTextChecked
                && record.descriptor.faceScore < 0.05 && record.pts.seconds < firstPerson
        }.min { $0.time < $1.time }?.id
    }

    func coverageBucket(for time: Double) -> Int {
        min(policy.targetCount - 1, max(0, Int(time / policy.duration * Double(policy.targetCount))))
    }

    func isConfirmedCardTime(_ time: Double) -> Bool { confirmedCardRanges.contains { $0.contains(time) } }

    func missingContentBuckets() -> [Int] {
        let verified = Set(records.values.filter(\.isExportVerified).map { coverageBucket(for: $0.pts.seconds) })
        return (0..<policy.targetCount).filter { bucket in
            guard !verified.contains(bucket) else { return false }
            let centre = (Double(bucket) + 0.5) * policy.duration / Double(policy.targetCount)
            if !isConfirmedCardTime(centre) { return true }
            // A real candidate outside a boundary must still be inspected even
            // when this coarse bucket's midpoint falls in a confirmed card run.
            return records.values.contains { coverageBucket(for: $0.pts.seconds) == bucket
                && !isConfirmedCardTime($0.pts.seconds) && $0.descriptor.isUsable }
        }
    }

    func coverageAuditIDs(limit: Int) -> [Int] {
        guard limit > 0 else { return [] }
        return Array(missingContentBuckets().compactMap { bucket in
            records.values.filter { coverageBucket(for: $0.pts.seconds) == bucket
                && !isConfirmedCardTime($0.pts.seconds) && $0.descriptor.isUsable
                && $0.descriptor.qualityEvidence?.state == .observed
                && $0.descriptor.personObservationState == .notEvaluated
                && $0.descriptor.textObservationState != .failed
            }.max { lhs, rhs in
                let left = lhs.descriptor.qualityScore, right = rhs.descriptor.qualityScore
                return left == right ? lhs.pts.seconds > rhs.pts.seconds : left < right
            }?.descriptor.id
        }.prefix(limit))
    }

    mutating func auditCoverageCandidates(limit: Int) throws {
        for id in coverageAuditIDs(limit: min(limit, policy.semanticRequestLimit - semanticChecks)) {
            try Task.checkCancellation()
            semanticChecks += 1
            try autoreleasepool { try audit(id: id) }
            performance.increment(.coverageAudits)
        }
        applyLocalFocusComparisons()
    }

    func recoveryPlan(selected: [FrameDescriptor], round: Int, remaining: Int) -> AutomaticRecoveryPlan {
        guard remaining > 0 else { return AutomaticRecoveryPlan() }
        let deficit = max(0, policy.targetCount - selected.count)
        let missing = missingContentBuckets().filter { deficit > 0 || !searchedCoverageBuckets.contains($0) }
        let coverage = missing.map { (Double($0) + 0.5) * policy.duration / Double(policy.targetCount) }
        let hasPeople = records.values.contains { $0.isSemanticallyVerified && $0.descriptor.peopleScore >= 0.08 }
        var focus: [Int: Double] = [:]
        var people: [Int: Double] = [:]
        for descriptor in selected where !isConfirmedCardTime(descriptor.time) {
            let bucket = coverageBucket(for: descriptor.time)
            let lowFocus = (descriptor.qualityEvidence?.subjectFocusScore ?? descriptor.qualityEvidence?.focusScore ?? 1) < 0.15
            if lowFocus && focusSearchesByBucket[bucket, default: 0] < 2 { focus[bucket] = descriptor.time }
            if hasPeople && descriptor.peopleScore < 0.08 && !searchedPersonBuckets.contains(bucket) {
                people[bucket] = descriptor.time
            }
        }
        let probePersonFree = !hasPeople && !didProbePersonFreeContent && !selected.isEmpty
        if probePersonFree {
            // One distributed probe is a chance to discover missed subjects, not
            // a rule requiring every landscape or diagram to contain a person.
            let probeCount = min(selected.count, max(3, policy.targetCount / 3))
            for index in 0..<probeCount {
                let position = probeCount == 1 ? 0 : index * (selected.count - 1) / (probeCount - 1)
                let descriptor = selected[position]
                let bucket = coverageBucket(for: descriptor.time)
                if !searchedPersonBuckets.contains(bucket) { people[bucket] = descriptor.time }
            }
        }
        let centres = coverage + focus.sorted { $0.key < $1.key }.map(\.value)
            + people.sorted { $0.key < $1.key }.map(\.value)
        // Preserve the maximum budget. If the last round is still short of K,
        // spend the remaining allowance; a full result only searches actual gaps
        // and untried soft improvements rather than unconditionally spending it.
        let desired = deficit * 3 + coverage.count * 2 + focus.count * 3 + people.count * 2
        let requestLimit = round > 0 && deficit > 0 ? remaining : min(remaining, max(12, desired))
        AutomaticFrameDiagnostics.write("recovery-plan round=\(round) selected=\(selected.count) deficit=\(deficit) missingContent=\(coverage.count) focus=\(focus.count) person=\(people.count) requestLimit=\(requestLimit)")
        return AutomaticRecoveryPlan(centres: centres, requestLimit: requestLimit,
            focusBuckets: Set(focus.keys), personBuckets: Set(people.keys), probesPersonFree: probePersonFree)
    }

    mutating func recordRecoveryAttempt(plan: AutomaticRecoveryPlan, requests: [AutomaticFrameTimeRequest]) {
        let submittedBuckets = Set(requests.map { coverageBucket(for: $0.time.seconds) })
        searchedCoverageBuckets.formUnion(submittedBuckets)
        searchedPersonBuckets.formUnion(plan.personBuckets.intersection(submittedBuckets))
        for bucket in plan.focusBuckets.intersection(submittedBuckets) { focusSearchesByBucket[bucket, default: 0] += 1 }
        didProbePersonFreeContent = didProbePersonFreeContent
            || (plan.probesPersonFree && plan.personBuckets.isSubset(of: submittedBuckets))
    }

}

struct AutomaticRecoveryPlan {
    var centres: [Double] = []
    var requestLimit = 0
    var focusBuckets = Set<Int>()
    var personBuckets = Set<Int>()
    var probesPersonFree = false
}

private enum AutomaticFrameDiagnostics {
    private static let enabled = ProcessInfo.processInfo.environment["SHOTMAP_FRAME_DIAGNOSTICS"] == "1"
    static func write(_ message: @autoclosure () -> String) {
        if enabled { print("[AutomaticFrameV2] " + message()) }
    }
}

struct AutomaticRecognizedTextLine {
    let text: String
    let confidence: Float
    let region: CGRect
}

enum AutomaticTextCardEvidence {
    static func fullImageRegion(_ region: CGRect, roi: CGRect) -> CGRect {
        CGRect(x: roi.minX + region.minX * roi.width, y: roi.minY + region.minY * roi.height,
               width: region.width * roi.width, height: region.height * roi.height)
    }

    /// Production roles are corroborating semantics, not single-word keyword
    /// bans. Normal bottom subtitles are excluded by the caller, and a credible
    /// on-screen person protects ordinary dialogue. No movie or crew names are
    /// encoded in this local rule.
    static func hasProductionCreditPhrases(_ lines: [String], hasSubject: Bool, layoutScore: Float) -> Bool {
        guard !hasSubject, !lines.isEmpty, layoutScore >= 0.04 else { return false }
        let text = lines.joined(separator: " ").lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        let compact = text.filter { !$0.isWhitespace && $0.isLetter }
        let strongPhrases = ["directedby", "writtenanddirected", "writtenby", "producedby", "directorofphotography",
            "musicandsound", "visualeffectsby",
            "directeurdelaphotographie", "realisepar", "direcciondefotografia", "dirigidopor",
            "withsupportfrom", "supportedby", "withthesupportof", "fundedby", "filmfund"]
        if lines.count >= 2 && strongPhrases.contains(where: compact.contains) { return true }
        if layoutScore >= 0.1 && compact.contains("vfx") && (compact.contains("allcg") || compact.contains("created")) { return true }
        let roleSets = [
            ["lighting", "animation", "compositing", "rendering", "editing", "sound", "music", "camera", "casting", "costume", "crew", "supervisor"],
            ["导演", "编剧", "摄影", "剪辑", "制片", "配乐", "出品"],
            ["監督", "脚本", "撮影", "編集", "制作", "音楽"],
            ["감독", "각본", "촬영", "편집", "제작", "음악"],
            ["режиссер", "оператор", "сценарий", "монтаж", "продюсер", "музыка"],
            ["realisation", "photographie", "montage", "production", "musique"],
            ["direccion", "fotografia", "montaje", "produccion", "musica"]
        ]
        return lines.count >= 2 && roleSets.contains { roles in roles.filter { compact.contains($0) }.count >= 2 }
    }

    /// A complete production/funding relation, never a bare director, fund,
    /// support, or institution keyword. Real subtitles may use those words too.
    static func hasExplicitFilmFundingSentence(_ lines: [String]) -> Bool {
        let text = lines.joined(separator: " ").lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        let compact = text.filter { !$0.isWhitespace && $0.isLetter }
        let phrases = ["thisfilmissupportedby", "thisfilmwassupportedby", "thisfilmwasfundedby",
            "thisfilmismadepossibleby", "thisfilmwasmadepossibleby", "thisproductionissupportedby",
            "cefilmestrealiseaveclesoutiende", "cefilmaetefinancepar", "estapeliculafuefinanciadapor"]
        return phrases.contains { compact.hasPrefix($0) }
    }

    /// A workflow heading over several narrower centred lines is production
    /// evidence only inside independently observed card context. A tutorial
    /// mentioning software pipelines in isolation is not a credit card.
    static func hasWorkflowCreditLayout(_ lines: [AutomaticRecognizedTextLine], hasSubject: Bool,
                                        hasIndependentCardContext: Bool) -> Bool {
        guard !hasSubject, hasIndependentCardContext, lines.count >= 3 else { return false }
        for heading in lines where heading.confidence >= 0.75 {
            let compact = heading.text.lowercased().filter { $0.isLetter }
            guard compact.contains("studiopipeline") && (compact.contains("development") || compact.contains("scripting")) else { continue }
            let below = lines.filter { $0.confidence >= 0.75 && $0.region.maxY < heading.region.minY
                && abs($0.region.midX - heading.region.midX) < 0.08
                && $0.region.width <= heading.region.width * 0.7 && $0.region.midY > 0.22 }
            if below.count >= 2 { return true }
        }
        return false
    }

    static func lineCount(_ regions: [CGRect]) -> Int {
        var baselines: [CGFloat] = []
        for region in regions.sorted(by: { $0.midY < $1.midY }) where region.midY > 0.22 && region.midY < 0.92 {
            if !baselines.contains(where: { abs($0 - region.midY) <= max(0.015, region.height * 0.6) }) {
                baselines.append(region.midY)
            }
        }
        return baselines.count
    }

    /// Normal bottom subtitles and corner watermarks do not define a title card.
    /// Sparse cards need less text evidence than a detailed cinematic frame.
    static func score(regions: [CGRect], sparse: Bool, hasSubject: Bool) -> Float {
        let content = regions.filter { $0.midY > 0.22 && $0.midY < 0.92 && $0.width > 0.08 }
        let area = content.reduce(CGFloat.zero) { $0 + $1.width * $1.height }
        // A face on a poster does not immunize an overwhelmingly textual card.
        // Ordinary subtitles are outside this central region and stay eligible.
        if content.count >= 6 && area >= 0.38 { return 0.95 }
        let broadText = content.contains { $0.width >= 0.28 && $0.height >= 0.04 }
        if sparse && !hasSubject && (broadText || area >= 0.025 || content.count >= 2) { return 0.9 }
        if !hasSubject && ((content.count >= 3 && area >= 0.075) || (content.count >= 6 && area >= 0.06)) { return 0.85 }
        if !hasSubject {
            // A small role above a larger aligned name is a common credit/title
            // layout even when text occupies only 2–4% of a detailed backdrop.
            for upper in content {
                for lower in content where upper.minY > lower.maxY {
                    let gap = upper.minY - lower.maxY
                    let aligned = abs(upper.minX - lower.minX) < 0.035 || abs(upper.midX - lower.midX) < 0.035
                    if aligned && gap < 0.14 && lower.width > 0.25
                        && lower.height > upper.height * 1.45 && lower.height >= 0.045 { return 0.85 }
                }
            }
        }
        return min(0.6, Float(area * 2 + CGFloat(content.count) * 0.035))
    }
}

/// Developer-only, per-analysis measurements. Parent wall intervals include
/// child work; their totals must never be added together as pipeline duration.
/// The normal path neither reads a clock nor builds a diagnostic payload.
final class AutomaticFramePerformance: @unchecked Sendable {
    enum Stage: String {
        case discoveryDecode, detailedDecode, openingDecode, finalDecode, semanticAudit
        case pixelMetrics, initialQuality, subjectQuality, finalQuality
        case personAndTextRegions, fastOCR, accurateOCR, fullTextCoverage, fullTextRegions, fullFastOCR, detailedAudit, previewJPEG, finalJPEG
        case verifiedSelection, semanticSelection, provisionalSelection
    }
    enum Counter: String {
        case discoveryDecoded, finalDecoded, uniqueCandidates, semanticAudits, rawCacheEvictions, finalRawCacheHits
        case semanticQualitySkips, semanticReuses, fullQualityReuses, coverageAudits
        case detailedMainThreadAudits, detailedBackgroundAudits
        case detailedTextFailureFallbacks, detailedTextFallbackRejections
    }
    private struct Measurement { var seconds: Double = 0; var count = 0 }
    private let enabled: Bool
    private let started: Double?
    private let lock = NSLock()
    private var measurements: [Stage: Measurement] = [:]
    private var counters: [Counter: Int] = [:]

    init(enabled: Bool = ProcessInfo.processInfo.environment["SHOTMAP_FRAME_PERFORMANCE"] == "1") {
        self.enabled = enabled
        started = enabled ? ProcessInfo.processInfo.systemUptime : nil
    }

    func begin() -> Double? { enabled ? ProcessInfo.processInfo.systemUptime : nil }

    func finish(_ stage: Stage, since start: Double?, count: Int = 1) {
        guard let start else { return }
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - start)
        lock.lock()
        var value = measurements[stage] ?? Measurement()
        value.seconds += elapsed
        value.count += count
        measurements[stage] = value
        lock.unlock()
    }

    func measure<T>(_ stage: Stage, _ body: () throws -> T) rethrows -> T {
        let start = begin()
        defer { finish(stage, since: start) }
        return try body()
    }

    func increment(_ counter: Counter, by count: Int = 1) {
        guard enabled else { return }
        lock.lock()
        counters[counter, default: 0] += count
        lock.unlock()
    }

    func recordDetailedThread() {
        guard enabled else { return }
        increment(Thread.isMainThread ? .detailedMainThreadAudits : .detailedBackgroundAudits)
    }

    func emit() {
        guard let started else { return }
        let wall = max(0, ProcessInfo.processInfo.systemUptime - started)
        lock.lock()
        let stages = Dictionary(uniqueKeysWithValues: measurements.map { ($0.key.rawValue, ["seconds": $0.value.seconds, "count": Double($0.value.count)]) })
        let counts = Dictionary(uniqueKeysWithValues: counters.map { ($0.key.rawValue, $0.value) })
        lock.unlock()
        let payload: [String: Any] = ["wallSeconds": wall, "stages": stages, "counters": counts,
            "timingSemantics": "Nested wall and synchronous work overlap; do not sum stages."]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print("[AutomaticFramePerformance] " + text) }
    }
}

/// Low-cost evidence for a narrowly scheduled opening review. Existing OCR
/// fragments provide location; separated, aligned high-frequency row bands
/// confirm layout without interpreting low-confidence recognition as words.
enum AutomaticOpeningOverlayEvidence {
    static func hasAlignedLowerLeftRows(image: CGImage, regions: [CGRect]) -> Bool {
        let fragments = regions.filter { $0.minX < 0.35 && $0.maxX < 0.60 && $0.midY > 0.10
            && $0.midY < 0.35 && $0.height < 0.18 && $0.width < 0.50 }
        guard fragments.count >= 2 else { return false }
        let bounds = fragments.reduce(CGRect.null) { $0.union($1) }
        guard bounds.minX < 0.18, bounds.width >= 0.15, bounds.height >= 0.06 else { return false }
        let roi = CGRect(x: 0.05, y: 0.10, width: 0.45, height: 0.20)
        let cropRect = CGRect(x: roi.minX * CGFloat(image.width), y: (1 - roi.maxY) * CGFloat(image.height),
            width: roi.width * CGFloat(image.width), height: roi.height * CGFloat(image.height)).integral
        guard let crop = image.cropping(to: cropRect) else { return false }
        let scale = min(1, 240 / Double(crop.width))
        let width = max(1, Int(Double(crop.width) * scale)), height = max(1, Int(Double(crop.height) * scale))
        guard width >= 40, height >= 12 else { return false }
        var gray = [UInt8](repeating: 0, count: width * height)
        let rendered = gray.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return false }
        var bands: [(start: Int, end: Int, left: Int)] = []
        var start: Int?, left = width
        for row in 0..<height {
            var hits = 0, first = width
            for column in 1..<width where abs(Int(gray[row * width + column]) - Int(gray[row * width + column - 1])) > 36 {
                hits += 1; first = min(first, column)
            }
            if Double(hits) / Double(width) > 0.12 {
                if start == nil { start = row; left = first } else { left = min(left, first) }
            } else if let began = start {
                if row - began >= 2 { bands.append((began, row, left)) }
                start = nil
            }
        }
        if let began = start, height - began >= 2 { bands.append((began, height, left)) }
        for (index, upper) in bands.enumerated() {
            for lower in bands.dropFirst(index + 1) where lower.start - upper.end >= 1
                && abs(lower.left - upper.left) <= max(3, width / 12)
                && upper.end - upper.start < height / 2 && lower.end - lower.start < height / 2 { return true }
        }
        return false
    }
}
