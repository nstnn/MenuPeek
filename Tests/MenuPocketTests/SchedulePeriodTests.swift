import XCTest
@testable import MenuPocket

final class SchedulePeriodTests: XCTestCase {
    // MARK: Civil arithmetic

    func testCivilDayNumberRoundTripsAcrossLeapDaysAndStorableBounds() throws {
        for key in ["0001-01-01", "1900-02-28", "1900-03-01", "2000-02-29", "2024-02-29", "2026-06-09",
                    "2026-12-31", "2027-01-01", "9999-12-31"] {
            let original = try day(key)
            XCTAssertEqual(try GregorianDay(civilDayNumber: original.civilDayNumber), original, key)
        }
        // Every day of a leap year and a common year, walked one civil number at a time.
        var walked = try day("2023-12-31")
        for _ in 0..<(366 + 365) {
            let next = try GregorianDay(civilDayNumber: walked.civilDayNumber + 1)
            XCTAssertGreaterThan(next, walked)
            XCTAssertEqual(next.civilDayNumber, walked.civilDayNumber + 1)
            walked = next
        }
        XCTAssertEqual(walked, try day("2025-12-31"))

        XCTAssertThrowsError(try day("0001-01-01").adding(days: -1))
        XCTAssertThrowsError(try day("9999-12-31").adding(days: 1))
        XCTAssertThrowsError(try day("2026-06-09").adding(days: .max))
        XCTAssertThrowsError(try GregorianDay(civilDayNumber: .min))
    }

    func testAddingDaysCrossesMonthYearAndLeapBoundaries() throws {
        XCTAssertEqual(try day("2024-02-28").adding(days: 1), try day("2024-02-29"))
        XCTAssertEqual(try day("2024-02-28").adding(days: 2), try day("2024-03-01"))
        XCTAssertEqual(try day("2025-03-01").adding(days: -1), try day("2025-02-28"))
        XCTAssertEqual(try day("2026-12-31").adding(days: 1), try day("2027-01-01"))
        XCTAssertEqual(try day("2027-01-01").adding(days: -1), try day("2026-12-31"))
        XCTAssertEqual(try day("2026-06-09").adding(days: 0), try day("2026-06-09"))
    }

    // MARK: ISO weeks

    func testWeekContainingJuneNinthIsMondayToSundayWeek24() throws {
        for key in ["2026-06-08", "2026-06-09", "2026-06-14"] {
            let period = try SchedulePeriod(mode: .week, anchor: day(key))
            XCTAssertEqual(period.range.start, try day("2026-06-08"), key)
            XCTAssertEqual(period.range.end, try day("2026-06-15"), key)
            XCTAssertEqual(period.days.map(\.key), ["2026-06-08", "2026-06-09", "2026-06-10", "2026-06-11",
                                                    "2026-06-12", "2026-06-13", "2026-06-14"], key)
            XCTAssertEqual(period.header, ScheduleHeader(title: "June 2026", detail: "Week 24"), key)
            XCTAssertEqual(period.header.text, "June 2026 · Week 24", key)
        }
        XCTAssertEqual(try day("2026-06-08").isoWeekday, 1)
        XCTAssertEqual(try day("2026-06-14").isoWeekday, 7)
    }

    func testISOWeeksAtYearBoundariesIncludingFiftyThreeWeekYears() throws {
        // 2026 starts on a Thursday, so it has 53 weeks; the last one runs into 2027.
        for key in ["2026-12-28", "2026-12-31", "2027-01-01", "2027-01-03"] {
            XCTAssertEqual(try isoWeek(key), YearWeek(2026, 53), key)
            let period = try SchedulePeriod(mode: .week, anchor: day(key))
            XCTAssertEqual(period.range.start, try day("2026-12-28"), key)
            XCTAssertEqual(period.header.text, "December 2026 – January 2027 · Week 53", key)
        }
        XCTAssertEqual(try isoWeek("2027-01-04"), YearWeek(2027, 1))
        XCTAssertEqual(try isoWeek("2026-01-01"), YearWeek(2026, 1))
        // Late December can belong to week 1 of the next ISO year.
        XCTAssertEqual(try isoWeek("2024-12-30"), YearWeek(2025, 1))
        XCTAssertEqual(try SchedulePeriod(mode: .week, anchor: day("2024-12-30")).header.text,
                       "December 2024 – January 2025 · Week 1")
        // Early January can belong to week 53 of the previous ISO year (2020 is a leap 53-week year).
        XCTAssertEqual(try isoWeek("2021-01-03"), YearWeek(2020, 53))
        XCTAssertEqual(try isoWeek("2020-12-31"), YearWeek(2020, 53))
        XCTAssertEqual(try isoWeek("2025-12-28"), YearWeek(2025, 52))
        // A week inside one year but across two months.
        XCTAssertEqual(try SchedulePeriod(mode: .week, anchor: day("2026-07-01")).header.text,
                       "June – July 2026 · Week 27")
    }

