import XCTest
@testable import MenuPocket

final class TaskHistoryDomainTests: XCTestCase {
    func testCivilDaysRejectMalformedOrNormalizedDates() {
        for key in ["", "2026-1-01", "2026-01-1", "2026/01/01", "2026-01-01 ",
                    " 2026-01-01", "２０２６-01-01", "2026-0a-01", "0000-01-01",
                    "10000-01-01", "2026-00-01", "2026-13-01", "2026-01-00",
                    "2026-01-32", "2026-04-31", "2026-02-30"] {
            XCTAssertThrowsError(try GregorianDay(key: key), key) {
                XCTAssertEqual($0 as? TaskHistoryDomainError, .invalidDayKey(key))
            }
        }
    }

    func testGregorianLeapRulesAndCanonicalOrdering() throws {
        for key in ["0001-01-01", "2000-02-29", "2024-02-29", "2400-02-29", "9999-12-31"] {
            XCTAssertEqual(try GregorianDay(key: key).key, key)
        }
        for key in ["1500-02-29", "1900-02-29", "2025-02-29", "2100-02-29"] {
            XCTAssertThrowsError(try GregorianDay(key: key))
        }
        let leapDay = try day("2024-02-29")
        XCTAssertEqual(leapDay.year, 2024)
        XCTAssertEqual(leapDay.month, 2)
        XCTAssertEqual(leapDay.day, 29)
        XCTAssertLessThan(try day("2026-12-31"), try day("2027-01-01"))
    }

    func testRangeIncludesStartAndExcludesEndAndRejectsEmptyOrReversedRanges() throws {
        let start = try day("2024-02-01")
        let end = try day("2024-03-01")
        let range = try HistoryDayRange(start: start, end: end)
        XCTAssertTrue(range.contains(start))
        XCTAssertTrue(range.contains(try day("2024-02-29")))
        XCTAssertFalse(range.contains(try day("2024-01-31")))
        XCTAssertFalse(range.contains(end))
        for (lower, upper) in [(start, start), (end, start)] {
            XCTAssertThrowsError(try HistoryDayRange(start: lower, end: upper)) {
                XCTAssertEqual($0 as? TaskHistoryDomainError, .invalidRange)
            }
        }
    }

    func testMonthBoundariesHandleLeapDaysAndYearTransitions() throws {
        for (selection, start, end) in [
            ("2024-02-29", "2024-02-01", "2024-03-01"),
            ("2025-02-28", "2025-02-01", "2025-03-01"),
            ("2026-03-08", "2026-03-01", "2026-04-01"),
            ("2026-12-31", "2026-12-01", "2027-01-01"),
            ("2027-01-01", "2027-01-01", "2027-02-01"),
        ] {
            let range = try HistoryDayRange.month(containing: day(selection))
            XCTAssertEqual(range.start.key, start)
            XCTAssertEqual(range.end.key, end)
        }
        XCTAssertThrowsError(try HistoryDayRange.month(containing: day("9999-12-01"))) {
            XCTAssertEqual($0 as? TaskHistoryDomainError, .invalidDayKey("10000-01-01"))
        }
    }

    func testInjectedClockAndTimeZoneAffectCutoffButNotSavedCivilSelection() throws {
        let instant = ISO8601DateFormatter().date(from: "2026-11-01T00:30:00Z")!
        var zone = TimeZone(identifier: "America/Toronto")!
        var clockReads = 0
        let days = NoteDay(now: { clockReads += 1; return instant }, timeZone: { zone })
        let keys = try days.historyKeys()
        XCTAssertEqual(clockReads, 1)
        XCTAssertEqual(keys.today.key, "2026-10-31")
        XCTAssertEqual(keys.yesterday.key, "2026-10-30")
        let selection = keys.yesterday
        let october = try days.historyMonthRange()
        XCTAssertEqual(october.start.key, "2026-10-01")

        zone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(try days.historyKeys().today.key, "2026-11-01")
        XCTAssertEqual(try days.historyMonthRange().start.key, "2026-11-01")
        XCTAssertEqual(selection.key, "2026-10-30")
        XCTAssertEqual(try HistoryDayRange.month(containing: selection), october)
    }

