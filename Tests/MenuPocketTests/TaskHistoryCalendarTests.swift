import XCTest
@testable import MenuPocket

final class TaskHistoryCalendarTests: XCTestCase {
    func testMonthLengthsAndClampingFollowGregorianLeapRules() throws {
        for (key, count) in [("2026-01-15", 31), ("2026-04-15", 30), ("2025-02-15", 28), ("2024-02-15", 29),
                             ("1900-02-01", 28), ("2000-02-01", 29), ("2026-12-31", 31)] {
            let month = try HistoryDayRange.month(containing: day(key))
            XCTAssertEqual(month.dayCount, count, key)
            XCTAssertEqual(try month.day(clampedTo: 31).day, count, key)
            XCTAssertEqual(try month.day(clampedTo: 0).day, 1, key)
        }
    }

    func testWeekdaysMatchFoundationAcrossYearsAndDSTZones() throws {
        for identifier in ["UTC", "America/Toronto"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: identifier)!
            for year in [1999, 2000, 2024, 2025, 2026, 2027, 2100] {
                for month in 1...12 {
                    let first = try day(String(format: "%04d-%02d-01", year, month))
                    let date = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
                    XCTAssertEqual(first.weekday, calendar.component(.weekday, from: date), first.key)
                    let range = try HistoryDayRange.month(containing: first)
                    XCTAssertEqual(range.dayCount, calendar.range(of: .day, in: .month, for: date)!.count, first.key)
                }
            }
        }
    }

    func testEveryStartingWeekdayProducesSundayFirstSevenColumnGeometry() throws {
        var startingWeekdays = Set<Int>()
        for month in 1...12 {
            let range = try HistoryDayRange.month(containing: day(String(format: "2026-%02d-01", month)))
            let grid = try HistoryMonthGrid(month: range, today: day("2026-10-06"), selectedDay: nil, summaries: [])
            startingWeekdays.insert(range.start.weekday)

            XCTAssertEqual(grid.weekdaySymbols, ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
            XCTAssertTrue(grid.weeks.allSatisfy { $0.count == 7 })
            XCTAssertTrue((4...6).contains(grid.weeks.count))
            XCTAssertEqual(leadingPadding(grid), range.start.weekday - 1, range.start.key)
            XCTAssertEqual(days(grid).map(\.day.day), Array(1...range.dayCount))
            XCTAssertEqual(Set(grid.cells.map(\.id)).count, grid.cells.count)
            XCTAssertLessThan(grid.cells.count - leadingPadding(grid) - range.dayCount, 7)
        }
        XCTAssertEqual(startingWeekdays, Set(1...7))
    }

    func testFirstWeekdayRotatesHeadersAndPaddingWithoutChangingDays() throws {
        let march = try HistoryDayRange.month(containing: day("2026-03-01")) // Sunday
        let grid = try HistoryMonthGrid(month: march, today: day("2026-10-06"), selectedDay: nil,
                                        summaries: [], firstWeekday: 2)
        XCTAssertEqual(grid.weekdaySymbols.first, "Mon")
        XCTAssertEqual(grid.weekdaySymbols.last, "Sun")
        XCTAssertEqual(leadingPadding(grid), 6)
        XCTAssertEqual(days(grid).count, 31)
        for invalid in [0, 8] {
            XCTAssertThrowsError(try HistoryMonthGrid(month: march, today: day("2026-10-06"), selectedDay: nil,
                                                      summaries: [], firstWeekday: invalid))
        }
    }

    func testDecemberToJanuaryContinuesWeekdaysAcrossYearBoundary() throws {
        let today = try day("2026-10-06")
        let december = try HistoryMonthGrid(month: .month(containing: day("2026-12-01")), today: today,
                                            selectedDay: nil, summaries: [])
        let january = try HistoryMonthGrid(month: .month(containing: december.month.end), today: today,
                                           selectedDay: nil, summaries: [])
        XCTAssertEqual(january.month.start.key, "2027-01-01")
        let lastColumn = (leadingPadding(december) + 30) % 7
        XCTAssertEqual(leadingPadding(january), (lastColumn + 1) % 7)
    }

    func testLoadedMonthCellStatesAndMarkers() throws {
        let today = try day("2026-10-06")
        let october = try HistoryDayRange.month(containing: today)
        let grid = try HistoryMonthGrid(month: october, today: today, selectedDay: day("2026-10-04"),
                                        summaries: [summary("2026-10-04", 3, 5), summary("2026-10-06", 0, 2),
                                                    summary("2026-10-20", 1, 1)])
        let cells = Dictionary(uniqueKeysWithValues: days(grid).map { ($0.day.key, $0) })

        XCTAssertEqual(cells["2026-10-04"]?.countText, "3/5")
        XCTAssertEqual(cells["2026-10-04"]?.statusText, "3 of 5 complete")
        XCTAssertEqual(cells["2026-10-04"]?.isSelected, true)
        XCTAssertEqual(cells["2026-10-04"]?.isToday, false)
        XCTAssertEqual(cells["2026-10-06"]?.isToday, true)
        XCTAssertEqual(cells["2026-10-06"]?.isSelected, false)
        XCTAssertEqual(cells["2026-10-05"]?.countText, "0/0")
        XCTAssertEqual(cells["2026-10-05"]?.statusText, "No tasks")
        XCTAssertEqual(cells["2026-10-05"]?.isSelectable, true)
        XCTAssertEqual(cells["2026-10-07"]?.countText, "—")
        XCTAssertEqual(cells["2026-10-07"]?.statusText, "Not yet")
        XCTAssertEqual(cells["2026-10-07"]?.isSelectable, false)
        // Saved future rows from an earlier clock/time-zone change stay readable.
        XCTAssertEqual(cells["2026-10-20"]?.countText, "1/1")
        XCTAssertEqual(cells["2026-10-20"]?.isFuture, true)
        XCTAssertEqual(cells["2026-10-20"]?.isSelectable, true)
    }

    func testUnavailableMonthShowsNoCountsAndPaddingStaysDistinct() throws {
        let today = try day("2026-10-06")
        let grid = try HistoryMonthGrid(month: .month(containing: today), today: today,
                                        selectedDay: nil, summaries: nil)
        XCTAssertTrue(days(grid).allSatisfy { $0.availability == .unavailable && $0.countText == "Unavailable" })
        XCTAssertEqual(days(grid).first { $0.day == today }?.isSelectable, true)
        XCTAssertEqual(days(grid).last?.isSelectable, false)
        XCTAssertEqual(leadingPadding(grid), 4) // October 1, 2026 is a Thursday.
        XCTAssertEqual(grid.cells.count, 35)
    }

    func testRejectsSummariesOutsideMonthOrDuplicated() throws {
        let today = try day("2026-10-06")
        let october = try HistoryDayRange.month(containing: today)
        for summaries in [[try summary("2026-11-01", 0, 1)],
                          [try summary("2026-10-02", 0, 1), try summary("2026-10-02", 1, 1)]] {
            XCTAssertThrowsError(try HistoryMonthGrid(month: october, today: today, selectedDay: nil,
                                                      summaries: summaries)) {
                XCTAssertEqual($0 as? TaskHistoryDomainError, .mismatchedDay)
            }
        }
    }

    func testTimeZoneChangeMovesTodayMarkerButNotSavedCellIdentity() throws {
        let instant = ISO8601DateFormatter().date(from: "2026-11-01T00:30:00Z")!
        var zone = TimeZone(identifier: "America/Toronto")!
        let noteDay = NoteDay(now: { instant }, timeZone: { zone })
        let october = try HistoryDayRange.month(containing: day("2026-10-31"))
        let saved = [try summary("2026-10-31", 1, 2)]

        let toronto = try HistoryMonthGrid(month: october, today: noteDay.historyKeys().today,
                                           selectedDay: day("2026-10-31"), summaries: saved)
        zone = TimeZone(secondsFromGMT: 0)!
        let utc = try HistoryMonthGrid(month: october, today: noteDay.historyKeys().today,
                                       selectedDay: day("2026-10-31"), summaries: saved)

        XCTAssertEqual(toronto.cells.map(\.id), utc.cells.map(\.id))
        let torontoCell = days(toronto).last!, utcCell = days(utc).last!
        XCTAssertEqual(torontoCell.id, "2026-10-31")
        XCTAssertTrue(torontoCell.isToday)
        XCTAssertFalse(utcCell.isToday)
        XCTAssertTrue(utcCell.isSelected)
        XCTAssertEqual(utcCell.countText, "1/2")
    }

    private func day(_ key: String) throws -> GregorianDay { try GregorianDay(key: key) }

    private func summary(_ key: String, _ completed: Int, _ total: Int) throws -> DayTaskSummary {
        try DayTaskSummary(dayKey: key, progress: NoteProgress(completed: completed, total: total))
    }

    private func days(_ grid: HistoryMonthGrid) -> [HistoryCalendarDay] {
        grid.cells.compactMap { if case let .day(day) = $0 { day } else { nil } }
    }

    private func leadingPadding(_ grid: HistoryMonthGrid) -> Int {
        grid.cells.prefix { if case .padding = $0 { true } else { false } }.count
    }
}
