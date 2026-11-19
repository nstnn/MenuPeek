import Foundation
import XCTest
@testable import MenuPocket

final class ScheduleMonthModelTests: XCTestCase {
    private func day(_ key: String) throws -> GregorianDay { try GregorianDay(key: key) }

    private func block(_ title: String, _ key: String, _ start: Int, _ end: Int,
                       id: UUID = UUID(), created: TimeInterval = 0) throws -> ScheduleBlock {
        try ScheduleBlock(id: id, title: title, day: day(key), startMinute: start, endMinute: end,
                          createdAt: Date(timeIntervalSince1970: created))
    }

    /// November 2026: starts on a Sunday, so Monday-first it spans six weeks.
    private func november(blocks: [ScheduleBlock], selected: String? = nil) throws -> ScheduleMonthModel {
        try ScheduleMonthModel(grid: ScheduleMonthGrid(containing: day("2026-11-18")), blocks: blocks,
                               today: day("2026-11-18"), selectedDay: selected.map(day))
    }

    // MARK: Grouping and order

    func testSeededMonthListsEachDaysBlocksInTimeOrder() throws {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let lunch = try block("Lunch", "2026-11-18", 720, 780)
        let review = try block("Design review", "2026-11-18", 600, 660, created: 2)
        let pairing = try block("Pairing", "2026-11-18", 630, 690)
        let early = try block("Early", "2026-11-18", 600, 615, created: 5)
        let tieB = try block("Tie B", "2026-11-03", 540, 600, id: second, created: 1)
        let tieA = try block("Tie A", "2026-11-03", 540, 600, id: first, created: 1)
        let monthEnd = try block("Month end", "2026-11-30", 1425, 1440)
        let model = try november(blocks: [lunch, monthEnd, pairing, tieB, review, early, tieA])

        XCTAssertEqual(model.day(try day("2026-11-18"))?.blocks.map(\.title),
                       ["Early", "Design review", "Pairing", "Lunch"])
        XCTAssertEqual(model.day(try day("2026-11-03"))?.blocks.map(\.title), ["Tie A", "Tie B"])
        XCTAssertEqual(model.day(try day("2026-11-30"))?.blocks, [monthEnd])
        XCTAssertEqual(model.day(try day("2026-11-19"))?.blocks, [])
        // Every block lands under exactly one day.
        XCTAssertEqual(model.days.map(\.blocks.count).reduce(0, +), 7)
    }