    func testFiltersPreserveWholeDayProgressSavedOrderAndCurrentCategoryLabels() throws {
        let work = try TaskCategory(name: "Renamed Work", creationOrder: 8)
        let home = try TaskCategory(name: "Home", creationOrder: 2)
        // The completion instant belongs to the next day; counts still use dayKey.
        let rows = [note("A", completed: true, categoryID: work.id),
                    note("B", categoryID: home.id), note("C", completed: true),
                    note("D", completed: true, categoryID: work.id), note("E")]
        let original = rows
        let snapshot = try HistoryDaySnapshot(dayKey: "2026-10-03", notes: rows,
                                               categories: [work, home])
        XCTAssertEqual(snapshot.dayKey, "2026-10-03")
        XCTAssertEqual(snapshot.progress, NoteProgress(completed: 3, total: 5))
        XCTAssertEqual(snapshot.summary.incomplete, 2)
        XCTAssertEqual(snapshot.filteredNotes(.all), original)
        XCTAssertEqual(snapshot.filteredNotes(.unfinished), [rows[1], rows[4]])
        XCTAssertEqual(snapshot.filteredNotes(.completed), [rows[0], rows[2], rows[3]])
        XCTAssertEqual(snapshot.progress, NoteProgress(completed: 3, total: 5))
        XCTAssertEqual(snapshot.notes, original)
        XCTAssertEqual(snapshot.categories, [home, work])
        XCTAssertEqual(snapshot.groups.map(\.name), ["Home", "Renamed Work", "General"])
        XCTAssertEqual(snapshot.groups[1].notes, [rows[0], rows[3]])
        XCTAssertEqual(snapshot.groups[2].progress, NoteProgress(completed: 1, total: 2))
    }

    func testSnapshotRejectsWrongDayAndMissingCategoryInsteadOfDroppingRows() {
        XCTAssertThrowsError(try HistoryDaySnapshot(dayKey: "2026-10-04", notes: [note("A")],
                                                    categories: [])) {
            XCTAssertEqual($0 as? TaskHistoryDomainError, .mismatchedDay)
        }
        let missingID = UUID()
        XCTAssertThrowsError(try HistoryDaySnapshot(dayKey: "2026-10-03",
                                                    notes: [note("A", categoryID: missingID)],
                                                    categories: [])) {
            XCTAssertEqual($0 as? TaskHistoryDomainError, .missingCategory(missingID))
        }
        XCTAssertThrowsError(try HistoryDaySnapshot(dayKey: "invalid", notes: [], categories: []))
    }

    func testEmptySnapshotIsSuccessfulAndAllFiltersAreEmpty() throws {
        let snapshot = try HistoryDaySnapshot(dayKey: "2026-10-03", notes: [], categories: [])
        XCTAssertEqual(snapshot.progress, NoteProgress(completed: 0, total: 0))
        XCTAssertTrue(snapshot.groups.isEmpty)
        for filter in HistoryTaskFilter.allCases {
            XCTAssertTrue(snapshot.filteredNotes(filter).isEmpty)
        }
    }

    func testSummaryRejectsImpossibleCountersAndMalformedKeys() throws {
        for (completed, total) in [(-1, 5), (0, -1), (6, 5), (1, 0)] {
            XCTAssertThrowsError(try DayTaskSummary(dayKey: "2026-10-03",
                                                   progress: NoteProgress(completed: completed,
                                                                          total: total))) {
                XCTAssertEqual($0 as? TaskHistoryDomainError,
                               .invalidProgress(completed: completed, total: total))
            }
        }
        XCTAssertThrowsError(try summary("2025-02-29"))
        XCTAssertEqual(try summary("2026-10-03", completed: 5, total: 5).incomplete, 0)
        XCTAssertEqual(try summary("2026-10-03", completed: 0, total: 0).incomplete, 0)
    }

