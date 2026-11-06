import AppKit
import AVFoundation
import SwiftUI
import XCTest
@testable import ShotMapApp

final class ManualEditorStartupTests: XCTestCase {
    @MainActor
    func testHostedEditorAutomaticallyPreparesPlayableSourceAndReleasesItOnClose() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotMap-editor-startup-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("portrait.mov")
        try await writeMovie(at: source)
        let model = StoryboardViewModel()
        model.addVideos([source])
        model.gridSide = 4
        model.format = .png
        model.background = .navy
        model.showTimestamps = false
        model.showTitleWatermark = true
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 18, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
        let data = try XCTUnwrap(ImageCodec.jpegData(from: XCTUnwrap(context.makeImage()), compressionQuality: 0.8))
        _ = await model.completeJob(data: data, result: StoryboardResult(frames: [], sourceURL: source, duration: 2),
                                    settings: model.currentExportSettings, index: 0, total: 1)
        var request = model.manualEditorRequest
        XCTAssertNotNil(request)
        var presented: NSWindow?
        let host = ManualFrameEditorWindowPresenter.HostView(presentWindow: { window in
            presented = window
        })
        defer { ManualFrameEditorWindowPresenter.dismantleNSView(host, coordinator: ()); model.clearVideos() }
        host.update(request: Binding(get: { request }, set: { request = $0 }), model: model,
                    language: .english, colorScheme: .light, onApply: { _, _, _ in })
        let window = try XCTUnwrap(presented)
        window.contentView?.layoutSubtreeIfNeeded()
        let deadline = ContinuousClock.now + .seconds(8)
        while ContinuousClock.now < deadline {
            window.contentView?.layoutSubtreeIfNeeded()
            if player(in: window.contentView)?.currentItem?.status == .readyToPlay { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let videoPlayer = try XCTUnwrap(player(in: window.contentView))
        let item = try XCTUnwrap(videoPlayer.currentItem,
            "The actual hosted view must prepare AVPlayer without any user command")
        XCTAssertEqual(item.status, .readyToPlay, "A created but unprepared player does not satisfy editor startup")
        XCTAssertEqual((item.asset as? AVURLAsset)?.url, source)
        XCTAssertEqual(item.duration.seconds, 2, accuracy: 0.05)
        XCTAssertEqual(window.title, source.lastPathComponent)

        // Appearance/language updates must retain the already prepared native
        // transport rather than rebuilding the host and starting it again.
        host.update(request: Binding(get: { request }, set: { request = $0 }), model: model,
                    language: .japanese, colorScheme: .dark, onApply: { _, _, _ in })
        for _ in 0..<5 { await Task.yield() }
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(player(in: window.contentView) === videoPlayer)
        XCTAssertTrue(videoPlayer.currentItem === item)

        ManualFrameEditorWindowPresenter.dismantleNSView(host, coordinator: ())
        let closeDeadline = ContinuousClock.now + .seconds(2)
        while videoPlayer.currentItem != nil, ContinuousClock.now < closeDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(videoPlayer.currentItem, "Closing the actual hosted editor must release its source")
        XCTAssertNil(window.contentView)
        XCTAssertNil(request)
    }

    @MainActor
    private func player(in view: NSView?) -> AVPlayer? {
        guard let view else { return nil }
        if let layer = view.layer as? AVPlayerLayer { return layer.player }
        return view.subviews.lazy.compactMap { self.player(in: $0) }.first
    }

    private func writeMovie(at url: URL) async throws {
        let width = 192, height = 320
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        defer { if writer.status == .writing { writer.cancelWriting() } }
        for index in 0..<60 {
            let deadline = ContinuousClock.now + .seconds(5)
            while !input.isReadyForMoreMediaData, ContinuousClock.now < deadline {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            guard input.isReadyForMoreMediaData else { throw CocoaError(.fileWriteUnknown) }
            var result: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                             [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &result)
            XCTAssertEqual(status, kCVReturnSuccess)
            let buffer = try XCTUnwrap(result)
            CVPixelBufferLockBaseAddress(buffer, [])
            let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * stride + x * 4
                    let bright = ((x / 12) + (y / 12) + index / 6).isMultiple(of: 2)
                    bytes[offset] = bright ? 200 : 40
                    bytes[offset + 1] = UInt8((index * 3) % 150 + 50)
                    bytes[offset + 2] = bright ? 240 : 40
                    bytes[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        writer.endSession(atSourceTime: CMTime(value: 2, timescale: 1))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }
}
