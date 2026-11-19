import XCTest
@testable import MenuPocket

final class ScheduleGridGeometryTests: XCTestCase {
    private let monday = try! GregorianDay(key: "2026-11-16")
    private let tuesday = try! GregorianDay(key: "2026-11-17")
    private let metrics = ScheduleGridMetrics(hourHeight: 48)

    private func block(_ start: Int, _ end: Int, day: GregorianDay? = nil, created: TimeInterval = 0,
                       id: String = UUID().uuidString, title: String = "Block") throws -> ScheduleBlock {
        try ScheduleBlock(id: UUID(uuidString: id)!, title: title, day: day ?? monday,
                          startMinute: start, endMinute: end,
                          createdAt: Date(timeIntervalSince1970: created))
    }

    private func layout(_ blocks: [ScheduleBlock]) -> [UUID: ScheduleBlockPlacement] {
        Dictionary(uniqueKeysWithValues: ScheduleOverlapLayout.placements(for: blocks).map { ($0.id, $0) })
    }

    private func assertPlacement(_ placement: ScheduleBlockPlacement?, column: Int, of count: Int,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(placement?.column, column, "column", file: file, line: line)
        XCTAssertEqual(placement?.columnCount, count, "column count", file: file, line: line)
    }

    // MARK: Minutes and offsets

    func testMinuteAndOffsetConvertBothWays() {
        XCTAssertEqual(metrics.minuteHeight, 0.8)
        XCTAssertEqual(metrics.offset(forMinute: 0), 0)
        XCTAssertEqual(metrics.offset(forMinute: 90), 72)
        XCTAssertEqual(metrics.offset(forMinute: 630.5), 504.4, accuracy: 0.0001)
        XCTAssertEqual(metrics.dayHeight, 1152)
        for minute in stride(from: 0, through: 1440, by: 15) {
            XCTAssertEqual(metrics.minute(atOffset: metrics.offset(forMinute: minute)),
                           Double(minute), accuracy: 0.0001)
        }
        // Offsets outside the grid read as minutes outside the day, unclamped.
        XCTAssertEqual(metrics.minute(atOffset: -24), -30, accuracy: 0.0001)
        XCTAssertEqual(metrics.minute(atOffset: 1200), 1500, accuracy: 0.0001)
        // Zoom changes only the scale.
        XCTAssertEqual(ScheduleGridMetrics(hourHeight: 96).offset(forMinute: 90), 144)
    }