    func testAvailabilityDistinguishesEmptyFutureSavedFutureAndUnavailable() throws {
        let today = try day("2026-10-05")
        let past = try day("2026-10-03")
        let future = try day("2026-10-06")
        let empty = NoteProgress(completed: 0, total: 0)
        XCTAssertEqual(try HistoryDayAvailability.loaded(day: past, summary: nil, today: today)
            .progress, empty)
        XCTAssertEqual(try HistoryDayAvailability.loaded(day: today, summary: nil, today: today)
            .progress, empty)
        XCTAssertEqual(try HistoryDayAvailability.loaded(day: future, summary: nil, today: today),
                       .notYet)
        let saved = try summary(future.key)
        XCTAssertEqual(try HistoryDayAvailability.loaded(day: future, summary: saved, today: today),
                       .available(saved))
        XCTAssertEqual(try HistoryDayAvailability.loaded(day: future,
                                                        summary: summary(future.key, completed: 0, total: 0),
                                                        today: today), .notYet)
        XCTAssertNil(HistoryDayAvailability.unavailable.progress)
        XCTAssertNil(HistoryDayAvailability.notYet.progress)
        XCTAssertThrowsError(try HistoryDayAvailability.loaded(day: past, summary: saved, today: today)) {
            XCTAssertEqual($0 as? TaskHistoryDomainError, .mismatchedDay)
        }
    }

    func testUnfinishedPagesUseExclusiveDayCursorAndWholeDayCounts() throws {
        let today = try day("2026-10-05")
        let rows = try [summary("2026-10-04"), summary("2026-02-01", completed: 1, total: 4)]
        let first = try UnfinishedDayPage(before: today, limit: 2, summaries: rows, hasMore: true)
        XCTAssertEqual(first.summaries, rows)
        XCTAssertEqual(first.summaries[0].progress, NoteProgress(completed: 3, total: 5))
        XCTAssertEqual(first.nextBefore, rows.last?.day)
        let next = try UnfinishedDayPage(before: XCTUnwrap(first.nextBefore), limit: 2,
                                         summaries: [summary("2025-12-31")], hasMore: false)
        XCTAssertEqual(next.before.key, "2026-02-01")
        XCTAssertNil(next.nextBefore)
        let empty = try UnfinishedDayPage(before: today, limit: 31, summaries: [], hasMore: false)
        XCTAssertTrue(empty.summaries.isEmpty)
        XCTAssertNil(empty.nextBefore)
    }

    func testUnfinishedPageRejectsInvalidBoundsOrderAndCompletedDays() throws {
        let today = try day("2026-10-05")
        let recent = try summary("2026-10-04")
        let older = try summary("2026-02-01")
        let invalidRows = try [[summary(today.key)], [summary("2026-10-06")], [older, recent],
                               [recent, recent], [summary(recent.dayKey, completed: 5, total: 5)],
                               [summary(recent.dayKey, completed: 0, total: 0)]]
        for rows in invalidRows {
            XCTAssertThrowsError(try UnfinishedDayPage(before: today, limit: 2,
                                                       summaries: rows, hasMore: false)) {
                XCTAssertEqual($0 as? TaskHistoryDomainError, .invalidPage)
            }
        }
        for (limit, rows, hasMore) in [(0, [], false), (-1, [], false), (Int.max, [], false),
                                      (1, [recent, older], false), (2, [recent], true), (2, [], true)] {
            XCTAssertThrowsError(try UnfinishedDayPage(before: today, limit: limit,
                                                       summaries: rows, hasMore: hasMore))
        }
    }

    private func day(_ key: String) throws -> GregorianDay { try GregorianDay(key: key) }

    private func summary(_ key: String, completed: Int = 3, total: Int = 5) throws -> DayTaskSummary {
        try DayTaskSummary(dayKey: key, progress: NoteProgress(completed: completed, total: total))
    }

    private func note(_ text: String, completed: Bool = false, categoryID: UUID? = nil) -> Note {
        Note(id: UUID(), text: text, dayKey: "2026-10-03",
             createdAt: ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z")!,
             completedAt: completed ? ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")! : nil,
             categoryID: categoryID)
    }
}
