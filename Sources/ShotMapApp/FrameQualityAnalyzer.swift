import Accelerate
import CoreGraphics
import Foundation

enum FrameEvidenceState: String, Sendable {
    case notEvaluated, observed, failed
}

enum FrameQualityRejection: String, Sendable {
    case blank, titleCard, severelyBlurred
}

/// Values describe the audited image, never a JPEG or a different seek result.
struct FrameQualityEvidence: Sendable {
    var state: FrameEvidenceState = .observed
    var rejection: FrameQualityRejection?
    /// Vision coordinates: normalized, origin at the bottom-left.
    let activeContentRect: CGRect
    let focusScore: Float
    let subjectFocusScore: Float?
    let contrast: Float
    let edgeCoverage: Float
    let informationFraction: Float
    let isSparseGraphic: Bool
    /// Curvature relative to edge energy separates a sharp sparse contour from
    /// broad, washed-out edge ramps. This is not a semantic or aesthetic score.
    var edgeAcuity: Float = 0
    /// A language-independent layout warning, never a title-card rejection.
    /// Small repeated glyph rows can disappear in low-resolution Vision input.
    var denseTextLayout: Bool = false
    var denseTextLayoutScore: Float = 0
    /// Ranking-only detail from the original subject crop, preserving pixels
    /// that would disappear when the complete image is reduced to 320 px.
    /// Existing eligibility evidence deliberately keeps its established scale.
    var subjectDetailScore: Float? = nil
    var subjectSamplePixelCount: Int = 0

    /// The caller must establish the same local shot and corresponding subject.
    /// Low detail alone cannot distinguish defocus from a wall, snow or fog.
    func rejectingSevereBlur(comparedWith reference: FrameQualityEvidence) -> FrameQualityEvidence {
        guard state == .observed, reference.state == .observed,
              rejection == nil, reference.rejection == nil else { return self }
        let candidateFocus: Float
        let referenceFocus: Float
        if let subjectFocusScore, let referenceSubjectFocus = reference.subjectFocusScore {
            candidateFocus = subjectFocusScore
            referenceFocus = referenceSubjectFocus
        } else if subjectFocusScore == nil, reference.subjectFocusScore == nil {
            candidateFocus = focusScore
            referenceFocus = reference.focusScore
        } else {
            return self
        }
        guard referenceFocus >= 0.40, candidateFocus < 0.12,
              candidateFocus < referenceFocus * 0.18 else { return self }
        var rejected = self
        rejected.rejection = .severelyBlurred
        return rejected
    }
}

