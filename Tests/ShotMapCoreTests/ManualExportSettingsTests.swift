import CoreGraphics
import XCTest
@testable import ShotMapApp

final class ManualExportSettingsTests: XCTestCase {
    @MainActor
    func testManualSaveRendersTheLatestBackgroundLabelsSizeAspectAndFormat() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (model, source, frames, id) = try await fixture(directory: directory)
        model.layoutAspect = .landscape
        model.width = 2560
        model.background = .navy
        model.format = .png
        model.showTimestamps = false
        model.showTitleWatermark = true
        model.language = .japanese

        model.applyManuallySelectedFrames(frames, targetPreviewID: id, sourceURL: source, duration: 20)
        XCTAssertTrue(model.isApplyingFrameAdjustments)
        try await waitForSave(model)

        let edited = try XCTUnwrap(model.completedPreviews.first)
        XCTAssertEqual(edited.id, id)
        XCTAssertEqual(edited.settings.layoutAspect, .landscape)
        XCTAssertEqual(edited.settings.background, .navy)
        XCTAssertFalse(edited.settings.showTimestamps)
        XCTAssertTrue(edited.settings.showTitleWatermark)
        XCTAssertEqual(edited.settings.language, .japanese)
        XCTAssertEqual(edited.savedURL?.pathExtension, "png")
        let data = try edited.loadData()
        XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let image = try XCTUnwrap(ImageCodec.cgImage(from: data))
        XCTAssertEqual(image.width, 2560)
        XCTAssertLessThan(image.height, image.width)
        let corner = try pixel(image, at: CGPoint(x: 0, y: 0))
        let navy = StoryboardBackground.navy.rgb
        // Compare in the sampling context's colour space. CGColor's generic
        // RGB values are colour-managed when painted into a DeviceRGB bitmap.
        let expected = try XCTUnwrap(CGColor(red: navy.red, green: navy.green, blue: navy.blue, alpha: 1)
            .converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)?.components)
        XCTAssertEqual(Double(corner[0]), expected[0] * 255, accuracy: 2)
        XCTAssertEqual(Double(corner[1]), expected[1] * 255, accuracy: 2)
        XCTAssertEqual(Double(corner[2]), expected[2] * 255, accuracy: 2)
    }

    @MainActor
    func testSaveSnapshotSurvivesSettingsChangesDuringAsynchronousRefinement() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (model, source, frames, id) = try await fixture(directory: directory)
        model.width = 2560
        model.format = .jpeg
        model.background = .mist
        model.showTimestamps = false
        let settingsAtSave = model.currentExportSettings
        // Refinement is asynchronous. Changes made after clicking Save belong
        // to the next operation, including changes to the required frame count.
        model.gridSide = 4
        model.width = 3840
        model.format = .png
        model.background = .cinema
        model.applyManuallySelectedFrames(frames, targetPreviewID: id, sourceURL: source, duration: 20, settings: settingsAtSave)
        XCTAssertTrue(model.isApplyingFrameAdjustments)
        try await waitForSave(model)

        let edited = try XCTUnwrap(model.completedPreviews.first)
        XCTAssertEqual(edited.frameCount, 9)
        XCTAssertEqual(edited.settings.gridSide, 3)
        XCTAssertEqual(edited.settings.width, 2560)
        XCTAssertEqual(edited.settings.background, .mist)
        XCTAssertFalse(edited.settings.showTimestamps)
        XCTAssertEqual(edited.savedURL?.pathExtension, "jpg")
        let data = try edited.loadData()
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
        XCTAssertEqual(try XCTUnwrap(ImageCodec.cgImage(from: data)).width, 2560)
        XCTAssertEqual(model.gridSide, 4)
        XCTAssertEqual(model.width, 3840)
        XCTAssertEqual(model.format, .png)
    }

    @MainActor
    func testOldGridFrameCountCannotSilentlyDuplicateFramesIntoNewGrid() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (model, source, frames, id) = try await fixture(directory: directory)
        let original = try XCTUnwrap(model.completedPreviews.first)
        model.gridSide = 4
        model.applyManuallySelectedFrames(frames, targetPreviewID: id, sourceURL: source, duration: 20)
        XCTAssertFalse(model.isApplyingFrameAdjustments)
        XCTAssertEqual(model.completedPreviews.first?.savedURL, original.savedURL)
        XCTAssertEqual(model.completedPreviews.first?.frameCount, 9)
    }

    @MainActor
    func testEditingEarlierHistoryUsesCurrentSettingsWithoutReplacingTheVisibleVideo() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (model, firstSource, frames, firstID) = try await fixture(directory: directory)
        let secondSource = directory.appendingPathComponent("second.mp4")
        _ = await model.completeJob(
            data: frames[0].jpegData,
            result: StoryboardResult(frames: frames, sourceURL: secondSource, duration: 20),
            settings: ExportSettings(format: .jpeg), index: 0, total: 1
        )
        let second = try XCTUnwrap(model.completedPreviews.last)
        let visible = model.previewImage
        model.background = .navy
        model.format = .png
        model.width = 2560

        model.applyManuallySelectedFrames(frames, targetPreviewID: firstID, sourceURL: firstSource, duration: 20)
        XCTAssertTrue(model.isApplyingFrameAdjustments)
        try await waitForSave(model)

        XCTAssertEqual(model.selectedPreviewIndex, 1)
        XCTAssertTrue(model.previewImage === visible)
        XCTAssertEqual(model.lastSavedURL, second.savedURL)
        XCTAssertEqual(model.completedPreviews[1].savedURL, second.savedURL)
        let edited = model.completedPreviews[0]
        XCTAssertEqual(edited.id, firstID)
        XCTAssertEqual(edited.sourceURL, firstSource)
        XCTAssertEqual(edited.settings.background, .navy)
        XCTAssertEqual(edited.settings.width, 2560)
        XCTAssertEqual(edited.savedURL?.pathExtension, "png")
    }

    func testEnlargingCandidatePoolPreservesSelectedMomentsAndManualOrigin() {
        let chosen = CapturedFrame(id: -10001, time: 5, jpegData: Data([1]))
        let manual = CapturedFrame(id: 1_000_001, time: 12, jpegData: Data([2]))
        let new = [
            CapturedFrame(id: -10001, time: 99, jpegData: Data([9])),
            CapturedFrame(id: -20001, time: 5.01, jpegData: Data([9])),
            CapturedFrame(id: -20002, time: 12.01, jpegData: Data([9])),
            CapturedFrame(id: -20003, time: 18, jpegData: Data([3]))
        ]
        let expanded = ManualCandidatePool.appending(new, to: [chosen], excluding: [manual])
        XCTAssertEqual(expanded.map(\.id), [chosen.id, -20003])
        XCTAssertEqual(expanded[0].time, chosen.time)
        XCTAssertEqual(expanded[0].jpegData, chosen.jpegData)
        XCTAssertFalse(expanded.contains { $0.id == manual.id })
        let repeated = ManualCandidatePool.appending(new, to: expanded, excluding: [manual])
        XCTAssertEqual(repeated.map(\.id), expanded.map(\.id))
    }

    @MainActor
    private func fixture(directory: URL) async throws -> (StoryboardViewModel, URL, [CapturedFrame], UUID) {
        let model = StoryboardViewModel()
        let source = directory.appendingPathComponent("sample.mp4")
        model.addVideos([source])
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 18, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
        let data = try XCTUnwrap(ImageCodec.jpegData(from: XCTUnwrap(context.makeImage()), compressionQuality: 0.8))
        let frames = (0..<9).map { CapturedFrame(id: $0, time: Double($0), jpegData: data) }
        let originalSettings = ExportSettings(layoutAspect: .portrait, format: .jpeg, width: 1920, background: .ivory,
                                               showTimestamps: true, showTitleWatermark: false)
        _ = await model.completeJob(data: data, result: StoryboardResult(frames: frames, sourceURL: source, duration: 20),
                                    settings: originalSettings, index: 0, total: 1)
        return (model, source, frames, try XCTUnwrap(model.completedPreviews.first?.id))
    }

    @MainActor
    private func waitForSave(_ model: StoryboardViewModel) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while model.isApplyingFrameAdjustments, ContinuousClock.now < deadline {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertFalse(model.isApplyingFrameAdjustments)
        XCTAssertFalse(model.showError, model.errorMessage)
    }

    private func pixel(_ image: CGImage, at point: CGPoint) throws -> [UInt8] {
        let crop = try XCTUnwrap(image.cropping(to: CGRect(origin: point, size: CGSize(width: 1, height: 1))))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotMap-settings-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
