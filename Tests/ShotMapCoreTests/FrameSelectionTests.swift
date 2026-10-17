import AppKit
import AVFoundation
import CoreText
import CoreVideo
import XCTest
@testable import ShotMapApp

final class FrameSelectionTests: XCTestCase {
    func testProgressivePreviewSlotsKeepGridOrderWhenFramesAreReplaced() {
        var slots = ProgressivePreviewSlots<Int>()
        slots.reset(total: 4)

        XCTAssertEqual(slots.slots.count, 4)
        XCTAssertEqual(slots.filledCount, 0)
        XCTAssertTrue(slots.replace(30, at: 2, total: 4))
        XCTAssertTrue(slots.replace(10, at: 0, total: 4))
        XCTAssertEqual(slots.slots.map { $0 ?? -1 }, [10, -1, 30, -1])

        // A refined capture replaces the broad-scan fallback in place rather
        // than moving later cards forward.
        XCTAssertTrue(slots.replace(31, at: 2, total: 4))
        XCTAssertEqual(slots.slots.map { $0 ?? -1 }, [10, -1, 31, -1])
        XCTAssertEqual(slots.filledCount, 2)
        XCTAssertFalse(slots.replace(40, at: 4, total: 4))
        XCTAssertEqual(slots.slots.map { $0 ?? -1 }, [10, -1, 31, -1])
    }

    @MainActor
    func testBatchQueueAcceptsMultipleVideosAndRemovesDuplicates() {
        let model = StoryboardViewModel()
        let first = URL(fileURLWithPath: "/tmp/first.mp4")
        let second = URL(fileURLWithPath: "/tmp/second.mp4")
        model.addVideos([first, second, first])
        XCTAssertEqual(model.videoJobs.map(\.url), [first, second])
        XCTAssertFalse(model.showError)
    }

    @MainActor
    func testQueueReportsOnlyActuallyUnsupportedFiles() {
        let model = StoryboardViewModel()
        model.addVideos([
            URL(fileURLWithPath: "/tmp/first.mp4"),
            URL(fileURLWithPath: "/tmp/readme.txt")
        ])

        XCTAssertEqual(model.videoJobs.map(\.url), [URL(fileURLWithPath: "/tmp/first.mp4")])
        XCTAssertTrue(model.showError)
    }

    @MainActor
    func testFailedJobsAreTrackedForTargetedRetry() {
        let model = StoryboardViewModel()
        model.addVideos([
            URL(fileURLWithPath: "/tmp/first.mp4"),
            URL(fileURLWithPath: "/tmp/second.mp4")
        ])
        model.markJobFailed(index: 1, message: "Unsupported codec")

        XCTAssertEqual(model.failedJobCount, 1)
        XCTAssertEqual(model.failedJobs.first?.url.lastPathComponent, "second.mp4")
        XCTAssertEqual(model.failedJobs.first?.state.failureMessage, "Unsupported codec")
    }

    @MainActor
    func testCodecFailuresAreExcludedFromRetry() {
        let model = StoryboardViewModel()
        model.addVideos([
            URL(fileURLWithPath: "/tmp/legacy.rmvb"),
            URL(fileURLWithPath: "/tmp/temporary.mov")
        ])
        model.markJobFailed(index: 0, failure: .needsTranscoding("Convert this video"))
        model.markJobFailed(index: 1, message: "Temporary read error")

        XCTAssertEqual(model.failedJobCount, 2)
        XCTAssertEqual(model.transcodingJobs.map(\.url.lastPathComponent), ["legacy.rmvb"])
        XCTAssertEqual(model.retryableFailedJobs.map(\.url.lastPathComponent), ["temporary.mov"])
    }

    func testBatchRunControlWaitsOnlyWhenPauseWasRequested() async {
        let control = BatchRunControl()
        await control.waitUntilResumed()

        await control.requestPause()
        let resumed = Task { () -> Bool in
            await control.waitUntilResumed()
            return true
        }
        await Task.yield()
        await control.resume()
        let didResume = await resumed.value
        XCTAssertTrue(didResume)
    }

    func testExportFilenameUsesShotSequence() {
        XCTAssertEqual(
            ExportDestination.filename(baseName: "concert", format: .png, sequence: 1),
            "concert-shot-001.png"
        )
        XCTAssertEqual(
            ExportDestination.filename(baseName: "concert", format: .jpeg, sequence: 42),
            "concert-shot-042.jpg"
        )
    }

    func testTimestampFormatting() {
        XCTAssertEqual(TimestampFormatter.string(for: 0), "00:00:00")
        XCTAssertEqual(TimestampFormatter.string(for: 83.9), "00:01:23")
        XCTAssertEqual(TimestampFormatter.string(for: 3_723), "01:02:03")
        XCTAssertEqual(TimestampFormatter.string(for: .nan), "00:00:00")
        XCTAssertEqual(TimestampFormatter.string(for: .infinity), "00:00:00")
    }

