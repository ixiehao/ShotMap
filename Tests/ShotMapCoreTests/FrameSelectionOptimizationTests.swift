import AVFoundation
import Foundation
import XCTest
@testable import ShotMapApp

final class FrameSelectionOptimizationTests: XCTestCase {
    func testStaticLayoutsFillWithSeparatedTimesInsteadOfTheSharpestAdjacentCopies() {
        let frames = (0..<48).map { index in
            FrameDescriptor(id: index, time: Double(index),
                histogram: Array(repeating: 1 / 16, count: 16), luminance: 0.5,
                blackRatio: 0, sharpness: 0.1 + Float(index) * 0.001,
                fingerprint: 0, previewData: nil)
        }
        let selected = FrameSelection.chooseFrames(from: frames, count: 9).sorted { $0.time < $1.time }
        XCTAssertEqual(selected.count, 9)
        XCTAssertEqual(Set(selected.map(\.id)).count, 9)
        XCTAssertLessThanOrEqual(selected.first?.time ?? 48, 1)
        XCTAssertEqual(selected.last?.time, 47)
        let gaps = zip(selected.dropFirst(), selected).map { $0.time - $1.time }
        XCTAssertGreaterThanOrEqual(gaps.min() ?? 0, 3,
                                   "Static content needs temporal coverage after visual alternatives are exhausted")
    }

    func testObservedCoverageReplacesWeakCrowdedSamplesBelowBestCloseupThreshold() {
        let times: [Double] = [0, 70, 140, 210, 300, 301.5, 303, 490, 560, 630, 350, 410]
        var frames = makeFrames(seed: 987, count: times.count)
        frames = frames.enumerated().map { index, original in
            var frame = FrameDescriptor(id: original.id, time: times[index], histogram: original.histogram,
                luminance: index == 5 ? 0.18 : 0.5, blackRatio: 0, sharpness: 0.18,
                fingerprint: original.fingerprint, previewData: nil)
            let focus: Float = index == 4 ? 0.30 : (index == 5 ? 0.60 : (index == 10 ? 0.70 : 0.80))
            frame.qualityEvidence = FrameQualityEvidence(rejection: nil,
                activeContentRect: CGRect(x: 0, y: 0, width: 1, height: 1), focusScore: focus,
                subjectFocusScore: nil, contrast: 0.2, edgeCoverage: 0.3, informationFraction: 1, isSparseGraphic: false)
            if index == 6 { frame.faceScore = 1; frame.bodyScore = 1 }
            return frame
        }
        let selected = Array(frames.prefix(10))
        let highestQuality = frames.map(\.qualityScore).max()!
        XCTAssertLessThan(frames[10].qualityScore, highestQuality * 0.70)
        XCTAssertLessThan(frames[11].qualityScore, highestQuality * 0.70)
        let repaired = FrameSelection.improveTimelineCoverage(selected, candidates: frames, count: 10)
        XCTAssertEqual(repaired.count, selected.count)
        XCTAssertFalse(repaired.contains { $0.id == 4 }, "The weak pan must not retain a slot beside two better local moments")
        XCTAssertFalse(repaired.contains { $0.id == 5 })
        XCTAssertTrue(repaired.contains { $0.id == 6 }, "Keep the readable principal subject")
        XCTAssertTrue(repaired.contains { $0.id == 10 })
        XCTAssertTrue(repaired.contains { $0.id == 11 })

        for state: FrameEvidenceState? in [nil, .notEvaluated, .failed] {
            let legacy = frames.map { original -> FrameDescriptor in
                var frame = original
                if let state { frame.qualityEvidence?.state = state }
                else { frame.qualityEvidence = nil }
                return frame
            }
            let unchanged = FrameSelection.improveTimelineCoverage(Array(legacy.prefix(10)), candidates: legacy, count: 10)
            XCTAssertEqual(unchanged.map(\.id), Array(legacy.prefix(10)).map(\.id),
                "Relative detail improvements require actually observed evidence")
        }
    }