    func testCellsAreMondayFirstWithInertPaddingAndStableIdentifiers() throws {
        let model = try november(blocks: [], selected: "2026-11-02")

        XCTAssertEqual(model.weekdaySymbols, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        XCTAssertEqual(model.weeks.count, 6)
        XCTAssertTrue(model.weeks.allSatisfy { $0.count == 7 })
        // 1 November 2026 is a Sunday: six padding cells before it, six after the 30th.
        XCTAssertEqual(model.weeks[0].map(\.id),
                       ["padding-0", "padding-1", "padding-2", "padding-3", "padding-4", "padding-5", "2026-11-01"])
        XCTAssertEqual(model.weeks[5].first?.id, "2026-11-30")
        XCTAssertEqual(model.weeks[5].dropFirst().map(\.id).allSatisfy { $0.hasPrefix("padding-") }, true)
        XCTAssertEqual(model.days.count, 30)
        XCTAssertEqual(model.days.first?.identifier, "scheduleMonthDay-2026-11-01")
        XCTAssertEqual(model.days.filter(\.isToday).map(\.id), ["2026-11-18"])
        XCTAssertEqual(model.days.filter(\.isSelected).map(\.id), ["2026-11-02"])
    }

    func testBlocksOutsideTheMonthAreLeftOut() throws {
        let inside = try block("Inside", "2026-11-01", 600, 660)
        let before = try block("Before", "2026-10-31", 600, 660)
        let after = try block("After", "2026-12-01", 600, 660)
        let model = try november(blocks: [before, inside, after])

        XCTAssertEqual(model.days.flatMap(\.blocks), [inside])
    }

    // MARK: Lines and overflow

    func testAllBlocksShowWhenTheyFit() throws {
        let blocks = try (0..<3).map { try block("B\($0)", "2026-11-18", 600 + $0 * 15, 615 + $0 * 15) }
        let cell = try XCTUnwrap(november(blocks: blocks).day(day("2026-11-18")))

        XCTAssertEqual(cell.lines(count: 3), ScheduleMonthLines(blocks: blocks, overflow: 0))
        XCTAssertEqual(cell.lines(count: 5), ScheduleMonthLines(blocks: blocks, overflow: 0))
        XCTAssertNil(cell.lines(count: 3).overflowText)
    }

    func testMoreBlocksThanFitShowTheFirstOnesAndTheOverflowCount() throws {
        let blocks = try (0..<5).map { try block("B\($0)", "2026-11-18", 600 + $0 * 15, 615 + $0 * 15) }
        let cell = try XCTUnwrap(november(blocks: blocks.reversed()).day(day("2026-11-18")))

        let three = cell.lines(count: 3)
        XCTAssertEqual(three.blocks.map(\.title), ["B0", "B1"])
        XCTAssertEqual(three.overflow, 3)
        XCTAssertEqual(three.overflowText, "+3 more")
        // The minimum: one block line plus "+N more".
        let two = cell.lines(count: 2)
        XCTAssertEqual(two.blocks.map(\.title), ["B0"])
        XCTAssertEqual(two.overflowText, "+4 more")
        XCTAssertEqual(cell.lines(count: 4).overflowText, "+2 more")
        // Shown lines plus the overflow line never exceed the line count.
        for count in 1...6 {
            let lines = cell.lines(count: count)
            XCTAssertLessThanOrEqual(lines.blocks.count + (lines.overflow > 0 ? 1 : 0), max(count, 1))
            XCTAssertEqual(lines.blocks.count + lines.overflow, 5)
        }
    }

    // MARK: Line-count rule

    func testLineCountFollowsCellHeight() {
        let chrome = ScheduleMonthSize.cellChrome
        let line = ScheduleMonthSize.lineHeight

        XCTAssertEqual(ScheduleMonthSize.lineCount(cellHeight: chrome + 4 * line), 4)
        XCTAssertEqual(ScheduleMonthSize.lineCount(cellHeight: chrome + 4 * line - 0.5), 3)
        XCTAssertEqual(ScheduleMonthSize.lineCount(cellHeight: chrome + 7 * line + 3), 7)
        XCTAssertEqual(ScheduleMonthSize.lineCount(cellHeight: ScheduleMonthSize.minimumRowHeight), 2)
    }

    func testLineCountNeverDropsBelowOneLinePlusOverflow() {
        for height: CGFloat in [0, -40, 10, ScheduleMonthSize.cellChrome, .nan, .infinity, -.infinity] {
            XCTAssertEqual(ScheduleMonthSize.lineCount(cellHeight: height), 2, "\(height)")
        }
        XCTAssertEqual(ScheduleMonthSize.lineCount(cellHeight: .greatestFiniteMagnitude), ScheduleMonthSize.maximumLines)
    }

    func testRowHeightSharesTheSpaceBelowTheWeekdayRow() {
        let header = ScheduleMonthSize.weekdayHeaderHeight
        XCTAssertEqual(ScheduleMonthSize.rowHeight(availableHeight: header + 6 * 70, weekCount: 6), 70)
        XCTAssertEqual(ScheduleMonthSize.rowHeight(availableHeight: header + 5 * 70 + 4, weekCount: 5), 70)
        // Too little room keeps the minimum; the grid then scrolls instead of clipping.
        XCTAssertEqual(ScheduleMonthSize.rowHeight(availableHeight: 100, weekCount: 6),
                       ScheduleMonthSize.minimumRowHeight)
        XCTAssertEqual(ScheduleMonthSize.rowHeight(availableHeight: .nan, weekCount: 6),
                       ScheduleMonthSize.minimumRowHeight)
        XCTAssertEqual(ScheduleMonthSize.rowHeight(availableHeight: 400, weekCount: 0),
                       ScheduleMonthSize.minimumRowHeight)
        XCTAssertEqual(ScheduleMonthSize.gridHeight(rowHeight: 70, weekCount: 6), header + 420)
    }

    /// A six-week month in the smallest pane still fits its minimum rows. The
    /// 800×560 window leaves about 400 pt under the Calendar header.
    func testSixWeekMonthFitsAtTheMinimumWindowHeight() {
        XCTAssertLessThanOrEqual(ScheduleMonthSize.gridHeight(rowHeight: ScheduleMonthSize.minimumRowHeight,
                                                              weekCount: 6), 400)
    }

    // MARK: Spoken text

    func testSpokenLabelNamesTheDateAndBlockCount() throws {
        let review = try block("Design review", "2026-11-18", 600, 660)
        let pairing = try block("Pairing", "2026-11-18", 630, 690)
        let gym = try block("Gym", "2026-11-20", 1080, 1140)
        let model = try november(blocks: [pairing, review, gym])

        let today = try XCTUnwrap(model.day(day("2026-11-18")))
        XCTAssertEqual(today.accessibilityLabel, "Wednesday 18 November, today, 2 blocks")
        XCTAssertEqual(today.accessibilityValue, "10:00 Design review, 10:30 Pairing")
        XCTAssertEqual(today.tooltip,
                       "Wednesday, November 18, 2026\n10:00–11:00 Design review\n10:30–11:30 Pairing")
        XCTAssertEqual(model.day(try day("2026-11-20"))?.accessibilityLabel, "Friday 20 November, 1 block")
        XCTAssertEqual(model.day(try day("2026-11-19"))?.accessibilityLabel, "Thursday 19 November, no blocks")
        XCTAssertEqual(model.day(try day("2026-11-19"))?.accessibilityValue, "")
    }
}
