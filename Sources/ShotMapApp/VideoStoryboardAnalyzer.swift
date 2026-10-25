import AVFoundation
import CoreGraphics
import Foundation
import OSLog
import Vision

/// OSSignposter has no Sendable annotation in the macOS 14 SDK. Its API is
/// safe for concurrent event producers, so contain that legacy annotation at
/// the diagnostic boundary instead of weakening the analyser's Sendable model.
private final class StoryboardSignposter: @unchecked Sendable {
    let value: OSSignposter

    init(category: String) {
        value = OSSignposter(
            subsystem: Bundle.main.bundleIdentifier ?? "com.ixiehao.shotmap",
            category: category
        )
    }
}

/// Stateless analysis worker. Keeping this as a value type lets Swift verify
/// that it is safe to pass into the detached generation task.
struct VideoStoryboardAnalyzer: Sendable {
    private static let pipelineSignposter = StoryboardSignposter(category: "StoryboardAnalysis")
    // The analysis thumbnail is also the storyboard source. Reusing it avoids a
    // second random-access decode pass after selection, which is the slowest part
    // of many H.264/HEVC files.
    private let maximumAnalysisSamples = 144
    private let minimumAnalysisEdge: CGFloat = 480
    private let maximumAnalysisEdge: CGFloat = 1280
    // Vision is valuable as a preference signal, but it must not dominate the
    // runtime of a normal storyboard. The lightweight pixel scan still covers
    // the full timeline; Vision only validates a small, representative subset.
    private let maximumPersonVisionCandidates = 16
    private let maximumTextVisionCandidates = 8

    func analyze(
        videoURL: URL,
        gridSide: Int,
        outputWidth: Int,
        progress: @escaping @Sendable (Double) -> Void,
        onPreviewFrame: @escaping @Sendable (CapturedFrame, Int, Int) async -> Void
    ) async throws -> StoryboardResult {
        try Task.checkCancellation()
        let gridSide = StoryboardGrid.boundedSide(gridSide)
        let wholePipeline = Self.pipelineSignposter.value.beginInterval("storyboardPipeline")
        defer {
            Self.pipelineSignposter.value.endInterval("storyboardPipeline", wholePipeline)
        }

        let asset = AVURLAsset(url: videoURL)
        // Unplayable also includes empty, truncated and non-video files.
        // Preserve metadata errors before deciding that conversion can help.
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw StoryboardError.unreadableVideo }
        let isPlayable = try await asset.load(.isPlayable)
        if !isPlayable {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard !videoTracks.isEmpty else { throw StoryboardError.unreadableVideo }
            throw StoryboardError.unsupportedCodec
        }

        let targetCount = gridSide * gridSide
        let sampleCount = analysisSampleCount(for: targetCount)
        let interval = max(0.22, duration / Double(sampleCount))
        let analysisGenerator = imageGenerator(
            asset: asset,
            maximumEdge: broadScanMaximumEdge(gridSide: gridSide, outputWidth: outputWidth)
        )

        var requestedTimes: [CMTime] = []
        var requestedSeconds = 0.0
        while requestedSeconds < duration {
            requestedTimes.append(CMTime(seconds: requestedSeconds, preferredTimescale: 600))
            requestedSeconds += interval
        }

