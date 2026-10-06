import XCTest
@testable import MenuPocket

@MainActor
final class UnfinishedTasksStateTests: XCTestCase {
    private enum Failure: Error { case read }
    private func day(_ key: String) throws -> GregorianDay { try GregorianDay(key: key) }
    private func clock() -> NoteDay {
        NoteDay(now: { ISO8601DateFormatter().date(from: "2026-10-06T12:00:00Z")! },
                timeZone: { TimeZone(secondsFromGMT: 0)! })
    }
    private func page(_ before: GregorianDay, _ keys: [String], more: Bool = false) throws -> UnfinishedDayPage {
        try UnfinishedDayPage(before: before, limit: 2, summaries: keys.map {
            try DayTaskSummary(dayKey: $0, progress: NoteProgress(completed: 1, total: 2))
        }, hasMore: more)
    }

    func testInitialFailureIsUnavailableAndRetryCanPublishEmptySuccess() throws {
        var failing = true
        let state = try UnfinishedTasksState(noteDay: clock(), pageSize: 2) { cutoff, _ in
            XCTAssertEqual(cutoff.key, "2026-10-06")
            if failing { throw Failure.read }
            return try self.page(cutoff, [])
        }
        XCTAssertNil(state.summaries)
        state.setVisible(true)
        XCTAssertEqual(state.initialIssue, .initial)
        XCTAssertFalse(state.isEmpty)
        XCTAssertNil(state.summaries)
        failing = false
        state.retryInitial()
        XCTAssertTrue(state.isEmpty)
        XCTAssertNil(state.initialIssue)
        XCTAssertFalse(state.hasMore)
        XCTAssertThrowsError(try UnfinishedTasksState(pageSize: 0, readPage: { _, _ in fatalError() }))
    }

    func testAppendFailurePreservesRowsCursorAndRetryDoesNotDuplicate() throws {
        var failAppend = true
        var cutoffs: [String] = []
        let state = try UnfinishedTasksState(noteDay: clock(), pageSize: 2) { cutoff, _ in
            cutoffs.append(cutoff.key)
            if cutoff.key == "2026-10-06" { return try self.page(cutoff, ["2026-10-05", "2026-10-04"], more: true) }
            if failAppend { throw Failure.read }
            return try self.page(cutoff, ["2026-09-30"])
        }
        state.setVisible(true)
        let rows = state.summaries
        state.loadMore()
        XCTAssertEqual(state.summaries, rows)
        XCTAssertEqual(state.nextBefore?.key, "2026-10-04")
        XCTAssertTrue(state.hasMore)
        XCTAssertEqual(state.appendIssue, .append)
        XCTAssertNil(state.initialIssue)
        failAppend = false
        state.loadMore()
        state.loadMore()
        XCTAssertEqual(state.summaries?.map(\.dayKey), ["2026-10-05", "2026-10-04", "2026-09-30"])
        XCTAssertEqual(cutoffs, ["2026-10-06", "2026-10-04", "2026-10-04"])
        XCTAssertNil(state.appendIssue)
        XCTAssertFalse(state.hasMore)
    }

    func testHiddenRefreshInvalidatesChainAndRetainsOlderSelectionUntilEligibilityKnown() throws {
        var reads = 0
        var changed = false
        let state = try UnfinishedTasksState(noteDay: clock(), pageSize: 2) { cutoff, _ in
            reads += 1
            if changed { return try self.page(cutoff, ["2026-10-05", "2026-10-04"], more: true) }
            return try self.page(cutoff, ["2026-09-30"])
        }
        state.setVisible(true)
        let intent = try XCTUnwrap(state.select(day("2026-09-30")))
        XCTAssertEqual(intent.filter, .unfinished)
        state.setVisible(false)
        changed = true
        try state.refresh(revision: 1)
        XCTAssertEqual(reads, 1)
        XCTAssertTrue(state.dirty)
        XCTAssertNil(state.summaries)
        state.loadMore()
        XCTAssertEqual(reads, 1)
        state.setVisible(true)
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(state.selectedDay?.key, "2026-09-30")
        XCTAssertNil(state.selectionIssue) // Not in the first page is not proof of removal.
        let empty = try HistoryDaySnapshot(dayKey: intent.day.key, notes: [], categories: [])
        state.reconcileSelection(intent, snapshot: empty)
        XCTAssertNil(state.selectionIssue) // Previous generation's detail is discarded.
        state.reconcileSelection(try XCTUnwrap(state.selectionIntent), snapshot: empty)
        XCTAssertEqual(state.selectionIssue, .noUnfinishedTasks)
        try state.refresh(revision: 1)
        XCTAssertEqual(reads, 2)
    }

