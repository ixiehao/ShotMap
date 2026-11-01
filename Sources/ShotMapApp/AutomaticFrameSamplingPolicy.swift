import AVFoundation
import Foundation

/// Budgets count submitted image requests, not the interdependent source frames
/// that AVFoundation may decode internally. All recovery rounds share one cap.
struct AutomaticFrameSamplingPolicy: Sendable {
    let duration: Double
    let targetCount: Int

    var initialCount: Int {
        let base = min(96, max(48, Int(ceil(Double(targetCount) * 1.5))))
        return duration >= 1_200 ? 96 : base
    }

    var additionalRequestLimit: Int { max(48, targetCount * 3) }
    var semanticRequestLimit: Int { max(48, targetCount * 4) }
    var finalReplacementLimit: Int { min(targetCount, 8) }
    var detailedTextRequestLimit: Int {
        if targetCount <= 9 { return 2 }
        if targetCount <= 16 { return 3 }
        return 6
    }

    func semanticStopCount(completed: Int, additionalLimit: Int) -> Int {
        let completed = min(semanticRequestLimit, max(0, completed))
        let remaining = semanticRequestLimit - completed
        return completed + min(remaining, max(0, additionalLimit))
    }

    var initialTimes: [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        return (0..<initialCount).map { (Double($0) + 0.5) * duration / Double(initialCount) }
    }

    /// A window is a search region, not a claimed shot. Three positions leave
    /// room to escape a long blur while keeping each recovery round bounded.
    func localTimes(around centre: Double, expansion: Int = 0) -> [Double] {
        let radius = min(1.5, max(0.25, duration / Double(initialCount) * 0.12)) * (expansion == 0 ? 1 : 2)
        return [-radius, 0, radius].map { min(max(0, centre + $0), max(0, duration - 0.001)) }
    }

    func coverageTimes(round: Int, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let phase = round == 0 ? 0.25 : 0.75
        return (0..<count).map { (Double($0) + phase) * duration / Double(count) }
    }
}

/// Rational identity preserves actual VFR timestamps instead of rounding them
/// into nominal frame-rate buckets or through a Double/600 timebase.
struct AutomaticFrameTimeKey: Hashable, Sendable {
    private let value: Int64
    private let scale: Int64
    private let epoch: Int64

    init?(_ time: CMTime) {
        guard time.isNumeric, time.timescale > 0, time.value != .min else { return nil }
        var a = abs(time.value)
        var b = Int64(time.timescale)
        while b != 0 { (a, b) = (b, a % b) }
        let divisor = max(1, a)
        value = time.value / divisor
        scale = Int64(time.timescale) / divisor
        epoch = time.epoch
    }
}

struct AutomaticFrameTimeRequest: Sendable {
    let id: Int
    let time: CMTime
}

enum AutomaticFrameExportGate {
    static func allows(
        quality: FrameEvidenceState?, person: FrameEvidenceState, text: FrameEvidenceState,
        usable: Bool, requiresDetailedText: Bool, detailedTextComplete: Bool
    ) -> Bool {
        quality == .observed && person == .observed && text == .observed && usable
            && (!requiresDetailedText || detailedTextComplete)
    }
}

/// AVAssetImageGenerator has legacy Sendable annotations in supported SDKs.
/// Only cancellation crosses executors; image consumption remains serial.
final class AutomaticGeneratorCancellation: @unchecked Sendable {
    let generator: AVAssetImageGenerator
    init(_ generator: AVAssetImageGenerator) { self.generator = generator }
    func cancel() { generator.cancelAllCGImageGeneration() }
}
