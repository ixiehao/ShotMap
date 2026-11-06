import AVFoundation
import CoreGraphics

/// The shared native decode boundary for both arm64 and x86_64 builds.
/// AVFoundation chooses the decoder supported by the actual codec and Mac;
/// architecture is not a reason to lower resolution or relax exact seeking.
enum MediaImageGenerator {
    static func make(
        asset: AVAsset,
        maximumEdge: CGFloat,
        tolerance: CMTime = .zero
    ) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumEdge, height: maximumEdge)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        return generator
    }
}