        var descriptors: [FrameDescriptor] = []
        descriptors.reserveCapacity(requestedTimes.count)
        var completedSamples = 0
        // AVFoundation's async image sequence batches the timeline requests in
        // one decoder pipeline. On current Apple Silicon Macs this avoids the
        // repeated caller-thread stalls of copyCGImage(at:) while retaining the
        // same tolerant keyframe behavior and macOS 13 compatibility.
        defer { analysisGenerator.cancelAllCGImageGeneration() }
        do {
            let broadDecode = Self.pipelineSignposter.value.beginInterval("storyboardBroadDecode")
            defer {
                Self.pipelineSignposter.value.endInterval("storyboardBroadDecode", broadDecode)
            }
            for await result in analysisGenerator.images(for: requestedTimes) {
                try Task.checkCancellation()
                completedSamples += 1
                guard case let .success(requestedTime, image, actualTime) = result else {
                    progress(0.05 + 0.53 * Double(completedSamples) / Double(max(1, requestedTimes.count)))
                    continue
                }
                // Image decoding and metric buffers can accumulate across a long
                // batch. Keep each pass scoped so memory remains stable on both
                // Intel and Apple Silicon Macs.
                let descriptor: FrameDescriptor? = autoreleasepool {
                    guard let previewData = ImageCodec.jpegData(from: image, compressionQuality: 0.88) else {
                        return nil
                    }
                    let metrics = PixelMetrics.make(from: image)
                    var descriptor = FrameDescriptor(
                        id: completedSamples - 1,
                        time: actualTime.isValid && actualTime.seconds.isFinite ? actualTime.seconds : requestedTime.seconds,
                        histogram: metrics.histogram,
                        luminance: metrics.luminance,
                        blackRatio: metrics.blackRatio,
                        brightRatio: metrics.brightRatio,
                        dominantToneRatio: metrics.dominantToneRatio,
                        sharpness: metrics.sharpness,
                        fingerprint: metrics.fingerprint,
                        previewData: previewData
                    )
                    descriptor.aspectRatio = image.height > 0 ? Double(image.width) / Double(image.height) : (16.0 / 9.0)
                    return descriptor
                }
                guard let descriptor else { continue }
                descriptors.append(descriptor)
                progress(0.05 + 0.53 * Double(completedSamples) / Double(max(1, requestedTimes.count)))
            }
        }

        try Task.checkCancellation()
        guard !descriptors.isEmpty else { throw StoryboardError.unreadableVideo }
        descriptors.sort { $0.time < $1.time }
        descriptors = addingTemporalSignals(to: descriptors)

        // Vision is the slowest part of automatic selection. Keep people and
        // text analysis intentionally independent: people scoring samples a
        // compact blend of shot leaders and time coverage, while OCR only
        // examines likely title-card locations. We do not run three Vision
        // requests against every broad-scan frame.
        let personCandidates = peopleCandidates(
            from: descriptors,
            count: personVisionBudget(for: targetCount)
        )
        let textCandidates = titleCardCandidates(
            from: descriptors,
            count: textVisionBudget(for: targetCount)
        )
        var peopleSignalsByID: [Int: PersonSignals] = [:]
        var textScoreByID: [Int: Float] = [:]
        let visionWorkCount = max(1, personCandidates.count + textCandidates.count)
        var completedVisionWork = 0
        do {
            let visionInterval = Self.pipelineSignposter.value.beginInterval("storyboardVision")
            defer {
                Self.pipelineSignposter.value.endInterval("storyboardVision", visionInterval)
            }

            // Boundary and low-detail candidates often need both person and OCR
            // checks. Decode and scale their JPEG once, rather than repeating
            // the same image work for each Vision request type.
            var visionPreviewsByID: [Int: CGImage] = [:]
            for candidate in personCandidates + textCandidates where visionPreviewsByID[candidate.id] == nil {
                try Task.checkCancellation()
                let preview: CGImage? = autoreleasepool {
                    guard let data = candidate.previewData,
                          let image = ImageCodec.cgImage(from: data) else {
                        return nil
                    }
                    return visionPreview(from: image)
                }
                if let preview {
                    visionPreviewsByID[candidate.id] = preview
                }
            }

            for candidate in personCandidates {
                try Task.checkCancellation()
                let people = visionPreviewsByID[candidate.id].map(personSignals(in:))
                if let people {
                    peopleSignalsByID[candidate.id] = people
                }
                completedVisionWork += 1
                progress(0.58 + 0.14 * Double(completedVisionWork) / Double(visionWorkCount))
            }
            for candidate in textCandidates {
                try Task.checkCancellation()
                let textScore = visionPreviewsByID[candidate.id].map(textOverlayScore(in:))
                if let textScore {
                    textScoreByID[candidate.id] = textScore
                }
                completedVisionWork += 1
                progress(0.58 + 0.14 * Double(completedVisionWork) / Double(visionWorkCount))
            }
        }
        descriptors = descriptors.map { descriptor in
            var updated = descriptor
            let signals = peopleSignalsByID[descriptor.id] ?? PersonSignals()
            updated.peopleScore = signals.score
            updated.faceScore = signals.faceScore
            updated.bodyScore = signals.bodyScore
            updated.faceCount = signals.faceCount
            updated.textOverlayScore = textScoreByID[descriptor.id] ?? 0
            return updated
        }
        progress(0.72)

