@preconcurrency import AppKit
import Foundation
import SwiftUI

/// This checks public release metadata only. No media or personal data leaves the Mac.
struct ReleaseVersion: Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(tag: String) {
        let raw = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]),
              major >= 0, minor >= 0, patch >= 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct AvailableUpdate: Equatable, Sendable {
    let version: String
    let downloadURL: URL
}

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease
    }

    func update(newerThan currentVersion: ReleaseVersion) -> AvailableUpdate? {
        guard !draft, !prerelease,
              let version = ReleaseVersion(tag: tagName), currentVersion < version,
              htmlURL.scheme == "https", htmlURL.host == "github.com",
              htmlURL.path.hasPrefix("/ixiehao/ShotMap/releases/") else { return nil }
        return AvailableUpdate(version: tagName, downloadURL: htmlURL)
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var lastCheckFailed = false

    private let session: URLSession
    private let currentVersion: ReleaseVersion
    private var isChecking = false
    private var lastCheckedAt: Date?

    private static let releaseURL = URL(string: "https://api.github.com/repos/ixiehao/ShotMap/releases/latest")!
    private static let checkInterval: TimeInterval = 12 * 60 * 60

    init(currentVersion: ReleaseVersion? = nil, session: URLSession = .shared) {
        self.currentVersion = currentVersion ?? Self.installedVersion
        self.session = session
    }

    var hasUpdate: Bool { availableUpdate != nil }

    func checkForUpdate(force: Bool = false) async {
        guard !isChecking else { return }
        if !force, let lastCheckedAt, Date().timeIntervalSince(lastCheckedAt) < Self.checkInterval { return }
        isChecking = true
        defer {
            lastCheckedAt = Date()
            isChecking = false
        }

        var request = URLRequest(url: Self.releaseURL)
        request.timeoutInterval = 10
        request.setValue("ShotMap update checker", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                lastCheckFailed = true
                return
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard ReleaseVersion(tag: release.tagName) != nil else {
                lastCheckFailed = true
                return
            }
            availableUpdate = release.update(newerThan: currentVersion)
            lastCheckFailed = false
        } catch {
            // Offline and transient API failures must never interrupt the app.
            lastCheckFailed = true
        }
    }

    func openDownloadPage() {
        guard let url = availableUpdate?.downloadURL else { return }
        NSWorkspace.shared.open(url)
    }

    private static var installedVersion: ReleaseVersion {
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return ReleaseVersion(tag: bundleVersion ?? "0.0.0") ?? ReleaseVersion(tag: "0.0.0")!
    }
}

struct UpdateAvailableBanner: View {
    @ObservedObject var checker: UpdateChecker
    let language: AppLanguage

    var body: some View {
        if let update = checker.availableUpdate {
            HStack(spacing: 10) {
                ProjectIcon(symbol: .refresh, size: 16)
                    .foregroundStyle(Color(red: 0.38, green: 0.89, blue: 0.93))
                Text(language.text("update.available", update.version))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Button(language.text("button.downloadUpdate")) {
                    checker.openDownloadPage()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color(red: 0.32, green: 0.78, blue: 0.91))
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 38)
            .background(Color(red: 0.10, green: 0.17, blue: 0.29).opacity(0.98), in: Capsule())
            .overlay { Capsule().strokeBorder(Color(red: 0.36, green: 0.84, blue: 0.93).opacity(0.68)) }
            .shadow(color: .black.opacity(0.24), radius: 10, y: 3)
            .accessibilityElement(children: .contain)
        }
    }
}
