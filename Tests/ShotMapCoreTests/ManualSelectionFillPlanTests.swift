import XCTest
@testable import ShotMapApp

final class ManualSelectionFillPlanTests: XCTestCase {
    private var frames: [CapturedFrame] {
        (0..<24).map { CapturedFrame(id: $0, time: Double($0), jpegData: Data()) }
    }

    func testThreeManualChoicesArePreservedAndOnlySixVacanciesAreFilled() {
        let chosen: Set<Int> = [0, 12, 23]
        let plan = ManualSelectionFillPlan(candidates: frames, selectedIDs: chosen, limit: 9)
        XCTAssertEqual(plan.additionalCount, 6)
        XCTAssertTrue(plan.candidates.allSatisfy { !chosen.contains($0.id) })
        let result = plan.completing(with: [1, 3, 5, 7, 9, 11])
        XCTAssertEqual(result.count, 9)
        XCTAssertTrue(chosen.isSubset(of: result))
    }

    func testFullGridIsUnchangedEvenIfAnotherSmartResultArrives() {
        let chosen = Set(0..<9)
        let plan = ManualSelectionFillPlan(candidates: frames, selectedIDs: chosen, limit: 9)
        XCTAssertEqual(plan.additionalCount, 0)
        XCTAssertEqual(plan.completing(with: Array(10..<20)), chosen)
    }

    func testDuplicateUnknownAndExcessResultsCannotEvictExistingChoicesOrOverfillGrid() {
        let chosen: Set<Int> = [1, 8, 17]
        let plan = ManualSelectionFillPlan(candidates: frames, selectedIDs: chosen, limit: 9)
        let result = plan.completing(with: [1, 8, 999, 2, 2, 3, 4, 5, 6, 7, 9, 10])
        XCTAssertEqual(result.count, 9)
        XCTAssertTrue(chosen.isSubset(of: result))
        XCTAssertFalse(result.contains(999))
        XCTAssertFalse(result.contains(9))
    }

    func testTooFewCandidatesAndRepeatedFillKeepAllAvailableManualChoices() {
        let few = Array(frames.prefix(5))
        let plan = ManualSelectionFillPlan(candidates: few, selectedIDs: [0, 3], limit: 9)
        XCTAssertEqual(plan.additionalCount, 3)
        let first = plan.completing(with: [1, 2, 4])
        XCTAssertEqual(first, Set(0..<5))
        let again = ManualSelectionFillPlan(candidates: few, selectedIDs: first, limit: 9)
        XCTAssertEqual(again.additionalCount, 0)
        XCTAssertEqual(again.completing(with: []), first)
    }
}
