import AppKit
import Combine
import UniformTypeIdentifiers
import XCTest
@testable import ShotMapApp

final class VideoImportLifecycleTests: XCTestCase {
    func testLargeDropPublishesOnceInOriginalOrderEvenWithReverseCallbacks() throws {
        var drops = OrderedVideoDrops()
        let urls = (0..<900).map { URL(fileURLWithPath: "/tmp/ShotMap-import-\($0).mp4") }
        let id = try XCTUnwrap(drops.register(count: urls.count))
        var completions: [OrderedVideoDrops.Completion] = []
        for index in urls.indices.reversed() {
            if let result = drops.resolve(urls[index], at: index, batchID: id) { completions.append(result) }
        }
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.urls, urls)
        XCTAssertEqual(completions.first?.failedCount, 0)
        XCTAssertTrue(drops.isEmpty)
    }

    func testConsecutiveDropsKeepArrivalOrderWhenLaterBatchFinishesFirst() throws {
        var drops = OrderedVideoDrops()
        let first = try XCTUnwrap(drops.register(count: 2))
        let second = try XCTUnwrap(drops.register(count: 2))
        let urls = (0..<4).map { URL(fileURLWithPath: "/tmp/\($0).mp4") }
        XCTAssertNil(drops.resolve(urls[3], at: 1, batchID: second))
        XCTAssertNil(drops.resolve(urls[2], at: 0, batchID: second))
        XCTAssertFalse(drops.isPending(second))
        XCTAssertFalse(drops.isEmpty)
        XCTAssertNil(drops.resolve(urls[1], at: 1, batchID: first))
        let completed = try XCTUnwrap(drops.resolve(urls[0], at: 0, batchID: first))
        XCTAssertEqual(completed.urls, urls)
        XCTAssertTrue(drops.isEmpty)
    }

    func testExpiredAndFailedProvidersReleaseLaterBatchesAndIgnoreLateCallbacks() throws {
        var drops = OrderedVideoDrops()
        let first = try XCTUnwrap(drops.register(count: 3))
        let second = try XCTUnwrap(drops.register(count: 1))
        let firstURL = URL(fileURLWithPath: "/tmp/first.mp4")
        let secondURL = URL(fileURLWithPath: "/tmp/second.mp4")
        XCTAssertNil(drops.resolve(firstURL, at: 0, batchID: first))
        XCTAssertNil(drops.resolve(nil, at: 1, batchID: first))
        XCTAssertNil(drops.resolve(firstURL, at: 0, batchID: first), "Duplicate provider completions must not change the remaining count")
        XCTAssertNil(drops.resolve(secondURL, at: 0, batchID: second))
        let completed = try XCTUnwrap(drops.expire(first))
        XCTAssertEqual(completed.urls, [firstURL, secondURL])
        XCTAssertEqual(completed.failedCount, 2)
        XCTAssertTrue(drops.isEmpty)
        XCTAssertNil(drops.resolve(firstURL, at: 2, batchID: first))
    }

    func testCancelledDropCannotRepopulateQueueOrConsumeNewDropCallbacks() throws {
        var drops = OrderedVideoDrops()
        let old = try XCTUnwrap(drops.register(count: 1))
        drops.cancelAll()
        let current = try XCTUnwrap(drops.register(count: 1))
        let url = URL(fileURLWithPath: "/tmp/current.mp4")
        XCTAssertNil(drops.resolve(url, at: 0, batchID: old))
        XCTAssertTrue(drops.isPending(current))
        XCTAssertEqual(drops.resolve(url, at: 0, batchID: current)?.urls, [url])
        XCTAssertTrue(drops.isEmpty)
    }

    @MainActor
    func testRealItemProvidersBatchPublishedUpdatesAndSupportConsecutiveDrops() async throws {
        let model = StoryboardViewModel()
        let providers = (0..<4).map { DeferredVideoProvider(started: expectation(description: "Provider \($0) starts")) }
        let urls = (0..<4).map { URL(fileURLWithPath: "/tmp/ShotMap-provider-\($0).mp4") }
        var published: [[URL]] = []
        var uiUpdates = 0
        let subscription = model.$videoJobs.dropFirst().sink { published.append($0.map(\.url)) }
        let uiSubscription = model.objectWillChange.sink { uiUpdates += 1 }
        defer { subscription.cancel(); uiSubscription.cancel(); model.cancelVideoImport() }
        XCTAssertTrue(model.acceptDrop(providers: providers.prefix(2).map { $0.provider() }))
        XCTAssertTrue(model.acceptDrop(providers: providers.suffix(2).map { $0.provider() }))
        await fulfillment(of: providers.map(\.started), timeout: 3)
        providers[3].complete(urls[3])
        providers[2].complete(urls[2])
        providers[1].complete(urls[1])
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(model.videoJobs.isEmpty)
        XCTAssertTrue(model.isImportingVideos)
        providers[0].complete(urls[0])
        try await waitForImport(model)
        XCTAssertEqual(model.videoJobs.map(\.url), urls)
        XCTAssertFalse(published.isEmpty)
        XCTAssertLessThanOrEqual(published.count, 2, "Publish each drop once, never each provider callback")
        XCTAssertTrue(published.allSatisfy { Array(urls.prefix($0.count)) == $0 })
        XCTAssertLessThanOrEqual(uiUpdates, 4, "Pending provider callbacks must not republish an unchanged importing flag")
        XCTAssertFalse(model.showError)
    }

    @MainActor
    func testUnresponsiveProviderTimesOutAndCancelsItsProgress() async throws {
        let model = StoryboardViewModel(dropTimeoutNanoseconds: 500_000_000)
        let pending = DeferredVideoProvider(started: expectation(description: "Unresponsive provider starts"))
        defer { pending.complete(nil); model.cancelVideoImport() }
        XCTAssertTrue(model.acceptDrop(providers: [pending.provider()]))
        await fulfillment(of: [pending.started], timeout: 3)
        try await waitForImport(model)
        XCTAssertTrue(model.showError)
        XCTAssertTrue(model.videoJobs.isEmpty)
        XCTAssertTrue(pending.progress.isCancelled)
    }

    @MainActor
    func testClearCancelsAnEmptyImportAndLateCompletionCannotRestoreIt() async throws {
        let model = StoryboardViewModel()
        let pending = DeferredVideoProvider(started: expectation(description: "Cancelled provider starts"))
        XCTAssertTrue(model.acceptDrop(providers: [pending.provider()]))
        await fulfillment(of: [pending.started], timeout: 3)
        XCTAssertTrue(model.videoJobs.isEmpty)
        model.clearVideos()
        XCTAssertFalse(model.isImportingVideos)
        XCTAssertTrue(pending.progress.isCancelled)
        pending.complete(URL(fileURLWithPath: "/tmp/obsolete.mp4"))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(model.videoJobs.isEmpty)
        XCTAssertFalse(model.showError)
    }

    @MainActor
    func testURLObjectProvidersStillImportUsingFileURLDataRepresentation() async throws {
        let model = StoryboardViewModel()
        let url = URL(fileURLWithPath: "/tmp/ShotMap URL 旅行.mp4")
        XCTAssertTrue(model.acceptDrop(providers: [NSItemProvider(object: url as NSURL)]))
        try await waitForImport(model)
        XCTAssertEqual(model.videoJobs.map(\.url), [url])
        XCTAssertFalse(model.showError)
    }

    @MainActor
    private func waitForImport(_ model: StoryboardViewModel) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while model.isImportingVideos, ContinuousClock.now < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertFalse(model.isImportingVideos)
    }
}

private final class DeferredVideoProvider: @unchecked Sendable {
    let progress = Progress(totalUnitCount: 1)
    let started: XCTestExpectation
    private let lock = NSLock()
    private var completion: ((Data?, Error?) -> Void)?

    init(started: XCTestExpectation) { self.started = started }

    func provider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { [self] completion in
            lock.withLock { self.completion = completion }
            started.fulfill()
            return progress
        }
        return provider
    }

    func complete(_ url: URL?) {
        let completion = lock.withLock { () -> ((Data?, Error?) -> Void)? in
            let callback = self.completion
            self.completion = nil
            return callback
        }
        completion?(url?.dataRepresentation, url == nil ? CocoaError(.fileReadUnknown) : nil)
    }
}
