import AVFoundation
import CoreGraphics
import CoreText
import Vision
import XCTest
@testable import ShotMapApp

final class AutomaticFramePipelineTests: XCTestCase {
    func testRecoverySharesOneBoundedRequestBudgetForSmallAndLargeGrids() {
        let small = AutomaticFrameSamplingPolicy(duration: 600, targetCount: 9)
        XCTAssertEqual(small.initialCount, 48)
        XCTAssertEqual(small.additionalRequestLimit, 48)
        XCTAssertEqual(small.detailedTextRequestLimit, 2)
        XCTAssertEqual(AutomaticFrameSamplingPolicy(duration: 600, targetCount: 16).detailedTextRequestLimit, 3)
        let large = AutomaticFrameSamplingPolicy(duration: 600, targetCount: 64)
        XCTAssertEqual(large.initialCount, 96)
        XCTAssertEqual(large.additionalRequestLimit, 192)
        XCTAssertEqual(large.detailedTextRequestLimit, 6)
        XCTAssertEqual(large.finalReplacementLimit, 8)
        XCTAssertGreaterThanOrEqual(large.semanticRequestLimit, 64)
        XCTAssertEqual(AutomaticFrameSamplingPolicy(duration: 3_000, targetCount: 9).initialCount, 96)
    }

    func testInitialCoverageUsesInteriorsInsteadOfReservingZeroSecondTile() throws {
        let policy = AutomaticFrameSamplingPolicy(duration: 3_000, targetCount: 16)
        let times = policy.initialTimes
        XCTAssertGreaterThan(try XCTUnwrap(times.first), 0)
        XCTAssertLessThan(try XCTUnwrap(times.last), policy.duration)
        XCTAssertEqual(times, times.sorted())
        XCTAssertEqual(Set(times.map { Int($0 / policy.duration * 8) }).count, 8)
        XCTAssertEqual(policy.localTimes(around: 0).count, 3)
        XCTAssertTrue(policy.localTimes(around: policy.duration).allSatisfy { $0 >= 0 && $0 < policy.duration })
    }

    func testRationalSourceTimestampsDoNotCollapseIntoNominalFrames() {
        XCTAssertNotEqual(AutomaticFrameTimeKey(CMTime(value: 1_001, timescale: 1_000)),
                          AutomaticFrameTimeKey(CMTime(value: 1_009, timescale: 1_000)))
        XCTAssertEqual(AutomaticFrameTimeKey(CMTime(value: 1, timescale: 30)),
                       AutomaticFrameTimeKey(CMTime(value: 2, timescale: 60)))
        XCTAssertNil(AutomaticFrameTimeKey(.invalid))
        XCTAssertNil(AutomaticFrameTimeKey(.positiveInfinity))
    }

    func testUnlimitedRecoveryAuditSaturatesWithoutIntegerOverflow() {
        let policy = AutomaticFrameSamplingPolicy(duration: 600, targetCount: 9)
        XCTAssertEqual(policy.semanticStopCount(completed: 18, additionalLimit: .max), 48)
        XCTAssertEqual(policy.semanticStopCount(completed: 47, additionalLimit: 20), 48)
        XCTAssertEqual(policy.semanticStopCount(completed: 48, additionalLimit: .max), 48)
    }

    func testUnknownFailedAndBudgetExhaustedTextCannotMasqueradeAsVerifiedZeroText() {
        for state in [FrameEvidenceState.notEvaluated, .failed] {
            XCTAssertFalse(AutomaticFrameExportGate.allows(quality: .observed, person: .observed,
                text: state, usable: true, requiresDetailedText: false, detailedTextComplete: false))
        }
        XCTAssertFalse(AutomaticFrameExportGate.allows(quality: .observed, person: .observed,
            text: .observed, usable: true, requiresDetailedText: true, detailedTextComplete: false),
            "Low-resolution OCR returning no text cannot bypass a required high-risk audit")
        XCTAssertFalse(AutomaticFrameExportGate.allows(quality: .observed, person: .observed,
            text: .observed, usable: false, requiresDetailedText: true, detailedTextComplete: true),
            "Even a completed audit cannot rehabilitate a rejected frame")
        XCTAssertTrue(AutomaticFrameExportGate.allows(quality: .observed, person: .observed,
            text: .observed, usable: true, requiresDetailedText: false, detailedTextComplete: false),
            "Observed zero people remains valid for landscapes and pets")
    }

    func testSmallObjectLabelsDoNotConsumeAMandatoryHDReviewQuota() {
        var state = AutomaticFrameAnalysisState(policy: AutomaticFrameSamplingPolicy(duration: 60, targetCount: 9))
        for id in 0..<48 {
            var record = auditedRecord(id: id, time: Double(id) + 0.5, face: 0, text: 0.18)
            record.textRegions = [CGRect(x: 0.35, y: 0.76, width: 0.25, height: 0.05),
                                  CGRect(x: 0.42, y: 0.62, width: 0.12, height: 0.03)]
            state.records[id] = record
        }
        state.markRiskAroundConfirmedTerminalCard()
        XCTAssertTrue(state.records.values.allSatisfy { !$0.needsDetailedTextCheck && $0.isExportVerified })
        XCTAssertEqual(state.verifiedSelection().count, 9,
                       "A two-audit budget must not cap a clear person-free video's output at two frames")
    }

    func testSparseObjectWithoutTextIsNotAnUnreviewedTitleCard() {
        var record = auditedRecord(id: 1, time: 5, face: 0, text: 0)
        record.descriptor.qualityEvidence = FrameQualityEvidence(rejection: nil,
            activeContentRect: CGRect(x: 0, y: 0, width: 1, height: 1), focusScore: 0.7,
            subjectFocusScore: nil, contrast: 0.2, edgeCoverage: 0.2,
            informationFraction: 0.2, isSparseGraphic: true)
        XCTAssertFalse(record.hasIndependentDetailedTextRisk)
        XCTAssertTrue(record.isExportVerified, "Blank exclusion belongs to observed pixel quality, not sparse composition")
    }

