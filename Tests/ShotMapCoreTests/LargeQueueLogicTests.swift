import AppKit
import Combine
import UniformTypeIdentifiers
import XCTest
@testable import ShotMapApp

/// URL/provider stress only. These tests do not decode media or touch real user
/// files, and keep correctness assertions separate from device speed claims.
final class LargeQueueLogicTests: XCTestCase {
    @MainActor
    func testFiveThousandURLsRemainUniqueStableAndBatchPublishedAcrossReimports() {
        let model = StoryboardViewModel()
        let urls = (0..<5_000).map { index in
            URL(fileURLWithPath: "/tmp/ShotMap-queue-\(index)/旅行 clip \(index).\(index.isMultiple(of: 3) ? "MOV" : "mp4")")
        }
        let resetID = model.queueResetID
        var publications: [Int] = []
        let observation = model.$videoJobs.dropFirst().sink { publications.append($0.count) }
        defer { observation.cancel(); model.clearVideos() }

        model.addVideos(Array(urls.prefix(1_000)))
        let originalIDs = model.videoJobs.map(\.id)
        model.addVideos(Array(urls.prefix(1_000).reversed()))
        XCTAssertEqual(publications, [1_000], "A duplicate-only import must not republish the queue")
        for lower in stride(from: 1_000, to: urls.count, by: 500) {
            // Include an already imported tail in each new batch.
            model.addVideos(Array(urls[max(0, lower - 100)..<min(lower + 500, urls.count)]))
        }
        let publicationsBeforeDuplicateImport = publications
        let aliases = urls.map { url in
            url.deletingLastPathComponent().appendingPathComponent("unused/../\(url.lastPathComponent)")
        }
        model.addVideos(Array(urls.reversed()) + aliases)

        XCTAssertEqual(model.videoJobs.map(\.url), urls.map(\.standardizedFileURL))
        XCTAssertEqual(Set(model.videoJobs.map { $0.url.path }).count, 5_000)
        XCTAssertEqual(Array(model.videoJobs.prefix(1_000).map(\.id)), originalIDs)
        XCTAssertEqual(publications, publicationsBeforeDuplicateImport)
        XCTAssertEqual(publications, [1_000, 1_500, 2_000, 2_500, 3_000, 3_500, 4_000, 4_500, 5_000])
        XCTAssertEqual(model.queueResetID, resetID)
        XCTAssertFalse(model.showError)
    }

    func testTwentyOutOfOrderDropsPreserveFiveThousandSlotsAndAggregateFailuresExactly() throws {
        var drops = OrderedVideoDrops()
        let batchSize = 250
        let urls = (0..<5_000).map { URL(fileURLWithPath: "/tmp/ShotMap-drop-\($0).mp4") }
        let ids = try (0..<20).map { _ in try XCTUnwrap(drops.register(count: batchSize)) }
        var publications: [OrderedVideoDrops.Completion] = []
        for batch in (1..<20).reversed() {
            for offset in (0..<batchSize).reversed() {
                let index = batch * batchSize + offset
                if let completion = drops.resolve(index.isMultiple(of: 17) ? nil : urls[index], at: offset, batchID: ids[batch]) {
                    publications.append(completion)
                }
            }
            XCTAssertFalse(drops.isPending(ids[batch]))
            XCTAssertNil(drops.resolve(URL(fileURLWithPath: "/tmp/duplicate-callback.mp4"), at: 0, batchID: ids[batch]))
        }
        XCTAssertTrue(publications.isEmpty, "Later drops cannot jump ahead of an unresolved first drop")
        XCTAssertNil(drops.resolve(urls[0], at: -1, batchID: ids[0]))
        XCTAssertNil(drops.resolve(urls[0], at: batchSize, batchID: ids[0]))
        for offset in stride(from: 0, to: batchSize, by: 2) {
            XCTAssertNil(drops.resolve(offset.isMultiple(of: 17) ? nil : urls[offset], at: offset, batchID: ids[0]))
        }
        let completed = try XCTUnwrap(drops.expire(ids[0]))
        let expected = urls.indices.filter { index in
            !index.isMultiple(of: 17) && (index >= batchSize || index.isMultiple(of: 2))
        }.map { urls[$0] }
        XCTAssertEqual(completed.urls, expected)
        XCTAssertEqual(completed.failedCount, urls.count - expected.count)
        XCTAssertTrue(drops.isEmpty)
        XCTAssertTrue(ids.allSatisfy { !drops.isPending($0) })
        XCTAssertNil(drops.resolve(urls[1], at: 1, batchID: ids[0]))
    }