    /// Foundation's ISO 8601 calendar, pinned to UTC, is only an oracle here; the
    /// code under test never touches Calendar or TimeZone.
    func testISOWeeksMatchFoundationForEveryDayOfSampleYears() throws {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        for year in [1999, 2004, 2015, 2020, 2026, 2027, 2032, 2100] {
            var current = try GregorianDay(year: year, month: 1, day: 1)
            while current.year == year {
                let date = calendar.date(from: DateComponents(year: current.year, month: current.month,
                                                              day: current.day))!
                let expected = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                XCTAssertEqual(try current.isoWeek().year, expected.yearForWeekOfYear, current.key)
                XCTAssertEqual(try current.isoWeek().week, expected.weekOfYear, current.key)
                current = try current.adding(days: 1)
            }
        }
    }

    // MARK: Stepping

    func testMonthStepClampsDayOfMonthWithoutInvalidDates() throws {
        let january = try SchedulePeriod(mode: .month, anchor: day("2026-01-31"))
        let february = try january.next()
        XCTAssertEqual(february.anchor, try day("2026-02-28"))
        XCTAssertEqual(february.range.start, try day("2026-02-01"))
        XCTAssertEqual(february.range.end, try day("2026-03-01"))
        XCTAssertEqual(february.days.count, 28)
        XCTAssertEqual(february.header.text, "February 2026")

        XCTAssertEqual(try SchedulePeriod(mode: .month, anchor: day("2024-01-31")).next().anchor, try day("2024-02-29"))
        XCTAssertEqual(try SchedulePeriod(mode: .month, anchor: day("2026-03-31")).previous().anchor,
                       try day("2026-02-28"))
        XCTAssertEqual(try SchedulePeriod(mode: .month, anchor: day("2026-12-15")).next().anchor, try day("2027-01-15"))
        XCTAssertEqual(try SchedulePeriod(mode: .month, anchor: day("2027-01-15")).previous().anchor,
                       try day("2026-12-15"))
    }

    func testDayAndWeekStepAcrossYearAndLeapBoundaries() throws {
        let newYearsEve = try SchedulePeriod(mode: .day, anchor: day("2026-12-31"))
        XCTAssertEqual(newYearsEve.header.text, "December 2026 · Thursday, December 31, 2026")
        XCTAssertEqual(newYearsEve.days, [try day("2026-12-31")])
        XCTAssertEqual(try newYearsEve.next().anchor, try day("2027-01-01"))
        XCTAssertEqual(try newYearsEve.next().header.text, "January 2027 · Friday, January 1, 2027")
        XCTAssertEqual(try SchedulePeriod(mode: .day, anchor: day("2024-03-01")).previous().anchor,
                       try day("2024-02-29"))
        XCTAssertEqual(try SchedulePeriod(mode: .day, anchor: day("2026-06-09")).header.text,
                       "June 2026 · Tuesday, June 9, 2026")

        let week24 = try SchedulePeriod(mode: .week, anchor: day("2026-06-09"))
        XCTAssertEqual(try week24.next().range.start, try day("2026-06-15"))
        XCTAssertEqual(try week24.next().header.detail, "Week 25")
        XCTAssertEqual(try week24.previous().range.start, try day("2026-06-01"))
        let week53 = try SchedulePeriod(mode: .week, anchor: day("2026-12-30"))
        XCTAssertEqual(try week53.next().range.start, try day("2027-01-04"))
        XCTAssertEqual(try week53.next().header.text, "January 2027 · Week 1")
        XCTAssertEqual(try week53.previous().header.detail, "Week 52")
    }

    func testTodayReanchorsInTheCurrentMode() throws {
        let today = try day("2026-11-18")
        for mode in ScheduleViewMode.allCases {
            let away = try SchedulePeriod(mode: mode, anchor: day("2025-03-04"))
            let back = try away.showingToday(today)
            XCTAssertEqual(back.mode, mode)
            XCTAssertEqual(back.anchor, today)
            XCTAssertTrue(back.contains(today))
        }
        XCTAssertEqual(ScheduleViewMode.initial, .week)
        XCTAssertEqual(ScheduleViewMode.allCases.map(\.title), ["Day", "Week", "Month"])
    }

    // MARK: Mode switching