    func testEditableTimestampRoundTripsMillisecondsAndAcceptsShortForms() throws {
        XCTAssertEqual(TimestampFormatter.editableString(for: 3_661.234), "01:01:01.234")
        XCTAssertEqual(try XCTUnwrap(TimestampFormatter.editableSeconds(from: "01:01:01.234")), 3_661.234, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(TimestampFormatter.editableSeconds(from: "01:02.5")), 62.5, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(TimestampFormatter.editableSeconds(from: "1.250")), 1.25, accuracy: 0.000_1)
        XCTAssertNil(TimestampFormatter.editableSeconds(from: "00:60:00"))
        XCTAssertNil(TimestampFormatter.editableSeconds(from: "00:00:60"))
        XCTAssertTrue(try XCTUnwrap(TimestampFormatter.editableSeconds(from: "\(Int.max):59:59")).isFinite)
    }

    func testEveryInAppLanguageHasAllRequiredTranslations() {
        for language in AppLanguage.allCases {
            for key in AppLanguage.requiredLocalizationKeys {
                XCTAssertNotEqual(language.text(key), key, "\(language.rawValue) is missing \(key)")
            }
            XCTAssertFalse(language.text("status.processing", 1, 2, "sample.mp4", 3, 9).contains("%"))
            XCTAssertFalse(language.text("button.generate.batch", 2).contains("%"))
            XCTAssertFalse(language.text("button.saveas", "PNG").contains("%"))
        }

        // A fallback to Bundle.module could look like a valid translation on
        // an English CI host. Assert distinctive localized text explicitly.
        XCTAssertEqual(AppLanguage.chinese.text("status.batchCompleted", 2), "批量处理完成：已保存 2 部。")
        XCTAssertEqual(AppLanguage.japanese.text("status.batchCompleted", 2), "バッチ処理完了：2 本を保存しました。")
    }

    @MainActor
    func testCompletedBatchStatusUpdatesWhenLanguageChanges() {
        let model = StoryboardViewModel()
        model.language = .chinese
        model.finishBatch()
        XCTAssertEqual(model.previewStatus, "批量处理完成：已保存 0 部。")

        model.language = .english
        XCTAssertEqual(model.previewStatus, "Batch complete: 0 saved.")

        model.language = .japanese
        XCTAssertEqual(model.previewStatus, "バッチ処理完了：0 本を保存しました。")
    }

    func testReleaseVersionComparesNumericTagsAndRejectsInvalidTags() {
        XCTAssertLessThan(tryVersion("v0.2.4"), tryVersion("v0.2.10"))
        XCTAssertLessThan(tryVersion("1.0.0"), tryVersion("v1.0.1"))
        XCTAssertNil(ReleaseVersion(tag: "v1.2"))
        XCTAssertNil(ReleaseVersion(tag: "preview"))
    }

    func testStoryboardErrorsUseTheRequestedLanguage() {
        let errors: [StoryboardError] = [.unreadableVideo, .unsupportedCodec, .noUsableFrames, .noExportData]
        for language in AppLanguage.allCases {
            for error in errors {
                XCTAssertFalse(error.message(in: language).isEmpty)
                XCTAssertFalse(error.message(in: language).hasPrefix("error."))
            }
        }
    }

    func testAspectLabelsAreTranslatedForEveryLanguage() {
        for language in AppLanguage.allCases {
            for aspect in StoryboardAspect.allCases {
                XCTAssertFalse(aspect.label(in: language).isEmpty)
            }
        }
    }

    func testTitleWatermarkUsesTheSourceFilenameWhenEnabled() {
        var settings = ExportSettings()
        let sourceURL = URL(fileURLWithPath: "/tmp/  夏日片段  .mp4")
        XCTAssertNil(settings.titleWatermark(for: sourceURL))

        settings.showTitleWatermark = true
        XCTAssertEqual(settings.titleWatermark(for: sourceURL), "夏日片段")
    }