    func testRectUsesTimeAndOverlapColumn() throws {
        let alone = ScheduleBlockPlacement(block: try block(600, 690), column: 0, columnCount: 1)
        XCTAssertEqual(metrics.rect(for: alone, columnWidth: 120), CGRect(x: 0, y: 480, width: 120, height: 72))
        let third = ScheduleBlockPlacement(block: try block(600, 690), column: 2, columnCount: 3)
        XCTAssertEqual(metrics.rect(for: third, columnWidth: 120), CGRect(x: 80, y: 480, width: 40, height: 72))
        XCTAssertEqual(third.leadingFraction, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(third.widthFraction, 1.0 / 3.0, accuracy: 0.0001)
    }

    // MARK: Snapping and clamping

    func testSnapRoundsToNearestQuarterHourWithinTheDay() {
        XCTAssertEqual(ScheduleGridGeometry.snappedMinute(0), 0)
        XCTAssertEqual(ScheduleGridGeometry.snappedMinute(7.4), 0)
        XCTAssertEqual(ScheduleGridGeometry.snappedMinute(7.5), 15)
        XCTAssertEqual(ScheduleGridGeometry.snappedMinute(622), 615)
        XCTAssertEqual(ScheduleGridGeometry.snappedMinute(623), 630)
        XCTAssertEqual(ScheduleGridGeometry.snappedMinute(-40), 0)
        XCTAssertEqual(ScheduleGridGeometry.snappedMinute(1439), 1440)
        XCTAssertEqual(ScheduleGridGeometry.snappedMinute(1e12), 1440)
        XCTAssertNil(ScheduleGridGeometry.snappedMinute(.nan))
        XCTAssertNil(ScheduleGridGeometry.snappedMinute(.infinity))
    }

    func testSlotStartFloorsToTheContainingSlot() {
        XCTAssertEqual(ScheduleGridGeometry.slotStartMinute(containing: 614.9), 600)
        XCTAssertEqual(ScheduleGridGeometry.slotStartMinute(containing: 615), 615)
        XCTAssertEqual(ScheduleGridGeometry.slotStartMinute(containing: -5), 0)
        XCTAssertEqual(ScheduleGridGeometry.slotStartMinute(containing: 1440), 1425)
        XCTAssertEqual(ScheduleGridGeometry.slotStartMinute(containing: 5000), 1425)
        XCTAssertNil(ScheduleGridGeometry.slotStartMinute(containing: -.infinity))
    }

    func testClampedStartKeepsTheBlockInsideTheDay() {
        XCTAssertEqual(ScheduleGridGeometry.clampedStart(600, durationMinutes: 60), 600)
        XCTAssertEqual(ScheduleGridGeometry.clampedStart(-45, durationMinutes: 60), 0)
        XCTAssertEqual(ScheduleGridGeometry.clampedStart(1410, durationMinutes: 60), 1380)
        XCTAssertEqual(ScheduleGridGeometry.clampedStart(30, durationMinutes: 1440), 0)
    }

    func testColumnIndexClampsToVisibleDays() {
        XCTAssertEqual(ScheduleGridGeometry.columnIndex(atX: 0, columnWidth: 100, columnCount: 7), 0)
        XCTAssertEqual(ScheduleGridGeometry.columnIndex(atX: 99.9, columnWidth: 100, columnCount: 7), 0)
        XCTAssertEqual(ScheduleGridGeometry.columnIndex(atX: 100, columnWidth: 100, columnCount: 7), 1)
        XCTAssertEqual(ScheduleGridGeometry.columnIndex(atX: -250, columnWidth: 100, columnCount: 7), 0)
        XCTAssertEqual(ScheduleGridGeometry.columnIndex(atX: 2000, columnWidth: 100, columnCount: 7), 6)
        XCTAssertEqual(ScheduleGridGeometry.columnIndex(atX: 500, columnWidth: 100, columnCount: 1), 0)
        XCTAssertNil(ScheduleGridGeometry.columnIndex(atX: 10, columnWidth: 100, columnCount: 0))
        XCTAssertNil(ScheduleGridGeometry.columnIndex(atX: 10, columnWidth: 0, columnCount: 7))
        XCTAssertNil(ScheduleGridGeometry.columnIndex(atX: .nan, columnWidth: 100, columnCount: 7))
    }

    // MARK: Overlap layout

    func testBackToBackBlocksKeepFullWidth() throws {
        let first = try block(600, 660)
        let second = try block(660, 720)
        let placements = layout([second, first])
        assertPlacement(placements[first.id], column: 0, of: 1)
        assertPlacement(placements[second.id], column: 0, of: 1)
    }

    func testTwoOverlappingBlocksEachGetHalf() throws {
        let first = try block(600, 690)
        let second = try block(630, 720)
        let placements = layout([second, first])
        assertPlacement(placements[first.id], column: 0, of: 2)
        assertPlacement(placements[second.id], column: 1, of: 2)
    }

    func testThreeWayOverlapGetsThirds() throws {
        let a = try block(600, 720)
        let b = try block(615, 690)
        let c = try block(645, 705)
        let placements = layout([c, a, b])
        assertPlacement(placements[a.id], column: 0, of: 3)
        assertPlacement(placements[b.id], column: 1, of: 3)
        assertPlacement(placements[c.id], column: 2, of: 3)
        XCTAssertEqual(placements[c.id].map { metrics.rect(for: $0, columnWidth: 90).minX }, 60)
    }

    func testChainedOverlapsShareAGroupAndReuseFreedColumns() throws {
        // A overlaps B, B overlaps C, but A ends before C starts: C reuses A's column.
        let a = try block(540, 600)
        let b = try block(570, 660)
        let c = try block(600, 630)
        // D starts after the group ends and gets full width again.
        let d = try block(660, 690)
        let placements = layout([d, c, b, a])
        assertPlacement(placements[a.id], column: 0, of: 2)
        assertPlacement(placements[b.id], column: 1, of: 2)
        assertPlacement(placements[c.id], column: 0, of: 2)
        assertPlacement(placements[d.id], column: 0, of: 1)
    }

    func testEqualStartsBreakTiesByCreationThenID() throws {
        let older = try block(600, 630, created: 1, id: "FFFFFFFF-0000-0000-0000-000000000000")
        let newer = try block(600, 720, created: 2, id: "00000000-0000-0000-0000-000000000000")
        let lowID = try block(600, 660, created: 3, id: "10000000-0000-0000-0000-000000000000")
        let highID = try block(600, 660, created: 3, id: "20000000-0000-0000-0000-000000000000")
        let blocks = [older, newer, lowID, highID]
        let expected = [older.id, newer.id, lowID.id, highID.id]
        for permutation in [blocks, blocks.reversed(), [highID, older, lowID, newer]] {
            let placements = ScheduleOverlapLayout.placements(for: permutation)
            XCTAssertEqual(placements.map(\.id), expected)
            XCTAssertEqual(placements.map(\.column), [0, 1, 2, 3])
            XCTAssertEqual(Set(placements.map(\.columnCount)), [4])
        }
    }

    func testDaysAreLaidOutIndependently() throws {
        let mondayBlock = try block(600, 720, day: monday)
        let tuesdayBlock = try block(630, 690, day: tuesday)
        let placements = ScheduleOverlapLayout.placements(for: [tuesdayBlock, mondayBlock])
        XCTAssertEqual(placements.map(\.id), [mondayBlock.id, tuesdayBlock.id])
        XCTAssertEqual(placements.map(\.columnCount), [1, 1])
        XCTAssertEqual(ScheduleOverlapLayout.placements(for: []), [])
    }

    // MARK: Create planner

    func testCreateSnapsBothPointsAndIsTheSameUpOrDown() {
        let down = ScheduleDragPlanner.create(anchorMinute: 601, currentMinute: 689)
        XCTAssertEqual(down, ScheduleTimeSpan(startMinute: 600, endMinute: 690))
        XCTAssertEqual(ScheduleDragPlanner.create(anchorMinute: 689, currentMinute: 601), down)
        // Through pointer offsets, as the view will call it.
        let anchor = metrics.minute(atOffset: metrics.offset(forMinute: 600))
        let current = metrics.minute(atOffset: metrics.offset(forMinute: 690))
        XCTAssertEqual(ScheduleDragPlanner.create(anchorMinute: anchor, currentMinute: current), down)
        XCTAssertEqual(ScheduleDragPlanner.create(anchorMinute: current, currentMinute: anchor), down)
    }

    func testCreateShorterThanASlotGrowsToFifteenMinutes() {
        XCTAssertEqual(ScheduleDragPlanner.create(anchorMinute: 600, currentMinute: 604),
                       ScheduleTimeSpan(startMinute: 600, endMinute: 615))
        XCTAssertEqual(ScheduleDragPlanner.create(anchorMinute: 1438, currentMinute: 1500),
                       ScheduleTimeSpan(startMinute: 1425, endMinute: 1440))
        XCTAssertEqual(ScheduleDragPlanner.create(anchorMinute: -20, currentMinute: -90),
                       ScheduleTimeSpan(startMinute: 0, endMinute: 15))
    }

    func testCreateClampsToTheDayAndRefusesNonFiniteInput() {
        XCTAssertEqual(ScheduleDragPlanner.create(anchorMinute: 1380, currentMinute: 2000),
                       ScheduleTimeSpan(startMinute: 1380, endMinute: 1440))
        XCTAssertEqual(ScheduleDragPlanner.create(anchorMinute: 60, currentMinute: -300),
                       ScheduleTimeSpan(startMinute: 0, endMinute: 60))
        XCTAssertNil(ScheduleDragPlanner.create(anchorMinute: .nan, currentMinute: 600))
        XCTAssertNil(ScheduleDragPlanner.create(anchorMinute: 600, currentMinute: .infinity))
    }

    func testTimeSpanRefusesInvalidTimes() {
        XCTAssertNil(ScheduleTimeSpan(startMinute: 600, endMinute: 600))
        XCTAssertNil(ScheduleTimeSpan(startMinute: 610, endMinute: 630))
        XCTAssertNil(ScheduleTimeSpan(startMinute: 1440, endMinute: 1455))
        XCTAssertEqual(ScheduleTimeSpan(startMinute: 0, endMinute: 1440)?.durationMinutes, 1440)
    }

    // MARK: Resize planner

    func testResizeSnapsTheEndAndKeepsEverythingElse() throws {
        let original = try block(600, 660, title: "Gym")
        let resized = try XCTUnwrap(ScheduleDragPlanner.resize(original, endMinute: 738))
        XCTAssertEqual(resized, try ScheduleBlockContent(title: "Gym", day: monday,
                                                         startMinute: 600, endMinute: 735))
    }

    func testResizeAboveTheStartYieldsTheMinimumNeverAReversedBlock() throws {
        let original = try block(600, 660)
        for rawEnd in [610.0, 600, 540, -100] {
            let resized = try XCTUnwrap(ScheduleDragPlanner.resize(original, endMinute: rawEnd))
            XCTAssertEqual(resized.startMinute, 600, "\(rawEnd)")
            XCTAssertEqual(resized.endMinute, 615, "\(rawEnd)")
        }
    }

    func testResizePastMidnightStopsAtTheEndOfTheDay() throws {
        let original = try block(1380, 1410)
        XCTAssertEqual(ScheduleDragPlanner.resize(original, endMinute: 1600)?.endMinute, 1440)
        XCTAssertNil(ScheduleDragPlanner.resize(original, endMinute: .nan))
    }

    // MARK: Move planner

    func testMoveSnapsTheStartAndKeepsTheDuration() throws {
        let original = try block(600, 660, title: "Gym")
        let moved = try XCTUnwrap(ScheduleDragPlanner.move(original, to: tuesday, startMinute: 868))
        XCTAssertEqual(moved, try ScheduleBlockContent(title: "Gym", day: tuesday,
                                                       startMinute: 870, endMinute: 930))
        XCTAssertEqual(ScheduleDragPlanner.move(original, to: monday, startMinute: 604)?.startMinute, 600)
    }

    func testMovePastEitherEndOfTheDayClampsAndKeepsTheDuration() throws {
        let original = try block(600, 690)
        let top = try XCTUnwrap(ScheduleDragPlanner.move(original, to: monday, startMinute: -200))
        XCTAssertEqual([top.startMinute, top.endMinute], [0, 90])
        let bottom = try XCTUnwrap(ScheduleDragPlanner.move(original, to: monday, startMinute: 1400))
        XCTAssertEqual([bottom.startMinute, bottom.endMinute], [1350, 1440])
        let far = try XCTUnwrap(ScheduleDragPlanner.move(original, to: monday, startMinute: 1e15))
        XCTAssertEqual([far.startMinute, far.endMinute], [1350, 1440])

        let wholeDay = try block(0, 1440)
        let stays = try XCTUnwrap(ScheduleDragPlanner.move(wholeDay, to: tuesday, startMinute: 300))
        XCTAssertEqual([stays.startMinute, stays.endMinute], [0, 1440])
        XCTAssertEqual(stays.day, tuesday)

        XCTAssertNil(ScheduleDragPlanner.move(original, to: monday, startMinute: .nan))
    }
}