    func testSwitchingModePrefersSelectedDayThenTodayThenAnchor() throws {
        let today = try day("2026-06-09")
        let june = try SchedulePeriod(mode: .month, anchor: today)

        // Selected day in the period wins over today.
        let selected = try june.switching(to: .week, selectedDay: day("2026-06-20"), today: today)
        XCTAssertEqual(selected.anchor, try day("2026-06-20"))
        XCTAssertEqual(selected.range.start, try day("2026-06-15"))

        // A selected day outside the period is ignored; today is in the period.
        let ignored = try june.switching(to: .day, selectedDay: day("2026-07-02"), today: today)
        XCTAssertEqual(ignored.anchor, today)
        XCTAssertEqual(ignored.mode, .day)

        // Neither selected day nor today is visible: the current anchor stays.
        let august = try june.next().next()
        XCTAssertEqual(august.anchor, try day("2026-08-09"))
        let week = try august.switching(to: .week, selectedDay: nil, today: today)
        XCTAssertEqual(week.anchor, try day("2026-08-09"))
        XCTAssertEqual(week.range.start, try day("2026-08-03"))

        // A week spanning two months goes to the anchor's month.
        let spanning = try SchedulePeriod(mode: .week, anchor: day("2026-07-01"))
        XCTAssertEqual(try spanning.switching(to: .month, selectedDay: nil, today: today).header.text, "July 2026")
        XCTAssertEqual(try spanning.switching(to: .month, selectedDay: day("2026-06-30"), today: today)
            .header.text, "June 2026")
    }

    // MARK: Month grid

    func testMonthGridsHaveCompleteMondayFirstWeeks() throws {
        for year in [2024, 2026] {
            for month in 1...12 {
                let first = try GregorianDay(year: year, month: month, day: 1)
                let grid = try ScheduleMonthGrid(containing: first)
                let leading = first.isoWeekday - 1

                XCTAssertEqual(grid.weekdaySymbols, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
                XCTAssertTrue(grid.cells.count.isMultiple(of: 7), first.key)
                XCTAssertTrue(grid.weeks.allSatisfy { $0.count == 7 }, first.key)
                XCTAssertTrue((4...6).contains(grid.weeks.count), first.key)
                XCTAssertTrue(grid.cells.prefix(leading).allSatisfy { $0.day == nil }, first.key)
                XCTAssertEqual(grid.cells[leading].day, first, first.key)
                XCTAssertEqual(grid.cells.compactMap(\.day), try SchedulePeriod(mode: .month, anchor: first).days,
                               first.key)
                XCTAssertLessThan(grid.cells.count - leading - grid.month.dayCount, 7, first.key)
                XCTAssertEqual(Set(grid.cells.map(\.id)).count, grid.cells.count, first.key)
                // Every day sits under its own weekday column.
                for (index, cell) in grid.cells.enumerated() {
                    if let day = cell.day { XCTAssertEqual(index % 7, day.isoWeekday - 1, day.key) }
                }
            }
        }
    }

    func testMonthGridPaddingForKnownMonths() throws {
        // Starts Monday: no leading padding.
        let june = try ScheduleMonthGrid(containing: day("2026-06-09"))
        XCTAssertEqual(june.cells.first, .day(try day("2026-06-01")))
        XCTAssertEqual(june.weeks.count, 5)
        // Starts Sunday with 31 days: six leading cells and six weeks.
        let march = try ScheduleMonthGrid(containing: day("2026-03-15"))
        XCTAssertEqual(Array(march.cells.prefix(6)), (0..<6).map(ScheduleMonthCell.padding))
        XCTAssertEqual(march.weeks.count, 6)
        // A February that starts on Monday fills exactly four rows.
        let february = try ScheduleMonthGrid(containing: day("2021-02-10"))
        XCTAssertEqual(february.cells.count, 28)
        XCTAssertTrue(february.cells.allSatisfy { $0.day != nil })
        // Leap February starting Thursday: 3 leading + 29 days + 3 trailing.
        let leap = try ScheduleMonthGrid(containing: day("2024-02-29"))
        XCTAssertEqual(leap.cells.count, 35)
        XCTAssertEqual(leap.cells.last, .padding(34))
        XCTAssertEqual(try SchedulePeriod(mode: .day, anchor: day("2024-02-29")).monthGrid(), leap)
    }

    func testPeriodsAtTheStorableEdgesThrowInsteadOfCrashing() throws {
        let first = try day("0001-01-01") // a Monday
        XCTAssertEqual(try SchedulePeriod(mode: .week, anchor: first).range.start, first)
        XCTAssertThrowsError(try SchedulePeriod(mode: .week, anchor: first).previous())
        XCTAssertThrowsError(try SchedulePeriod(mode: .day, anchor: first).previous())
        XCTAssertThrowsError(try SchedulePeriod(mode: .month, anchor: first).previous())
        XCTAssertThrowsError(try SchedulePeriod(mode: .month, anchor: day("9999-12-01")))
        XCTAssertThrowsError(try SchedulePeriod(mode: .week, anchor: day("9999-12-31")))
    }

    // MARK: Helpers

    private struct YearWeek: Equatable {
        let year: Int
        let week: Int
        init(_ year: Int, _ week: Int) { self.year = year; self.week = week }
    }

    private func isoWeek(_ key: String) throws -> YearWeek {
        let value = try day(key).isoWeek()
        return YearWeek(value.year, value.week)
    }

    private func day(_ key: String) throws -> GregorianDay { try GregorianDay(key: key) }
}