        let selected = FrameSelection.chooseFrames(from: descriptors, count: targetCount)
        guard !selected.isEmpty else { throw StoryboardError.noUsableFrames }

        var captured: [CapturedFrame] = []
        let finalFrameEdge = analysisMaximumEdge(gridSide: gridSide, outputWidth: outputWidth)
        do {
            let finalRefinement = Self.pipelineSignposter.value.beginInterval("storyboardFinalRefinement")
            defer {
                Self.pipelineSignposter.value.endInterval("storyboardFinalRefinement", finalRefinement)
            }

            let fallbackByID = Dictionary(uniqueKeysWithValues: selected.compactMap { descriptor -> (Int, CapturedFrame)? in
                guard let data = descriptor.previewData else { return nil }
                return (
                    descriptor.id,
                    CapturedFrame(
                        id: descriptor.id,
                        time: descriptor.time,
                        jpegData: data,
                        aspectRatio: descriptor.aspectRatio
                    )
                )
            })

            // The broad-scan frame is already a usable, chronological preview.
            // Publish it before the optional presentation/sharpness work starts
            // so the studio can render a stable grid immediately. The same slot
            // is later replaced by the final captured frame below; this callback
            // deliberately uses the selected descriptor's index rather than an
            // append count, because a missing timestamp must never shift a card.
            for (offset, descriptor) in selected.enumerated() {
                try Task.checkCancellation()
                if let fallback = fallbackByID[descriptor.id] {
                    await onPreviewFrame(fallback, offset, targetCount)
                }
                await Task.yield()
            }

            let refinementInputs = selected.compactMap { descriptor -> CapturedFrame? in
                guard requiresExactRefinement(descriptor) else { return nil }
                return fallbackByID[descriptor.id]
            }
            let refinedByID: [Int: CapturedFrame]
            if refinementInputs.isEmpty {
                refinedByID = [:]
            } else {
                do {
                    let refined = try await ManualFrameExtractor.captureSharpestFrames(
                        from: asset,
                        duration: duration,
                        frames: refinementInputs,
                        maximumEdge: finalFrameEdge,
                        compressionQuality: 0.92
                    )
                    refinedByID = Dictionary(uniqueKeysWithValues: refined.map { ($0.id, $0) })
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // A damaged timestamp must not turn a usable automatic
                    // storyboard into an error; all cards retain their broad
                    // scan image when the optional batch refinement fails.
                    refinedByID = [:]
                }
            }

            // Refinement already attempts an export-sized decode and its result
            // takes precedence (including the analysis fallback for a damaged
            // final seek). Upgrade only cards without a refinement result;
            // this preserves the previous fallback order without decoding
            // presentation images that would immediately be discarded.
            let presentationByID: [Int: CapturedFrame]
            if needsPresentationUpgrade(gridSide: gridSide, outputWidth: outputWidth) {
                do {
                    let presentationFrames = try await ManualFrameExtractor.capturePresentationFrames(
                        from: asset,
                        frames: Self.presentationUpgradeInputs(
                            selected.compactMap { fallbackByID[$0.id] },
                            refinedIDs: Set(refinedByID.keys)
                        ),
                        maximumEdge: finalFrameEdge,
                        compressionQuality: 0.92
                    )
                    presentationByID = Dictionary(uniqueKeysWithValues: presentationFrames.map { ($0.id, $0) })
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    presentationByID = [:]
                }
            } else {
                presentationByID = [:]
            }

            for (offset, descriptor) in selected.enumerated() {
                try Task.checkCancellation()
                guard let fallback = fallbackByID[descriptor.id] else { continue }
                let frame = refinedByID[descriptor.id] ?? presentationByID[descriptor.id] ?? fallback
                captured.append(frame)
                progress(0.72 + 0.26 * Double(offset + 1) / Double(selected.count))
                // Yield so the main actor can present progressive cards, but do not
                // add an artificial half-second delay to every video in a batch.
                await Task.yield()
            }
        }

