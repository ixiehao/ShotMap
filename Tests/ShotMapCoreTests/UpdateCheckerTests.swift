import Foundation
import XCTest
@testable import ShotMapApp

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private let url = URL(string: "https://api.github.com/repos/ixiehao/ShotMap/releases/latest")!

    func testFailedAutomaticCheckRetriesAfterOneMinuteAndFindsUpdate() async throws {
        var time = Date(timeIntervalSince1970: 1_000)
        var requests = 0
        let checker = UpdateChecker(currentVersion: try XCTUnwrap(ReleaseVersion(tag: "0.2.18")), now: { time }, load: { request in
            requests += 1
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
            if requests <= 2 { throw URLError(.notConnectedToInternet) }
            return (self.releaseData(tag: "v0.2.19"), HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        await checker.checkForUpdate()
        XCTAssertTrue(checker.lastCheckFailed)
        time.addTimeInterval(59)
        await checker.checkForUpdate()
        XCTAssertEqual(requests, 2)
        time.addTimeInterval(1)
        await checker.checkForUpdate()
        XCTAssertEqual(requests, 3)
        XCTAssertEqual(checker.availableUpdate?.version, "v0.2.19")
        XCTAssertFalse(checker.lastCheckFailed)
        await checker.checkForUpdate()
        XCTAssertEqual(requests, 3, "Successful automatic checks are throttled")
    }

    func testForcedCheckBypassesThrottleAndFailureKeepsKnownUpdate() async throws {
        var requests = 0
        let checker = UpdateChecker(currentVersion: try XCTUnwrap(ReleaseVersion(tag: "0.2.18")), load: { _ in
            requests += 1
            if requests >= 2 { throw URLError(.timedOut) }
            return (self.releaseData(tag: "v0.2.19"), HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        await checker.checkForUpdate()
        await checker.checkForUpdate(force: true)
        XCTAssertEqual(requests, 3)
        XCTAssertTrue(checker.lastCheckFailed)
        XCTAssertEqual(checker.availableUpdate?.version, "v0.2.19")
    }

    func testRateLimitedAPIUsesTrustedLatestPageRedirect() async throws {
        var requests = 0
        let latest = URL(string: "https://github.com/ixiehao/ShotMap/releases/tag/v0.2.19")!
        let checker = UpdateChecker(currentVersion: try XCTUnwrap(ReleaseVersion(tag: "0.2.18")), load: { request in
            requests += 1
            if request.url?.host == "api.github.com" {
                return (Data(), HTTPURLResponse(url: self.url, statusCode: 403, httpVersion: nil, headerFields: nil)!)
            }
            XCTAssertEqual(request.url?.absoluteString, "https://github.com/ixiehao/ShotMap/releases/latest")
            return (Data(), HTTPURLResponse(url: latest, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        await checker.checkForUpdate()
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(checker.availableUpdate, AvailableUpdate(version: "v0.2.19", downloadURL: latest))
        XCTAssertFalse(checker.lastCheckFailed)
    }

    func testUntrustedFallbackRedirectIsRejected() async throws {
        let checker = UpdateChecker(currentVersion: try XCTUnwrap(ReleaseVersion(tag: "0.2.18")), load: { request in
            if request.url?.host == "api.github.com" { throw URLError(.timedOut) }
            let invalid = URL(string: "https://example.com/ixiehao/ShotMap/releases/tag/v9.0.0")!
            return (Data(), HTTPURLResponse(url: invalid, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        await checker.checkForUpdate()
        XCTAssertTrue(checker.lastCheckFailed)
        XCTAssertNil(checker.availableUpdate)
    }

    func testRunningAppChecksAgainAfterSuccessfulInterval() async throws {
        var time = Date(timeIntervalSince1970: 1_000)
        var requests = 0
        let checker = UpdateChecker(currentVersion: try XCTUnwrap(ReleaseVersion(tag: "0.2.18")), now: { time }, load: { _ in
            requests += 1
            let tag = requests == 1 ? "v0.2.18" : "v0.2.19"
            return (self.releaseData(tag: tag), HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        await checker.checkForUpdate()
        XCTAssertFalse(checker.hasUpdate)
        time.addTimeInterval(12 * 60 * 60 - 1)
        await checker.checkForUpdate()
        XCTAssertEqual(requests, 1)
        time.addTimeInterval(1)
        await checker.checkForUpdate()
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(checker.availableUpdate?.version, "v0.2.19")
    }

    func testConcurrentManualAndAutomaticChecksShareRequest() async throws {
        var requests = 0
        let checker = UpdateChecker(currentVersion: try XCTUnwrap(ReleaseVersion(tag: "0.2.18")), load: { _ in
            requests += 1
            try await Task.sleep(nanoseconds: 30_000_000)
            return (self.releaseData(tag: "v0.2.19"), HTTPURLResponse(url: self.url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        async let automatic: Void = checker.checkForUpdate()
        async let manual: Void = checker.checkForUpdate(force: true)
        _ = await (automatic, manual)
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(checker.hasUpdate)
        XCTAssertFalse(checker.isChecking)
    }

    private func releaseData(tag: String) -> Data {
        Data("""
        {"tag_name":"\(tag)","html_url":"https://github.com/ixiehao/ShotMap/releases/tag/\(tag)","draft":false,"prerelease":false}
        """.utf8)
    }
}