    func testObservedRelativeCoverageDoesNotTradeDetailForExposure() {
        var frames = makeFrames(seed: 654, count: 4)
        let times: [Double] = [0, 1, 100, 50]
        frames = frames.enumerated().map { index, original in
            var frame = FrameDescriptor(id: original.id, time: times[index], histogram: original.histogram,
                luminance: index == 0 ? 0.08 : 0.5, blackRatio: 0, sharpness: 0.18,
                fingerprint: original.fingerprint, previewData: nil)
            let focus: Float = index == 3 ? 0.4 : 0.8
            frame.qualityEvidence = FrameQualityEvidence(rejection: nil,
                activeContentRect: CGRect(x: 0, y: 0, width: 1, height: 1), focusScore: focus,
                subjectFocusScore: nil, contrast: 0.2, edgeCoverage: 0.3, informationFraction: 1, isSparseGraphic: false)
            if index == 1 { frame.faceScore = 1; frame.bodyScore = 1 }
            return frame
        }
        XCTAssertGreaterThan(frames[3].qualityScore, frames[0].qualityScore)
        let selected = Array(frames.prefix(3))
        XCTAssertEqual(FrameSelection.improveTimelineCoverage(selected, candidates: frames, count: 3).map(\.id), selected.map(\.id))
    }

    func testAuditedNearIdenticalMomentsUseADistinctAvailableAlternative() {
        var frames = makeFrames(seed: 120, count: 10)
        let histogramA: [Float] = [0.4, 0.3, 0.3]
        let histogramB: [Float] = [0.15, 0.3, 0.55]
        frames[0] = FrameDescriptor(id: 0, time: 11.45, histogram: histogramA, luminance: 0.5,
            blackRatio: 0, sharpness: 0.2, fingerprint: 0x3E3E_3E3E_3E3E_3E3E, previewData: nil)
        frames[1] = FrameDescriptor(id: 1, time: 12.37, histogram: histogramB, luminance: 0.5,
            blackRatio: 0, sharpness: 0.2, fingerprint: 0x3E3E_3E3E_3E3E_3E3E ^ 0x1FF, previewData: nil)
        for index in 2..<frames.count {
            let original = frames[index]
            frames[index] = FrameDescriptor(id: original.id, time: 30 + Double(index) * 10,
                histogram: original.histogram, luminance: original.luminance, blackRatio: original.blackRatio,
                sharpness: original.sharpness, fingerprint: original.fingerprint, previewData: nil)
        }
        for index in frames.indices {
            frames[index].qualityEvidence = FrameQualityEvidence(rejection: nil,
                activeContentRect: CGRect(x: 0, y: 0, width: 1, height: 1), focusScore: index == 1 ? 0.55 : 0.65,
                subjectFocusScore: nil, contrast: 0.2, edgeCoverage: 0.3, informationFraction: 1, isSparseGraphic: false)
        }
        let selected = Array(frames.prefix(9))
        let repaired = FrameSelection.improveVisualDiversity(selected, pool: frames, count: 9)
        XCTAssertEqual(repaired.count, 9)
        XCTAssertEqual(Set(repaired.map(\.id)).count, 9)
        XCTAssertTrue(repaired.contains { $0.id == 0 })
        XCTAssertFalse(repaired.contains { $0.id == 1 })
        XCTAssertTrue(repaired.contains { $0.id == 9 })
    }

    func testStaticAuditedVideoKeepsUniqueTimestampsWhenNoDistinctAlternativeExists() {
        let frames = (0..<12).map { index -> FrameDescriptor in
            var frame = FrameDescriptor(id: index, time: Double(index), histogram: [0.4, 0.6], luminance: 0.5,
                blackRatio: 0, sharpness: 0.2, fingerprint: 0x00FF_00FF_00FF_00FF, previewData: nil)
            frame.qualityEvidence = FrameQualityEvidence(rejection: nil,
                activeContentRect: CGRect(x: 0, y: 0, width: 1, height: 1), focusScore: 0.6,
                subjectFocusScore: nil, contrast: 0.2, edgeCoverage: 0.2, informationFraction: 1, isSparseGraphic: false)
            return frame
        }
        let selected = FrameSelection.chooseFrames(from: frames, count: 9)
        XCTAssertEqual(selected.count, 9)
        XCTAssertEqual(Set(selected.map(\.time)).count, 9)
    }

