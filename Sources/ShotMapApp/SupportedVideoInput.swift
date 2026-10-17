import Foundation
import UniformTypeIdentifiers

enum SupportedVideoInput {
    // Containers are accepted up front; the system decoder remains the final
    // authority because a container can hold an unsupported video codec.
    static let commonExtensions: Set<String> = [
        "mp4", "m4v", "mov", "avi", "mkv", "webm", "3gp", "3g2", "3gpp",
        "mpeg", "mpg", "mpe", "mts", "m2ts", "ts", "vob", "wmv", "flv",
        "asf", "ogv", "dv", "f4v"
    ]

    static func accepts(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        guard !fileExtension.isEmpty else { return false }
        if commonExtensions.contains(fileExtension) { return true }
        guard let type = UTType(filenameExtension: fileExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }
}
