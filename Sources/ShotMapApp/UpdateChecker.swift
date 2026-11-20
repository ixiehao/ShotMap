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
    @Published private(set) var isChecking = false

    private let load: (URLRequest) async throws -> (Data, URLResponse)
    private let now: () -> Date
    private let currentVersion: ReleaseVersion
    private var lastSuccessfulCheckAt: Date?
    private var lastFailedCheckAt: Date?
    private var currentCheck: Task<Void, Never>?

    private static let releaseURL = URL(string: "https://api.github.com/repos/ixiehao/ShotMap/releases/latest")!
    private static let latestPageURL = URL(string: "https://github.com/ixiehao/ShotMap/releases/latest")!
    private static let checkInterval: TimeInterval = 12 * 60 * 60
    private static let retryInterval: TimeInterval = 60

    init(currentVersion: ReleaseVersion? = nil, session: URLSession = .shared,
         now: @escaping () -> Date = Date.init,
         load: ((URLRequest) async throws -> (Data, URLResponse))? = nil) {
        self.currentVersion = currentVersion ?? Self.installedVersion
        self.now = now
        self.load = load ?? { try await session.data(for: $0) }
    }

    var hasUpdate: Bool { availableUpdate != nil }

    func checkForUpdate(force: Bool = false) async {
        if let currentCheck {
            await currentCheck.value
            return
        }
        if !force {
            if let lastSuccessfulCheckAt, now().timeIntervalSince(lastSuccessfulCheckAt) < Self.checkInterval { return }
            if let lastFailedCheckAt, now().timeIntervalSince(lastFailedCheckAt) < Self.retryInterval { return }
        }
        isChecking = true
        let task = Task { @MainActor in
            await self.performCheck()
        }
        currentCheck = task
        await task.value
        currentCheck = nil
        isChecking = false
    }

    private func performCheck() async {
        var request = URLRequest(url: Self.releaseURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 10
        request.setValue("ShotMap update checker", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        do {
            let (data, response) = try await load(request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw CheckError.invalidResponse
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard ReleaseVersion(tag: release.tagName) != nil,
                  release.htmlURL.scheme == "https", release.htmlURL.host == "github.com",
                  release.htmlURL.query == nil, release.htmlURL.fragment == nil,
                  release.htmlURL.path == "/ixiehao/ShotMap/releases/tag/\(release.tagName)" else {
                throw CheckError.invalidResponse
            }
            recordSuccess(release.update(newerThan: currentVersion))
        } catch {
            do {
                // GitHub's unauthenticated API has a shared-IP rate limit.
                // Its public latest-release URL redirects to the stable tag.
                var fallback = URLRequest(url: Self.latestPageURL, cachePolicy: .reloadIgnoringLocalCacheData)
                fallback.timeoutInterval = 10
                fallback.setValue("ShotMap update checker", forHTTPHeaderField: "User-Agent")
                fallback.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                let (_, response) = try await load(fallback)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode), let url = response.url,
                      url.scheme == "https", url.host == "github.com",
                      url.query == nil, url.fragment == nil else { throw CheckError.invalidResponse }
                let prefix = "/ixiehao/ShotMap/releases/tag/"
                guard url.path.hasPrefix(prefix) else { throw CheckError.invalidResponse }
                let tag = String(url.path.dropFirst(prefix.count))
                guard let version = ReleaseVersion(tag: tag) else { throw CheckError.invalidResponse }
                recordSuccess(currentVersion < version ? AvailableUpdate(version: tag, downloadURL: url) : nil)
            } catch {
                // Offline and transient failures must never interrupt the app.
                lastCheckFailed = true
                lastSuccessfulCheckAt = nil
                lastFailedCheckAt = now()
            }
        }
    }

    private func recordSuccess(_ update: AvailableUpdate?) {
        availableUpdate = update
        lastCheckFailed = false
        lastSuccessfulCheckAt = now()
        lastFailedCheckAt = nil
    }

    private enum CheckError: Error { case invalidResponse }

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
