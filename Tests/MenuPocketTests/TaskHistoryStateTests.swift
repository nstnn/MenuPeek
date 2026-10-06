import XCTest
@testable import MenuPocket

@MainActor
final class TaskHistoryStateTests: XCTestCase {
    private enum Failure: Error { case read }
    private func day(_ key: String) throws -> GregorianDay { try GregorianDay(key: key) }
    private func clock(_ instant: String) -> NoteDay {
        NoteDay(now: { ISO8601DateFormatter().date(from: instant)! }, timeZone: { TimeZone(secondsFromGMT: 0)! })
    }
    private func empty(_ key: String) throws -> HistoryDaySnapshot {
        try HistoryDaySnapshot(dayKey: key, notes: [], categories: [])
    }

    func testYesterdayDefaultsAcrossMonthYearAndLeapBoundaries() throws {
        for (instant, expected, month) in [
            ("2027-01-01T12:00:00Z", "2026-12-31", "2026-12-01"),
            ("2024-03-01T12:00:00Z", "2024-02-29", "2024-02-01")
        ] {
            let state = try TaskHistoryState(noteDay: clock(instant), readMonth: { _ in [] }, readDay: empty)
            XCTAssertEqual(state.selectedDay?.key, expected)
            XCTAssertEqual(state.month.start.key, month)
            XCTAssertNil(state.daySnapshot)
        }
    }

    func testFiltersKeepWholeDayAndGroupProgressAndDistinguishEmptyStates() throws {
        let key = "2026-10-05"
        let date = Date()
        let notes = [Note(id: UUID(), text: "first", dayKey: key, createdAt: date, completedAt: nil),
                     Note(id: UUID(), text: "second", dayKey: key, createdAt: date, completedAt: date)]
        var snapshot = try HistoryDaySnapshot(dayKey: key, notes: notes, categories: [])
        let state = try TaskHistoryState(noteDay: clock("2026-10-06T12:00:00Z"), readMonth: { _ in [] }, readDay: { _ in snapshot })
        state.setVisible(month: true, day: true)
        state.setFilter(.completed)
        XCTAssertEqual(state.progress, NoteProgress(completed: 1, total: 2))
        XCTAssertEqual(state.detailGroups.first?.group.progress, state.progress)
        XCTAssertEqual(state.detailGroups.first?.visibleNotes.map(\.text), ["second"])
        state.toggleDisclosure(.general)
        snapshot = try HistoryDaySnapshot(dayKey: key, notes: [notes[0]], categories: [])
        state.retryDay()
        XCTAssertEqual(state.detailMessage, "No completed tasks for this day.")
        XCTAssertEqual(state.collapsedGroups, [.general])
        snapshot = try empty(key)
        state.retryDay()
        XCTAssertEqual(state.detailMessage, "No saved tasks for this day.")
    }

    func testPaneFailuresRetryIndependentlyAndSelectionNeverShowsOldDay() throws {
        var failMonth = false
        var failDay = false
        var monthReads = 0
        var dayReads = 0
        let state = try TaskHistoryState(noteDay: clock("2026-10-06T12:00:00Z"), readMonth: { _ in
            monthReads += 1
            if failMonth { throw Failure.read }
            return []
        }, readDay: { key in
            dayReads += 1
            if failDay { throw Failure.read }
            return try self.empty(key)
        })
        state.setVisible(month: true, day: true)
        failDay = true
        try state.select(day("2026-10-04"), filter: .unfinished)
        XCTAssertNil(state.daySnapshot)
        XCTAssertEqual(state.dayIssue, .day)
        XCTAssertEqual(state.monthSummaries, [])
        XCTAssertEqual(monthReads, 1)
        failDay = false
        state.retryDay()
        XCTAssertEqual(state.daySnapshot?.dayKey, "2026-10-04")
        failMonth = true
        state.retryMonth()
        XCTAssertNil(state.monthSummaries)
        XCTAssertEqual(state.monthIssue, .month)
        XCTAssertEqual(state.daySnapshot?.dayKey, "2026-10-04")
        XCTAssertEqual(dayReads, 3)
        failMonth = false
        state.retryMonth()
        XCTAssertEqual(state.monthSummaries, [])
        XCTAssertNil(state.monthIssue)
    }

