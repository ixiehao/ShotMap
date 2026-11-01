import Vision
import XCTest
@testable import ShotMapApp

final class AutomaticVisionCancellationTests: XCTestCase {
    func testCancelledBridgeDoesNotStartAnotherVisionOperation() {
        let cancellation = AutomaticVisionCancellation()
        cancellation.cancel()
        XCTAssertThrowsError(try cancellation.withActiveRequests([VNDetectFaceRectanglesRequest()]) {
            XCTFail("An already cancelled video must not begin another inference")
        }) { error in XCTAssertTrue(error is CancellationError) }
    }

    func testCancellationDuringRegisteredWorkIsReportedAsCancellation() {
        let cancellation = AutomaticVisionCancellation()
        let entered = DispatchSemaphore(value: 0)
        let cancelled = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            guard entered.wait(timeout: .now() + 2) == .success else { return }
            cancellation.cancel()
            cancelled.signal()
        }
        XCTAssertThrowsError(try cancellation.withActiveRequests([VNDetectFaceRectanglesRequest()]) {
            entered.signal()
            XCTAssertEqual(cancelled.wait(timeout: .now() + 2), .success)
            return 42
        }) { error in XCTAssertTrue(error is CancellationError) }
    }

    func testOrdinaryInferenceFailureIsNotMisreportedAsCancellation() {
        enum FixtureError: Error { case invalidImage }
        let cancellation = AutomaticVisionCancellation()
        XCTAssertThrowsError(try cancellation.withActiveRequests([VNDetectFaceRectanglesRequest()]) {
            throw FixtureError.invalidImage
        }) { error in XCTAssertTrue(error is FixtureError) }
        XCTAssertEqual(try cancellation.withActiveRequests([]) { 42 }, 42,
                       "A failed request must release registration for the next operation")
    }
}