    func testWatermarkTitleUsesBundledOFLBoldFont() {
        let font = WatermarkTypography.titleFont(size: 42)
        XCTAssertTrue(WatermarkTypography.isBundledFontAvailable)
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, WatermarkTypography.postScriptName)
    }

    func testComposerRendersAVisibleTitleWatermark() throws {
        let sourceImage = NSImage(size: NSSize(width: 320, height: 180))
        sourceImage.lockFocus()
        NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.58, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 320, height: 180)).fill()
        sourceImage.unlockFocus()
        let imageData = try XCTUnwrap(sourceImage.tiffRepresentation)
        let frames = (0..<9).map { index in
            CapturedFrame(id: index, time: Double(index), jpegData: imageData)
        }
        let result = StoryboardResult(frames: frames, sourceURL: URL(fileURLWithPath: "/tmp/sample.mp4"))
        let baseSettings = ExportSettings(gridSide: 3, format: .png, width: 1920)
        let plainData = try StoryboardComposer.render(result: result, settings: baseSettings)
        let titledData = try StoryboardComposer.render(
            result: result,
            settings: ExportSettings(gridSide: 3, format: .png, width: 1920, showTitleWatermark: true)
        )
        XCTAssertNotEqual(plainData, titledData)
    }

    func testComposerUsesTheSelectedStoryboardBackground() throws {
        let sourceImage = NSImage(size: NSSize(width: 320, height: 180))
        sourceImage.lockFocus()
        NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.58, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 320, height: 180)).fill()
        sourceImage.unlockFocus()
        let imageData = try XCTUnwrap(sourceImage.tiffRepresentation)
        let frames = (0..<9).map { CapturedFrame(id: $0, time: Double($0), jpegData: imageData) }
        let result = StoryboardResult(frames: frames, sourceURL: URL(fileURLWithPath: "/tmp/sample.mp4"))

        var cinema = ExportSettings(gridSide: 3, format: .png, width: 1_920)
        cinema.background = .cinema
        var ivory = cinema
        ivory.background = .ivory

        let cinemaData = try StoryboardComposer.render(result: result, settings: cinema)
        let ivoryData = try StoryboardComposer.render(result: result, settings: ivory)
        XCTAssertNotEqual(cinemaData, ivoryData)
        XCTAssertNotEqual(StoryboardBackground.cinema.rgb.red, StoryboardBackground.ivory.rgb.red)
    }

    func testImageCodecJPEGRoundTripPreservesDimensions() throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 37,
                height: 19,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.12, green: 0.46, blue: 0.78, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 37, height: 19))
        let source = try XCTUnwrap(context.makeImage())

        let encoded = try XCTUnwrap(ImageCodec.jpegData(from: source, compressionQuality: 0.88))
        let decoded = try XCTUnwrap(ImageCodec.cgImage(from: encoded))

        XCTAssertEqual(encoded.prefix(2), Data([0xFF, 0xD8]))
        XCTAssertEqual(decoded.width, source.width)
        XCTAssertEqual(decoded.height, source.height)
    }

    func testSyntheticH264VideoCompletesTheFullStoryboardPipeline() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotMapTests-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = temporaryDirectory.appendingPathComponent("synthetic.mov")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try await makeSyntheticVideo(at: sourceURL)
        let result = try await VideoStoryboardAnalyzer().analyze(
            videoURL: sourceURL,
            gridSide: 3,
            outputWidth: 1_920,
            progress: { _ in },
            onPreviewFrame: { _, _, _ in }
        )

        XCTAssertEqual(result.frames.count, 9)
        XCTAssertTrue(result.duration.isFinite)
        XCTAssertGreaterThan(result.duration, 0)
        XCTAssertEqual(result.frames.map(\.time), result.frames.map(\.time).sorted())

        let outputData = try StoryboardComposer.render(
            result: result,
            settings: ExportSettings(gridSide: 3, format: .jpeg, width: 1_920, showTimestamps: true)
        )
        let image = try XCTUnwrap(ImageCodec.cgImage(from: outputData))
        XCTAssertEqual(image.width, 1_920)
        XCTAssertGreaterThan(image.height, 0)

        let manualCandidates = try await ManualFrameExtractor.captureCandidates(
            from: sourceURL,
            gridSide: 3,
            outputWidth: 1_920,
            count: 18,
            batch: 0
        )
        XCTAssertEqual(manualCandidates.count, 18)
        XCTAssertEqual(manualCandidates.map(\.time), manualCandidates.map(\.time).sorted())
        XCTAssertEqual(Set(manualCandidates.map(\.id)).count, 18)
        XCTAssertEqual(ManualFrameSelector.selectIDs(from: manualCandidates, count: 9).count, 9)

        let selectedManualCandidates = Array(manualCandidates.prefix(9))
        let refinedManualCandidates = try await ManualFrameExtractor.captureSharpestFrames(
            from: AVURLAsset(url: sourceURL),
            duration: result.duration,
            frames: selectedManualCandidates,
            maximumEdge: 640,
            compressionQuality: 0.92
        )
        XCTAssertEqual(refinedManualCandidates.count, selectedManualCandidates.count)
        XCTAssertEqual(
            Set(refinedManualCandidates.map(\.id)),
            Set(selectedManualCandidates.map(\.id))
        )
        XCTAssertTrue(refinedManualCandidates.allSatisfy { !$0.jpegData.isEmpty })

        let presentationManualCandidates = try await ManualFrameExtractor.capturePresentationFrames(
            from: AVURLAsset(url: sourceURL),
            frames: selectedManualCandidates,
            maximumEdge: 640,
            compressionQuality: 0.92
        )
        XCTAssertEqual(presentationManualCandidates.count, selectedManualCandidates.count)
        XCTAssertEqual(
            Set(presentationManualCandidates.map(\.id)),
            Set(selectedManualCandidates.map(\.id))
        )

        let manuallyPositionedFrame = try await ManualFrameExtractor.captureFrame(
            from: sourceURL,
            at: 1.25,
            identifier: 1_000_001
        )
        XCTAssertEqual(manuallyPositionedFrame.id, 1_000_001)
        XCTAssertEqual(manuallyPositionedFrame.time, 1.25, accuracy: 0.12)
        XCTAssertFalse(manuallyPositionedFrame.jpegData.isEmpty)
        XCTAssertGreaterThan(manuallyPositionedFrame.aspectRatio, 1)
    }

    func testSharpnessComparisonUsesThreeFramesOnBothSidesOfTheTarget() {
        let times = ManualFrameExtractor.sharpnessComparisonTimes(
            around: 5,
            duration: 12,
            frameRate: 30
        )

        XCTAssertEqual(times.count, 7)
        XCTAssertEqual(try XCTUnwrap(times.first), 5 - (3.0 / 30.0), accuracy: 0.000_001)
        XCTAssertEqual(times[3], 5, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(times.last), 5 + (3.0 / 30.0), accuracy: 0.000_001)

        let atStart = ManualFrameExtractor.sharpnessComparisonTimes(
            around: 0,
            duration: 12,
            frameRate: 30
        )
        XCTAssertEqual(try XCTUnwrap(atStart.first), 0, accuracy: 0.000_001)
        XCTAssertLessThan(atStart.count, 7)
        XCTAssertEqual(Set(atStart.map { Int(($0 * 30).rounded()) }).count, atStart.count)
    }

    func testManualCandidateProbeUsesACompactExactNeighborhood() {
        let times = ManualFrameExtractor.candidateComparisonTimes(
            around: 5,
            duration: 12,
            frameRate: 30
        )

        XCTAssertEqual(times.count, 3)
        XCTAssertEqual(try XCTUnwrap(times.first), 5 - 0.45, accuracy: 0.000_001)
        XCTAssertEqual(times[1], 5, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(times.last), 5 + 0.45, accuracy: 0.000_001)

        let atStart = ManualFrameExtractor.candidateComparisonTimes(
            around: 0,
            duration: 12,
            frameRate: 30
        )
        XCTAssertEqual(atStart.count, 2)
        XCTAssertEqual(try XCTUnwrap(atStart.first), 0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(atStart.last), 0.45, accuracy: 0.000_001)
    }

    func testCentreFirstRecoveryKeepsActionAndDissolveNeighbourhoodsAvailable() {
        let candidateRecovery = ManualFrameExtractor.candidateRecoveryTimes(
            around: 5,
            duration: 12,
            frameRate: 30
        )
        XCTAssertEqual(candidateRecovery.count, 2)
        XCTAssertEqual(candidateRecovery[0], 4.55, accuracy: 0.000_001)
        XCTAssertEqual(candidateRecovery[1], 5.45, accuracy: 0.000_001)

        let sharpnessRecovery = ManualFrameExtractor.sharpnessRecoveryTimes(
            around: 5,
            duration: 12,
            frameRate: 30
        )
        XCTAssertEqual(sharpnessRecovery.count, 6)
        XCTAssertFalse(sharpnessRecovery.contains(where: { abs($0 - 5) < 0.000_001 }))
        XCTAssertEqual(try XCTUnwrap(sharpnessRecovery.first), 5 - (3.0 / 30.0), accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(sharpnessRecovery.last), 5 + (3.0 / 30.0), accuracy: 0.000_001)

        let likelyActionBlur = PixelMetrics(
            histogram: Array(repeating: 1.0 / 16.0, count: 16),
            luminance: 0.46,
            blackRatio: 0.02,
            brightRatio: 0.03,
            dominantToneRatio: 0.10,
            sharpness: 0.07,
            focusedEdgeRatio: 0.21,
            contrast: 0.10,
            fingerprint: 0
        )
        XCTAssertTrue(ManualFrameExtractor.candidateNeedsRecovery(likelyActionBlur))

        let crispStill = PixelMetrics(
            histogram: Array(repeating: 1.0 / 16.0, count: 16),
            luminance: 0.46,
            blackRatio: 0.02,
            brightRatio: 0.03,
            dominantToneRatio: 0.10,
            sharpness: 0.22,
            focusedEdgeRatio: 0.72,
            contrast: 0.27,
            fingerprint: 1
        )
        XCTAssertFalse(ManualFrameExtractor.candidateNeedsRecovery(crispStill))
    }

    func testCentreFirstDecodeDiagnosticsProtectTheBatchBudget() {
        let gallery = ManualFrameExtractor.candidateSamplingDiagnostics(
            itemCount: 72,
            primaryRequests: 72,
            localRecoveryRequests: 0,
            wideRecoveryRequests: 0
        )
        XCTAssertEqual(gallery.fixedBaselineRequestCount, 216)
        XCTAssertEqual(gallery.totalRequests, 72)
        XCTAssertEqual(gallery.avoidedRequests, 144)
        XCTAssertEqual(gallery.avoidedRequestRatio, 2.0 / 3.0, accuracy: 0.000_001)

        let selected = ManualFrameExtractor.selectedRefinementDiagnostics(
            itemCount: 36,
            primaryRequests: 36,
            localRecoveryRequests: 0,
            finalRequests: 36
        )
        XCTAssertEqual(selected.fixedBaselineRequestCount, 288)
        XCTAssertEqual(selected.totalRequests, 72)
        XCTAssertEqual(selected.avoidedRequestRatio, 0.75, accuracy: 0.000_001)

        // When every selected card is blurred, the full former recovery budget
        // remains available rather than silently dropping action moments.
        let allActionRecovery = ManualFrameExtractor.selectedRefinementDiagnostics(
            itemCount: 36,
            primaryRequests: 36,
            localRecoveryRequests: 216,
            finalRequests: 36
        )
        XCTAssertEqual(allActionRecovery.totalRequests, allActionRecovery.fixedBaselineRequestCount)
        XCTAssertEqual(allActionRecovery.avoidedRequests, 0)
    }

    func testLargeGridsUseEnoughSpareCandidatesWithoutTheFormerFiftyPercentOverscan() {
        let analyzer = VideoStoryboardAnalyzer()

        XCTAssertEqual(analyzer.analysisSampleCount(for: 9), 48)
        XCTAssertEqual(analyzer.analysisSampleCount(for: 36), 48)
        XCTAssertEqual(analyzer.analysisSampleCount(for: 49), 62)
        XCTAssertEqual(analyzer.analysisSampleCount(for: 64), 80)
    }

    func testSharpnessComparisonCapsOnlyItsAnalysisDecodeResolution() {
        // The winning frame must still be decoded at the requested output edge;
        // this cap applies solely to the seven lightweight scoring decodes.
        XCTAssertEqual(ManualFrameExtractor.sharpnessAnalysisMaximumEdge(for: 1_600), 480)
        XCTAssertEqual(ManualFrameExtractor.sharpnessAnalysisMaximumEdge(for: 480), 480)
        XCTAssertEqual(ManualFrameExtractor.sharpnessAnalysisMaximumEdge(for: 320), 320)
        XCTAssertEqual(ManualFrameExtractor.sharpnessAnalysisMaximumEdge(for: 0), 1)
    }

    func testStoryboardAspectUsesTheSourceForPortraitAndSupportsCommonOverrides() {
        let portraitFrame = CapturedFrame(
            id: 0,
            time: 0,
            jpegData: Data(),
            aspectRatio: 9.0 / 16.0
        )
        let result = StoryboardResult(
            frames: [portraitFrame],
            sourceURL: URL(fileURLWithPath: "/tmp/vertical.mp4")
        )

        var settings = ExportSettings(gridSide: 3, width: 1920)
        let automaticSize = StoryboardComposer.canvasSize(result: result, settings: settings)
        XCTAssertGreaterThan(automaticSize.height, automaticSize.width)

        settings.layoutAspect = .square
        let squareSize = StoryboardComposer.canvasSize(result: result, settings: settings)
        XCTAssertEqual(squareSize.height, squareSize.width, accuracy: 4)

        settings.layoutAspect = .ultraWide
        let ultraWideSize = StoryboardComposer.canvasSize(result: result, settings: settings)
        XCTAssertGreaterThan(ultraWideSize.width, ultraWideSize.height * 2)
    }

    func testExtremePortraitExportStaysWithinTheBitmapMemoryBudget() {
        let portraitFrame = CapturedFrame(
            id: 0,
            time: 0,
            jpegData: Data(),
            aspectRatio: 9.0 / 16.0
        )
        let result = StoryboardResult(
            frames: [portraitFrame],
            sourceURL: URL(fileURLWithPath: "/tmp/vertical.mp4")
        )
        let settings = ExportSettings(gridSide: 8, width: 12_000)
        let canvas = StoryboardComposer.canvasSize(result: result, settings: settings)
        let pixels = canvas.width * canvas.height

        XCTAssertLessThanOrEqual(max(canvas.width, canvas.height), 16_384)
        XCTAssertLessThanOrEqual(pixels, 64_000_000)
    }

    func testEveryGridWidthAndAspectStaysWithinTheBitmapBudget() {
        let aspectRatios = [1.0 / 3.0, 9.0 / 16.0, 3.0 / 4.0, 1, 4.0 / 3.0, 16.0 / 9.0, 3]
        let widths = [1_920, 2_560, 3_840, 5_120, 7_680, 12_000]

        for gridSide in StoryboardGrid.availableSides {
            for requestedWidth in widths {
                for aspectRatio in aspectRatios {
                    let result = StoryboardResult(
                        frames: [CapturedFrame(id: 0, time: 0, jpegData: Data(), aspectRatio: aspectRatio)],
                        sourceURL: URL(fileURLWithPath: "/tmp/layout-check.mp4")
                    )
                    let settings = ExportSettings(gridSide: gridSide, width: requestedWidth)
                    let canvas = StoryboardComposer.canvasSize(result: result, settings: settings)
                    let context = "grid=\(gridSide), width=\(requestedWidth), aspect=\(aspectRatio)"

                    XCTAssertGreaterThanOrEqual(canvas.width, 1_920, context)
                    XCTAssertLessThanOrEqual(max(canvas.width, canvas.height), 16_384, context)
                    XCTAssertLessThanOrEqual(canvas.width * canvas.height, 64_000_000, context)
                }
            }
        }
    }

    func testAspectChoicesCoverLandscapeSquareAndVerticalVideo() {
        XCTAssertEqual(StoryboardAspect.source.resolvedCardAspectRatio(sourceAspectRatio: 9.0 / 16.0), 9.0 / 16.0)
        XCTAssertEqual(StoryboardAspect.square.resolvedCardAspectRatio(sourceAspectRatio: nil), 1)
        XCTAssertEqual(StoryboardAspect.landscape.resolvedCardAspectRatio(sourceAspectRatio: nil), 16.0 / 9.0)
        XCTAssertEqual(StoryboardAspect.portrait.resolvedCardAspectRatio(sourceAspectRatio: nil), 9.0 / 16.0)
        XCTAssertEqual(StoryboardAspect.ultraWide.resolvedCardAspectRatio(sourceAspectRatio: nil), 21.0 / 9.0)
    }

    func testCommonVideoContainersAreAccepted() {
        for fileExtension in ["mp4", "mov", "mkv", "webm", "avi", "3gp", "mpeg", "ts"] {
            XCTAssertTrue(SupportedVideoInput.accepts(URL(fileURLWithPath: "/tmp/sample.\(fileExtension)")))
        }
        XCTAssertFalse(SupportedVideoInput.accepts(URL(fileURLWithPath: "/tmp/notes.txt")))
    }

    func testHistogramDistanceIsZeroForSameFrame() {
        XCTAssertEqual(FrameSelection.histogramDistance([0.5, 0.5], [0.5, 0.5]), 0, accuracy: 0.0001)
    }

    func testSceneDetectionSeparatesLargeHistogramChange() {
        let frames = [
            frame(id: 0, time: 0, histogram: [1, 0]),
            frame(id: 1, time: 1, histogram: [0.95, 0.05]),
            frame(id: 2, time: 2, histogram: [0.05, 0.95]),
            frame(id: 3, time: 3, histogram: [0, 1])
        ]
        XCTAssertEqual(FrameSelection.sceneRanges(in: frames).count, 2)
    }

    func testSelectionRejectsDarkAndNearDuplicateFrames() {
        let frames = [
            frame(id: 0, time: 0, histogram: [1, 0], blackRatio: 0.97, sharpness: 0.01, fingerprint: 0),
            frame(id: 1, time: 1, histogram: [0.8, 0.2], fingerprint: 1),
            frame(id: 2, time: 2, histogram: [0.8, 0.2], fingerprint: 3),
            frame(id: 3, time: 3, histogram: [0.1, 0.9], fingerprint: .max),
            frame(id: 4, time: 4, histogram: [0.4, 0.6], fingerprint: 0x0F0F_0F0F_0F0F_0F0F)
        ]
        let selected = FrameSelection.chooseFrames(from: frames, count: 3)
        XCTAssertFalse(selected.contains(where: { $0.id == 0 }))
        XCTAssertEqual(Set(selected.map(\.id)).count, selected.count)
    }

    func testSelectionFillsARequestedEightByEightGrid() {
        let frames = (0..<180).map { index in
            frame(
                id: index,
                time: Double(index) * 0.5,
                histogram: [0.45, 0.55],
                fingerprint: UInt64(index) << 16
            )
        }
        let selected = FrameSelection.chooseFrames(from: frames, count: 64)
        XCTAssertEqual(selected.count, 64)
        XCTAssertEqual(Set(selected.map(\.id)).count, 64)
    }

    func testGridChoicesStopAtEightByEight() {
        XCTAssertEqual(StoryboardGrid.availableSides, [3, 4, 5, 6, 7, 8])
    }

    func testAllBlackFramesProduceNoStoryboardCandidates() {
        let frames = (0..<12).map { index in
            frame(id: index, time: Double(index), histogram: [1, 0], blackRatio: 0.96, sharpness: 0.01, fingerprint: UInt64(index))
        }
        XCTAssertTrue(FrameSelection.chooseFrames(from: frames, count: 9).isEmpty)
    }

    func testDetectedPersonOutranksSimilarQualityLandscape() {
        let landscape = frame(id: 0, time: 0, histogram: [0.2, 0.8], sharpness: 0.22, fingerprint: 1)
        var portrait = frame(id: 1, time: 1, histogram: [0.8, 0.2], sharpness: 0.18, fingerprint: .max)
        portrait.peopleScore = 0.32
        XCTAssertEqual(FrameSelection.chooseFrames(from: [landscape, portrait], count: 1).first?.id, portrait.id)
    }

    func testTextOnlyCoverAndWarningFramesAreExcludedWhenVideoContentExists() {
        var cover = frame(id: 0, time: 0, histogram: [0.1, 0.9], sharpness: 0.30)
        cover.textOverlayScore = 0.72
        var warning = frame(id: 1, time: 1, histogram: [0.2, 0.8], sharpness: 0.28)
        warning.textOverlayScore = 0.88
        var person = frame(id: 2, time: 2, histogram: [0.7, 0.3], sharpness: 0.20)
        person.peopleScore = 0.34
        let scenery = frame(id: 3, time: 3, histogram: [0.6, 0.4], sharpness: 0.19)

        let selected = FrameSelection.chooseFrames(from: [cover, warning, person, scenery], count: 2)
        XCTAssertEqual(Set(selected.map(\.id)), Set([person.id, scenery.id]))
    }

    func testSparseWhiteAndDarkTitleCardsAreExcludedWithoutPeople() {
        var whiteCard = frame(id: 0, time: 0, histogram: [0.05, 0.95], sharpness: 0.26)
        whiteCard.brightRatio = 0.84
        whiteCard.dominantToneRatio = 0.88
        var darkCard = frame(id: 1, time: 1, histogram: [0.90, 0.10], blackRatio: 0.74, sharpness: 0.24)
        darkCard.dominantToneRatio = 0.90
        let scene = frame(id: 2, time: 2, histogram: [0.45, 0.55], sharpness: 0.20)

        let selected = FrameSelection.chooseFrames(from: [whiteCard, darkCard, scene], count: 1)
        XCTAssertEqual(selected.map(\.id), [scene.id])
    }

    func testSparseCinematicShotRemainsEligibleWithoutTextDetection() {
        var atmosphericShot = frame(
            id: 0,
            time: 0,
            histogram: [0.10, 0.90],
            sharpness: 0.20,
            fingerprint: 0x0000_0000_0000_FFFF
        )
        // A visually simple night or fog shot is not a detected text card.
        atmosphericShot.dominantToneRatio = 0.90
        let middleScene = frame(id: 1, time: 10, histogram: [0.20, 0.80], fingerprint: 0x00FF_00FF_00FF_00FF)
        let lateScene = frame(id: 2, time: 11, histogram: [0.80, 0.20], fingerprint: 0xFF00_FF00_FF00_FF00)

        let selected = FrameSelection.chooseFrames(from: [atmosphericShot, middleScene, lateScene], count: 2)

        XCTAssertTrue(selected.contains(where: { $0.id == atmosphericShot.id }), "Selected IDs: \(selected.map(\.id))")
    }

    func testAHumanOnAnOtherwiseSparseFramePreventsFalseTitleCardRejection() {
        var brightHumanScene = frame(id: 0, time: 0, histogram: [0.05, 0.95], sharpness: 0.20)
        brightHumanScene.brightRatio = 0.86
        brightHumanScene.dominantToneRatio = 0.90
        brightHumanScene.peopleScore = 0.38

        XCTAssertFalse(brightHumanScene.isLikelyNonContentGraphic)
        XCTAssertEqual(FrameSelection.chooseFrames(from: [brightHumanScene], count: 1).map(\.id), [0])
    }

    func testStorySelectionDoesNotReserveSlotsForLowValueTimestamps() {
        var intro = frame(id: 0, time: 0, histogram: [1, 0], sharpness: 0.03)
        intro.textOverlayScore = 0.45 // Normal overlay: not a hard title-card rejection.
        let dialogue = frame(id: 1, time: 10, histogram: [0.7, 0.3], sharpness: 0.22, fingerprint: 0x00FF)
        var action = frame(id: 2, time: 20, histogram: [0.3, 0.7], sharpness: 0.20, fingerprint: 0xFF00)
        action.bodyScore = 0.62
        action.peopleScore = 0.62
        action.motionScore = 0.72
        let credits = frame(id: 3, time: 30, histogram: [0.45, 0.55], sharpness: 0.03, fingerprint: 0xF0F0)

        let selected = FrameSelection.chooseFrames(from: [intro, dialogue, action, credits], count: 2)
        XCTAssertEqual(Set(selected.map(\.id)), Set([dialogue.id, action.id]))
    }

    func testReadableActionPoseOutranksAnEmptyLandscape() {
        let landscape = frame(id: 0, time: 0, histogram: [0.2, 0.8], sharpness: 0.24, fingerprint: 1)
        var action = frame(id: 1, time: 1, histogram: [0.8, 0.2], sharpness: 0.17, fingerprint: .max)
        action.peopleScore = 0.58
        action.bodyScore = 0.58
        action.motionScore = 0.68

        XCTAssertEqual(FrameSelection.chooseFrames(from: [landscape, action], count: 1).first?.id, action.id)
    }

    @MainActor
    func testManualSmartSelectionFillsTheRequestedGridInTimeOrder() throws {
        let candidates = try (0..<24).map { index -> CapturedFrame in
            let image = NSImage(size: NSSize(width: 96, height: 54))
            image.lockFocus()
            NSColor(
                calibratedRed: CGFloat(index % 5) / 5,
                green: CGFloat((index * 2) % 7) / 7,
                blue: CGFloat((index * 3) % 9) / 9,
                alpha: 1
            ).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 96, height: 54)).fill()
            NSColor.white.withAlphaComponent(0.65).setStroke()
            let stripe = NSBezierPath()
            stripe.move(to: NSPoint(x: CGFloat((index * 7) % 90), y: 0))
            stripe.line(to: NSPoint(x: CGFloat((index * 7) % 90 + 20), y: 54))
            stripe.lineWidth = 3
            stripe.stroke()
            image.unlockFocus()
            return CapturedFrame(
                id: index,
                time: Double(index) * 0.75,
                jpegData: try XCTUnwrap(image.tiffRepresentation),
                aspectRatio: 16.0 / 9.0
            )
        }

        let selectedIDs = ManualFrameSelector.selectIDs(from: candidates, count: 9)
        XCTAssertEqual(selectedIDs.count, 9)
        XCTAssertEqual(Set(selectedIDs).count, 9)
        let timeByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0.time) })
        XCTAssertEqual(selectedIDs, selectedIDs.sorted { timeByID[$0, default: 0] < timeByID[$1, default: 0] })
    }

    private func frame(
        id: Int,
        time: Double,
        histogram: [Float],
        blackRatio: Float = 0.02,
        sharpness: Float = 0.22,
        fingerprint: UInt64? = nil
    ) -> FrameDescriptor {
        FrameDescriptor(
            id: id,
            time: time,
            histogram: histogram,
            luminance: 0.45,
            blackRatio: blackRatio,
            sharpness: sharpness,
            fingerprint: fingerprint ?? stableFingerprint(for: id),
            previewData: nil
        )
    }

    private func tryVersion(_ tag: String) -> ReleaseVersion {
        guard let version = ReleaseVersion(tag: tag) else {
            XCTFail("Expected a valid release tag: \(tag)")
            return ReleaseVersion(tag: "0.0.0")!
        }
        return version
    }

    private func stableFingerprint(for id: Int) -> UInt64 {
        var value = UInt64(bitPattern: Int64(id)) &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    private func makeSyntheticVideo(at url: URL) async throws {
        let width = 320
        let height = 180
        let frameRate: Int32 = 12
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        guard writer.canAdd(input) else { throw SyntheticVideoError.cannotAddInput }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? SyntheticVideoError.cannotStartWriter }
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<36 {
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            let pixelBuffer = try makePixelBuffer(width: width, height: height, frameIndex: frameIndex)
            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: frameRate)
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? SyntheticVideoError.cannotAppendFrame
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? SyntheticVideoError.cannotFinishWriter
        }
    }

    private func makePixelBuffer(width: Int, height: Int, frameIndex: Int) throws -> CVPixelBuffer {
        var optionalBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &optionalBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = optionalBuffer else {
            throw SyntheticVideoError.cannotCreatePixelBuffer
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw SyntheticVideoError.cannotCreatePixelBuffer
        }
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let checker = ((x / 20) + (y / 20) + frameIndex / 3).isMultiple(of: 2)
                bytes[offset] = UInt8(checker ? (frameIndex * 17) % 180 + 50 : 28)
                bytes[offset + 1] = UInt8(checker ? 220 : (frameIndex * 29) % 170 + 55)
                bytes[offset + 2] = UInt8(checker ? 245 : 74)
                bytes[offset + 3] = 255
            }
        }
        return pixelBuffer
    }
}

private enum SyntheticVideoError: Error {
    case cannotAddInput
    case cannotStartWriter
    case cannotAppendFrame
    case cannotFinishWriter
    case cannotCreatePixelBuffer
}