/// Small, aspect-preserving gray planes keep the first quality pass inexpensive.
/// vImage convolutions use CPU vector implementations on both Mac architectures.
enum FrameQualityAnalyzer {
    static func assess(image: CGImage, subjectRegions: [CGRect] = []) -> FrameQualityEvidence {
        guard let plane = grayPlane(image: image, maximumEdge: 320) else {
            // A failed analysis is not proof of blank content. The decoder owns
            // retry/error handling; leave this image uncertain rather than fake
            // a positive or negative observation.
            var failed = FrameQualityEvidence(rejection: nil, activeContentRect: CGRect(x: 0, y: 0, width: 1, height: 1), focusScore: 0,
                subjectFocusScore: nil, contrast: 0, edgeCoverage: 0, informationFraction: 0, isSparseGraphic: false)
            failed.state = .failed
            return failed
        }
        let active = activeArea(in: plane)
        let content = plane.cropped(to: active)
        let metrics = measurements(in: content)
        let normalizedRect = CGRect(x: CGFloat(active.minX) / CGFloat(plane.width),
            y: 1 - CGFloat(active.maxY) / CGFloat(plane.height),
            width: CGFloat(active.width) / CGFloat(plane.width), height: CGFloat(active.height) / CGFloat(plane.height))
        let subjects = subjectRegions.prefix(4).compactMap { region -> Measurements? in
            guard region.origin.x.isFinite, region.origin.y.isFinite,
                  region.width.isFinite, region.height.isFinite,
                  region.width > 0, region.height > 0 else { return nil }
            let clipped = region.standardized.intersection(normalizedRect)
            guard !clipped.isNull, clipped.width.isFinite, clipped.height.isFinite,
                  clipped.width > 0, clipped.height > 0 else { return nil }
            let pixels = CGRect(x: clipped.minX * CGFloat(plane.width),
                y: (1 - clipped.maxY) * CGFloat(plane.height),
                width: clipped.width * CGFloat(plane.width), height: clipped.height * CGFloat(plane.height)).integral
            guard pixels.width >= 12, pixels.height >= 12 else { return nil }
            return measurements(in: plane.cropped(to: pixels))
        }
        // Only overwhelmingly uniform, edgeless content is a blank image.
        // Tiny high-contrast logos remain uncertain graphics for text analysis.
        let blank = subjects.isEmpty && metrics.contrast < 0.009
            && metrics.dynamicRange < 0.025 && metrics.edgeCoverage < 0.006
            && metrics.information <= 0.10
        let principal = subjects.max { $0.focus < $1.focus } ?? metrics
        // Strong scene contrast spread across the image, but only broad edge
        // ramps and almost no decisive contours, is positive blur evidence.
        // Flat fog/snow has insufficient contrast; an isolated sharp subject or
        // a clean contour has sufficient acuity and remains eligible.
        let broadBlur = principal.contrast > 0.09 && principal.dynamicRange > 0.22
            && principal.focus < 0.09 && principal.edgeAcuity < 0.24
            && principal.meanGradient > 0.0015 && principal.gradientBalance > 0.18
            && principal.strongEdgeFraction < 0.025
            && principal.information > 0.35
        var evidence = FrameQualityEvidence(rejection: blank ? .blank : (broadBlur ? .severelyBlurred : nil), activeContentRect: normalizedRect,
            focusScore: metrics.focus, subjectFocusScore: subjects.map(\.focus).max(), contrast: metrics.contrast,
            edgeCoverage: metrics.edgeCoverage, informationFraction: metrics.information,
            isSparseGraphic: metrics.dominantRatio > 0.86 && metrics.information < 0.30)
        evidence.edgeAcuity = principal.edgeAcuity
        evidence.denseTextLayoutScore = denseTextLayoutRisk(in: content)
        evidence.denseTextLayout = evidence.denseTextLayoutScore >= 0.60
        let subjectDetails = subjectRegions.prefix(4).compactMap { region -> (score: Float, pixels: Int)? in
            guard region.origin.x.isFinite, region.origin.y.isFinite,
                  region.width.isFinite, region.height.isFinite,
                  region.width > 0, region.height > 0 else { return nil }
            let clipped = region.intersection(normalizedRect)
            guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
            let rectangle = CGRect(x: clipped.minX * CGFloat(image.width),
                y: (1 - clipped.maxY) * CGFloat(image.height),
                width: clipped.width * CGFloat(image.width), height: clipped.height * CGFloat(image.height)).integral
            guard rectangle.width >= 24, rectangle.height >= 24,
                  let crop = image.cropping(to: rectangle),
                  let subject = grayPlane(image: crop, maximumEdge: 160) else { return nil }
            return (measurements(in: subject).focus, subject.width * subject.height)
        }
        if let subject = subjectDetails.max(by: { $0.score < $1.score }) {
            evidence.subjectDetailScore = subject.score
            evidence.subjectSamplePixelCount = subject.pixels
        }
        return evidence
    }

    /// Repeated broad, horizontally aligned bands suggest a dense text block.
    /// Ordinary subtitles occupy too little vertical space to qualify. Facades
    /// can share this layout, so the result only schedules a bounded HD check.
    private static func denseTextLayoutRisk(in plane: GrayPlane) -> Float {
        guard plane.width >= 48, plane.height >= 48 else { return 0 }
        let left = max(1, plane.width / 10), right = min(plane.width - 1, plane.width * 95 / 100)
        let lastRow = min(plane.height - 2, plane.height * 78 / 100)
        guard right > left + 16, lastRow > 8 else { return 0 }
        var rowEnergy = [Float](repeating: 0, count: plane.height)
        var spans = [Float](repeating: 0, count: plane.height)
        for y in 0..<plane.height {
            var total: Float = 0
            var first: Int?, last = 0
            for x in left..<right {
                let delta = abs(plane.values[y * plane.width + x] - plane.values[y * plane.width + x - 1])
                total += delta
                if delta > 0.08 {
                    if first == nil { first = x }
                    last = x
                }
            }
            rowEnergy[y] = total / Float(right - left)
            if let first { spans[y] = Float(last - first) / Float(plane.width) }
        }
        var peaks: [Int] = []
        for y in 2..<lastRow where rowEnergy[y] > 0.018 && spans[y] > 0.45 {
            guard rowEnergy[y] > rowEnergy[y - 1] * 1.08,
                  rowEnergy[y] >= rowEnergy[y + 1] * 1.08 else { continue }
            if let previous = peaks.last, y - previous < 2 {
                if rowEnergy[y] > rowEnergy[previous] { peaks[peaks.count - 1] = y }
            } else {
                peaks.append(y)
            }
        }
        guard peaks.count >= 7, let first = peaks.first, let last = peaks.last,
              last - first >= plane.height / 4 else { return 0 }
        let gaps = zip(peaks.dropFirst(), peaks).map { $0 - $1 }
        let ordered = gaps.sorted()
        let period = ordered[ordered.count / 2]
        guard period >= 2, period <= max(4, plane.height / 10) else { return 0 }
        let repeating = gaps.filter { abs($0 - period) <= 1 || abs($0 - period * 2) <= 1 }.count
        let regularity = Float(repeating) / Float(gaps.count)
        guard regularity >= 0.55 else { return 0 }
        return min(1, Float(peaks.count) / 10) * 0.45
            + min(1, Float(last - first) / Float(plane.height) / 0.50) * 0.20
            + regularity * 0.35
    }