    func testReentrantRefreshDiscardsStaleAppendAndItsError() throws {
        for failing in [false, true] {
            var state: UnfinishedTasksState!
            var revisionChanged = false
            state = try UnfinishedTasksState(noteDay: clock(), pageSize: 2) { cutoff, _ in
                if cutoff.key == "2026-10-06" {
                    return try self.page(cutoff, revisionChanged ? ["2026-10-03"] : ["2026-10-05", "2026-10-04"], more: !revisionChanged)
                }
                revisionChanged = true
                try state.refresh(revision: 1)
                if failing { throw Failure.read }
                return try self.page(cutoff, ["2026-09-30"])
            }
            state.setVisible(true)
            state.loadMore()
            XCTAssertEqual(state.summaries?.map(\.dayKey), ["2026-10-03"])
            XCTAssertNil(state.appendIssue)
            XCTAssertFalse(state.hasMore)
        }
    }

    func testCutoffChangesWithoutRevisionChangeAndExcludedSelectionIsExplained() throws {
        var instant = ISO8601DateFormatter().date(from: "2026-10-06T00:30:00Z")!
        var zone = TimeZone(secondsFromGMT: 0)!
        let noteDay = NoteDay(now: { instant }, timeZone: { zone })
        var cutoffs: [String] = []
        let state = try UnfinishedTasksState(noteDay: noteDay, pageSize: 2) { cutoff, _ in
            cutoffs.append(cutoff.key)
            return try self.page(cutoff, cutoff.key == "2026-10-06" ? ["2026-10-05"] : [])
        }
        try state.refresh(revision: 1)
        state.setVisible(true)
        XCTAssertNotNil(state.select(try day("2026-10-05")))
        XCTAssertNil(state.select(try day("2026-10-06")))
        zone = TimeZone(identifier: "America/Toronto")!
        try state.refresh(revision: 1)
        XCTAssertEqual(state.today.key, "2026-10-05")
        XCTAssertEqual(state.selectionIssue, .noLongerPast)
        XCTAssertNil(state.selectionIntent)
        instant = ISO8601DateFormatter().date(from: "2026-10-07T12:00:00Z")!
        try state.refresh(revision: 1)
        XCTAssertEqual(cutoffs, ["2026-10-06", "2026-10-05", "2026-10-07"])
        XCTAssertEqual(state.selectionIssue, .noUnfinishedTasks)
    }

    func testMismatchedPageCannotPublishOrAdvanceCursor() throws {
        let state = try UnfinishedTasksState(noteDay: clock(), pageSize: 2) { _, _ in
            try self.page(self.day("2026-10-05"), [])
        }
        state.setVisible(true)
        XCTAssertNil(state.summaries)
        XCTAssertEqual(state.initialIssue, .initial)
        XCTAssertNil(state.nextBefore)
    }

    func testFacadeSelectionUsesSharedDetailWithoutChangingTodayOrWholeDayCounts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteNoteRepository(databaseURL: directory.appendingPathComponent("notes.sqlite"))
        let key = "2026-10-05"
        let date = Date()
        try repository.add(Note(id: UUID(), text: "open", dayKey: key, createdAt: date, completedAt: nil))
        try repository.add(Note(id: UUID(), text: "done", dayKey: key, createdAt: date, completedAt: date))
        let suite = "UnfinishedTasksStateTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let daily = DailyNotesState(repositoryFactory: { repository }, day: clock(),
                                   notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter(),
                                   categoryPreferences: TaskCategoryPreferences(userDefaults: defaults))
        defer { daily.stopForTermination() }
        daily.startup()
        daily.draft = "Keep draft"
        let revision = daily.historyRevision
        let progress = daily.availableProgress
        let savedDefaults = defaults.persistentDomain(forName: suite)
        let state = try UnfinishedTasksState(dailyState: daily, noteDay: clock())
        state.setVisible(true)
        let intent = try XCTUnwrap(state.select(day(key)))
        let history = try TaskHistoryState(dailyState: daily, noteDay: clock())
        try history.select(intent.day, filter: intent.filter)
        history.setVisible(month: false, day: true)
        let snapshot = try XCTUnwrap(history.daySnapshot)
        state.reconcileSelection(intent, snapshot: snapshot)
        XCTAssertEqual(history.progress, NoteProgress(completed: 1, total: 2))
        XCTAssertEqual(history.detailGroups.first?.visibleNotes.map(\.text), ["open"])
        XCTAssertNil(state.selectionIssue)
        XCTAssertEqual(daily.todayKey, "2026-10-06")
        XCTAssertEqual(daily.notes, [])
        XCTAssertEqual(daily.availableProgress, progress)
        XCTAssertEqual(daily.historyRevision, revision)
        XCTAssertEqual(daily.draft, "Keep draft")
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, savedDefaults as NSDictionary?)
        daily.stopForTermination()
        state.retryInitial()
        XCTAssertEqual(state.initialIssue, .initial)
        XCTAssertNil(state.summaries)
    }
}