        guard !captured.isEmpty else { throw StoryboardError.noUsableFrames }
        // Decoders occasionally reject an isolated timestamp in a damaged or VFR
        // file. Preserve a complete requested grid instead of rendering blank cards.
        if captured.count < targetCount {
            let fallback = captured
            var nextID = -1
            while captured.count < targetCount {
                let source = fallback[captured.count % fallback.count]
                captured.append(CapturedFrame(id: nextID, time: source.time, jpegData: source.jpegData, aspectRatio: source.aspectRatio))
                nextID -= 1
            }
        }

        // Keep the visual order stable while replacing broad-scan cards with
        // presentation-size or sharpness-refined captures. Export still receives
        // only `captured`, so preview timing cannot alter the saved storyboard.
        for (index, frame) in captured.enumerated() {
            try Task.checkCancellation()
            await onPreviewFrame(frame, index, targetCount)
            await Task.yield()
        }
        progress(1)
        return StoryboardResult(frames: captured, sourceURL: videoURL, duration: duration)
    }

    static func presentationUpgradeInputs(
        _ frames: [CapturedFrame],
        refinedIDs: Set<Int>
    ) -> [CapturedFrame] {
        frames.filter { !refinedIDs.contains($0.id) }
    }

    private func imageGenerator(asset: AVAsset, maximumEdge: CGFloat) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumEdge, height: maximumEdge)
        // A small keyframe tolerance avoids expensive exact-frame seeks during
        // analysis, without noticeably changing a representative storyboard shot.
        let tolerance = CMTime(seconds: 0.75, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        return generator
    }

    private func analysisMaximumEdge(gridSide: Int, outputWidth: Int) -> CGFloat {
        let estimatedCellWidth = Double(max(1920, outputWidth)) / Double(gridSide)
        let desiredEdge = CGFloat(estimatedCellWidth * 1.15)
        return min(maximumAnalysisEdge, max(minimumAnalysisEdge, desiredEdge))
    }

    func analysisSampleCount(for targetCount: Int) -> Int {
        // A small contact sheet needs a generous fixed pool to discover scene
        // changes. For 7 × 7 and 8 × 8, however, a 50% surplus decodes many
        // cards that cannot influence the final grid. Keep at least 12 spare
        // candidates and roughly 25% headroom, which is sufficient for cuts,
        // near-duplicates, and title-card rejection without wasting a long
        // video's decoder budget.
        let extraCandidates = max(12, Int((Double(max(1, targetCount)) * 0.25).rounded(.up)))
        let requested = max(48, targetCount + extraCandidates)
        return min(maximumAnalysisSamples, requested)
    }

    /// Pixel metrics are reduced to 48 × 48 and Vision previews are capped at
    /// 400 px, so a small grid does not need to decode every broad-scan moment
    /// at export resolution. Decode its 9–16 final cards once at full display
    /// size after selection instead. Large grids already operate near the card
    /// size, where a second pass would cost more than it saves.
    private func broadScanMaximumEdge(gridSide: Int, outputWidth: Int) -> CGFloat {
        let presentationEdge = analysisMaximumEdge(gridSide: gridSide, outputWidth: outputWidth)
        guard needsPresentationUpgrade(gridSide: gridSide, outputWidth: outputWidth) else {
            return presentationEdge
        }
        return min(400, presentationEdge)
    }

    private func needsPresentationUpgrade(gridSide: Int, outputWidth: Int) -> Bool {
        gridSide <= 4 && analysisMaximumEdge(gridSide: gridSide, outputWidth: outputWidth) > 400
    }

    private func personVisionBudget(for targetCount: Int) -> Int {
        let scaled = max(8, Int((Double(max(1, targetCount)).squareRoot() * 2).rounded(.up)))
        return min(maximumPersonVisionCandidates, scaled)
    }

    private func textVisionBudget(for targetCount: Int) -> Int {
        // OCR is reserved for common cover/credit/warning locations. It remains
        // available as a guard without making every cinematic frame pay for text
        // recognition.
        let scaled = max(6, Int((Double(max(1, targetCount)).squareRoot()).rounded(.up)))
        return min(maximumTextVisionCandidates, scaled)
    }

    private func requiresExactRefinement(_ descriptor: FrameDescriptor) -> Bool {
        // The broad scan already yields a clear, correctly sized JPEG. Only
        // spend seven exact decodes where the low-cost temporal metrics signal a
        // realistic risk of a motion trail, cut, or weak detail. Static dialogue
        // and establishing shots keep their selected scan image immediately.
        descriptor.motionScore >= 0.50
            || descriptor.transitionScore >= 0.18
            || descriptor.sharpness < 0.10
    }

    private func peopleCandidates(from descriptors: [FrameDescriptor], count: Int) -> [FrameDescriptor] {
        let usable = descriptors.filter(\.isUsable)
        guard !usable.isEmpty, count > 0 else { return [] }
        // Opening/closing cards often occupy several consecutive samples. Always
        // inspect the first and last moments rather than relying solely on a
        // broad evenly-spaced pass, which could otherwise miss a 0s/19s intro.
        let boundaryCount = min(3, usable.count)
        let boundaries = Array(usable.prefix(boundaryCount)) + Array(usable.suffix(boundaryCount))
        let shotLeaders = FrameSelection.sceneRanges(in: usable).compactMap { range in
            usable[range].max { $0.qualityScore < $1.qualityScore }
        }
        let distributed = FrameSelection.evenlySpaced(usable, count: max(1, count / 4))
        let visualLeaders = usable.sorted { $0.qualityScore > $1.qualityScore }
        var seen = Set<Int>()
        var candidates: [FrameDescriptor] = []
        for candidate in boundaries + shotLeaders + distributed + visualLeaders where candidates.count < count {
            if seen.insert(candidate.id).inserted {
                candidates.append(candidate)
            }
        }
        return candidates
    }

    private func titleCardCandidates(from descriptors: [FrameDescriptor], count: Int) -> [FrameDescriptor] {
        let usable = descriptors.filter(\.isUsable)
        guard !usable.isEmpty, count > 0 else { return [] }

        // Covers and credits cluster at the boundaries; warnings and intertitles
        // are usually sparse or uniform. These inexpensive pixel metrics provide
        // a focused OCR shortlist without treating a dark cinematic shot as bad.
        let boundaryCount = min(2, usable.count)
        let boundaries = Array(usable.prefix(boundaryCount)) + Array(usable.suffix(boundaryCount))
        let sparse = usable
            .filter(\.isVisuallySparseCard)
            .sorted { $0.qualityScore < $1.qualityScore }
        let lowestDetail = usable.sorted { $0.sharpness < $1.sharpness }

        var seen = Set<Int>()
        var candidates: [FrameDescriptor] = []
        for candidate in boundaries + sparse + lowestDetail where candidates.count < count {
            if seen.insert(candidate.id).inserted {
                candidates.append(candidate)
            }
        }
        return candidates
    }

    private struct PersonSignals: Sendable {
        var score: Float = 0
        var faceScore: Float = 0
        var bodyScore: Float = 0
        var faceCount = 0
    }

    private func personSignals(in image: CGImage) -> PersonSignals {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let faces = VNDetectFaceRectanglesRequest()
        let bodies = VNDetectHumanRectanglesRequest()
        bodies.upperBodyOnly = false
        // A single handler pass shares image preparation between face and body
        // detection. The old two-pass version doubled Vision overhead per frame.
        guard (try? handler.perform([faces, bodies])) != nil else { return PersonSignals() }
        let detectedFaces = faces.results ?? []
        let faceArea = detectedFaces
            .map { Float($0.boundingBox.width * $0.boundingBox.height) }
            .max() ?? 0
        let faceScore = min(1, faceArea * 11)

        let bodyArea = (bodies.results ?? [])
            .map { Float($0.boundingBox.width * $0.boundingBox.height) }
            .max() ?? 0

        // A clear close-up is useful, while a large human rectangle favors a
        // readable pose. Multiple faces are a strong dialogue/interaction cue.
        let bodyScore = min(1, bodyArea * 4)
        let interaction: Float = detectedFaces.count >= 2 ? min(0.30, Float(detectedFaces.count - 1) * 0.12) : 0
        return PersonSignals(
            score: min(1, max(faceScore * 0.92, bodyScore * 0.78) + interaction),
            faceScore: faceScore,
            bodyScore: bodyScore,
            faceCount: detectedFaces.count
        )
    }

    private func addingTemporalSignals(to descriptors: [FrameDescriptor]) -> [FrameDescriptor] {
        guard descriptors.count > 1 else { return descriptors }
        return descriptors.indices.map { index in
            var descriptor = descriptors[index]
            let previous = index > 0 ? FrameSelection.histogramDistance(descriptors[index - 1].histogram, descriptor.histogram) : 0
            let next = index + 1 < descriptors.count ? FrameSelection.histogramDistance(descriptor.histogram, descriptors[index + 1].histogram) : 0
            descriptor.motionScore = min(1, (previous + next) / 0.28)
            // A severe discontinuity is a cut or fade; it should never be the
            // preferred still even if its histogram happens to be high contrast.
            descriptor.transitionScore = max(previous, next) >= 0.52 ? 1 : max(0, max(previous, next) - 0.30) / 0.22
            return descriptor
        }
    }

    private func textOverlayScore(in image: CGImage) -> Float {
        let regionScore = textRegionScore(in: image)
        // A small subtitle line is not a title card; an obvious multi-line card
        // needs no character recognition at all. Restrict the comparatively
        // expensive OCR pass to the ambiguous middle band, where it can still
        // separate a genuine cover or warning from on-screen dialogue.
        guard regionScore >= 0.34 else { return 0 }
        guard regionScore < 0.70 else { return regionScore }
        return max(regionScore, recognizedTextOverlayScore(in: image))
    }

    private func textRegionScore(in image: CGImage) -> Float {
        let request = VNDetectTextRectanglesRequest()
        // We score line regions only; character boxes provide no selection
        // benefit and add work on frames that are clearly not title cards.
        request.reportCharacterBoxes = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return 0 }
        let textRegions = request.results ?? []
        return overlayTextScore(
            area: textRegions.reduce(Float(0)) { partial, observation in
                partial + Float(observation.boundingBox.width * observation.boundingBox.height)
            },
            count: textRegions.count
        )
    }

    private func recognizedTextOverlayScore(in image: CGImage) -> Float {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.018
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return 0 }
        let textRegions = (request.results ?? []).filter { !$0.topCandidates(1).isEmpty }
        guard !textRegions.isEmpty else { return 0 }
        let area = textRegions.reduce(Float(0)) { partial, observation in
            partial + Float(observation.boundingBox.width * observation.boundingBox.height)
        }
        return overlayTextScore(area: area, count: textRegions.count)
    }

    private func overlayTextScore(area: Float, count: Int) -> Float {
        // One large title or several warning lines are meaningful. A normal
        // one-line subtitle remains below the rejection threshold.
        min(1, area * 4 + Float(count) * 0.10)
    }

    private func visionPreview(from image: CGImage) -> CGImage {
        let maxEdge: CGFloat = 400
        let longestEdge = max(CGFloat(image.width), CGFloat(image.height))
        guard longestEdge > maxEdge else { return image }
        let scale = maxEdge / longestEdge
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}