    private struct GrayPlane {
        let width: Int
        let height: Int
        let values: [Float]

        func cropped(to rectangle: CGRect) -> GrayPlane {
            let x = max(0, min(width - 1, Int(rectangle.minX)))
            let y = max(0, min(height - 1, Int(rectangle.minY)))
            let right = max(x + 1, min(width, Int(rectangle.maxX)))
            let bottom = max(y + 1, min(height, Int(rectangle.maxY)))
            var output: [Float] = []
            output.reserveCapacity((right - x) * (bottom - y))
            for row in y..<bottom { output.append(contentsOf: values[(row * width + x)..<(row * width + right)]) }
            return GrayPlane(width: right - x, height: bottom - y, values: output)
        }
    }

    private static func grayPlane(image: CGImage, maximumEdge: Int) -> GrayPlane? {
        let scale = min(1, CGFloat(maximumEdge) / CGFloat(max(image.width, image.height)))
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        var bytes = [UInt8](repeating: 0, count: width * height)
        let drawn = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return GrayPlane(width: width, height: height, values: bytes.map { Float($0) / 255 })
    }

    /// Crop only paired, nearly equal, uniform black borders. A single dark
    /// edge is insufficient evidence. Cap trimming to preserve composition.
    private static func activeArea(in plane: GrayPlane) -> CGRect {
        let width = plane.width, height = plane.height
        guard width >= 32, height >= 32 else { return CGRect(x: 0, y: 0, width: width, height: height) }
        func dark(_ values: [Float]) -> Bool {
            guard let maximum = values.max(), let minimum = values.min() else { return false }
            return maximum <= 0.025 && maximum - minimum <= 0.012
        }
        let maxRows = height / 5, maxColumns = width / 5
        func row(_ y: Int) -> [Float] { Array(plane.values[(y * width)..<((y + 1) * width)]) }
        func column(_ x: Int) -> [Float] { (0..<height).map { plane.values[$0 * width + x] } }
        let top = (0..<maxRows).prefix(while: { dark(row($0)) }).count
        let bottom = (0..<maxRows).prefix(while: { dark(row(height - 1 - $0)) }).count
        let left = (0..<maxColumns).prefix(while: { dark(column($0)) }).count
        let right = (0..<maxColumns).prefix(while: { dark(column(width - 1 - $0)) }).count
        let vertical = top >= 2 && bottom >= 2 && abs(top - bottom) <= max(2, height / 30)
        let horizontal = left >= 2 && right >= 2 && abs(left - right) <= max(2, width / 30)
        let x = horizontal ? left : 0, y = vertical ? top : 0
        return CGRect(x: x, y: y, width: width - (horizontal ? left + right : 0), height: height - (vertical ? top + bottom : 0))
    }

    private struct Measurements {
        let contrast: Float
        let dynamicRange: Float
        let edgeCoverage: Float
        let information: Float
        let dominantRatio: Float
        let focus: Float
        let edgeAcuity: Float
        let strongEdgeFraction: Float
        let meanGradient: Float
        let gradientBalance: Float
    }