    func testExactRequestsDoNotMergeDistinctVFRMomentsInOneNominalFrameBucket() {
        // These can be distinct source frames in a VFR clip even though a
        // nominal 30fps index would round both timestamps to frame 30.
        let requests = FrameImageRequestBatch(planTimes: [(index: 0, times: [1.001]), (index: 1, times: [1.009])])
        XCTAssertEqual(requests.requestedTimes.count, 2)
        XCTAssertEqual(requests.planIndices(for: requests.requestedTimes[0]), [0])
        XCTAssertEqual(requests.planIndices(for: requests.requestedTimes[1]), [1])
    }

    func testRoundedDecoderRequestStillMapsBackToItsPlan() throws {
        // 29.97fps half-frame boundary: conversion to the decoder timebase
        // rounds up, whereas a key made from the original Double rounds down.
        let seconds = 47.5 * 1_001 / 30_000 - 0.000_001
        let requests = FrameImageRequestBatch(planTimes: [(index: 7, times: [seconds])])
        let submitted = try XCTUnwrap(requests.requestedTimes.first)
        XCTAssertEqual(requests.planIndices(for: submitted), [7])
        XCTAssertEqual(requests.planIndices(for: CMTime(value: submitted.value * 2, timescale: submitted.timescale * 2)), [7])
    }

    func testSharedExactRequestsDecodeOnceWithoutDuplicatingAPlan() throws {
        let requests = FrameImageRequestBatch(planTimes: [
            (index: 4, times: [2, 1, 1.000_000_1]),
            (index: 9, times: [1])
        ])
        XCTAssertEqual(requests.requestedTimes.map(\.seconds), [1, 2])
        XCTAssertEqual(requests.planIndices(for: CMTime(seconds: 1, preferredTimescale: 600)), [4, 9])
        XCTAssertEqual(requests.planIndices(for: CMTime(seconds: 2, preferredTimescale: 600)), [4])
        XCTAssertTrue(requests.planIndices(for: .invalid).isEmpty)
    }

