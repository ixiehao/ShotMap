import AppKit
import XCTest
@testable import ShotMapApp

final class ManualTimelineMarkerTests: XCTestCase {
    func testPinsAndScrubberUseTheSameCoordinatesIncludingEndpoints() {
        for width in [CGFloat(1), 12, 500, 1_200] {
            for time in [0.0, 0.001, 12.345, 59.999, 60] {
                let x = ManualTimelineGeometry.center(time: time, duration: 60, width: width)
                XCTAssertGreaterThanOrEqual(x, 0)
                XCTAssertLessThanOrEqual(x, width)
                if width > 12 {
                    XCTAssertEqual(ManualTimelineGeometry.time(at: x, duration: 60, width: width), time, accuracy: 0.000_001)
                }
            }
        }
        XCTAssertEqual(ManualTimelineGeometry.time(at: -100, duration: 60, width: 500), 0)
        XCTAssertEqual(ManualTimelineGeometry.time(at: 900, duration: 60, width: 500), 60)
        XCTAssertEqual(ManualTimelineGeometry.time(at: .nan, duration: 60, width: 500), 0)
        XCTAssertEqual(ManualTimelineGeometry.center(time: .nan, duration: 60, width: 500), 6)
    }

    func testSeparatedFramesKeepTheirOwnChronologicalNumbersAndExactTimes() {
        let entries = [
            ManualTimelineSelection(id: 55, number: 1, time: 5.123),
            ManualTimelineSelection(id: 2, number: 2, time: 14.567),
            ManualTimelineSelection(id: 80, number: 3, time: 30.789)
        ]
        let groups = ManualTimelineGeometry.groups(for: entries, duration: 60, width: 650)
        XCTAssertEqual(groups.map(\.label), ["1", "2", "3"])
        XCTAssertEqual(groups.flatMap(\.selections), entries)
    }

    func testAddButtonFollowsPlayheadAndAvoidsEndpointLabelsInNarrowAndWideLayouts() {
        for width in [CGFloat(520), 650, 1_200] {
            for buttonWidth in [CGFloat(84), 124, 160] {
                for time in [0.0, 10, 30, 50, 60] {
                    let x = ManualTimelineGeometry.insertionOrigin(
                        time: time, duration: 60, width: width, buttonWidth: buttonWidth, endpointWidth: 56
                    )
                    XCTAssertGreaterThanOrEqual(x, 56)
                    XCTAssertLessThanOrEqual(x + buttonWidth, width - 56)
                    if time == 30 {
                        XCTAssertEqual(x + buttonWidth / 2, width / 2, accuracy: 0.000_001)
                    }
                }
            }
        }
    }

    func testCrowdedSelectionsKeepEveryFrameReachableWithoutOverlappingBadgeHeads() {
        for width in [CGFloat(300), 520, 1_000] {
            for spread in [0.001, 0.9] {
                let entries = (0..<64).map {
                    ManualTimelineSelection(id: $0, number: $0 + 1, time: 10 + Double($0) * spread)
                }
                let groups = ManualTimelineGeometry.groups(for: entries, duration: 90, width: width)
                XCTAssertEqual(groups.flatMap(\.selections), entries, "Grouping must preserve timestamps and gallery numbering")
                XCTAssertTrue(groups.contains { $0.selections.count > 1 })
                for pair in zip(groups, groups.dropFirst()) {
                    XCTAssertGreaterThanOrEqual(pair.1.center - pair.0.center, 32 - 0.000_001)
                }
                for group in groups {
                    XCTAssertGreaterThanOrEqual(group.center, 16)
                    XCTAssertLessThanOrEqual(group.center, width - 16)
                }
            }
        }
    }

    func testAddingOrRemovingAnEarlierSelectionRenumbersPinsFromCurrentSelection() {
        let first = ManualTimelineSelection(id: 10, number: 1, time: 5)
        let later = ManualTimelineSelection(id: 20, number: 2, time: 15)
        let both = ManualTimelineGeometry.groups(for: [first, later], duration: 60, width: 650)
        XCTAssertEqual(both.map(\.label), ["1", "2"])
        let remaining = ManualTimelineSelection(id: later.id, number: 1, time: later.time)
        let afterRemoval = ManualTimelineGeometry.groups(for: [remaining], duration: 60, width: 650)
        XCTAssertEqual(afterRemoval.map(\.label), ["1"])
        XCTAssertEqual(afterRemoval.first?.selections.first?.time, later.time)
        XCTAssertTrue(ManualTimelineGeometry.groups(for: [], duration: 60, width: 650).isEmpty)
        XCTAssertTrue(ManualTimelineGeometry.groups(for: [first], duration: 60, width: .nan).isEmpty)
    }

    @MainActor
    func testCompactTimeFieldFitsCompleteTimestampsAndLongVideos() {
        let font = NSFont.monospacedSystemFont(ofSize: 18, weight: .semibold)
        for duration in [60.0, 3_661.234, 360_000] {
            let text = TimestampFormatter.editableString(for: duration)
            let glyphWidth = (text as NSString).size(withAttributes: [.font: font]).width
            XCTAssertGreaterThanOrEqual(ManualEditorLayout.timeFieldWidth(duration: duration), glyphWidth + 16)
        }
        XCTAssertLessThan(ManualEditorLayout.timeFieldWidth(duration: 60), 160)
        XCTAssertGreaterThan(ManualEditorLayout.timeFieldWidth(duration: 360_000), ManualEditorLayout.timeFieldWidth(duration: 60))
    }

    @MainActor
    func testAllSevenFrameUnitsFitWithoutTruncationInCompactStepButtons() {
        let numberFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        let unitFont = NSFont.systemFont(ofSize: 9, weight: .medium)
        let numberWidth = ("−5" as NSString).size(withAttributes: [.font: numberFont]).width
        for language in AppLanguage.allCases {
            let unit = language.text("editor.frameUnit.short")
            let width = numberWidth + 2 + (unit as NSString).size(withAttributes: [.font: unitFont]).width
            XCTAssertLessThanOrEqual(width, 44, "The full unit must fit in \(language.rawValue)")
        }
    }
}
