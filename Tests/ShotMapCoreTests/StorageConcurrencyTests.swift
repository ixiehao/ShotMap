import CoreGraphics
import Foundation
import XCTest
@testable import ShotMapApp

final class StorageConcurrencyTests: XCTestCase {
    func testCancellingOneWaiterPreservesPauseForOtherWorkers() async throws {
        let control = BatchRunControl()
        await control.requestPause()
        let first = Task { await control.waitUntilResumed() }
        let second = Task { await control.waitUntilResumed() }
        defer { first.cancel(); second.cancel() }
        let deadline = ContinuousClock.now + .seconds(2)
        while await control.waitingWorkerCount < 2, ContinuousClock.now < deadline {
            await Task.yield()
        }
        let registered = await control.waitingWorkerCount
        XCTAssertEqual(registered, 2)
        first.cancel()
        await first.value
        let stillPaused = await control.isPauseRequested()
        let remaining = await control.waitingWorkerCount
        XCTAssertTrue(stillPaused, "Cancellation is local to a worker, not a global Resume command")
        XCTAssertEqual(remaining, 1)
        await control.resume()
        await second.value
        let drained = await control.waitingWorkerCount
        XCTAssertEqual(drained, 0)
    }

    func testCancelledSaveDoesNotWriteToDisk() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("cancelled.jpg")
        let writer = StoryboardOutputWriter()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await writer.save(Data([1, 2, 3]), to: destination)
        }
        do {
            try await task.value
            XCTFail("A queued cancelled save must stop before modifying disk")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testInvalidPreparedImageDoesNotCreateAnExportOrConsumeItsFilename() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = StoryboardOutputWriter()
        let result = StoryboardResult(frames: [], sourceURL: directory.appendingPathComponent("video.mp4"))
        let store = PreviewImageStore()
        do {
            _ = try await writer.prepare(data: Data([1, 2, 3]), result: result,
                                         settings: ExportSettings(format: .jpeg), jobIndex: 0,
                                         jobCount: 1, previewStore: store)
            XCTFail("Malformed export should fail before a file is written")
        } catch StoryboardError.noExportData {
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
        }
        let output = try await writer.prepare(data: imageData(), result: result,
                                              settings: ExportSettings(format: .jpeg), jobIndex: 0,
                                              jobCount: 1, previewStore: store)
        XCTAssertEqual(output.preview.savedURL?.lastPathComponent, "video-shot-001.jpg")
    }

    func testSavedAndUnsavedPresentationsPreserveSaveAsDataAndThumbnailSize() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try imageData(width: 2_560, height: 1_440)
        let source = directory.appendingPathComponent("video.mp4")
        let result = StoryboardResult(frames: [], sourceURL: source)
        let store = PreviewImageStore()
        for canSave in [true, false] {
            let writer = StoryboardOutputWriter { data, url in
                if !canSave { throw CocoaError(.fileWriteNoPermission) }
                try data.write(to: url, options: .atomic)
            }
            let output = try await writer.prepare(data: data, result: result,
                                                  settings: ExportSettings(format: .jpeg), jobIndex: 0,
                                                  jobCount: 1, previewStore: store)
            let presentation = try output.preview.loadPresentation()
            XCTAssertEqual(presentation.image.width, 1_280)
            XCTAssertEqual(presentation.image.height, 720)
            XCTAssertEqual(presentation.pendingData, canSave ? nil : data)
            XCTAssertNil(output.preview.fallbackData, "Unexported history should live in temporary storage")
        }
    }

    func testExtremePastedTimestampsAndFiniteMetadataDoNotOverflow() throws {
        let pasted = try XCTUnwrap(TimestampFormatter.editableSeconds(from: "\(Int.max):00:00"))
        XCTAssertEqual(TimestampFormatter.editableString(for: pasted), "2562047788015:12:55.807")
        XCTAssertEqual(TimestampFormatter.editableString(for: Double.greatestFiniteMagnitude), "2562047788015:12:55.807")
        XCTAssertEqual(TimestampFormatter.string(for: Double.greatestFiniteMagnitude), "2562047788015215:30:07")
        XCTAssertEqual(TimestampFormatter.editableString(for: -Double.greatestFiniteMagnitude), "00:00:00.000")
        XCTAssertEqual(TimestampFormatter.editableString(for: 3_661.125), "01:01:01.125")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ShotMap-storage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func imageData(width: Int = 32, height: Int = 18) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(ImageCodec.jpegData(from: XCTUnwrap(context.makeImage()), compressionQuality: 0.8))
    }
}