    func testHiddenInvalidationReloadsOnlyVisiblePanesAndKeepsSelection() throws {
        var monthReads = 0
        var dayReads = 0
        let state = try TaskHistoryState(noteDay: clock("2026-10-06T12:00:00Z"), readMonth: { _ in monthReads += 1; return [] },
                                         readDay: { key in dayReads += 1; return try self.empty(key) })
        try state.refresh(revision: 1)
        XCTAssertEqual(monthReads, 0)
        state.setVisible(month: true, day: false)
        XCTAssertEqual(monthReads, 1)
        XCTAssertEqual(dayReads, 0)
        try state.refresh(revision: 2)
        XCTAssertEqual(monthReads, 2)
        XCTAssertTrue(state.dayDirty)
        state.setVisible(month: true, day: true)
        XCTAssertEqual(dayReads, 1)
        try state.refresh(revision: 2)
        XCTAssertEqual(dayReads, 1)
        state.setVisible(month: false, day: false)
        try state.select(day("2026-09-02"), filter: .completed)
        XCTAssertNil(state.daySnapshot)
        try state.refresh(revision: 3)
        state.setVisible(month: true, day: true)
        XCTAssertEqual(state.selectedDay?.key, "2026-09-02")
        XCTAssertEqual(state.daySnapshot?.dayKey, "2026-09-02")
        XCTAssertEqual(state.filter, .completed)
    }

    func testMonthClampingFutureSavedDataRetryAndThisMonth() throws {
        var summaries: [DayTaskSummary] = []
        var fail = false
        let state = try TaskHistoryState(noteDay: clock("2026-01-01T12:00:00Z"), readMonth: { _ in
            if fail { throw Failure.read }; return summaries
        }, readDay: empty)
        state.setVisible(month: true, day: true)
        try state.changeMonth(containing: day("2025-02-01"))
        XCTAssertEqual(state.selectedDay?.key, "2025-02-28")
        fail = true
        try state.changeMonth(containing: day("2026-02-01"))
        XCTAssertNil(state.selectedDay)
        XCTAssertNil(state.daySnapshot)
        XCTAssertNil(state.detailMessage)
        fail = false
        state.retryMonth()
        XCTAssertEqual(state.detailMessage, "Not yet")
        summaries = [try DayTaskSummary(dayKey: "2026-02-28", progress: NoteProgress(completed: 0, total: 1))]
        try state.refresh(revision: 1)
        XCTAssertEqual(state.selectedDay?.key, "2026-02-28")
        summaries = []
        state.retryMonth()
        XCTAssertNil(state.selectedDay)
        XCTAssertNil(state.daySnapshot)
        try state.refresh(revision: 2)
        XCTAssertNil(state.selectedDay)
        XCTAssertNil(state.daySnapshot)
        state.setFilter(.completed)
        try state.thisMonth()
        XCTAssertEqual(state.selectedDay?.key, "2026-01-01")
        XCTAssertEqual(state.filter, .all)
    }

    func testMonthStepsCrossYearBoundariesAndLabelsKeepTheCivilDate() throws {
        var reads: [String] = []
        let state = try TaskHistoryState(noteDay: clock("2026-01-31T12:00:00Z"), readMonth: {
            reads.append($0.start.key); return []
        }, readDay: empty)
        state.setVisible(month: true, day: true)
        XCTAssertEqual(state.selectedDay?.key, "2026-01-30")
        try state.showPreviousMonth()
        XCTAssertEqual(state.month.start.key, "2025-12-01")
        XCTAssertEqual(state.selectedDay?.key, "2025-12-30")
        try state.showNextMonth()
        try state.showNextMonth()
        XCTAssertEqual(state.month.start.key, "2026-02-01")
        XCTAssertNil(state.selectedDay)
        XCTAssertEqual(reads, ["2026-01-01", "2025-12-01", "2026-01-01", "2026-02-01"])
        // Labels format the saved civil date, never an instant shifted by the device zone.
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        NSTimeZone.default = TimeZone(identifier: "Pacific/Kiritimati")!
        XCTAssertEqual(try day("2024-02-29").label("EEEE, MMMM d, yyyy"), "Thursday, February 29, 2024")
        NSTimeZone.default = TimeZone(identifier: "Pacific/Pago_Pago")!
        XCTAssertEqual(try day("2026-12-31").label("MMMM yyyy"), "December 2026")
    }

