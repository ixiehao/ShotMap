import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Stateless ImageIO helpers used by detached analysis, selection, and export
/// tasks. Keeping background image work out of AppKit avoids main-thread image
/// objects and gives every path the same JPEG encoder/decoder behavior.
enum ImageCodec {
    static func jpegData(from image: CGImage, compressionQuality: CGFloat) -> Data? {
        data(from: image, format: .jpeg, jpegCompressionQuality: compressionQuality)
    }

    static func data(
        from image: CGImage,
        format: ExportFormat,
        jpegCompressionQuality: CGFloat = 0.94
    ) -> Data? {
        let destinationData = NSMutableData()
        let type: CFString = format == .png
            ? UTType.png.identifier as CFString
            : UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(destinationData, type, 1, nil) else {
            return nil
        }

        let properties: [CFString: Any] = format == .jpeg
            ? [kCGImageDestinationLossyCompressionQuality: jpegCompressionQuality]
            : [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return destinationData as Data
    }

    static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
