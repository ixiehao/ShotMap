import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ShotMapApp

final class ImageMemoryRegressionTests: XCTestCase {
    func testLargeExportPreviewDecodesOnlyTheRequestedDimensionsFromDataAndDisk() throws {
        let data = try imageData(width: 4_096, height: 2_304)
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("large-export.jpg")
        try data.write(to: url)

        let memoryPreview = try XCTUnwrap(ImageCodec.thumbnail(from: data, maximumPixelSize: 256))
        let diskPreview = try XCTUnwrap(ImageCodec.thumbnail(at: url, maximumPixelSize: 256))
        XCTAssertEqual(memoryPreview.width, 256)
        XCTAssertEqual(memoryPreview.height, 144)
        XCTAssertEqual(diskPreview.width, memoryPreview.width)
        XCTAssertEqual(diskPreview.height, memoryPreview.height)
        XCTAssertEqual(try pixels(of: diskPreview), try pixels(of: memoryPreview))
        // A displayed thumbnail owns at most the bounded decoded raster, not
        // the 36 MiB source bitmap. Do not assert process RSS: allocator and
        // codec caches make that measurement host- and test-order-dependent.
        XCTAssertLessThan(memoryPreview.bytesPerRow * memoryPreview.height, 256 * 144 * 8)
    }

    func testThumbnailAppliesOrientationAndPreservesPortraitShape() throws {
        let data = try imageData(width: 320, height: 180, orientation: 6)
        let thumbnail = try XCTUnwrap(ImageCodec.thumbnail(from: data, maximumPixelSize: 160))
        XCTAssertEqual(thumbnail.width, 90)
        XCTAssertEqual(thumbnail.height, 160)
    }

    func testWebPExportPreservesImageOrientationAndColors() throws {
        let original = try XCTUnwrap(ImageCodec.cgImage(from: imageData(width: 120, height: 80)))
        let encoded = try XCTUnwrap(ImageCodec.data(from: original, format: .webp))
        let decoded = try XCTUnwrap(ImageCodec.cgImage(from: encoded))
        let reference = try pixels(of: original)
        let actual = try pixels(of: decoded)
        for (x, y) in [(10, 10), (10, 70), (100, 10), (100, 70)] {
            let offset = (y * 120 + x) * 4
            for channel in 0..<3 {
                XCTAssertLessThan(abs(Int(actual[offset + channel]) - Int(reference[offset + channel])), 24,
                                  "WebP changed color or orientation at \(x),\(y)")
            }
        }
    }

    func testThumbnailDoesNotUpscaleAndHandlesInvalidLimitsAndInput() throws {
        let data = try imageData(width: 80, height: 40)
        let thumbnail = try XCTUnwrap(ImageCodec.thumbnail(from: data, maximumPixelSize: 1_280))
        XCTAssertEqual(thumbnail.width, 80)
        XCTAssertEqual(thumbnail.height, 40)
        for limit in [0, -1, Int.min] {
            let smallest = try XCTUnwrap(ImageCodec.thumbnail(from: data, maximumPixelSize: limit))
            XCTAssertEqual(max(smallest.width, smallest.height), 1)
        }
        for malformed in [Data(), Data("not an image".utf8), Data([0xFF, 0xD8, 0xFF])] {
            XCTAssertNil(ImageCodec.thumbnail(from: malformed))
            XCTAssertNil(ImageCodec.cgImage(from: malformed))
        }
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotMap-missing-\(UUID()).png")
        XCTAssertNil(ImageCodec.thumbnail(at: missing))
    }

    func testOptionalVideoInfoIsRenderedAndMissingMetadataDoesNotFail() async throws {
        let info = VideoExportInfo(filename: "Family.mp4", fileSize: "2.4 MB", resolution: "1920 × 1080", frameRate: "~29.97 fps", duration: "00:00:42", videoCodec: "H.264", videoBitrate: "~8.4 Mbps", audioCodec: "AAC")
        XCTAssertEqual(info.lines, ["Family.mp4  ·  00:00:42  ·  2.4 MB", "1920 × 1080  ·  ~29.97 fps  ·  H.264  ·  ~8.4 Mbps  ·  AAC"])
        let missing = await VideoExportInfo.load(url: URL(fileURLWithPath: "/tmp/shotmap-missing-video.mp4"), duration: 0)
        XCTAssertEqual(missing.lines, ["shotmap-missing-video.mp4"])
        let longFilename = String(repeating: "a", count: 180) + ".mp4"
        let longInfo = await VideoExportInfo.load(url: URL(fileURLWithPath: "/tmp/" + longFilename), duration: 42)
        XCTAssertEqual(longInfo.filename, longFilename, "Display truncation must preserve the filename suffix")
        let partial = VideoExportInfo(filename: "silent.mov", fileSize: nil, resolution: "1920 × 1080", frameRate: nil, duration: "00:00:42", videoCodec: "HEVC")
        XCTAssertEqual(partial.lines, ["silent.mov  ·  00:00:42", "1920 × 1080  ·  HEVC"])
        let image = try imageData(width: 320, height: 180)
        let frames = (0..<9).map { CapturedFrame(id: $0, time: Double($0), jpegData: image) }
        let result = StoryboardResult(frames: frames, sourceURL: URL(fileURLWithPath: "/tmp/Family.mp4"))
        let withoutInfo = try StoryboardComposer.render(result: result, settings: ExportSettings(format: .png))
        let withInfo = try StoryboardComposer.render(result: result, settings: ExportSettings(format: .png, showVideoInfo: true), videoInfo: info)
        XCTAssertNotEqual(withInfo, withoutInfo)
        XCTAssertNotNil(ImageCodec.cgImage(from: withInfo))
    }