    func testDisclosureResetsForAnotherDayButSurvivesRefreshOfTheSameDay() throws {
        let state = try TaskHistoryState(noteDay: clock("2026-10-06T12:00:00Z"), readMonth: { _ in [] }, readDay: empty)
        state.setVisible(month: true, day: true)
        state.toggleDisclosure(.general)
        state.retryDay()
        try state.refresh(revision: 1)
        XCTAssertEqual(state.collapsedGroups, [.general])
        try state.select(day("2026-10-03"))
        XCTAssertEqual(state.collapsedGroups, [])
    }

    func testSharedFacadeBrowsingPreservesTodayDraftProgressAndDefaults() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "TaskHistoryStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let repository = try SQLiteNoteRepository(databaseURL: folder.appendingPathComponent("notes.sqlite"))
        let old = Note(id: UUID(), text: "History", dayKey: "2026-10-05",
                       createdAt: Date(timeIntervalSince1970: 1_759_680_000), completedAt: nil)
        try repository.add(old)
        let noteDay = clock("2026-10-06T12:00:00Z")
        let daily = DailyNotesState(repositoryFactory: { repository }, day: noteDay,
                                   notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter(),
                                   categoryPreferences: TaskCategoryPreferences(userDefaults: defaults))
        defer { daily.stopForTermination() }
        daily.startup()
        daily.draft = "Keep my draft"
        let revision = daily.historyRevision
        let progress = daily.availableProgress
        let savedDefaults = defaults.persistentDomain(forName: suite)
        let history = try TaskHistoryState(dailyState: daily, noteDay: noteDay)
        history.setVisible(month: true, day: true)
        XCTAssertEqual(history.daySnapshot?.notes, [old])
        history.toggleDisclosure(.general)
        try history.select(day("2026-10-03"), filter: .unfinished)
        XCTAssertEqual(daily.todayKey, "2026-10-06")
        XCTAssertEqual(daily.notes, [])
        XCTAssertEqual(daily.availableProgress, progress)
        XCTAssertEqual(daily.draft, "Keep my draft")
        XCTAssertEqual(daily.historyRevision, revision)
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, savedDefaults as NSDictionary?)
        XCTAssertEqual(try repository.notes(for: old.dayKey), [old])
        daily.stopForTermination()
        history.retryDay()
        XCTAssertEqual(history.dayIssue, .day)
        XCTAssertNil(history.daySnapshot)
    }

    func testRolloverTimeZoneKeepsCivilSelectionAndMismatchedReadsAreUnavailable() throws {
        var zone = TimeZone(identifier: "America/Toronto")!
        let noteDay = NoteDay(now: { ISO8601DateFormatter().date(from: "2026-11-01T00:30:00Z")! }, timeZone: { zone })
        let state = try TaskHistoryState(noteDay: noteDay, readMonth: { _ in [] }, readDay: empty)
        state.setVisible(month: true, day: true)
        let selected = state.selectedDay
        zone = TimeZone(secondsFromGMT: 0)!
        try state.refresh(revision: 1)
        XCTAssertEqual(state.today.key, "2026-11-01")
        XCTAssertEqual(state.selectedDay, selected)
        let invalid = try TaskHistoryState(noteDay: noteDay, readMonth: { _ in
            [try DayTaskSummary(dayKey: "2000-01-01", progress: NoteProgress(completed: 0, total: 1))]
        }, readDay: { _ in try self.empty("2000-01-01") })
        invalid.setVisible(month: true, day: true)
        XCTAssertNil(invalid.monthSummaries)
        XCTAssertNil(invalid.daySnapshot)
        XCTAssertEqual(invalid.monthIssue, .month)
        XCTAssertEqual(invalid.dayIssue, .day)
    }
}
