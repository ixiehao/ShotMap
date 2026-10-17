import XCTest
@testable import ShotMapApp

final class ManualEditorStateTests: XCTestCase {
    func testRepeatedFrameNudgesAdvanceFromTheLatestPosition() {
        var timeline = ManualEditorTimeline()
        timeline.seek(to: 10, duration: 60)
        for _ in 0..<5 {
            timeline.seek(to: timeline.time + 1.0 / 25, duration: 60)
        }
        XCTAssertEqual(timeline.time, 10.2, accuracy: 0.000_001)
        XCTAssertEqual(timeline.editableText, "00:00:10.200")
        timeline.seek(to: timeline.time - 5.0 / 25, duration: 60)
        XCTAssertEqual(timeline.time, 10, accuracy: 0.000_001)
        XCTAssertEqual(timeline.editableText, "00:00:10.000")
    }

    func testManualTimestampAndScrubKeepNumericPositionInSync() throws {
        var timeline = ManualEditorTimeline()
        timeline.editableText = "00:00:12.345"
        let input = try XCTUnwrap(TimestampFormatter.editableSeconds(from: timeline.editableText))
        timeline.seek(to: input, duration: 60)
        XCTAssertEqual(timeline.time, 12.345, accuracy: 0.000_001)
        XCTAssertEqual(timeline.editableText, TimestampFormatter.editableString(for: timeline.time))

        timeline.seek(to: 24.5, duration: 60)
        timeline.seek(to: timeline.time + 1.0 / 30, duration: 60)
        XCTAssertEqual(timeline.time, 24.5 + 1.0 / 30, accuracy: 0.000_001)
        XCTAssertEqual(timeline.editableText, "00:00:24.533")
    }

    func testPositionClampsToVideoBoundsAndRejectsNonfiniteInput() {
        var timeline = ManualEditorTimeline()
        XCTAssertEqual(timeline.seek(to: -1, duration: 60), 0)
        XCTAssertEqual(timeline.seek(to: 100, duration: 60), 60)
        XCTAssertEqual(timeline.editableText, "00:01:00.000")
        XCTAssertEqual(timeline.seek(to: .nan, duration: 60), 0)
        XCTAssertEqual(timeline.seek(to: 1, duration: .infinity), 0)
    }

    func testCancellingUIWaiterCancelsDetachedMediaWork() async {
        let finished = expectation(description: "Cancelled media work finishes promptly")
        let worker = Task.detached { () throws -> Int in
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return 42
        }
        let waiter = Task {
            defer { finished.fulfill() }
            do {
                _ = try await worker.valuePropagatingCancellation()
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        waiter.cancel()
        await fulfillment(of: [finished], timeout: 2)
        let workerWasCancelled = worker.isCancelled
        worker.cancel()
        let cancelled = await waiter.value
        XCTAssertTrue(workerWasCancelled)
        XCTAssertTrue(cancelled)
    }
}