    func testDenseAndSubstantialTextRetainRequiredReviewAndConfirmedCardsStayRejected() {
        var record = auditedRecord(id: 1, time: 5, face: 0, text: 0.4)
        record.textRegions = (0..<3).map { CGRect(x: 0.2, y: 0.3 + Double($0) * 0.12, width: 0.6, height: 0.06) }
        XCTAssertTrue(record.hasIndependentDetailedTextRisk)
        record.needsDetailedTextCheck = record.hasIndependentDetailedTextRisk
        XCTAssertFalse(record.isExportVerified)
        record.detailedTextChecked = true
        XCTAssertTrue(record.isExportVerified)
        record.descriptor.textOverlayScore = 0.9
        XCTAssertFalse(record.isExportVerified)

        record.descriptor.textOverlayScore = 0
        record.independentTextScore = 0
        record.textRegions = []
        record.descriptor.qualityEvidence?.denseTextLayout = true
        XCTAssertTrue(record.hasIndependentDetailedTextRisk, "Small end credits still receive mandatory HD analysis")
    }

    func testBottomSubtitlesAndCornerWatermarksAreNotTitleCards() {
        let subtitles = [CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.08)]
        let logo = [CGRect(x: 0.86, y: 0.90, width: 0.10, height: 0.05)]
        XCTAssertLessThan(AutomaticTextCardEvidence.score(regions: subtitles, sparse: false, hasSubject: false), 0.65)
        XCTAssertLessThan(AutomaticTextCardEvidence.score(regions: logo, sparse: true, hasSubject: false), 0.65)
        XCTAssertLessThan(AutomaticTextCardEvidence.score(regions: subtitles, sparse: false, hasSubject: true), 0.65)
    }

    func testFaceOnTextDominatedPosterDoesNotBypassTheTitleGate() {
        let lines = (0..<8).map { CGRect(x: 0.075, y: 0.25 + Double($0) * 0.075, width: 0.85, height: 0.06) }
        XCTAssertGreaterThanOrEqual(AutomaticTextCardEvidence.score(regions: lines, sparse: false, hasSubject: true), 0.65)
    }

    func testSplitFrameCounterIsStillOneTextLineRatherThanAHighRiskCreditLayout() {
        let digits = (0..<3).map { CGRect(x: 0.4 + Double($0) * 0.05, y: 0.45, width: 0.04, height: 0.08) }
        XCTAssertEqual(AutomaticTextCardEvidence.lineCount(digits), 1)
        XCTAssertEqual(AutomaticTextCardEvidence.lineCount(digits + [CGRect(x: 0.4, y: 0.65, width: 0.2, height: 0.05)]), 2)
    }

    func testSparseCentralTitleIsRejectedWithoutRejectingARealPersonOverlay() {
        let title = [CGRect(x: 0.2, y: 0.45, width: 0.6, height: 0.12)]
        XCTAssertGreaterThanOrEqual(AutomaticTextCardEvidence.score(regions: title, sparse: true, hasSubject: false), 0.65)
        XCTAssertLessThan(AutomaticTextCardEvidence.score(regions: title, sparse: true, hasSubject: true), 0.65)
    }

    func testSmallCreditRoleAndLargerAlignedNameAreNotLostToTextAreaThreshold() {
        let credits = [CGRect(x: 0.10, y: 0.80, width: 0.14, height: 0.03),
                       CGRect(x: 0.10, y: 0.70, width: 0.38, height: 0.08)]
        XCTAssertGreaterThanOrEqual(AutomaticTextCardEvidence.score(regions: credits, sparse: false, hasSubject: false), 0.65)
        XCTAssertLessThan(AutomaticTextCardEvidence.score(regions: credits, sparse: false, hasSubject: true), 0.65)
    }

    func testPropagatedCreditRunCannotCreateNewAnchorsOrConsumeEarlierContent() throws {
        var state = AutomaticFrameAnalysisState(policy: AutomaticFrameSamplingPolicy(duration: 734, targetCount: 9))
        let times = [599.625, 601.125, 602.625, 604.125, 617, 680, 683, 726]
        for (id, time) in times.enumerated() {
            var descriptor = FrameDescriptor(id: id, time: time,
                histogram: Array(repeating: 1 / 16, count: 16), luminance: 0.4, blackRatio: 0,
                sharpness: 0.2, fingerprint: UInt64(id), previewData: nil)
            descriptor.personObservationState = .observed
            descriptor.textObservationState = .observed
            // The portrait has its own independently strong text evidence;
            // the later ordinary person bounds the confirmed card run.
            descriptor.faceScore = time == 617 || time == 726 ? 0.2 : 0
            descriptor.qualityEvidence = FrameQualityEvidence(rejection: nil,
                activeContentRect: CGRect(x: 0, y: 0, width: 1, height: 1), focusScore: 0.7,
                subjectFocusScore: nil, contrast: 0.2, edgeCoverage: 0.3, informationFraction: 1, isSparseGraphic: false)
            let independent: Float = time == 604.125 || time == 617 || time == 680 ? 0.85 : 0
            descriptor.textOverlayScore = independent
            var record = AutomaticFrameRecord(descriptor: descriptor, pts: CMTime(seconds: time, preferredTimescale: 60_000))
            record.independentTextScore = independent
            state.records[id] = record
        }
        for _ in 0..<4 {
            state.markRiskAroundConfirmedTerminalCard()
            try state.confirmTerminalCardRun()
        }
        XCTAssertEqual(state.records.values.filter { $0.independentTextScore >= 0.65 }.count, 3)
        XCTAssertEqual(state.records[0]?.descriptor.textOverlayScore, 0)
        XCTAssertEqual(state.records[1]?.descriptor.textOverlayScore, 0,
                       "Uncertain neighbouring artwork is not a new independent text anchor")
        XCTAssertEqual(state.records[1]?.needsDetailedTextCheck, true)
        XCTAssertGreaterThanOrEqual(state.records[4]?.descriptor.textOverlayScore ?? 0, 0.65)
        XCTAssertEqual(state.records[7]?.descriptor.textOverlayScore, 0, "A post-credit person ends the inferred run")
    }

    func testCreditPrecursorReviewIsGridIndependentAndDoesNotTrimUnobservedPersonFreeContent() {
        for count in [9, 64] {
            var state = AutomaticFrameAnalysisState(policy: AutomaticFrameSamplingPolicy(duration: 734, targetCount: count))
            for (id, sample) in [(500.0, Float(0.7), Float(0)), (585, 0, 0.491), (592, 0, 0.554), (684, 0, 0.95)].enumerated() {
                var descriptor = FrameDescriptor(id: id, time: sample.0,
                    histogram: Array(repeating: 1 / 16, count: 16), luminance: 0.4, blackRatio: 0,
                    sharpness: 0.2, fingerprint: UInt64(id), previewData: nil)
                descriptor.personObservationState = .observed
                descriptor.faceScore = sample.1
                var record = AutomaticFrameRecord(descriptor: descriptor,
                    pts: CMTime(seconds: sample.0, preferredTimescale: 60_000))
                record.independentTextScore = sample.2
                state.records[id] = record
            }
            XCTAssertEqual(state.precedingCreditReviewStart(seedTime: 684), 585,
                           "More initial samples must not shrink the earlier-credit review span")
            state.records[0]?.descriptor.faceScore = 0
            XCTAssertGreaterThan(state.precedingCreditReviewStart(seedTime: 684), 680,
                                 "Without a trusted content boundary, do not mark all earlier person-free media")
        }
    }

    func testCreditRunsSplitAtOrdinaryPeopleAndExplicitNegativeDetailedAudits() throws {
        var state = AutomaticFrameAnalysisState(policy: AutomaticFrameSamplingPolicy(duration: 1_000, targetCount: 16))
        let samples: [(Double, Float, Float)] = [(600, 0, 0.85), (620, 0, 0), (800, 0.3, 0),
            (850, 0, 0), (950, 0, 0.85), (960, 0, 0), (970, 0, 0.85), (990, 0.2, 0)]
        for (id, item) in samples.enumerated() { state.records[id] = auditedRecord(id: id, time: item.0, face: item.1, text: item.2) }
        state.records[3]?.detailedTextChecked = true
        state.records[3]?.detailedTextObservedScore = 0
        state.records[3]?.detailedTextCoveredFullFrame = true
        for _ in 0..<3 { try state.confirmTerminalCardRun() }
        XCTAssertEqual(state.records[1]?.descriptor.textOverlayScore, 0, "A lone chapter card does not define the rest of a movie")
        XCTAssertTrue(state.records[2]?.descriptor.isUsable == true, "Ordinary human scenes split independently observed cards")
        XCTAssertTrue(state.records[3]?.descriptor.isUsable == true, "An explicit negative detailed audit splits a run")
        XCTAssertGreaterThanOrEqual(state.records[5]?.descriptor.textOverlayScore ?? 0, 0.65)
        XCTAssertEqual(state.records[7]?.descriptor.textOverlayScore, 0, "A post-credit scene remains valid")
    }

    func testRecoveryReservesDistributedCoverageWhenLocalRequestsOverflowTheBatch() {
        var state = AutomaticFrameAnalysisState(policy: AutomaticFrameSamplingPolicy(duration: 120, targetCount: 9))
        let requests = state.makeRecoveryRequests(localTimes: (0..<100).map { Double($0) / 100 },
            coverageTimes: [10, 40, 70, 100], limit: 8)
        XCTAssertEqual(requests.count, 8)
        XCTAssertTrue(requests.contains { $0.time.seconds == 10 })
        XCTAssertTrue(requests.contains { $0.time.seconds == 100 }, "Coverage is reserved before local prefix truncation")
    }

    func testAccurateOCRRegionsAreMappedFromROIToFullImageBeforeScoring() {
        let roi = CGRect(x: 0.15, y: 0.35, width: 0.7, height: 0.3)
        let local = CGRect(x: 0.4, y: 0.5, width: 0.2, height: 0.1)
        let full = AutomaticTextCardEvidence.fullImageRegion(local, roi: roi)
        XCTAssertEqual(full.minX, 0.43, accuracy: 0.000_001)
        XCTAssertEqual(full.minY, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(full.width, 0.14, accuracy: 0.000_001)
        XCTAssertEqual(full.height, 0.03, accuracy: 0.000_001)
    }

    func testProductionCreditPhrasesAreCorroboratingSemanticsRatherThanDialogueWordBans() {
        XCTAssertTrue(AutomaticTextCardEvidence.hasProductionCreditPhrases(["Written and Directed by", "Crew member"], hasSubject: false, layoutScore: 0.1))
        XCTAssertTrue(AutomaticTextCardEvidence.hasProductionCreditPhrases(["All CG and VFX made with", "Free software"], hasSubject: false, layoutScore: 0.2))
        XCTAssertTrue(AutomaticTextCardEvidence.hasProductionCreditPhrases(["摄影", "剪辑"], hasSubject: false, layoutScore: 0.1))
        XCTAssertFalse(AutomaticTextCardEvidence.hasProductionCreditPhrases(["40 YEARS LATER"], hasSubject: false, layoutScore: 0.5))
        XCTAssertFalse(AutomaticTextCardEvidence.hasProductionCreditPhrases(["The director spoke to the producer."], hasSubject: false, layoutScore: 0.2))
        XCTAssertFalse(AutomaticTextCardEvidence.hasProductionCreditPhrases(["Written and Directed by", "Crew member"], hasSubject: true, layoutScore: 0.1))
    }

    func testCancelledAutomaticDecodeDoesNotTouchMissingAsset() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await ManualFrameExtractor.decodeAutomaticFrames(
                from: AVURLAsset(url: URL(fileURLWithPath: "/nonexistent/automatic-cancel.mov")),
                requests: [AutomaticFrameTimeRequest(id: 0, time: .zero)],
                maximumEdge: 480, tolerance: .zero, requireExactPTS: true
            ) { _, _, _ in XCTFail("Cancelled decoding cannot emit an image") }
        }
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch { XCTFail("Expected cancellation, got \(error)") }
    }

    func testExactAutomaticResolutionUpgradePreservesDistinctRealVFRPresentationTimes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotMapExactVFR-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vfr.mov")
        try await Self.writeVFRFixture(to: url)
        let asset = AVURLAsset(url: url)
        let requests = [AutomaticFrameTimeRequest(id: 1, time: CMTime(value: 1_001, timescale: 1_000)),
                        AutomaticFrameTimeRequest(id: 2, time: CMTime(value: 1_009, timescale: 1_000))]
        var analysisPTS: [Int: CMTime] = [:]
        try await ManualFrameExtractor.decodeAutomaticFrames(from: asset, requests: requests, maximumEdge: 96, tolerance: .zero, requireExactPTS: true) { id, time, _ in
            analysisPTS[id] = time
        }
        XCTAssertEqual(analysisPTS.count, 2, "Two real PTS within one nominal 30fps bucket remain separate")
        let finalRequests = analysisPTS.map { AutomaticFrameTimeRequest(id: $0.key, time: $0.value) }
        var finalPTS: [Int: CMTime] = [:]
        try await ManualFrameExtractor.decodeAutomaticFrames(from: asset, requests: finalRequests, maximumEdge: 640, tolerance: .zero, requireExactPTS: true) { id, time, _ in
            finalPTS[id] = time
        }
        XCTAssertEqual(finalPTS.count, 2)
        for request in requests {
            let analysis = try XCTUnwrap(analysisPTS[request.id])
            let final = try XCTUnwrap(finalPTS[request.id])
            XCTAssertEqual(CMTimeCompare(analysis, request.time), 0)
            XCTAssertEqual(CMTimeCompare(final, analysis), 0, "Resolution upgrade must never choose a neighbouring frame")
        }
    }

    func testDiscoveryAcceptsActualFramesForNonFrameAlignedCFRAndVFRRequests() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShotMapDiscoveryPTS-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtures: [([Int], Int)] = [([0, 40, 80, 120, 160, 200], 95), ([0, 1_001, 1_009, 1_100, 1_200], 1_004)]
        for (index, fixture) in fixtures.enumerated() {
            let url = directory.appendingPathComponent("discovery-\(index).mov")
            try await Self.writeVFRFixture(to: url, presentationTimes: fixture.0)
            let asset = AVURLAsset(url: url)
            let request = AutomaticFrameTimeRequest(id: 7, time: CMTime(value: Int64(fixture.1), timescale: 1_000))
            var found: [CMTime] = []
            try await ManualFrameExtractor.decodeAutomaticFrames(from: asset, requests: [request], maximumEdge: 96,
                tolerance: .zero, requireExactPTS: false) { _, time, image in
                XCTAssertEqual(FrameQualityAnalyzer.assess(image: image).state, .observed)
                found.append(time)
            }
            let actual = try XCTUnwrap(found.first)
            XCTAssertEqual(found.count, 1)
            XCTAssertNotEqual(CMTimeCompare(actual, request.time), 0)
            XCTAssertTrue(fixture.0.contains { CMTimeCompare(actual, CMTime(value: Int64($0), timescale: 1_000)) == 0 })
            var exactCount = 0
            try await ManualFrameExtractor.decodeAutomaticFrames(from: asset,
                requests: [AutomaticFrameTimeRequest(id: 7, time: actual)], maximumEdge: 640,
                tolerance: .zero, requireExactPTS: true) { _, time, _ in
                XCTAssertEqual(CMTimeCompare(time, actual), 0)
                exactCount += 1
            }
            XCTAssertEqual(exactCount, 1)
        }
    }

    func testFinalCacheReuseRequiresOriginalImageVerifiedPTSAndSufficientResolution() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        var record = auditedRecord(id: 7, time: 1.001, face: 0, text: 0)
        record.image = image
        XCTAssertTrue(record.reusableFinalImage(maximumEdge: 480) === image)
        XCTAssertNil(record.reusableFinalImage(maximumEdge: 640), "Exporting a larger image requires a fresh exact decode")
        record.image = nil
        record.encodedPreview = ImageCodec.jpegData(from: image, compressionQuality: 0.9)
        XCTAssertNil(record.reusableFinalImage(maximumEdge: 480), "An encoded preview is not the retained source CGImage")
        record.image = image
        record.descriptor.textObservationState = .failed
        XCTAssertNil(record.reusableFinalImage(maximumEdge: 480), "A retained image never bypasses failed evidence")
    }

    func testCachedAndDecodedFinalImagesSharePTSAndQualityRejectionGate() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let blank = try XCTUnwrap(context.makeImage())
        let record = auditedRecord(id: 7, time: 1.001, face: 0, text: 0)
        let performance = AutomaticFramePerformance(enabled: false)
        switch AutomaticFinalFrameRenderer.render(record: record, actualPTS: record.pts,
            image: blank, slotID: 7, performance: performance) {
        case .rejected: break
        default: XCTFail("A final blank rejection is authoritative even for a previously accepted cache record")
        }
        switch AutomaticFinalFrameRenderer.render(record: record, actualPTS: CMTime(value: 1_002, timescale: 1_000),
            image: blank, slotID: 7, performance: performance) {
        case .rejected: break
        default: XCTFail("A cached/final image at a neighbouring PTS cannot inherit the record's evidence")
        }
    }

    func testKnownQualityRejectionsNeedNoSemanticAuditAndDoNotBlockConfirmedCreditRuns() throws {
        var state = AutomaticFrameAnalysisState(policy: AutomaticFrameSamplingPolicy(duration: 1_000, targetCount: 16))
        state.records[0] = auditedRecord(id: 0, time: 800, face: 0, text: 0.9)
        state.records[1] = auditedRecord(id: 1, time: 820, face: 0, text: 0)
        state.records[2] = auditedRecord(id: 2, time: 840, face: 0, text: 0.9)
        state.records[3] = auditedRecord(id: 3, time: 860, face: 0, text: 0)
        state.records[4] = auditedRecord(id: 4, time: 880, face: 0.3, text: 0)
        state.records[1]?.descriptor.qualityEvidence?.rejection = .severelyBlurred
        state.records[1]?.descriptor.personObservationState = .notEvaluated
        state.records[1]?.descriptor.textObservationState = .notEvaluated
        try state.audit(id: 1)
        XCTAssertEqual(state.records[1]?.descriptor.personObservationState, .notEvaluated,
            "A rejected image does not require a proxy image or fabricated zero-person result")
        try state.confirmTerminalCardRun()
        XCTAssertEqual(state.semanticChecks, 0)
        XCTAssertGreaterThanOrEqual(state.records[3]?.descriptor.textOverlayScore ?? 0, 0.65)
        XCTAssertEqual(state.records[4]?.descriptor.textOverlayScore, 0)
    }

    func testRepeatedSemanticAuditPreservesExistingSamePTSEvidenceWithoutAnImage() throws {
        var state = AutomaticFrameAnalysisState(policy: AutomaticFrameSamplingPolicy(duration: 10, targetCount: 9))
        let original = auditedRecord(id: 7, time: 1, face: 0.4, text: 0.2)
        state.records[7] = original
        try state.audit(id: 7)
        XCTAssertEqual(state.records[7]?.descriptor.faceScore, 0.4)
        XCTAssertEqual(state.records[7]?.descriptor.personObservationState, .observed)
        XCTAssertEqual(state.records[7]?.descriptor.textObservationState, .observed)
        XCTAssertEqual(state.records[7]?.descriptor.textOverlayScore, 0.2)
    }

    func testFailedSemanticInputsExhaustABoundedPassWithoutReauditingOrExporting() throws {
        let policy = AutomaticFrameSamplingPolicy(duration: 1_000, targetCount: 9)
        var state = AutomaticFrameAnalysisState(policy: policy)
        // These passed pixel inspection but lost their image backing before
        // inference. Exercise the production failure transition, not fabricated
        // observed "zero people/text" records, and leave more candidates than
        // the semantic pass is allowed to inspect.
        for id in 0..<(policy.semanticRequestLimit + 9) {
            var record = auditedRecord(id: id, time: Double(id) * 3 + 1, face: 0, text: 0)
            record.descriptor.personObservationState = .notEvaluated
            record.descriptor.textObservationState = .notEvaluated
            state.records[id] = record
        }
        try state.auditProvisionalSelection()
        XCTAssertEqual(state.semanticChecks, policy.semanticRequestLimit)
        XCTAssertEqual(state.records.values.filter { $0.descriptor.personObservationState == .failed }.count,
            policy.semanticRequestLimit)
        XCTAssertTrue(state.verifiedSelection().isEmpty)
        XCTAssertTrue(state.semanticSelection().isEmpty)

        // Re-entry after a budget-limited recovery must finish without either
        // restarting failed records or manufacturing an output to fill a grid.
        try state.auditProvisionalSelection()
        try state.auditRecoveredCandidates(Array(state.records.keys), limit: .max)
        XCTAssertEqual(state.semanticChecks, policy.semanticRequestLimit)
        XCTAssertTrue(state.verifiedSelection().isEmpty)
    }

    func testPersonWithFailedOrUnobservedTextCannotBecomeATrustedContentBoundary() {
        var record = auditedRecord(id: 1, time: 50, face: 0.4, text: 0)
        XCTAssertTrue(record.isTrustedContentBoundary, "Observed ordinary person shots still stop unrelated credits propagation")
        for state in [FrameEvidenceState.failed, .notEvaluated] {
            record.descriptor.textObservationState = state
            XCTAssertFalse(record.isTrustedContentBoundary,
                "A face cannot turn an OCR failure or missing observation into proof of ordinary content")
            XCTAssertFalse(record.isExportVerified)
        }
    }

    func testCancelledSemanticAuditPropagatesWithoutFabricatingFailedOrVerifiedEvidence() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        var state = AutomaticFrameAnalysisState(policy: AutomaticFrameSamplingPolicy(duration: 60, targetCount: 9))
        var record = auditedRecord(id: 1, time: 10, face: 0, text: 0)
        record.descriptor.personObservationState = .notEvaluated
        record.descriptor.textObservationState = .notEvaluated
        record.image = try XCTUnwrap(context.makeImage())
        state.records[1] = record
        state.cancellation.cancel()

        XCTAssertThrowsError(try state.audit(id: 1)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(state.records[1]?.descriptor.personObservationState, .notEvaluated)
        XCTAssertEqual(state.records[1]?.descriptor.textObservationState, .notEvaluated)
        XCTAssertTrue(state.verifiedSelection().isEmpty)
    }

    func testCoverageAuditsAnExistingContentCandidateEvenWhenSelectedCountIsFull() {
        var state = AutomaticFrameAnalysisState(policy: AutomaticFrameSamplingPolicy(duration: 100, targetCount: 9))
        var selected: [FrameDescriptor] = []
        for id in 0..<9 {
            let record = auditedRecord(id: id, time: 2 + Double(id) * 2, face: 0.5, text: 0)
            state.records[id] = record
            selected.append(record.descriptor)
        }
        var late = auditedRecord(id: 99, time: 95, face: 0, text: 0)
        late.descriptor.personObservationState = .notEvaluated
        late.descriptor.textObservationState = .notEvaluated
        state.records[99] = late
        XCTAssertEqual(selected.count, state.policy.targetCount)
        XCTAssertTrue(state.coverageAuditIDs(limit: 4).contains(99),
            "A full K layout does not excuse a decoded content interval never being audited")
        let before = state.missingContentBuckets()
        state.records[99]?.descriptor.personObservationState = .observed
        state.records[99]?.descriptor.textObservationState = .observed
        XCTAssertLessThan(state.missingContentBuckets().count, before.count,
            "All audited candidates provide coverage even if not selected into the K slots")
        XCTAssertFalse(state.missingContentBuckets().contains(state.coverageBucket(for: 95)))
    }

    func testConfirmedCardRunIsNotRepeatedlyScheduledAsMissingContent() throws {
        var state = AutomaticFrameAnalysisState(policy: AutomaticFrameSamplingPolicy(duration: 100, targetCount: 9))
        var selected: [FrameDescriptor] = []
        for id in 0..<9 {
            let record = auditedRecord(id: id, time: 5 + Double(id) * 8, face: 0.5, text: 0)
            state.records[id] = record
            selected.append(record.descriptor)
        }
        state.records[10] = auditedRecord(id: 10, time: 80, face: 0, text: 0.9)
        state.records[11] = auditedRecord(id: 11, time: 90, face: 0, text: 0.9)
        state.records[12] = auditedRecord(id: 12, time: 98, face: 0.5, text: 0)
        try state.confirmTerminalCardRun()
        XCTAssertTrue(state.isConfirmedCardTime(85))
        let plan = state.recoveryPlan(selected: selected, round: 1, remaining: 48)
        XCTAssertFalse(plan.centres.contains { state.isConfirmedCardTime($0) },
            "Two content-confirmed cards define a bounded run, not an endless coverage hole")
        XCTAssertFalse(state.isConfirmedCardTime(98), "Post-credit content remains eligible")
    }

    func testOnlySubmittedSoftSearchBucketsAreMarkedAttemptedAndShortResultsKeepBudget() {
        var state = AutomaticFrameAnalysisState(policy: AutomaticFrameSamplingPolicy(duration: 100, targetCount: 9))
        let plan = AutomaticRecoveryPlan(centres: [5, 95], requestLimit: 12,
            focusBuckets: [0, 8], personBuckets: [0, 8], probesPersonFree: true)
        state.recordRecoveryAttempt(plan: plan, requests: [AutomaticFrameTimeRequest(id: 1, time: CMTime(seconds: 5, preferredTimescale: 600))])
        XCTAssertTrue(state.searchedPersonBuckets.contains(0))
        XCTAssertFalse(state.searchedPersonBuckets.contains(8), "Prefix truncation must not claim an unsubmitted interval was searched")
        XCTAssertFalse(state.didProbePersonFreeContent)
        XCTAssertEqual(state.recoveryPlan(selected: [], round: 1, remaining: 37).requestLimit, 37,
            "The final recovery keeps the full remaining allowance when fewer than K pass")
    }

    func testOpeningFundingNeedsACompleteProductionRelationshipNotDialogueKeywords() {
        XCTAssertTrue(AutomaticTextCardEvidence.hasExplicitFilmFundingSentence(["This film is supported by", "Example Film Fund"]))
        XCTAssertFalse(AutomaticTextCardEvidence.hasExplicitFilmFundingSentence(["We were supported by our friends", "during the difficult journey"]))
        XCTAssertFalse(AutomaticTextCardEvidence.hasExplicitFilmFundingSentence(["Film funding helps our director"]))
        XCTAssertFalse(AutomaticTextCardEvidence.hasExplicitFilmFundingSentence(["Director", "Producer"]))
    }

    func testOpeningRiskSchedulesOneRepresentativeWithoutBlockingOtherCandidatesOrPersonFreeMedia() {
        var state = AutomaticFrameAnalysisState(policy: AutomaticFrameSamplingPolicy(duration: 100, targetCount: 16))
        var selected: [FrameDescriptor] = []
        for id in 0..<10 {
            var record = auditedRecord(id: id, time: 5 + Double(id), face: 0, text: 0)
            record.openingLayoutCandidate = true
            state.records[id] = record
            selected.append(record.descriptor)
        }
        XCTAssertNil(state.openingReviewCandidate(in: selected), "No later human scene means no opening-only escalation for a tutorial or landscape")
        state.records[99] = auditedRecord(id: 99, time: 40, face: 0.6, text: 0)
        XCTAssertEqual(state.openingReviewCandidate(in: selected), 0)
        XCTAssertTrue(state.records.values.allSatisfy(\.isExportVerified), "Optional layout risk never makes ten candidates pending HD")
        state.openingTextChecks = 1
        XCTAssertNil(state.openingReviewCandidate(in: selected))
        XCTAssertTrue(state.records.values.allSatisfy(\.isExportVerified))
        XCTAssertEqual(state.detailedTextChecks, 0, "Opening representative does not consume a tail slot")
    }

    func testOpeningLayoutNeedsTwoAlignedLowerLeftRowBandsAndOCRFragments() throws {
        let width = 480, height = 200
        func fixture(rows: [Range<Int>]) throws -> CGImage {
            var bytes = [UInt8](repeating: 15, count: width * height * 3)
            for band in rows { for row in band { for column in 38..<210 where column % 8 < 3 {
                let offset = (row * width + column) * 3
                bytes[offset] = 240; bytes[offset + 1] = 240; bytes[offset + 2] = 240
            } } }
            let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
            return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                bytesPerRow: width * 3, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        }
        let fragments = [CGRect(x: 0.21, y: 0.20, width: 0.035, height: 0.045),
                         CGRect(x: 0.079, y: 0.14, width: 0.206, height: 0.11)]
        let two = try fixture(rows: [152..<158, 162..<172])
        XCTAssertTrue(AutomaticOpeningOverlayEvidence.hasAlignedLowerLeftRows(image: two, regions: fragments))
        XCTAssertFalse(AutomaticOpeningOverlayEvidence.hasAlignedLowerLeftRows(image: two, regions: [fragments[1]]), "A single corner watermark is insufficient")
        XCTAssertFalse(AutomaticOpeningOverlayEvidence.hasAlignedLowerLeftRows(image: try fixture(rows: [162..<172]), regions: fragments))
        XCTAssertFalse(AutomaticOpeningOverlayEvidence.hasAlignedLowerLeftRows(image: two,
            regions: [CGRect(x: 0.25, y: 0.05, width: 0.5, height: 0.04), CGRect(x: 0.30, y: 0.10, width: 0.4, height: 0.04)]), "Ordinary centered bottom subtitles do not schedule this review")
    }

    func testRegionalZeroCannotSplitCreditsButCoveredNegativeStillDefinesContent() throws {
        var state = AutomaticFrameAnalysisState(policy: AutomaticFrameSamplingPolicy(duration: 1_000, targetCount: 16))
        for (id, sample) in [(650.0, Float(0.9)), (720, 0), (800, 0.9), (830, 0.9), (990, 0)].enumerated() {
            state.records[id] = auditedRecord(id: id, time: sample.0, face: id == 4 ? 0.3 : 0, text: sample.1)
        }
        state.records[1]?.detailedTextChecked = true
        state.records[1]?.detailedTextObservedScore = 0
        XCTAssertFalse(state.records[1]?.isTrustedContentBoundary ?? true,
            "A zero in a local ROI never proves absence outside that ROI")
        try state.confirmTerminalCardRun()
        XCTAssertGreaterThanOrEqual(state.records[1]?.descriptor.textOverlayScore ?? 0, 0.65)
        state.records[1]?.detailedTextCoveredFullFrame = true
        try state.confirmTerminalCardRun()
        XCTAssertTrue(state.records[1]?.isTrustedContentBoundary ?? false)
        XCTAssertEqual(state.records[1]?.descriptor.textOverlayScore, 0,
            "A genuinely covered negative can split independent card groups and retain ordinary content")
        XCTAssertEqual(state.records[4]?.descriptor.textOverlayScore, 0)
    }

    func testAccurateRegionalMissFindsProductionTextOutsideTheInitialROI() async throws {
        let result = try await Task.detached(priority: .userInitiated) { () -> (Bool, Float, Bool) in
            XCTAssertFalse(Thread.isMainThread, "Match the production background media pipeline")
            let context = try XCTUnwrap(CGContext(data: nil, width: 1_280, height: 720, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.setFillColor(CGColor(gray: 0.12, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1_280, height: 720))
            let font = CTFontCreateWithName("Helvetica" as CFString, 32, nil)
            let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1)] as CFDictionary
            for (index, text) in ["Lighting", "Sound editing", "Camera crew", "Music production"].enumerated() {
                let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes))
                context.textPosition = CGPoint(x: 36, y: 630 - index * 48)
                CTLineDraw(line, context)
            }
            let image = try XCTUnwrap(context.makeImage())
            var state = AutomaticFrameAnalysisState(policy: AutomaticFrameSamplingPolicy(duration: 100, targetCount: 9))
            defer { state.performance.emit() }
            var descriptor = FrameDescriptor(id: 1, time: 50, histogram: Array(repeating: 1 / 16, count: 16),
                luminance: 0.4, blackRatio: 0, sharpness: 0.2, fingerprint: 1, previewData: nil)
            descriptor.personObservationState = .observed; descriptor.textObservationState = .observed
            descriptor.qualityEvidence = FrameQualityEvidence(rejection: nil,
                activeContentRect: CGRect(x: 0, y: 0, width: 1, height: 1), focusScore: 0.7,
                subjectFocusScore: nil, contrast: 0.2, edgeCoverage: 0.3, informationFraction: 1, isSparseGraphic: false)
            var record = AutomaticFrameRecord(descriptor: descriptor, pts: CMTime(seconds: 50, preferredTimescale: 600))
            record.textRegions = [CGRect(x: 0.65, y: 0.10, width: 0.10, height: 0.08)]
            record.needsDetailedTextCheck = true
            state.records[1] = record
            try state.auditDetailedText(id: 1, image: image)
            return (state.records[1]?.detailedTextCoveredFullFrame ?? false,
                    state.records[1]?.descriptor.textOverlayScore ?? 0,
                    state.records[1]?.isExportVerified ?? true)
        }.value
        XCTAssertTrue(result.0)
        XCTAssertGreaterThanOrEqual(result.1, 0.65,
            "An initial empty crop cannot clear independently located production text elsewhere")
        XCTAssertFalse(result.2)
    }

    func testAccurateTextFailureUsesOneFullFramePositiveFallbackAndReusesItsEvidence() throws {
        var (state, image) = try detailedTextFailureFixture()
        var accurateReads = 0, fastReads = 0
        let lines = productionCreditLines()
        let reader: (VNRequestTextRecognitionLevel, CGRect) throws -> [AutomaticRecognizedTextLine] = { level, roi in
            if level == .accurate {
                accurateReads += 1
                throw NSError(domain: VNErrorDomain, code: VNErrorCode.operationFailed.rawValue)
            }
            fastReads += 1
            XCTAssertEqual(roi, CGRect(x: 0, y: 0, width: 1, height: 1))
            return lines
        }
        try state.auditDetailedText(id: 1, image: image, textReader: reader)
        try state.auditDetailedText(id: 1, image: image, textReader: reader)
        let record = try XCTUnwrap(state.records[1])
        XCTAssertEqual(accurateReads, 1)
        XCTAssertEqual(fastReads, 1)
        XCTAssertTrue(record.detailedTextFailureFallbackUsed)
        XCTAssertTrue(record.detailedTextChecked)
        XCTAssertTrue(record.detailedTextCoveredFullFrame)
        XCTAssertGreaterThanOrEqual(record.descriptor.textOverlayScore, 0.65)
        XCTAssertFalse(record.isExportVerified)
        XCTAssertFalse(record.isTrustedContentBoundary)
    }

    func testNegativeOrFailedFastFallbackNeverClearsThePreciseReviewRisk() throws {
        for fallbackFails in [false, true] {
            var (state, image) = try detailedTextFailureFixture()
            var reads = 0
            try state.auditDetailedText(id: 1, image: image) { level, _ in
                reads += 1
                if level == .accurate || fallbackFails { throw NSError(domain: VNErrorDomain, code: VNErrorCode.operationFailed.rawValue) }
                return []
            }
            let record = try XCTUnwrap(state.records[1])
            XCTAssertEqual(reads, 2)
            XCTAssertTrue(record.needsDetailedTextCheck)
            XCTAssertTrue(record.detailedTextFailureFallbackUsed)
            XCTAssertFalse(record.detailedTextChecked)
            XCTAssertFalse(record.detailedTextCoveredFullFrame)
            XCTAssertEqual(record.descriptor.textObservationState, .failed)
            XCTAssertFalse(record.isTrustedContentBoundary)
            XCTAssertFalse(record.isExportVerified)
        }
    }

    func testCancellationDuringPreciseOrFastFailureReviewPropagatesWithoutConfirmingEvidence() throws {
        for cancelMode in 0...2 {
            var (state, image) = try detailedTextFailureFixture()
            let bridge = state.cancellation
            let lines = productionCreditLines()
            var reads = 0
            XCTAssertThrowsError(try state.auditDetailedText(id: 1, image: image) { level, _ in
                reads += 1
                if level == .accurate && cancelMode > 0 {
                    throw NSError(domain: VNErrorDomain, code: VNErrorCode.operationFailed.rawValue)
                }
                if cancelMode == 2 {
                    bridge.cancel()
                    return lines
                }
                throw CancellationError()
            }) { XCTAssertTrue($0 is CancellationError) }
            XCTAssertEqual(reads, cancelMode > 0 ? 2 : 1)
            XCTAssertFalse(state.records[1]?.detailedTextFailureFallbackUsed ?? true)
            XCTAssertFalse(state.records[1]?.detailedTextChecked ?? true)
            XCTAssertFalse(state.records[1]?.isExportVerified ?? true)
        }
    }

    func testSuccessfulPrecisePositiveReviewDoesNotRunTheFailureFallback() throws {
        var (state, image) = try detailedTextFailureFixture()
        let lines = productionCreditLines()
        var reads = 0
        try state.auditDetailedText(id: 1, image: image) { level, _ in
            reads += 1
            XCTAssertEqual(level, .accurate)
            return lines
        }
        XCTAssertEqual(reads, 1)
        XCTAssertFalse(state.records[1]?.detailedTextFailureFallbackUsed ?? true)
        XCTAssertTrue(state.records[1]?.detailedTextChecked ?? false)
    }

    func testWorkflowHeaderRequiresIndependentCardContextAndNarrowAlignedRows() {
        let lines = [AutomaticRecognizedTextLine(text: "Development, scripting and studio pipeline", confidence: 1,
                        region: CGRect(x: 0.15, y: 0.60, width: 0.40, height: 0.04)),
                     AutomaticRecognizedTextLine(text: "Team member", confidence: 1,
                        region: CGRect(x: 0.29, y: 0.53, width: 0.12, height: 0.04)),
                     AutomaticRecognizedTextLine(text: "Contributor", confidence: 1,
                        region: CGRect(x: 0.29, y: 0.46, width: 0.12, height: 0.04))]
        XCTAssertTrue(AutomaticTextCardEvidence.hasWorkflowCreditLayout(lines, hasSubject: false, hasIndependentCardContext: true))
        XCTAssertFalse(AutomaticTextCardEvidence.hasWorkflowCreditLayout(lines, hasSubject: false, hasIndependentCardContext: false),
            "An ordinary person-free software diagram is not classified by workflow words alone")
        XCTAssertFalse(AutomaticTextCardEvidence.hasWorkflowCreditLayout(lines, hasSubject: true, hasIndependentCardContext: true))
    }

    func testCancellingRegisteredRealVisionRecognitionReturnsCancellationPromptly() async throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1_024, height: 1_024, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1_024, height: 1_024))
        let font = try XCTUnwrap(CTFontCreateUIFontForLanguage(.system, 20, nil))
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)] as CFDictionary
        for index in 0..<32 {
            let text = "Camera lighting sound production equipment and editorial review"
            let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes))
            context.textPosition = CGPoint(x: 32, y: 980 - index * 28); CTLineDraw(line, context)
        }
        let image = try XCTUnwrap(context.makeImage())
        let bridge = AutomaticVisionCancellation()
        let (started, signal) = AsyncStream<Double>.makeStream()
        let worker = Task.detached(priority: .userInitiated) {
            defer { signal.finish() }
            try await withTaskCancellationHandler {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.progressHandler = { _, progress, _ in
                    guard progress > 0 && progress < 1 else { return }
                    signal.yield(ProcessInfo.processInfo.systemUptime)
                    // Cancel the same registered native request at observed
                    // intermediate inference progress, not at a guessed delay.
                    bridge.cancel()
                }
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                try bridge.perform([request], using: handler)
            } onCancel: { bridge.cancel() }
        }
        var cancelledAt: Double?
        for await event in started { cancelledAt = event; break }
        guard let cancelledAt else {
            try await worker.value
            throw XCTSkip("This Vision revision completed without observable intermediate recognition progress")
        }
        do { try await worker.value; XCTFail("Expected cancellation during native recognition") }
        catch is CancellationError { }
        catch { XCTFail("Expected CancellationError, got \(error)") }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - cancelledAt, 3,
            "Cancellation should not wait through a complete OCR page")
    }

    private func detailedTextFailureFixture() throws -> (AutomaticFrameAnalysisState, CGImage) {
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        var state = AutomaticFrameAnalysisState(policy: AutomaticFrameSamplingPolicy(duration: 100, targetCount: 9))
        var record = auditedRecord(id: 1, time: 50, face: 0, text: 0)
        record.needsDetailedTextCheck = true
        record.descriptor.qualityEvidence?.denseTextLayout = true
        state.records[1] = record
        return (state, try XCTUnwrap(context.makeImage()))
    }

    private func productionCreditLines() -> [AutomaticRecognizedTextLine] {
        ["Lighting", "Sound editing", "Camera crew", "Music production"].enumerated().map { index, text in
            AutomaticRecognizedTextLine(text: text, confidence: 1,
                region: CGRect(x: 0.1, y: 0.3 + Double(index) * 0.1, width: 0.45, height: 0.08))
        }
    }

    private func auditedRecord(id: Int, time: Double, face: Float, text: Float) -> AutomaticFrameRecord {
        var descriptor = FrameDescriptor(id: id, time: time, histogram: Array(repeating: 1 / 16, count: 16),
            luminance: 0.4, blackRatio: 0, sharpness: 0.2, fingerprint: UInt64(id), previewData: nil)
        descriptor.personObservationState = .observed
        descriptor.textObservationState = .observed
        descriptor.faceScore = face
        descriptor.textOverlayScore = text
        descriptor.qualityEvidence = FrameQualityEvidence(rejection: nil,
            activeContentRect: CGRect(x: 0, y: 0, width: 1, height: 1), focusScore: 0.7,
            subjectFocusScore: nil, contrast: 0.2, edgeCoverage: 0.3, informationFraction: 1, isSparseGraphic: false)
        var record = AutomaticFrameRecord(descriptor: descriptor, pts: CMTime(seconds: time, preferredTimescale: 60_000))
        record.independentTextScore = text
        return record
    }

    private static func writeVFRFixture(to url: URL, presentationTimes: [Int] = [0, 1_001, 1_009, 1_100, 1_200]) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 96,
            AVVideoCompressionPropertiesKey: [AVVideoMaxKeyFrameIntervalKey: 48]
        ])
        input.mediaTimeScale = 60_000
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 96
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? StoryboardError.noExportData }
        writer.startSession(atSourceTime: .zero)
        for (index, milliseconds) in presentationTimes.enumerated() {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var optional: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 160, 96, kCVPixelFormatType_32BGRA, nil, &optional)
            guard let buffer = optional else { throw StoryboardError.noExportData }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                for y in 0..<96 { for x in 0..<160 {
                    let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
                    bytes[offset] = UInt8((x + index * 40) % 255)
                    bytes[offset + 1] = UInt8((y * 2 + index * 20) % 255)
                    bytes[offset + 2] = UInt8(index * 45)
                    bytes[offset + 3] = 255
                } }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(milliseconds), timescale: 1_000)) else {
                throw writer.error ?? StoryboardError.noExportData
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? StoryboardError.noExportData }
    }
}