    func testIncrementalDiversityMatchesFullRecalculation() {
        for seed in 0..<16 {
            let frames = makeFrames(seed: UInt64(seed), count: 24)
            let scenes = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0.id / 7) })
            for count in [0, 1, 9, 16, 30] {
                XCTAssertEqual(
                    FrameSelection.selectStoryDiverse(from: frames, sceneIndexByID: scenes, count: count).map(\.id),
                    referenceSelection(frames, scenes: scenes, count: count).map(\.id),
                    "seed=\(seed), count=\(count)"
                )
            }
        }
    }

    func testFullSizeDiversityMatchesFullRecalculation() {
        let frames = makeFrames(seed: 42)
        let scenes = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0.id / 7) })
        XCTAssertEqual(
            FrameSelection.selectStoryDiverse(from: frames, sceneIndexByID: scenes, count: 64).map(\.id),
            referenceSelection(frames, scenes: scenes, count: 64).map(\.id)
        )
    }

    func testDiversityPreservesTiesAndDuplicateRemoval() {
        let original = makeFrames(seed: 4)[0]
        let duplicate = FrameDescriptor(
            id: 1000, time: original.time + 10, histogram: original.histogram,
            luminance: original.luminance, blackRatio: original.blackRatio,
            sharpness: original.sharpness, fingerprint: original.fingerprint, previewData: nil
        )
        let frames = [original, duplicate] + makeFrames(seed: 9, count: 24)
        XCTAssertEqual(
            FrameSelection.selectStoryDiverse(from: frames, sceneIndexByID: [:], count: 64).map(\.id),
            referenceSelection(frames, scenes: [:], count: 64).map(\.id)
        )
    }

    func testZeroOrNegativeEvenSpacingReturnsNoFrames() {
        let frames = makeFrames(seed: 1)
        XCTAssertTrue(FrameSelection.evenlySpaced(frames, count: 0).isEmpty)
        XCTAssertTrue(FrameSelection.evenlySpaced(frames, count: -1).isEmpty)
    }

    func testCancelledManualCaptureDoesNotOpenTheAsset() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ManualFrameExtractor.captureFrame(
                from: URL(fileURLWithPath: "/nonexistent/shotmap-cancelled-input.mov"),
                at: 1, identifier: 1
            )
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled capture must not return a frame")
        } catch is CancellationError {
            // Cancellation takes precedence over missing-file/codec errors.
        } catch {
            XCTFail("Expected cancellation, received \(error)")
        }
    }

    func testPresentationUpgradeRetainsEveryUnrefinedFrameInOrder() {
        let frames = (0..<9).map { CapturedFrame(id: $0, time: Double($0), jpegData: Data([$0 == 0 ? 0 : 1])) }
        XCTAssertEqual(
            VideoStoryboardAnalyzer.presentationUpgradeInputs(frames, refinedIDs: [1, 4, 8]).map(\.id),
            [0, 2, 3, 5, 6, 7]
        )
        XCTAssertEqual(VideoStoryboardAnalyzer.presentationUpgradeInputs(frames, refinedIDs: []).map(\.id), frames.map(\.id))
        XCTAssertTrue(VideoStoryboardAnalyzer.presentationUpgradeInputs(frames, refinedIDs: Set(frames.map(\.id))).isEmpty)
    }

    /// Run explicitly in release mode; timing is diagnostic, never a flaky CI
    /// assertion. This measures selection only, not video decode or export.
    func testSelectionMicrobenchmarkWhenRequested() {
        guard ProcessInfo.processInfo.environment["SHOTMAP_RUN_SELECTION_BENCHMARK"] == "1" else { return }
        let frames = makeFrames(seed: 42)
        let scenes = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0.id / 7) })
        let rounds = 50
        let oldStart = Date()
        var oldIDs: [Int] = []
        for _ in 0..<rounds { oldIDs = referenceSelection(frames, scenes: scenes, count: 64).map(\.id) }
        let oldDuration = Date().timeIntervalSince(oldStart)
        let newStart = Date()
        var newIDs: [Int] = []
        for _ in 0..<rounds {
            newIDs = FrameSelection.selectStoryDiverse(from: frames, sceneIndexByID: scenes, count: 64).map(\.id)
        }
        let newDuration = Date().timeIntervalSince(newStart)
        XCTAssertEqual(oldIDs, newIDs)
        print("SELECTION_BENCHMARK candidates=144 target=64 rounds=\(rounds) reference_s=\(oldDuration) incremental_s=\(newDuration)")
    }

    private func makeFrames(seed: UInt64, count: Int = 144) -> [FrameDescriptor] {
        var state = seed &+ 1
        func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
        return (0..<count).map { index in
            let bins = (0..<16).map { _ in Float(next() % 100 + 1) }
            let total = bins.reduce(0, +)
            return FrameDescriptor(
                id: index, time: Double(index) * 1.3,
                histogram: bins.map { $0 / total }, luminance: 0.45,
                blackRatio: 0.02, sharpness: Float(next() % 100) / 500 + 0.1,
                fingerprint: next(), previewData: nil
            )
        }
    }

    // Deliberately simple full-recalculation oracle for just the diversity
    // kernel. Scene detection, pool filtering and coverage are not duplicated.
    private func referenceSelection(_ frames: [FrameDescriptor], scenes: [Int: Int], count: Int) -> [FrameDescriptor] {
        let maxQuality = max(0.001, frames.map(\.qualityScore).max() ?? 0.001)
        var remaining = frames
        var selected: [FrameDescriptor] = []
        var sceneUses: [Int: Int] = [:]
        func utility(_ frame: FrameDescriptor) -> Float {
            let quality = frame.qualityScore / maxQuality
            guard !selected.isEmpty else { return quality }
            let novelty = selected.map {
                min(1, FrameSelection.histogramDistance(frame.histogram, $0.histogram) * 1.8
                    + Float(FrameSelection.hammingDistance(frame.fingerprint, $0.fingerprint)) / 64 * 0.45)
            }.min() ?? 1
            let uses = scenes[frame.id].map { sceneUses[$0, default: 0] } ?? 0
            let penalty: Float = uses == 0 ? 0 : (uses == 1 ? 0.10 : 0.22)
            return quality * 0.72 + novelty * 0.48 - penalty
        }
        while selected.count < count, let winner = remaining.max(by: { utility($0) < utility($1) }) {
            selected.append(winner)
            if let scene = scenes[winner.id] { sceneUses[scene, default: 0] += 1 }
            remaining.removeAll {
                let hamming = FrameSelection.hammingDistance($0.fingerprint, winner.fingerprint)
                return $0.id == winner.id || abs($0.time - winner.time) < 0.35 || hamming < 7
                    || (hamming < 18 && FrameSelection.histogramDistance($0.histogram, winner.histogram) < 0.035)
            }
        }
        return selected
    }
}