    func testFiveThousandCancelledCallbacksCannotPopulateOrConsumeANewThousandURLDrop() throws {
        var drops = OrderedVideoDrops()
        let old = try XCTUnwrap(drops.register(count: 5_000))
        for index in 0..<1_000 {
            XCTAssertNil(drops.resolve(URL(fileURLWithPath: "/tmp/obsolete-\(index).mp4"), at: index, batchID: old))
        }
        drops.cancelAll()
        let current = try XCTUnwrap(drops.register(count: 1_000))
        for index in (0..<5_000).reversed() {
            XCTAssertNil(drops.resolve(URL(fileURLWithPath: "/tmp/obsolete-\(index).mp4"), at: index, batchID: old))
        }
        XCTAssertTrue(drops.isPending(current))
        let urls = (0..<1_000).map { URL(fileURLWithPath: "/tmp/current-\($0).mp4") }
        var completions: [OrderedVideoDrops.Completion] = []
        for index in urls.indices.reversed() {
            if let completion = drops.resolve(urls[index], at: index, batchID: current) { completions.append(completion) }
        }
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.urls, urls)
        XCTAssertEqual(completions.first?.failedCount, 0)
        XCTAssertTrue(drops.isEmpty)
    }

    @MainActor
    func testThousandMixedFailuresRetryOnlyRecoverableJobsAndLateRunCannotRestoreClearedQueue() async {
        let model = StoryboardViewModel()
        let urls = (0..<1_000).map { URL(fileURLWithPath: "/tmp/ShotMap-mixed-retry-\($0).mp4") }
        model.addVideos(urls)
        for index in urls.indices {
            let failure: VideoFailure = switch index % 3 {
            case 0: .retryable("transient fixture")
            case 1: .permanent("unreadable fixture")
            default: .needsTranscoding("unsupported fixture")
            }
            model.markJobFailed(index: index, failure: failure)
        }
        let originalIDs = model.videoJobs.map(\.id)
        XCTAssertEqual(model.retryableFailedJobCount, 334)
        XCTAssertEqual(model.transcodingJobs.count, 333)
        model.retryFailedJobs()
        XCTAssertTrue(model.isProcessing)
        XCTAssertEqual(model.videoJobs.map(\.id), originalIDs)
        XCTAssertEqual(model.videoJobs.map(\.url), urls)
        for index in urls.indices {
            if index.isMultiple(of: 3) {
                XCTAssertEqual(model.videoJobs[index].state, .queued)
            } else {
                XCTAssertFalse(model.videoJobs[index].state.canRetry)
                XCTAssertNotNil(model.videoJobs[index].state.failureMessage)
            }
        }
        // No MainActor suspension occurs between start and cancellation, so a
        // queued old worker must validate its run ID before beginning media I/O.
        model.cancelGeneration()
        model.clearVideos()
        let current = URL(fileURLWithPath: "/tmp/ShotMap-after-retry-cancellation.mp4")
        model.addVideos([current])
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(model.videoJobs.map(\.url), [current])
        XCTAssertEqual(model.videoJobs.first?.state, .queued)
        XCTAssertFalse(model.isBusy)
        XCTAssertTrue(model.completedPreviews.isEmpty)
        XCTAssertFalse(model.showError)
    }

    @MainActor
    func testClearCancelsThousandRealProvidersAndLateCallbacksCannotMixIntoNewDrop() async throws {
        let model = StoryboardViewModel()
        let allStarted = expectation(description: "All deferred providers started")
        allStarted.expectedFulfillmentCount = 1_000
        let providers = (0..<1_000).map { _ in QueueStressProvider(started: allStarted) }
        defer { providers.forEach { $0.complete(nil) }; model.cancelVideoImport() }
        XCTAssertTrue(model.acceptDrop(providers: providers.map { $0.provider() }))
        await fulfillment(of: [allStarted], timeout: 10)
        let resetID = model.queueResetID
        model.clearVideos()
        XCTAssertNotEqual(model.queueResetID, resetID)
        XCTAssertFalse(model.isImportingVideos)
        XCTAssertTrue(providers.allSatisfy { $0.progress.isCancelled })
        let freshURL = URL(fileURLWithPath: "/tmp/ShotMap-current-import.mp4")
        XCTAssertTrue(model.acceptDrop(providers: [NSItemProvider(object: freshURL as NSURL)]))
        for index in providers.indices.reversed() {
            providers[index].complete(URL(fileURLWithPath: "/tmp/ShotMap-old-import-\(index).mp4"))
        }
        let deadline = ContinuousClock.now + .seconds(10)
        while model.isImportingVideos, ContinuousClock.now < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertFalse(model.isImportingVideos)
        XCTAssertEqual(model.videoJobs.map(\.url), [freshURL])
        XCTAssertFalse(model.showError)
    }
}

private final class QueueStressProvider: @unchecked Sendable {
    let progress = Progress(totalUnitCount: 1)
    private let started: XCTestExpectation
    private let lock = NSLock()
    private var completion: ((Data?, Error?) -> Void)?

    init(started: XCTestExpectation) { self.started = started }

    func provider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { [self] callback in
            lock.withLock { completion = callback }
            started.fulfill()
            return progress
        }
        return provider
    }

    func complete(_ url: URL?) {
        let callback = lock.withLock { () -> ((Data?, Error?) -> Void)? in
            defer { completion = nil }
            return completion
        }
        callback?(url?.dataRepresentation, url == nil ? CocoaError(.fileReadUnknown) : nil)
    }
}
