import Vision
import XCTest
@testable import ShotMapApp

final class AutomaticVisionCancellationTests: XCTestCase {
    func testNormalInferenceKeepsAutomaticHardwareSelection() throws {
        var attempts = 0
        try AutomaticVisionCancellation().performRecoveringComputeFailure(
            [VNDetectTextRectanglesRequest()], configureCPU: { _ in
                XCTFail("Successful hardware inference must not configure a CPU fallback")
                return false
            }
        ) { attempts += 1 }
        XCTAssertEqual(attempts, 1)
    }

    func testUnavailableInferenceContextRetriesOnceOnSupportedCPU() throws {
        var attempts = 0
        var configurations = 0
        try AutomaticVisionCancellation().performRecoveringComputeFailure(
            [VNDetectTextRectanglesRequest()], configureCPU: { _ in configurations += 1; return true }
        ) {
            attempts += 1
            if attempts == 1 { throw self.inferenceFailure }
        }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(configurations, 1)
    }

    func testFailedCPUInferenceStillFailsWithoutRepeatedRetries() {
        var attempts = 0
        XCTAssertThrowsError(try AutomaticVisionCancellation().performRecoveringComputeFailure(
            [VNDetectTextRectanglesRequest()], configureCPU: { _ in true }
        ) { attempts += 1; throw self.inferenceFailure })
        XCTAssertEqual(attempts, 2)
    }

    func testUnavailableCPUDoesNotRetryOrFakeAnObservation() {
        var attempts = 0
        XCTAssertThrowsError(try AutomaticVisionCancellation().performRecoveringComputeFailure(
            [VNDetectTextRectanglesRequest()], configureCPU: { _ in false }
        ) { attempts += 1; throw self.inferenceFailure })
        XCTAssertEqual(attempts, 1)
    }

    func testInvalidImageIsNotTreatedAsAComputeFailure() {
        XCTAssertThrowsError(try AutomaticVisionCancellation().performRecoveringComputeFailure(
            [VNDetectTextRectanglesRequest()], configureCPU: { _ in
                XCTFail("Invalid images cannot be recovered by switching devices")
                return true
            }
        ) { throw NSError(domain: VNErrorDomain, code: VNErrorCode.invalidImage.rawValue) })
    }

    func testCancellationPreventsTheCPUFallbackFromStarting() {
        let cancellation = AutomaticVisionCancellation()
        var attempts = 0
        XCTAssertThrowsError(try cancellation.performRecoveringComputeFailure(
            [VNDetectTextRectanglesRequest()], configureCPU: { _ in
                XCTFail("Cancellation must stop fallback configuration")
                return true
            }
        ) {
            attempts += 1
            cancellation.cancel()
            throw self.inferenceFailure
        }) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(attempts, 1)
    }

    private var inferenceFailure: NSError {
        NSError(domain: VNErrorDomain, code: VNErrorCode.internalError.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Could not create inference context"])
    }

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