    func testVideoInfoCodecNamesPreserveUnknownFourCCAndDistinguishAudio() {
        func fourCC(_ value: String) -> FourCharCode {
            value.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
        }
        XCTAssertEqual(VideoExportInfo.codecName(fourCC("avc1"), video: true), "H.264")
        XCTAssertEqual(VideoExportInfo.codecName(fourCC("hvc1"), video: true), "HEVC")
        XCTAssertEqual(VideoExportInfo.codecName(fourCC("aac "), video: false), "AAC")
        XCTAssertEqual(VideoExportInfo.codecName(fourCC("alac"), video: false), "ALAC")
        XCTAssertEqual(VideoExportInfo.codecName(fourCC("zzzz"), video: true), "zzzz")
        XCTAssertNil(VideoExportInfo.codecName(0, video: true))
    }

    func testEveryGridProducesDecodableExportsWithBothWatermarks() throws {
        let data = try imageData(width: 320, height: 180)
        let source = URL(fileURLWithPath: "/tmp/Family 旅行 東京.mp4")
        for side in StoryboardGrid.availableSides {
            for format in ExportFormat.allCases {
                try autoreleasepool {
                    let frames = (0..<(side * side)).map {
                        CapturedFrame(id: $0, time: Double($0) * 1.25, jpegData: data)
                    }
                    let result = StoryboardResult(frames: frames, sourceURL: source)
                    let settings = ExportSettings(
                        gridSide: side, format: format, width: 1_920,
                        showTimestamps: true, showTitleWatermark: true
                    )
                    let output = try StoryboardComposer.render(result: result, settings: settings)
                    let image = try XCTUnwrap(ImageCodec.cgImage(from: output))
                    let expected = StoryboardComposer.canvasSize(result: result, settings: settings)
                    XCTAssertEqual(image.width, Int(expected.width))
                    XCTAssertEqual(image.height, Int(expected.height))
                    XCTAssertEqual(image.width, 1_920)
                    if format == .png {
                        XCTAssertEqual(output.prefix(8), Data([137, 80, 78, 71, 13, 10, 26, 10]))
                    } else if format == .jpeg {
                        XCTAssertEqual(output.prefix(2), Data([0xFF, 0xD8]))
                    } else {
                        XCTAssertEqual(output.prefix(4), Data("RIFF".utf8))
                        XCTAssertEqual(output[8..<12], Data("WEBP".utf8))
                        XCTAssertNotNil(ImageCodec.thumbnail(from: output, maximumPixelSize: 256))
                    }
                }
            }
        }
    }

    func testCancelledCompositionStopsBeforeAllocatingAnExport() async {
        let task = Task.detached { () throws -> Data in
            withUnsafeCurrentTask { $0?.cancel() }
            return try StoryboardComposer.render(
                result: StoryboardResult(frames: [], sourceURL: URL(fileURLWithPath: "/tmp/cancelled.mp4")),
                settings: ExportSettings(gridSide: 8, layoutAspect: .portrait, width: 12_000)
            )
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled composition must not produce a large obsolete export")
        } catch is CancellationError {
            // Expected: the cancellation check precedes the canvas allocation.
        } catch {
            XCTFail("Expected cancellation, got \(error)")
        }
    }

    func testBundledWatermarkFontCoversEnglishChineseAndJapaneseFilenames() {
        let font = WatermarkTypography.titleFont(size: 36)
        XCTAssertTrue(WatermarkTypography.isBundledFontAvailable)
        for title in ["Family trip 2026", "旅行与家庭回忆", "東京の旅行と思い出"] {
            let characters = Array(title.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            XCTAssertTrue(CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count), title)
            XCTAssertFalse(glyphs.contains(0), "Bundled font lost filename coverage: \(title)")
        }
    }

    private func imageData(width: Int, height: Int, orientation: Int = 1) throws -> Data {
        try autoreleasepool {
            let context = try XCTUnwrap(CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(CGColor(red: 0.15, green: 0.4, blue: 0.7, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(red: 0.85, green: 0.3, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width / 3, height: height / 2))
            let image = try XCTUnwrap(context.makeImage())
            let data = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, [
                kCGImageDestinationLossyCompressionQuality: 0.9,
                kCGImagePropertyOrientation: orientation
            ] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            return data as Data
        }
    }

    private func pixels(of image: CGImage) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try XCTUnwrap(context.data), count: context.bytesPerRow * context.height)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotMap-image-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
