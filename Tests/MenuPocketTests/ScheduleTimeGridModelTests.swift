import Foundation
import XCTest
@testable import MenuPocket

final class ScheduleTimeGridModelTests: XCTestCase {
    private func day(_ key: String) throws -> GregorianDay { try GregorianDay(key: key) }

    private func block(_ title: String, _ key: String, _ start: Int, _ end: Int,
                       id: UUID = UUID(), created: TimeInterval = 0) throws -> ScheduleBlock {
        try ScheduleBlock(id: id, title: title, day: day(key), startMinute: start, endMinute: end,
                          createdAt: Date(timeIntervalSince1970: created))
    }

    /// Monday 16 ... Sunday 22 November 2026.
    private func week() throws -> [GregorianDay] {
        try SchedulePeriod(mode: .week, anchor: day("2026-11-18")).days
    }

    // MARK: Columns

    func testWeekPlacesEachBlockInItsDayColumnWithTodayMarked() throws {
        let standup = try block("Standup", "2026-11-16", 540, 555)
        let review = try block("Review", "2026-11-18", 600, 660)
        let gym = try block("Gym", "2026-11-22", 1080, 1140)
        let model = try ScheduleTimeGridModel(days: week(), blocks: [gym, review, standup],
                                              today: day("2026-11-18"))

        XCTAssertEqual(model.days.map(\.id), ["2026-11-16", "2026-11-17", "2026-11-18", "2026-11-19",
                                              "2026-11-20", "2026-11-21", "2026-11-22"])
        XCTAssertEqual(model.days.map(\.weekdaySymbol), ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        XCTAssertEqual(model.days.map(\.isToday), [false, false, true, false, false, false, false])
        XCTAssertEqual(model.todayIndex, 2)
        XCTAssertEqual(model.days[0].placements.map(\.block), [standup])
        XCTAssertEqual(model.days[1].placements, [])
        XCTAssertEqual(model.days[2].placements.map(\.block), [review])
        XCTAssertEqual(model.days[6].placements.map(\.block), [gym])
        XCTAssertEqual(model.columnIndex(of: try day("2026-11-22")), 6)
        XCTAssertNil(model.columnIndex(of: try day("2026-11-23")))
    }

    func testOverlapsSitSideBySideAndNoBlockIsDropped() throws {
        let first = try block("A", "2026-11-17", 600, 720, created: 1)
        let second = try block("B", "2026-11-17", 630, 690, created: 2)
        let third = try block("C", "2026-11-17", 660, 750, created: 3)
        let after = try block("D", "2026-11-17", 750, 780, created: 4)
        let model = try ScheduleTimeGridModel(days: week(), blocks: [after, third, second, first],
                                              today: day("2026-11-18"))
        let tuesday = model.days[1].placements

        XCTAssertEqual(tuesday.count, 4)
        XCTAssertEqual(tuesday.map(\.block.title), ["A", "B", "C", "D"])
        XCTAssertEqual(tuesday.map(\.column), [0, 1, 2, 0])
        XCTAssertEqual(tuesday.map(\.columnCount), [3, 3, 3, 1])
        // Side by side: the overlapping rectangles do not intersect.
        let metrics = ScheduleTimeGridSize.metrics
        let rects = tuesday.prefix(3).map { metrics.rect(for: $0, columnWidth: 90) }
        XCTAssertEqual(rects.map(\.minX), [0, 30, 60])
        XCTAssertFalse(rects[0].intersects(rects[1]))
        XCTAssertFalse(rects[1].intersects(rects[2]))
    }

    func testDayViewHasOneColumnWithTheSameBlocksAsTheWeek() throws {
        let tuesday = try day("2026-11-17")
        let blocks = [try block("A", "2026-11-17", 600, 720), try block("B", "2026-11-17", 630, 690),
                      try block("Other", "2026-11-18", 600, 660)]
        let week = try ScheduleTimeGridModel(days: week(), blocks: blocks, today: day("2026-11-18"))
        let dayBlocks = blocks.filter { $0.day == tuesday }
        let single = ScheduleTimeGridModel(days: try SchedulePeriod(mode: .day, anchor: tuesday).days,
                                           blocks: dayBlocks, today: try day("2026-11-18"))

        XCTAssertEqual(single.days.map(\.id), ["2026-11-17"])
        XCTAssertNil(single.todayIndex)
        XCTAssertEqual(single.days[0].placements, week.days[1].placements)
    }

    func testBlocksOutsideTheVisibleDaysAreLeftOut() throws {
        let model = try ScheduleTimeGridModel(days: [day("2026-11-17")],
                                              blocks: [block("Elsewhere", "2026-11-18", 0, 60)],
                                              today: day("2026-11-18"))
        XCTAssertEqual(model.days.flatMap(\.placements), [])
    }

    // MARK: Text and identifiers

    func testHeaderTextAndIdentifiers() throws {
        let model = try ScheduleTimeGridModel(days: week(), blocks: [], today: day("2026-11-18"))
        XCTAssertEqual(model.days[1].headerLabel, "Tuesday 17 November")
        XCTAssertEqual(model.days[2].headerLabel, "Wednesday 18 November, today")
        XCTAssertEqual(model.days[2].weekdayName, "Wednesday")
        XCTAssertEqual(model.days[2].dayNumber, "18")
        XCTAssertEqual(model.days[2].headerIdentifier, "scheduleDayHeader-2026-11-18")
        XCTAssertEqual(model.days[2].columnIdentifier, "scheduleDayColumn-2026-11-18")
    }

    func testBlockLabelNamesTitleDayAndTimeRange() throws {
        let id = try XCTUnwrap(UUID(uuidString: "6F1C1E9A-2B47-4C1A-9A51-0D2E3F4A5B6C"))
        let ats = try block("ats", "2026-06-09", 600, 660, id: id)
        XCTAssertEqual(ScheduleBlockText.accessibilityLabel(ats), "ats, Tuesday 9 June, 10:00 to 11:00")
        XCTAssertEqual(ScheduleBlockText.timeRange(ats), "10:00–11:00")
        XCTAssertEqual(ScheduleBlockText.start(ats), "10:00")
        XCTAssertEqual(ScheduleBlockText.tooltip(ats), "ats\n10:00–11:00")
        XCTAssertEqual(ScheduleBlockText.identifier(ats), "scheduleBlock-6F1C1E9A-2B47-4C1A-9A51-0D2E3F4A5B6C")

        let late = try block("Wind down", "2026-11-22", 1425, 1440)
        XCTAssertEqual(ScheduleBlockText.accessibilityLabel(late), "Wind down, Sunday 22 November, 23:45 to 24:00")
    }

    func testTitleWrapsOnlyWhenEveryWordFits() {
        let title = "Quarterly planning with the whole product team"
        // "Quarterly" is 9 characters: 54 pt at 6 pt per character.
        XCTAssertEqual(ScheduleBlockText.titleLineLimit(title, textWidth: 60, availableLines: 4, characterWidth: 6), 4)
        XCTAssertEqual(ScheduleBlockText.titleLineLimit(title, textWidth: 54, availableLines: 4, characterWidth: 6), 4)
        XCTAssertEqual(ScheduleBlockText.titleLineLimit(title, textWidth: 53, availableLines: 4, characterWidth: 6), 1)
        XCTAssertEqual(ScheduleBlockText.titleLineLimit("Retro", textWidth: 20, availableLines: 3, characterWidth: 6), 1)
        XCTAssertEqual(ScheduleBlockText.titleLineLimit(title, textWidth: 500, availableLines: 1, characterWidth: 6), 1)
    }

    // MARK: Sizes, current time and scrolling

    func testColumnsShareTheWidthRightOfTheGutter() {
        XCTAssertEqual(ScheduleTimeGridSize.columnWidth(contentWidth: 534, columnCount: 7), 70)
        XCTAssertEqual(ScheduleTimeGridSize.columnWidth(contentWidth: 534, columnCount: 1), 490)
        XCTAssertEqual(ScheduleTimeGridSize.columnWidth(contentWidth: 20, columnCount: 7), 0)
        XCTAssertEqual(ScheduleTimeGridSize.columnWidth(contentWidth: 534, columnCount: 0), 0)
        // A legacy scroller narrows the content; a stale, wider measurement never widens the grid.
        XCTAssertEqual(ScheduleTimeGridSize.scrollerInset(paneWidth: 600, scrollContentWidth: 585), 15)
        XCTAssertEqual(ScheduleTimeGridSize.scrollerInset(paneWidth: 600, scrollContentWidth: 600), 0)
        XCTAssertEqual(ScheduleTimeGridSize.scrollerInset(paneWidth: 550, scrollContentWidth: 750), 0)
        XCTAssertEqual(ScheduleTimeGridSize.scrollerInset(paneWidth: 900, scrollContentWidth: 550), 24)
        XCTAssertEqual(ScheduleTimeGridSize.scrollerInset(paneWidth: 600, scrollContentWidth: 0), 0)
        // One point per minute: a 15-minute block is 15 pt tall.
        XCTAssertEqual(ScheduleTimeGridSize.metrics.offset(forMinute: 15), 15)
        XCTAssertEqual(ScheduleTimeGridSize.metrics.dayHeight, 1440)
    }

    func testCurrentTimeReadsTheCalendarsTimeZone() throws {
        var toronto = Calendar(identifier: .gregorian)
        toronto.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-18T21:30:30Z"))
        let now = try XCTUnwrap(ScheduleCurrentTime(instant: instant, calendar: toronto))
        XCTAssertEqual(now.day, try day("2026-11-18"))
        XCTAssertEqual(now.minute, 16 * 60 + 30.5, accuracy: 0.0001)
        XCTAssertEqual(now.clockText, "16:30")

        // Past local midnight the reading belongs to the next civil day.
        let late = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-19T05:10:00Z"))
        let next = try XCTUnwrap(ScheduleCurrentTime(instant: late, calendar: toronto))
        XCTAssertEqual(next.day, try day("2026-11-19"))
        XCTAssertEqual(next.minute, 10, accuracy: 0.0001)
    }

    func testCurrentTimeLineAppearsOnlyInTheVisibleTodayColumn() throws {
        let model = try ScheduleTimeGridModel(days: week(), blocks: [], today: day("2026-11-18"))
        XCTAssertEqual(model.columnIndex(of: try day("2026-11-18")), 2)
        let nextWeek = try ScheduleTimeGridModel(days: SchedulePeriod(mode: .week, anchor: day("2026-11-25")).days,
                                                 blocks: [], today: day("2026-11-18"))
        XCTAssertNil(nextWeek.todayIndex)
        XCTAssertNil(nextWeek.columnIndex(of: try day("2026-11-18")))
    }

    func testInitialScrollShowsTheHourBeforeNowOrEarlyMorning() throws {
        let model = try ScheduleTimeGridModel(days: week(), blocks: [], today: day("2026-11-18"))
        let afternoon = ScheduleCurrentTime(day: try day("2026-11-18"), minute: 16 * 60 + 5)
        XCTAssertEqual(model.initialScrollHour(current: afternoon), 14)
        XCTAssertEqual(model.initialScrollHour(current: ScheduleCurrentTime(day: try day("2026-11-18"), minute: 80)), 0)
        XCTAssertEqual(model.initialScrollHour(current: ScheduleCurrentTime(day: try day("2026-11-18"), minute: 1439)), 21)
        // Today not visible, or no clock reading: early morning.
        XCTAssertEqual(model.initialScrollHour(current: ScheduleCurrentTime(day: try day("2026-11-25"), minute: 960)),
                       ScheduleTimeGridModel.morningHour)
        XCTAssertEqual(model.initialScrollHour(current: nil), 7)
    }
}
