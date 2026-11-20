import AVFoundation
import AudioToolbox
import CoreGraphics
import Foundation

/// Metadata is advisory; missing fields never prevent an otherwise valid export.
struct VideoExportInfo: Sendable {
    let filename: String
    let fileSize: String?
    let resolution: String?
    let frameRate: String?
    let duration: String?
    var videoCodec: String? = nil
    var videoBitrate: String? = nil
    var audioCodec: String? = nil

    var firstLineSuffix: String {
        [duration, fileSize].compactMap { $0 }.map { "  ·  " + $0 }.joined()
    }

    var lines: [String] {
        let details = [resolution, frameRate, videoCodec, videoBitrate, audioCodec].compactMap { $0 }
        return [filename + firstLineSuffix] + (details.isEmpty ? [] : [details.joined(separator: "  ·  ")])
    }

    static func codecName(_ subtype: FourCharCode, video: Bool) -> String? {
        let bytes = (0..<4).map { UInt8((subtype >> (24 - $0 * 8)) & 0xff) }
        let code = String(bytes: bytes, encoding: .ascii)?.lowercased() ?? ""
        let names = video
            ? ["avc1": "H.264", "avc3": "H.264", "hvc1": "HEVC", "hev1": "HEVC", "av01": "AV1", "vp09": "VP9", "apch": "ProRes 422 HQ", "apcn": "ProRes 422", "apcs": "ProRes 422 LT", "apco": "ProRes 422 Proxy", "ap4h": "ProRes 4444", "ap4x": "ProRes 4444 XQ"]
            : ["mp4a": "MPEG-4 Audio", "aac ": "AAC", "aach": "HE-AAC", "aacp": "HE-AAC v2", "alac": "ALAC", "lpcm": "PCM", "sowt": "PCM", "twos": "PCM", "ac-3": "AC-3", "ec-3": "E-AC-3", "opus": "Opus", ".mp3": "MP3"]
        if let name = names[code] { return name }
        guard code.count == 4, bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }) else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }

    static func load(url: URL, duration: Double) async -> VideoExportInfo {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map {
            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
        }
        let asset = AVURLAsset(url: url)
        var resolution: String?
        var frameRate: String?
        var videoCodec: String?
        var videoBitrate: String?
        var audioCodec: String?
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            if let natural = try? await track.load(.naturalSize),
               let transform = try? await track.load(.preferredTransform) {
                let size = natural.applying(transform)
                let width = abs(size.width), height = abs(size.height)
                if width.isFinite, height.isFinite, width > 0, height > 0,
                   width < 100_000, height < 100_000 {
                    resolution = "\(Int(width.rounded())) × \(Int(height.rounded()))"
                }
            }
            if let rate = try? await track.load(.nominalFrameRate), rate.isFinite, rate > 0, rate < 1_000 {
                frameRate = String(format: "~%.2f fps", rate)
            }
            if let description = try? await track.load(.formatDescriptions).first {
                videoCodec = codecName(CMFormatDescriptionGetMediaSubType(description), video: true)
            }
            if let bitrate = try? await track.load(.estimatedDataRate), bitrate.isFinite, bitrate > 0 {
                videoBitrate = bitrate >= 1_000_000
                    ? String(format: "~%.1f Mbps", bitrate / 1_000_000)
                    : String(format: "~%.0f kbps", bitrate / 1_000)
            }
        }
        if let track = try? await asset.loadTracks(withMediaType: .audio).first,
           let description = try? await track.load(.formatDescriptions).first {
            let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee.mFormatID
                ?? CMFormatDescriptionGetMediaSubType(description)
            audioCodec = codecName(format, video: false)
        }
        return VideoExportInfo(filename: url.lastPathComponent, fileSize: size,
                               resolution: resolution, frameRate: frameRate,
                               duration: duration.isFinite && duration > 0 ? TimestampFormatter.string(for: duration) : nil,
                               videoCodec: videoCodec, videoBitrate: videoBitrate, audioCodec: audioCodec)
    }
}
