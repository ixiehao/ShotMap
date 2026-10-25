import AVFoundation
import XCTest
@testable import ShotMapApp

/// Small generated fixtures exercise system codecs without bundling private media.
final class MediaPipelineIntegrationTests: XCTestCase {
    func testHEVCProcessingAndManualRefinement() async throws {
        try await exercisePipeline(codec: .hevc, variableRate: false, portrait: false)
    }

    func testVariableFrameRatePortraitProcessingAndManualRefinement() async throws {
        try await exercisePipeline(codec: .h264, variableRate: true, portrait: true)
    }

    func testCancellingAfterFirstDecodedSampleStopsBeforeVisionAndPreview() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotMap-active-cancel-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("fixture.mov")
        _ = try await writeFixture(at: source, codec: .h264, variableRate: false, portrait: false)
        let probe = ActiveCancellationProbe()
        let finished = expectation(description: "Active decoder exits after cancellation")
        let operation = Task.detached {
            defer { finished.fulfill() }
            do {
                _ = try await VideoStoryboardAnalyzer().analyze(
                    videoURL: source, gridSide: 8, outputWidth: 1920,
                    progress: { value in
                        // This callback follows a successful decode and metric
                        // pass. Cancel only now, not before opening the asset.
                        if value > 0.05, value <= 0.58, probe.didDecodeSample() {
                            withUnsafeCurrentTask { $0?.cancel() }
                        }
                    },
                    onPreviewFrame: { _, _, _ in probe.didPublishPreview() }
                )
            } catch is CancellationError {
                probe.didCancel()
            } catch {
                probe.didFail(error)
            }
        }
        await fulfillment(of: [finished], timeout: 5)
        operation.cancel()
        let state = probe.snapshot()
        XCTAssertTrue(state.cancelled, "Expected active cancellation, received \(state.failure ?? "a normal result")")
        XCTAssertEqual(state.samples, 1)
        XCTAssertEqual(state.previews, 0)
    }

    /// Opt-in release-mode diagnostic. Warm both paths, then alternate their
    /// order at the same moments so decoder warm-up and filesystem caches do
    /// not systematically favour one implementation. No speed threshold in CI.
    func testSingleFrameBatchBenchmarkWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["SHOTMAP_RUN_FRAME_BENCHMARK"] == "1" else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotMap-frame-benchmark-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source: URL
        if let path = ProcessInfo.processInfo.environment["SHOTMAP_BENCHMARK_VIDEO"] {
            source = URL(fileURLWithPath: path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        } else {
            source = directory.appendingPathComponent("fixture.mov")
            _ = try await writeFixture(at: source, codec: .h264, variableRate: false, portrait: false)
        }
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        let moments = [0.25, 0.50, 0.75].map { duration * $0 }
        _ = try await legacySingleFrameCapture(asset: asset, duration: duration, time: moments[1])
        _ = try await ManualFrameExtractor.captureSharpestFrame(
            from: asset, duration: duration, at: moments[1], identifier: 0,
            maximumEdge: 1_600, compressionQuality: 0.92
        )
        var serialSeconds: [Double] = []
        var batchSeconds: [Double] = []
        var serialTimes: [Double] = []
        var batchTimes: [Double] = []
        for round in 0..<6 {
            let time = moments[round % moments.count]
            for useBatch in round.isMultiple(of: 2) ? [false, true] : [true, false] {
                let start = ProcessInfo.processInfo.systemUptime
                let frame: CapturedFrame
                if useBatch {
                    frame = try await ManualFrameExtractor.captureSharpestFrame(
                        from: asset, duration: duration, at: time, identifier: round,
                        maximumEdge: 1_600, compressionQuality: 0.92
                    )
                    batchSeconds.append(ProcessInfo.processInfo.systemUptime - start)
                    batchTimes.append(frame.time)
                } else {
                    frame = try await legacySingleFrameCapture(asset: asset, duration: duration, time: time)
                    serialSeconds.append(ProcessInfo.processInfo.systemUptime - start)
                    serialTimes.append(frame.time)
                }
                XCTAssertFalse(frame.jpegData.isEmpty)
            }
            XCTAssertEqual(serialTimes[round], batchTimes[round], accuracy: 1.0 / 60_000,
                           "Async batching must retain the same sharpness winner as the serial baseline")
        }
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            return (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
        }
        print("FRAME_BENCHMARK captures_per_path=\(batchTimes.count) source=\(source.lastPathComponent) serial_median_s=\(median(serialSeconds)) async_median_s=\(median(batchSeconds)) serial_times=\(serialTimes) async_times=\(batchTimes)")

        for gridSide in [3, 8] {
            let analyzer = VideoStoryboardAnalyzer()
            _ = try await analyzer.analyze(videoURL: source, gridSide: gridSide, outputWidth: 2560,
                                          progress: { _ in }, onPreviewFrame: { _, _, _ in })
            var seconds: [Double] = []
            var frameCounts: [Int] = []
            for _ in 0..<3 {
                let start = ProcessInfo.processInfo.systemUptime
                let result = try await analyzer.analyze(videoURL: source, gridSide: gridSide, outputWidth: 2560,
                                                       progress: { _ in }, onPreviewFrame: { _, _, _ in })
                seconds.append(ProcessInfo.processInfo.systemUptime - start)
                frameCounts.append(result.frames.count)
                XCTAssertEqual(result.frames.count, gridSide * gridSide)
            }
            print("PIPELINE_BENCHMARK grid=\(gridSide)x\(gridSide) source=\(source.lastPathComponent) median_s=\(median(seconds)) durations_s=\(seconds) output_frame_counts=\(frameCounts)")
        }
    }

    /// Historical implementation retained only as a benchmark oracle. The
    /// seven serial exact seeks, clarity score and full-resolution final seek
    /// intentionally match the previous production path.
    private func legacySingleFrameCapture(asset: AVURLAsset, duration: Double, time: Double) async throws -> CapturedFrame {
        let centre = min(max(0, time), max(0, duration - 0.001))
        let track = try await asset.loadTracks(withMediaType: .video).first
        let loadedRate = try await track?.load(.nominalFrameRate) ?? 30
        let rate = loadedRate.isFinite && loadedRate > 1 ? Double(loadedRate) : 30
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var best: (image: CGImage, time: Double, score: Float)?
        for seconds in ManualFrameExtractor.sharpnessComparisonTimes(around: centre, duration: duration, frameRate: rate) {
            let candidate: (image: CGImage, time: Double, score: Float)? = autoreleasepool {
                var actual = CMTime.zero
                guard let image = try? generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 60_000), actualTime: &actual) else { return nil }
                let metrics = PixelMetrics.make(from: image)
                let detail = min(1, metrics.sharpness / 0.18)
                let focused = min(1, metrics.focusedEdgeRatio / 0.62)
                let contrast = min(1, metrics.contrast / 0.24)
                let exposure = min(1, max(0, (metrics.luminance - 0.06) / 0.32))
                let clipping = max(0, metrics.brightRatio - 0.40) * 0.28 + max(0, metrics.blackRatio - 0.68) * 0.10
                let diffuse = max(0, 0.45 - metrics.focusedEdgeRatio) * 0.30
                let lowContrast = max(0, 0.10 - metrics.contrast) * 0.20
                let resolved = actual.isValid && actual.seconds.isFinite ? actual.seconds : seconds
                let score = detail * 0.43 + focused * 0.39 + contrast * 0.14 + exposure * 0.04
                    - clipping - diffuse - lowContrast - Float(abs(resolved - centre)) * 0.0001
                return (image, resolved, score)
            }
            if let candidate, candidate.score > (best?.score ?? -.greatestFiniteMagnitude) { best = candidate }
        }
        guard let best else { throw StoryboardError.noUsableFrames }
        let final = AVAssetImageGenerator(asset: asset)
        final.appliesPreferredTrackTransform = true
        final.maximumSize = CGSize(width: 1_600, height: 1_600)
        final.requestedTimeToleranceBefore = .zero
        final.requestedTimeToleranceAfter = .zero
        var actual = CMTime.zero
        let fullImage = try? final.copyCGImage(at: CMTime(seconds: best.time, preferredTimescale: 60_000), actualTime: &actual)
        let image = fullImage ?? best.image
        let jpeg = try XCTUnwrap(ImageCodec.jpegData(from: image, compressionQuality: 0.92))
        let resolved = fullImage != nil && actual.isValid && actual.seconds.isFinite ? actual.seconds : best.time
        return CapturedFrame(id: 0, time: resolved, jpegData: jpeg, aspectRatio: Double(image.width) / Double(image.height))
    }

    private func exercisePipeline(codec: AVVideoCodecType, variableRate: Bool, portrait: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotMap-codec-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("fixture.mov")
        let timestamps = try await writeFixture(at: source, codec: codec, variableRate: variableRate, portrait: portrait)
        let asset = AVURLAsset(url: source)
        let result = try await VideoStoryboardAnalyzer().analyze(
            videoURL: source, gridSide: 3, outputWidth: 1920,
            progress: { _ in }, onPreviewFrame: { _, _, _ in }
        )
        XCTAssertEqual(result.frames.count, 9)
        XCTAssertEqual(result.frames.map(\.time), result.frames.map(\.time).sorted())
        let candidates = try await ManualFrameExtractor.captureCandidates(
            from: source, gridSide: 3, outputWidth: 1920, count: 12, batch: 0
        )
        XCTAssertEqual(candidates.count, 12)
        XCTAssertEqual(Set(candidates.map(\.id)).count, 12)
        var selected = Array(candidates.prefix(9))
        let first = try XCTUnwrap(selected.first)
        selected.append(CapturedFrame(id: 10_000, time: first.time, jpegData: first.jpegData, aspectRatio: first.aspectRatio))
        let refined = try await ManualFrameExtractor.captureSharpestFrames(
            from: asset, duration: result.duration, frames: selected,
            maximumEdge: 640, compressionQuality: 0.92
        )
        XCTAssertEqual(refined.map(\.id), selected.map(\.id))
        XCTAssertEqual(refined.first?.jpegData, refined.last?.jpegData,
                       "A shared decoded time must still map to both requested IDs")
        for frame in refined {
            let image = try XCTUnwrap(ImageCodec.cgImage(from: frame.jpegData))
            XCTAssertEqual(max(image.width, image.height), 640,
                           "Final refinement must not silently return the 480px analysis image")
        }
        let single = try await ManualFrameExtractor.captureSharpestFrame(
            from: asset, duration: result.duration, at: first.time, identifier: 20_000,
            maximumEdge: 640, compressionQuality: 0.92
        )
        XCTAssertEqual(single.id, 20_000)
        let singleImage = try XCTUnwrap(ImageCodec.cgImage(from: single.jpegData))
        XCTAssertEqual(max(singleImage.width, singleImage.height), 640)
        for frame in result.frames + refined + [single] {
            XCTAssertGreaterThanOrEqual(frame.time, 0)
            XCTAssertLessThan(frame.time, result.duration)
            XCTAssertTrue(timestamps.contains { abs($0 - frame.time) < 0.003 },
                          "Returned timestamp must identify an actual frame, including VFR media")
            let image = try XCTUnwrap(ImageCodec.cgImage(from: frame.jpegData))
            XCTAssertEqual(image.width < image.height, portrait)
        }
        let output = try StoryboardComposer.render(
            result: result, settings: ExportSettings(gridSide: 3, format: .jpeg, width: 1920)
        )
        XCTAssertEqual(try XCTUnwrap(ImageCodec.cgImage(from: output)).width, 1920)
    }

    @MainActor
    func testManualPlaybackAdvancesPausesAndReachesTheEndOfARealVideo() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotMap-playback-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("fixture.mov")
        _ = try await writeFixture(at: source, codec: .h264, variableRate: false, portrait: false)
        let duration = try await AVURLAsset(url: source).load(.duration).seconds
        let playback = ManualVideoPlayback()
        defer { playback.stopAndRelease() }
        playback.prepare(url: source)
        playback.play(from: 0, duration: duration)
        let playingDeadline = ContinuousClock.now + .seconds(5)
        while playback.currentTime < 0.15, ContinuousClock.now < playingDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThan(playback.currentTime, 0.1, "The real AVPlayer clock must drive the manual timeline")
        let pausedAt = playback.pause()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.currentTime, pausedAt, accuracy: 0.01)

        playback.play(from: duration - 0.3, duration: duration)
        let endDeadline = ContinuousClock.now + .seconds(5)
        while playback.endCount == 0, ContinuousClock.now < endDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(playback.endCount, 1)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.currentTime, duration, accuracy: 0.1)
        playback.stopAndRelease()
        XCTAssertFalse(playback.hasObservers)
        XCTAssertNil(playback.player.currentItem)
    }

    private func writeFixture(at url: URL, codec: AVVideoCodecType, variableRate: Bool, portrait: Bool) async throws -> [Double] {
        let width = portrait ? 540 : 960
        let height = portrait ? 960 : 540
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height]
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw XCTSkip("This host cannot encode the \(codec.rawValue) fixture")
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height
        ])
        guard writer.canAdd(input) else { throw FixtureError.writer }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FixtureError.writer }
        writer.startSession(atSourceTime: .zero)
        defer { if writer.status == .writing { writer.cancelWriting() } }
        var ticks: Int64 = 0
        var timestamps: [Double] = []
        for index in 0..<48 {
            let deadline = Date().addingTimeInterval(10)
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing, Date() < deadline else { throw writer.error ?? FixtureError.writer }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            let buffer = try pixelBuffer(width: width, height: height, index: index)
            let time = CMTime(value: ticks, timescale: 600)
            guard adaptor.append(buffer, withPresentationTime: time) else { throw writer.error ?? FixtureError.writer }
            timestamps.append(time.seconds)
            ticks += variableRate ? [20, 50, 30, 100][index % 4] : 50
        }
        writer.endSession(atSourceTime: CMTime(value: ticks, timescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? FixtureError.writer }
        return timestamps
    }

    private func pixelBuffer(width: Int, height: Int, index: Int) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &result)
        guard status == kCVReturnSuccess, let buffer = result else { throw FixtureError.buffer }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw FixtureError.buffer }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * stride + x * 4
                let checker = ((x / 20) + (y / 20) + index / 3).isMultiple(of: 2)
                bytes[offset] = UInt8(checker ? (index * 17) % 180 + 50 : 28)
                bytes[offset + 1] = UInt8(checker ? 220 : (index * 29) % 170 + 55)
                bytes[offset + 2] = UInt8(checker ? 245 : 74)
                bytes[offset + 3] = 255
            }
        }
        return buffer
    }
}

private final class ActiveCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var samples = 0
    private var previews = 0
    private var cancelled = false
    private var failure: String?

    func didDecodeSample() -> Bool {
        lock.withLock {
            samples += 1
            return samples == 1
        }
    }

    func didPublishPreview() { lock.withLock { previews += 1 } }
    func didCancel() { lock.withLock { cancelled = true } }
    func didFail(_ error: Error) { lock.withLock { failure = String(describing: error) } }
    func snapshot() -> (samples: Int, previews: Int, cancelled: Bool, failure: String?) {
        lock.withLock { (samples, previews, cancelled, failure) }
    }
}

private enum FixtureError: Error { case writer, buffer }
