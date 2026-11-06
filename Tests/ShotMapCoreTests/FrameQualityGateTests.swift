import CoreGraphics
import Accelerate
import CoreText
import XCTest
@testable import ShotMapApp

final class FrameQualityGateTests: XCTestCase {
    func testSolidWhiteBlackAndGrayAreRejectedFromActualPixels() throws {
        for level: CGFloat in [0, 0.5, 1] {
            let image = try makeImage { context in
                context.setFillColor(gray: level, alpha: 1)
                context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
            }
            let audit = FrameQualityAnalyzer.assess(image: image)
            XCTAssertEqual(audit.state, .observed)
            XCTAssertEqual(audit.rejection, .blank)
        }
    }

    func testSmallLogoRemainsUncertainUntilTextConfirmsCard() throws {
        let image = try makeImage { context in
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 290, y: 165, width: 60, height: 30))
        }
        let audit = FrameQualityAnalyzer.assess(image: image)
        XCTAssertNil(audit.rejection, "A sparse object is not proof of an empty/title image.")
        XCTAssertTrue(audit.isSparseGraphic)
        var descriptor = frame(0)
        descriptor.qualityEvidence = audit
        descriptor.textObservationState = .observed
        descriptor.textOverlayScore = 0.9
        XCTAssertEqual(descriptor.qualityRejection, .titleCard)
        XCTAssertTrue(FrameSelection.chooseFrames(from: [descriptor], count: 9).isEmpty)
    }

    func testAlmostBlankWhiteWithTinyFaintLogoIsNotAUsefulFrame() throws {
        let image = try makeImage { context in
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
            context.setFillColor(gray: 0.9, alpha: 1)
            context.fill(CGRect(x: 310, y: 175, width: 20, height: 10))
        }
        XCTAssertEqual(FrameQualityAnalyzer.assess(image: image).rejection, .blank)
    }

    func testBroadContrastWithOnlyBlurredRampsIsRejectedWithoutReference() throws {
        let patterned = try checkerImage()
        let original = try makeImage { context in
            context.draw(patterned, in: CGRect(x: 0, y: 0, width: 640, height: 360))
            context.setFillColor(gray: 0.08, alpha: 1)
            context.fill(CGRect(x: 120, y: 100, width: 400, height: 160))
        }
        let image = try blurredImage(original, radius: 14)
        let evidence = FrameQualityAnalyzer.assess(image: image)
        XCTAssertEqual(evidence.rejection, .severelyBlurred)
        var descriptor = frame(0)
        descriptor.qualityEvidence = evidence
        XCTAssertTrue(FrameSelection.chooseFrames(from: [descriptor], count: 9).isEmpty)
    }

    func testLowContrastFogAndSnowGradientRemainEligible() throws {
        let image = try makeImage { context in
            for x in 0..<640 {
                let level = 0.88 + 0.06 * sin(Double(x) / 180)
                context.setFillColor(gray: level, alpha: 1)
                context.fill(CGRect(x: x, y: 0, width: 1, height: 360))
            }
        }
        let evidence = FrameQualityAnalyzer.assess(image: image)
        XCTAssertNil(evidence.rejection)
    }

    func testEveryConfirmedTitleRemainsRejectedWhenGridIsIncomplete() {
        let frames = (0..<9).map { index -> FrameDescriptor in
            var descriptor = frame(index)
            descriptor.textOverlayScore = 0.9
            descriptor.textObservationState = .observed
            descriptor.peopleScore = 1
            descriptor.faceScore = 1
            return descriptor
        }
        XCTAssertTrue(FrameSelection.chooseFrames(from: frames, count: 9).isEmpty)
    }

    func testPersonBonusCannotReviveConfirmedBlankOrSevereBlur() throws {
        let blank = FrameQualityAnalyzer.assess(image: try makeImage { context in
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
        })
        for reason in [FrameQualityRejection.blank, .severelyBlurred] {
            var descriptor = frame(0)
            var audit = blank
            audit.rejection = reason
            descriptor.qualityEvidence = audit
            descriptor.faceScore = 1
            descriptor.bodyScore = 1
            descriptor.peopleScore = 1
            XCTAssertFalse(descriptor.isUsable)
            XCTAssertTrue(FrameSelection.chooseFrames(from: [descriptor], count: 9).isEmpty)
        }
    }

    func testDarkSceneAndLetterboxKeepTheirRealContent() throws {
        let image = try makeImage { context in
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
            context.setFillColor(gray: 0.03, alpha: 1)
            context.fill(CGRect(x: 0, y: 50, width: 640, height: 260))
            context.setFillColor(gray: 0.22, alpha: 1)
            context.fill(CGRect(x: 270, y: 90, width: 100, height: 180))
        }
        let audit = FrameQualityAnalyzer.assess(image: image)
        XCTAssertNil(audit.rejection)
        XCTAssertLessThan(audit.activeContentRect.height, 0.9)
        XCTAssertGreaterThan(audit.activeContentRect.height, 0.6)
        var descriptor = frame(0, blackRatio: 0.95)
        descriptor.qualityEvidence = audit
        XCTAssertTrue(descriptor.isUsable, "Old full-frame darkness must not override active-area evidence.")
    }

    func testSubjectFocusIsNotHiddenBySharpBackground() throws {
        let crisp = try checkerImage()
        let blurred = try blurredImage(crisp, radius: 12)
        let mixed = try makeImage { context in
            context.saveGState()
            context.clip(to: CGRect(x: 0, y: 0, width: 320, height: 360))
            context.draw(crisp, in: CGRect(x: 0, y: 0, width: 640, height: 360))
            context.restoreGState()
            context.clip(to: CGRect(x: 320, y: 0, width: 320, height: 360))
            context.draw(blurred, in: CGRect(x: 0, y: 0, width: 640, height: 360))
        }
        let region = CGRect(x: 0.55, y: 0.1, width: 0.4, height: 0.8)
        let audit = FrameQualityAnalyzer.assess(image: mixed, subjectRegions: [region])
        let subjectFocus = try XCTUnwrap(audit.subjectFocusScore)
        XCTAssertLessThan(subjectFocus, audit.focusScore * 0.5)
        let reference = FrameQualityAnalyzer.assess(image: crisp, subjectRegions: [region])
        XCTAssertEqual(audit.rejectingSevereBlur(comparedWith: reference).rejection, .severelyBlurred)
        XCTAssertNil(audit.rejection, "Single-frame uncertainty must not silently become a blur claim.")
    }

    func testSharpSubjectAllowsBlurredBackground() throws {
        let crisp = try checkerImage()
        let blurred = try blurredImage(crisp, radius: 12)
        let image = try makeImage { context in
            context.draw(blurred, in: CGRect(x: 0, y: 0, width: 640, height: 360))
            context.clip(to: CGRect(x: 200, y: 60, width: 240, height: 240))
            context.draw(crisp, in: CGRect(x: 0, y: 0, width: 640, height: 360))
        }
        let subject = CGRect(x: 0.34, y: 0.2, width: 0.30, height: 0.6)
        let audit = FrameQualityAnalyzer.assess(image: image, subjectRegions: [subject])
        let reference = FrameQualityAnalyzer.assess(image: crisp, subjectRegions: [subject])
        XCTAssertGreaterThan(try XCTUnwrap(audit.subjectFocusScore), 0.4)
        XCTAssertNil(audit.rejectingSevereBlur(comparedWith: reference).rejection)
    }

    func testObservationFailureIsDifferentFromARealZeroObservation() {
        var untested = frame(0)
        XCTAssertEqual(untested.personObservationState, .notEvaluated)
        untested.personObservationState = .failed
        XCTAssertEqual(untested.peopleScore, 0)
        XCTAssertNotEqual(untested.personObservationState, .observed)
        untested.personObservationState = .observed
        XCTAssertEqual(untested.peopleScore, 0)
        XCTAssertEqual(untested.personObservationState, .observed)
    }

    func testDenseAlignedGlyphRowsRequestInspectionWithoutHardRejection() throws {
        let image = try makeImage { context in
            context.setFillColor(gray: 0.12, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
            drawGlyphRows(in: context, rows: Array(stride(from: 36, to: 324, by: 12)))
        }
        let evidence = FrameQualityAnalyzer.assess(image: image)
        XCTAssertTrue(evidence.denseTextLayout)
        XCTAssertGreaterThanOrEqual(evidence.denseTextLayoutScore, 0.60)
        XCTAssertNil(evidence.rejection, "Row layout only schedules a better text check.")
    }

    func testTwoSubtitleRowsDoNotResembleDenseCredits() throws {
        let background = try checkerImage()
        let image = try makeImage { context in
            context.draw(background, in: CGRect(x: 0, y: 0, width: 640, height: 360))
            context.setFillColor(gray: 0.10, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 50))
            drawGlyphRows(in: context, rows: [12, 28])
        }
        let evidence = FrameQualityAnalyzer.assess(image: image)
        XCTAssertFalse(evidence.denseTextLayout)
        XCTAssertNil(evidence.rejection)
    }

    func testSubjectDetailUsesOriginalPixelsAndDoesNotUpsampleTinyFaces() throws {
        let image = try checkerImage()
        let region = CGRect(x: 0.2, y: 0.2, width: 0.075, height: 0.15)
        let evidence = FrameQualityAnalyzer.assess(image: image, subjectRegions: [region])
        XCTAssertNotNil(evidence.subjectDetailScore)
        XCTAssertGreaterThan(evidence.subjectSamplePixelCount, 2_000,
                             "The original 48×54 crop must retain pixels lost in a full-image 320px reduction.")
        let tiny = FrameQualityAnalyzer.assess(image: image,
            subjectRegions: [CGRect(x: 0.2, y: 0.2, width: 0.02, height: 0.03)])
        XCTAssertNil(tiny.subjectDetailScore, "Upsampling cannot turn a tiny uncertain detection into reliable facial detail.")
        XCTAssertEqual(tiny.subjectSamplePixelCount, 0)
    }

    func testOriginalSubjectCropConvertsVisionBottomLeftCoordinatesWithoutVerticalFlip() throws {
        let width = 640, height = 360
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        // CGImage's first pixel rows are the top of the image. Construct the
        // storage explicitly so CGContext drawing transforms cannot mask an
        // accidentally inverted Vision-to-CGImage crop.
        for y in 0..<height {
            for x in 0..<width {
                let value: UInt8 = y < height / 2 ? ((x / 8 + y / 8).isMultiple(of: 2) ? 35 : 220) : 115
                let offset = (y * width + x) * 4
                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let upper = FrameQualityAnalyzer.assess(image: image,
            subjectRegions: [CGRect(x: 0.10, y: 0.62, width: 0.80, height: 0.28)])
        let lower = FrameQualityAnalyzer.assess(image: image,
            subjectRegions: [CGRect(x: 0.10, y: 0.10, width: 0.80, height: 0.28)])
        let upperDetail = try XCTUnwrap(upper.subjectDetailScore)
        let lowerDetail = try XCTUnwrap(lower.subjectDetailScore)
        XCTAssertGreaterThan(upperDetail, lowerDetail + 0.30,
                             "The upper Vision box must sample the textured top, not the smooth bottom.")
        XCTAssertLessThan(lowerDetail, 0.01)
        XCTAssertEqual(upper.subjectSamplePixelCount, lower.subjectSamplePixelCount)
    }

    func testMeasuredSubjectReadabilityOutranksFaceAreaAndSharpBackground() {
        var softLargeFace = frame(0)
        softLargeFace.faceScore = 1
        softLargeFace.qualityEvidence = evidenceForRanking(global: 1, subject: 0.15)
        var clearSmallerFace = frame(1)
        clearSmallerFace.faceScore = 0.6
        clearSmallerFace.qualityEvidence = evidenceForRanking(global: 0.7, subject: 0.75)
        XCTAssertGreaterThan(clearSmallerFace.qualityScore, softLargeFace.qualityScore)
        XCTAssertTrue(softLargeFace.isUsable, "Relative softness is a ranking preference, not a new eligibility rule.")
        XCTAssertTrue(clearSmallerFace.isUsable)
    }

    private func evidenceForRanking(global: Float, subject: Float) -> FrameQualityEvidence {
        var evidence = FrameQualityEvidence(rejection: nil,
            activeContentRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            focusScore: global, subjectFocusScore: subject, contrast: 0.2,
            edgeCoverage: 0.2, informationFraction: 1, isSparseGraphic: false)
        evidence.subjectDetailScore = subject
        evidence.subjectSamplePixelCount = 1_600
        return evidence
    }

    private func drawGlyphRows(in context: CGContext, rows: [Int]) {
        // Use actual rasterized glyphs. Equal-height filled rectangles become
        // broad grid bands after downsampling, not the ink profile of tiny text.
        let font = CTFontCreateWithName("Helvetica" as CFString, 9, nil)
        let attributes = [kCTFontAttributeName: font,
                          kCTForegroundColorAttributeName: CGColor(gray: 0.9, alpha: 1)] as CFDictionary
        for y in rows {
            let text = CFAttributedStringCreate(nil,
                "Alex Brown • Jordan Lee • Morgan Taylor • Robin Clark • Casey Smith • Sam White • Avery King • Jamie Scott" as CFString, attributes)!
            context.textPosition = CGPoint(x: 72, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }
    }

    private func frame(_ index: Int, blackRatio: Float = 0.02) -> FrameDescriptor {
        FrameDescriptor(id: index, time: Double(index), histogram: [0.4, 0.6], luminance: 0.5,
            blackRatio: blackRatio, sharpness: 0.2, fingerprint: UInt64(index), previewData: nil)
    }

    private func makeImage(_ draw: (CGContext) -> Void) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 360, bitsPerComponent: 8,
            bytesPerRow: 640 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        draw(context)
        return try XCTUnwrap(context.makeImage())
    }

    private func checkerImage() throws -> CGImage {
        try makeImage { context in
            for y in stride(from: 0, to: 360, by: 16) {
                for x in stride(from: 0, to: 640, by: 16) {
                    context.setFillColor(gray: (x / 16 + y / 16).isMultiple(of: 2) ? 0.15 : 0.85, alpha: 1)
                    context.fill(CGRect(x: x, y: y, width: 16, height: 16))
                }
            }
        }
    }

    private func blurredImage(_ image: CGImage, radius: Double) throws -> CGImage {
        // The fixture must not depend on a Core Image/OpenCL device. Under
        // Rosetta that renderer can return an all-black image without throwing,
        // turning a blur assertion into a test of an unavailable graphics path.
        // Three CPU box passes produce a broad, approximately Gaussian ramp.
        let width = image.width, height = image.height, rowBytes = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: rowBytes, space: colorSpace, bitmapInfo: bitmapInfo))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let sourceData = try XCTUnwrap(context.data)
        let scratch = UnsafeMutableRawPointer.allocate(byteCount: rowBytes * height, alignment: 64)
        defer { scratch.deallocate() }
        var source = vImage_Buffer(data: sourceData, height: vImagePixelCount(height),
            width: vImagePixelCount(width), rowBytes: rowBytes)
        var destination = vImage_Buffer(data: scratch, height: source.height, width: source.width, rowBytes: rowBytes)
        let kernel = UInt32(max(3, Int((radius * 2).rounded()) | 1))
        for _ in 0..<3 {
            let status = vImageBoxConvolve_ARGB8888(&source, &destination, nil, 0, 0,
                kernel, kernel, nil, vImage_Flags(kvImageEdgeExtend))
            XCTAssertEqual(status, kvImageNoError)
            guard status == kvImageNoError else { throw NSError(domain: "BlurFixture", code: Int(status)) }
            swap(&source, &destination)
        }
        let data = Data(bytes: source.data, count: rowBytes * height)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: rowBytes, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}