    private static func measurements(in plane: GrayPlane) -> Measurements {
        let values = plane.values
        var mean: Float = 0, meanSquare: Float = 0
        vDSP_meanv(values, 1, &mean, vDSP_Length(values.count))
        vDSP_measqv(values, 1, &meanSquare, vDSP_Length(values.count))
        let contrast = sqrt(max(0, meanSquare - mean * mean))
        var histogram = [Int](repeating: 0, count: 64)
        for value in values { histogram[min(63, max(0, Int(value * 64)))] += 1 }
        func percentile(_ fraction: Float) -> Float {
            let target = max(1, Int(Float(values.count) * fraction))
            var sum = 0
            for (index, count) in histogram.enumerated() {
                sum += count
                if sum >= target { return Float(index) / 63 }
            }
            return 1
        }
        // Suppress 8-bit quantization/JPEG ringing before judging edge width;
        // otherwise a broad blurred ramp can appear to have sharp micro-steps.
        let edgePlane = GrayPlane(width: plane.width, height: plane.height,
            values: convolved(plane, kernel: [1, 2, 1, 2, 4, 2, 1, 2, 1].map { Float($0) / 16 }))
        let gradients = convolved(edgePlane, kernel: [-1, 0, 1, -2, 0, 2, -1, 0, 1].map { Float($0) / 8 })
        let vertical = convolved(edgePlane, kernel: [-1, -2, -1, 0, 0, 0, 1, 2, 1].map { Float($0) / 8 })
        let laplacian = convolved(plane, kernel: [0, -1, 0, -1, 4, -1, 0, -1, 0])
        let edgeLaplacian = convolved(edgePlane, kernel: [0, -1, 0, -1, 4, -1, 0, -1, 0])
        var edges = 0, strongEdges = 0, detail: Float = 0, curvature: Float = 0, gradientEnergy: Float = 0
        var horizontalEnergy: Float = 0, verticalEnergy: Float = 0
        for index in values.indices {
            let magnitude = abs(gradients[index]) + abs(vertical[index])
            if magnitude >= 0.035 { edges += 1 }
            if magnitude >= 0.10 { strongEdges += 1 }
            gradientEnergy += magnitude
            horizontalEnergy += abs(gradients[index])
            verticalEnergy += abs(vertical[index])
            curvature += abs(edgeLaplacian[index])
            detail += min(0.5, abs(laplacian[index]))
        }
        let edgeCoverage = Float(edges) / Float(max(1, values.count))
        // Require information across spatial cells, not a single sharp subtitle.
        var informative = 0, cellCount = 0
        let columns = min(8, plane.width), rows = min(8, plane.height)
        for row in 0..<rows {
            for column in 0..<columns {
                let x0 = column * plane.width / columns, x1 = (column + 1) * plane.width / columns
                let y0 = row * plane.height / rows, y1 = (row + 1) * plane.height / rows
                var low: Float = 1, high: Float = 0
                for y in y0..<y1 { for x in x0..<x1 { let value = values[y * plane.width + x]; low = min(low, value); high = max(high, value) } }
                if high - low >= 0.045 { informative += 1 }
                cellCount += 1
            }
        }
        let information = Float(informative) / Float(max(1, cellCount))
        let halfWidth = max(1, plane.width / 2), halfHeight = max(1, plane.height / 2)
        var coarseValues = [Float](repeating: 0, count: halfWidth * halfHeight)
        for y in 0..<halfHeight { for x in 0..<halfWidth {
            let x0 = min(plane.width - 1, x * 2), x1 = min(plane.width - 1, x * 2 + 1)
            let y0 = min(plane.height - 1, y * 2), y1 = min(plane.height - 1, y * 2 + 1)
            coarseValues[y * halfWidth + x] = (values[y0 * plane.width + x0] + values[y0 * plane.width + x1]
                + values[y1 * plane.width + x0] + values[y1 * plane.width + x1]) * 0.25
        } }
        let coarse = GrayPlane(width: halfWidth, height: halfHeight, values: coarseValues)
        let coarseLaplacian = convolved(coarse, kernel: [0, -1, 0, -1, 4, -1, 0, -1, 0])
        let coarseDetail = coarseLaplacian.reduce(Float(0)) { $0 + min(0.5, abs($1)) } / Float(max(1, coarseValues.count))
        let focus = min(1, (detail / Float(max(1, values.count)) * 0.75 + coarseDetail * 0.25) / 0.10)
        return Measurements(contrast: contrast, dynamicRange: percentile(0.95) - percentile(0.05),
            edgeCoverage: edgeCoverage, information: information,
            dominantRatio: Float(histogram.max() ?? values.count) / Float(max(1, values.count)), focus: focus,
            edgeAcuity: curvature / max(0.0001, gradientEnergy), strongEdgeFraction: Float(strongEdges) / Float(max(1, edges)),
            meanGradient: gradientEnergy / Float(max(1, values.count)),
            gradientBalance: min(horizontalEnergy, verticalEnergy) / max(0.0001, max(horizontalEnergy, verticalEnergy)))
    }

    private static func convolved(_ plane: GrayPlane, kernel: [Float]) -> [Float] {
        var output = [Float](repeating: 0, count: plane.values.count)
        plane.values.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                var inputBuffer = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: source.baseAddress!),
                    height: vImagePixelCount(plane.height), width: vImagePixelCount(plane.width), rowBytes: plane.width * MemoryLayout<Float>.stride)
                var outputBuffer = vImage_Buffer(data: destination.baseAddress!, height: vImagePixelCount(plane.height),
                    width: vImagePixelCount(plane.width), rowBytes: plane.width * MemoryLayout<Float>.stride)
                _ = vImageConvolve_PlanarF(&inputBuffer, &outputBuffer, nil, 0, 0, kernel, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))
            }
        }
        return output
    }
}
