import CoreGraphics
import CWebP
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
        if format == .webp { return webpData(from: image) }
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

    /// WebP's encoder consumes packed RGBA; draw into a known sRGB bitmap
    /// rather than relying on the source image's byte layout or color space.
    private static func webpData(from image: CGImage) -> Data? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= 16_383, height <= 16_383,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let bytes = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var output: UnsafeMutablePointer<UInt8>?
        let count = WebPEncodeRGBA(bytes.assumingMemoryBound(to: UInt8.self), Int32(width), Int32(height), Int32(width * 4), 85, &output)
        guard count > 0, let output else { return nil }
        defer { WebPFree(output) }
        return Data(bytes: output, count: count)
    }

    static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func thumbnail(from data: Data, maximumPixelSize: Int = 1_280) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return nil }
        return thumbnail(from: source, maximumPixelSize: maximumPixelSize)
    }

    static func thumbnail(at url: URL, maximumPixelSize: Int = 1_280) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return nil }
        return thumbnail(from: source, maximumPixelSize: maximumPixelSize)
    }

    private static func thumbnail(from source: CGImageSource, maximumPixelSize: Int) -> CGImage? {
        // Decode only the requested thumbnail, eagerly. The source must not
        // retain a full-size decoded export while a small preview is displayed.
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maximumPixelSize),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}