/// Compact visual metrics shared by automatic analysis and manual candidate
/// selection. They remain low-resolution so interactive selection stays fast.
struct PixelMetrics {
    let histogram: [Float]
    let luminance: Float
    let blackRatio: Float
    let brightRatio: Float
    let dominantToneRatio: Float
    let sharpness: Float
    /// Dissolves and motion trails have lots of weak edges; this tells them
    /// apart from decisive, in-focus boundaries.
    let focusedEdgeRatio: Float
    /// A secondary cue for washed-out dissolves and flash frames.
    let contrast: Float
    let fingerprint: UInt64

    static func make(from image: CGImage) -> PixelMetrics {
        let size = 48
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &bytes,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return PixelMetrics(
                histogram: Array(repeating: 0, count: 16),
                luminance: 0,
                blackRatio: 1,
                brightRatio: 0,
                dominantToneRatio: 1,
                sharpness: 0,
                focusedEdgeRatio: 0,
                contrast: 0,
                fingerprint: 0
            )
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        var luminance = [Float](repeating: 0, count: size * size)
        var histogram = [Float](repeating: 0, count: 16)
        var blackPixels = 0
        var brightPixels = 0
        var sum: Float = 0
        for pixel in 0..<(size * size) {
            let offset = pixel * 4
            let value = (0.2126 * Float(bytes[offset]) + 0.7152 * Float(bytes[offset + 1]) + 0.0722 * Float(bytes[offset + 2])) / 255
            luminance[pixel] = value
            sum += value
            if value < 0.055 { blackPixels += 1 }
            if value > 0.92 { brightPixels += 1 }
            histogram[min(15, Int(value * 16))] += 1
        }
        histogram = histogram.map { $0 / Float(size * size) }

        var edgeEnergy: Float = 0
        var focusedEdgeEnergy: Float = 0
        for y in 1..<(size - 1) {
            for x in 1..<(size - 1) {
                let center = luminance[y * size + x]
                let laplacian = abs(4 * center - luminance[y * size + x - 1] - luminance[y * size + x + 1] - luminance[(y - 1) * size + x] - luminance[(y + 1) * size + x])
                edgeEnergy += laplacian
                if laplacian >= 0.18 { focusedEdgeEnergy += laplacian }
            }
        }

        let average = sum / Float(size * size)
        let variance = luminance.reduce(Float.zero) { partial, value in
            let delta = value - average
            return partial + delta * delta
        } / Float(size * size)
        let fingerprint = averageHash(luminance)
        return PixelMetrics(
            histogram: histogram,
            luminance: average,
            blackRatio: Float(blackPixels) / Float(size * size),
            brightRatio: Float(brightPixels) / Float(size * size),
            dominantToneRatio: histogram.max() ?? 1,
            sharpness: edgeEnergy / Float((size - 2) * (size - 2)),
            focusedEdgeRatio: edgeEnergy > 0 ? focusedEdgeEnergy / edgeEnergy : 0,
            contrast: sqrt(variance),
            fingerprint: fingerprint
        )
    }

    private static func averageHash(_ luminance: [Float]) -> UInt64 {
        let sourceSize = 48
        let hashSize = 8
        var reduced = [Float](repeating: 0, count: hashSize * hashSize)
        for y in 0..<hashSize {
            for x in 0..<hashSize {
                var sum: Float = 0
                for sourceY in (y * 6)..<((y + 1) * 6) {
                    for sourceX in (x * 6)..<((x + 1) * 6) {
                        sum += luminance[sourceY * sourceSize + sourceX]
                    }
                }
                reduced[y * hashSize + x] = sum / 36
            }
        }
        let mean = reduced.reduce(0, +) / Float(reduced.count)
        return reduced.enumerated().reduce(into: UInt64(0)) { hash, element in
            if element.element >= mean { hash |= UInt64(1) << UInt64(element.offset) }
        }
    }
}
