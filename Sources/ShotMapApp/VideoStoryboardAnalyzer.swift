import CoreGraphics
import Foundation

/// Automatic selection owns a bounded decode/analyse/verify pipeline. The
/// manual editor keeps its independent exact-position capture behaviour.
struct VideoStoryboardAnalyzer: Sendable {
    func analyze(
        videoURL: URL,
        gridSide: Int,
        outputWidth: Int,
        progress: @escaping @Sendable (Double) -> Void,
        onPreviewFrame: @escaping @Sendable (CapturedFrame, Int, Int) async -> Void
    ) async throws -> StoryboardResult {
        try await AutomaticFramePipeline.run(
            videoURL: videoURL, gridSide: gridSide, outputWidth: outputWidth,
            progress: progress, onPreviewFrame: onPreviewFrame
        )
    }

    func analysisSampleCount(for targetCount: Int) -> Int {
        AutomaticFrameSamplingPolicy(duration: 0, targetCount: targetCount).initialCount
    }

    static func presentationUpgradeInputs(_ frames: [CapturedFrame], refinedIDs: Set<Int>) -> [CapturedFrame] {
        frames.filter { !refinedIDs.contains($0.id) }
    }
}

/// Compact visual metrics shared by automatic analysis and manual candidate
/// selection. They remain low-resolution so interactive selection stays fast.
struct PixelMetrics {
    let histogram: [Float]
    let luminance: Float
    let blackRatio: Float
    let brightRatio: Float
    let dominantToneRatio: Float
    let sharpness: Float
    /// Dissolves and motion trails have lots of weak edges; this tells them
    /// apart from decisive, in-focus boundaries.
    let focusedEdgeRatio: Float
    /// A secondary cue for washed-out dissolves and flash frames.
    let contrast: Float
    let fingerprint: UInt64

    static func make(from image: CGImage) -> PixelMetrics {
        let size = 48
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &bytes,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return PixelMetrics(
                histogram: Array(repeating: 0, count: 16),
                luminance: 0,
                blackRatio: 1,
                brightRatio: 0,
                dominantToneRatio: 1,
                sharpness: 0,
                focusedEdgeRatio: 0,
                contrast: 0,
                fingerprint: 0
            )
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        var luminance = [Float](repeating: 0, count: size * size)
        var histogram = [Float](repeating: 0, count: 16)
        var blackPixels = 0
        var brightPixels = 0
        var sum: Float = 0
        for pixel in 0..<(size * size) {
            let offset = pixel * 4
            let value = (0.2126 * Float(bytes[offset]) + 0.7152 * Float(bytes[offset + 1]) + 0.0722 * Float(bytes[offset + 2])) / 255
            luminance[pixel] = value
            sum += value
            if value < 0.055 { blackPixels += 1 }
            if value > 0.92 { brightPixels += 1 }
            histogram[min(15, Int(value * 16))] += 1
        }
        histogram = histogram.map { $0 / Float(size * size) }

        var edgeEnergy: Float = 0
        var focusedEdgeEnergy: Float = 0
        for y in 1..<(size - 1) {
            for x in 1..<(size - 1) {
                let center = luminance[y * size + x]
                let laplacian = abs(4 * center - luminance[y * size + x - 1] - luminance[y * size + x + 1] - luminance[(y - 1) * size + x] - luminance[(y + 1) * size + x])
                edgeEnergy += laplacian
                if laplacian >= 0.18 { focusedEdgeEnergy += laplacian }
            }
        }

        let average = sum / Float(size * size)
        let variance = luminance.reduce(Float.zero) { partial, value in
            let delta = value - average
            return partial + delta * delta
        } / Float(size * size)
        let fingerprint = averageHash(luminance)
        return PixelMetrics(
            histogram: histogram,
            luminance: average,
            blackRatio: Float(blackPixels) / Float(size * size),
            brightRatio: Float(brightPixels) / Float(size * size),
            dominantToneRatio: histogram.max() ?? 1,
            sharpness: edgeEnergy / Float((size - 2) * (size - 2)),
            focusedEdgeRatio: edgeEnergy > 0 ? focusedEdgeEnergy / edgeEnergy : 0,
            contrast: sqrt(variance),
            fingerprint: fingerprint
        )
    }

    private static func averageHash(_ luminance: [Float]) -> UInt64 {
        let sourceSize = 48
        let hashSize = 8
        var reduced = [Float](repeating: 0, count: hashSize * hashSize)
        for y in 0..<hashSize {
            for x in 0..<hashSize {
                var sum: Float = 0
                for sourceY in (y * 6)..<((y + 1) * 6) {
                    for sourceX in (x * 6)..<((x + 1) * 6) {
                        sum += luminance[sourceY * sourceSize + sourceX]
                    }
                }
                reduced[y * hashSize + x] = sum / 36
            }
        }
        let mean = reduced.reduce(0, +) / Float(reduced.count)
        return reduced.enumerated().reduce(into: UInt64(0)) { hash, element in
            if element.element >= mean { hash |= UInt64(1) << UInt64(element.offset) }
        }
    }
}
