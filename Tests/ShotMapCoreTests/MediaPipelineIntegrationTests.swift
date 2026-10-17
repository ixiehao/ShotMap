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
        for frame in result.frames + refined {
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

private enum FixtureError: Error { case writer, buffer }
