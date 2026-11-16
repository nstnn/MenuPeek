import Foundation
import SQLite3
import XCTest
@testable import MenuPocket

/// Cross-layer checks: real SQLite → DailyNotesState read facade →
/// TaskWindowPresentation projections → HistoryMonthGrid cells.
@MainActor
final class TaskHistoryIntegrationTests: XCTestCase {
    // XCTest calls setUp/tearDown outside the main actor.
    nonisolated(unsafe) private var directory: URL!
    nonisolated(unsafe) private var suite: String!
    nonisolated(unsafe) private var defaults: UserDefaults!
    private final class Clock { var now = "2026-10-06T12:00:00Z" }
    private let clock = Clock()
    private var databaseURL: URL { directory.appendingPathComponent("notes.sqlite") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "TaskHistoryIntegrationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    func testContinueHistorySelectionUpdatesBothSurfacesPreservesDraftsAndRejectsRollover() throws {
        let repository = try SQLiteNoteRepository(databaseURL: databaseURL)
        let category = try repository.createCategory(name: "Work")
        let source = note("Continue me", "2026-10-05", done: false, categoryID: category.id)
        let remaining = note("Keep yesterday", "2026-10-05", done: false, categoryID: nil)
        try repository.add(source)
        try repository.add(remaining)
        let (daily, _) = makeApp(repository: repository)
        let presentation = daily.taskWindowPresentation
        defer { presentation.stopForTermination(); daily.stopForTermination() }
        daily.startup()
        presentation.setWindowVisible(true, state: daily)
        daily.draft = "Today draft"
        daily.laterDraft = "Later draft"
        XCTAssertTrue(presentation.showHistory(state: daily, entry: .yesterday))
        let history = try XCTUnwrap(presentation.historyState)
        let today = history.today
        let rowsBefore = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
        // A write failure preserves selection targets, published rows and drafts.
        try executeRaw("CREATE TRIGGER fail_continuation BEFORE UPDATE OF continued_on ON notes BEGIN SELECT RAISE(ABORT, 'fixture failure'); END")
        XCTAssertFalse(daily.continueHistoryTasks([source], expectedToday: today))
        XCTAssertEqual(daily.notes, [])
        XCTAssertEqual(daily.yesterdayIncompleteCount, 2)
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), rowsBefore)
        try executeRaw("DROP TRIGGER fail_continuation")
        XCTAssertTrue(daily.continueHistoryTasks([source], expectedToday: today))
        XCTAssertEqual(presentation.route, .history)
        XCTAssertEqual(daily.availableProgress, NoteProgress(completed: 0, total: 1))
        XCTAssertEqual(daily.notes.map(\.text), [source.text])
        XCTAssertEqual(daily.notes.first?.categoryID, category.id)
        XCTAssertEqual(daily.yesterdayIncompleteCount, 1)
        XCTAssertEqual(history.progress, NoteProgress(completed: 0, total: 2))
        XCTAssertEqual(history.daySnapshot?.filteredNotes(.unfinished), [remaining])
        XCTAssertEqual(history.daySnapshot?.notes.first?.continuedOn, "2026-10-06")
        XCTAssertEqual(daily.draft, "Today draft")
        XCTAssertEqual(daily.laterDraft, "Later draft")
        XCTAssertFalse(daily.continueHistoryTasks([source], expectedToday: today))
        XCTAssertEqual(daily.notes.count, 1)
        clock.now = "2026-10-07T12:00:00Z"
        XCTAssertFalse(daily.continueHistoryTasks([remaining], expectedToday: today))
        XCTAssertEqual(try repository.notes(for: "2026-10-07"), [])
        XCTAssertEqual(try repository.incompleteCount(for: remaining.dayKey), 1)
        XCTAssertEqual(daily.draft, "Today draft")
        // Completing the new attempt does not rewrite its source day's result.
        let attempt = try XCTUnwrap(repository.notes(for: "2026-10-06").first)
        try repository.setCompleted(id: attempt.id, completedAt: Date())
        XCTAssertEqual(try repository.historyDaySnapshot(for: source.dayKey).progress,
                       NoteProgress(completed: 0, total: 2))
    }


    func testCommittedCategoryOrderReloadsRetainedHistoryAndPreservesTasksAcrossFailureRetryAndReopen() throws {
        let repository = try SQLiteNoteRepository(databaseURL: databaseURL)
        let a = try repository.createCategory(name: "A")
        let longName = "B — A long category name that wraps in the task window and manager"
        let b = try repository.createCategory(name: longName)
        let empty = try repository.createCategory(name: "Unused")
        for key in ["2026-10-05", "2026-10-06"] {
            try repository.add(note("General", key, done: false, categoryID: nil))
            try repository.add(note("A completed", key, done: true, categoryID: a.id))
            try repository.add(note("B open", key, done: false, categoryID: b.id))
        }
        try repository.addLater(LaterTask(id: UUID(), text: "Later B", createdAt: Date(timeIntervalSince1970: 3),
                                          completedAt: nil, categoryID: b.id))
        try repository.addLater(LaterTask(id: UUID(), text: "Later A completed", createdAt: Date(timeIntervalSince1970: 4),
                                          completedAt: Date(timeIntervalSince1970: 5), categoryID: a.id))
        try repository.addLater(LaterTask(id: UUID(), text: "Later General", createdAt: Date(timeIntervalSince1970: 6),
                                          completedAt: nil, categoryID: nil))
        // Legacy sparse ranks are valid. Only a changed reorder may compact them.
        try executeRaw("UPDATE categories SET creation_order = creation_order * 100 + 20")
        try executeRaw("UPDATE notes SET display_order = display_order * 10 + 7")
        let initialCategories = try repository.categories()
        defaults.set("Unrelated preference", forKey: "integration.sentinel")
        defaults.set(a.id.uuidString, forKey: TaskCategoryPreferences.lastUsedCategoryIDKey)
        defaults.set(b.id.uuidString, forKey: TaskCategoryPreferences.laterLastUsedCategoryIDKey)
        let (daily, _) = makeApp(repository: repository)
        let presentation = daily.taskWindowPresentation
        defer { presentation.stopForTermination(); daily.stopForTermination() }
        daily.startup()
        presentation.setWindowVisible(true, state: daily)
        daily.draft = "Today draft"
        daily.draftCategoryID = empty.id
        daily.laterDraft = "Later draft"
        daily.laterDraftCategoryID = a.id
        for destination in [TaskListDestination.today, .later] {
            daily.categoryPreferences.setCollapsed(true, for: .category(b.id), in: destination)
        }
        let defaultsBefore = defaults.persistentDomain(forName: suite) as NSDictionary?
        let taskRows = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
        let laterRows = try rawRows("SELECT rowid, * FROM later_tasks ORDER BY rowid")
        let categoryFields = try rawRows("SELECT rowid, id, name, name_key FROM categories ORDER BY rowid")
        let schema = try rawRows("SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name")
        XCTAssertTrue(presentation.showHistory(state: daily))
        let history = try XCTUnwrap(presentation.historyState)
        try history.select(GregorianDay(key: "2026-10-05"))
        let snapshot = try XCTUnwrap(history.daySnapshot)
        XCTAssertEqual(history.detailGroups.map(\.group.name), ["General", "A", longName])
        XCTAssertTrue(presentation.showToday(state: daily))
        let revision = daily.historyRevision
        let request = CategoryMoveRequest(categoryID: b.id, expectedOrderIDs: [a.id, b.id, empty.id], placement: .before(a.id))
        let allCategoriesBefore = try rawRows("SELECT rowid, * FROM categories ORDER BY rowid")
        func assertUnchanged(file: StaticString = #filePath, line: UInt = #line) throws {
            XCTAssertEqual(daily.categories, initialCategories, file: file, line: line)
            XCTAssertEqual(daily.historyRevision, revision, file: file, line: line)
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM categories ORDER BY rowid"), allCategoriesBefore, file: file, line: line)
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), taskRows, file: file, line: line)
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM later_tasks ORDER BY rowid"), laterRows, file: file, line: line)
            XCTAssertNil(presentation.categoryMovementReveal, file: file, line: line)
            XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, defaultsBefore, file: file, line: line)
        }
        XCTAssertEqual(daily.moveCategory(CategoryMoveRequest(categoryID: b.id,
            expectedOrderIDs: [b.id, a.id, empty.id], placement: .before(a.id)), in: .list(.today)), .rejected(.catalogChanged))
        try assertUnchanged()
        XCTAssertEqual(daily.moveCategory(CategoryMoveRequest(categoryID: b.id,
            expectedOrderIDs: request.expectedOrderIDs, placement: .after(a.id)), in: .list(.today)), .unchanged)
        try assertUnchanged()
        // A real SQLite failure must roll back without publishing or invalidating History.
        try executeRaw("CREATE TRIGGER fail_category_reorder BEFORE UPDATE OF creation_order ON categories BEGIN SELECT RAISE(ABORT, 'injected reorder failure'); END")
        XCTAssertNil(daily.moveCategory(request, in: .list(.today)))
        XCTAssertEqual(daily.categories, initialCategories)
        XCTAssertEqual(daily.historyRevision, revision)
        XCTAssertEqual(try repository.categories(), initialCategories)
        XCTAssertNil(presentation.categoryMovementReveal)
        XCTAssertTrue(presentation.showHistory(state: daily))
        XCTAssertEqual(history.daySnapshot, snapshot)
        XCTAssertTrue(presentation.showToday(state: daily))
        try assertUnchanged()
        try executeRaw("DROP TRIGGER fail_category_reorder")
        // An independent reader permits rank updates but blocks COMMIT in rollback-journal mode.
        var reader: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &reader), SQLITE_OK)
        let connection = try XCTUnwrap(reader)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(sqlite3_exec(connection, "BEGIN; SELECT * FROM categories", nil, nil, nil), SQLITE_OK)
        XCTAssertNil(daily.moveCategory(request, in: .list(.today)))
        XCTAssertEqual(daily.categoryReorderIssue, .reorder)
        XCTAssertEqual(sqlite3_exec(connection, "ROLLBACK", nil, nil, nil), SQLITE_OK)
        try assertUnchanged()
        guard case .changed? = daily.moveCategory(request, in: .list(.today)) else { return XCTFail("Retry did not commit") }
        XCTAssertEqual(daily.historyRevision, revision + 1)
        XCTAssertTrue(presentation.showHistory(state: daily))
        XCTAssertTrue(presentation.historyState === history)
        XCTAssertEqual(history.detailGroups.map(\.group.name), ["General", longName, "A"])
        XCTAssertEqual(history.selectedDay, snapshot.summary.day)
        XCTAssertEqual(history.daySnapshot?.notes, snapshot.notes)
        XCTAssertEqual(history.progress, snapshot.progress)
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), taskRows)
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM later_tasks ORDER BY rowid"), laterRows)
        XCTAssertEqual(try rawRows("SELECT rowid, id, name, name_key FROM categories ORDER BY rowid"), categoryFields)
        XCTAssertEqual(try rawRows("SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name"), schema)
        XCTAssertEqual(try rawRows("PRAGMA user_version"), [[String(SQLiteNoteRepository.schemaVersion)]])
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, defaultsBefore)
        XCTAssertEqual(daily.draft, "Today draft")
        XCTAssertEqual(daily.draftCategoryID, empty.id)
        XCTAssertEqual(daily.laterDraft, "Later draft")
        XCTAssertEqual(daily.laterDraftCategoryID, a.id)
        XCTAssertEqual(TaskGroup.groups(categories: daily.categories, notes: daily.notes).map(\.name), ["General", longName, "A"])
        XCTAssertEqual(LaterTaskGroup.groups(categories: daily.categories, tasks: daily.laterTasks).map(\.name), ["General", longName, "A"])
        XCTAssertEqual(TaskCategoryOption.ordered(categories: daily.categories).map(\.categoryID), [nil, b.id, a.id, empty.id])
        XCTAssertTrue(presentation.showToday(state: daily))
        // Account for CRUD separately: create/remove an unused row; rename preserves ID and rank.
        let appended = try XCTUnwrap(daily.createCategory(name: "Temporary unused"))
        XCTAssertEqual(appended.creationOrder, 3)
        let renamed = try XCTUnwrap(daily.renameCategory(id: a.id, name: "A renamed"))
        XCTAssertEqual(renamed.creationOrder, 1)
        XCTAssertTrue(daily.removeCategory(id: appended.id))
        XCTAssertEqual(daily.historyRevision, revision + 4)
        XCTAssertEqual(daily.categories.map(\.id), [b.id, a.id, empty.id])
        XCTAssertTrue(presentation.showHistory(state: daily))
        XCTAssertTrue(presentation.historyState === history)
        XCTAssertEqual(history.detailGroups.map(\.group.name), ["General", longName, "A renamed"])
        XCTAssertEqual(history.daySnapshot?.notes, snapshot.notes)
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), taskRows)
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM later_tasks ORDER BY rowid"), laterRows)
        // The only surviving non-rank category changes are the explicit rename's name/name_key.
        var expectedFields = categoryFields
        let renamedIndex = try XCTUnwrap(expectedFields.firstIndex { $0[1] == a.id.uuidString })
        expectedFields[renamedIndex][2] = renamed.name
        expectedFields[renamedIndex][3] = renamed.nameKey
        XCTAssertEqual(try rawRows("SELECT rowid, id, name, name_key FROM categories ORDER BY rowid"), expectedFields)
        XCTAssertEqual(try rawRows("SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name"), schema)
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, defaultsBefore)
        presentation.stopForTermination()
        daily.stopForTermination()
        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.categories().map(\.id), [b.id, a.id, empty.id])
        let reopenedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let reloaded = DailyNotesState(repositoryFactory: { reopened },
            day: NoteDay(now: { ISO8601DateFormatter().date(from: "2026-10-06T12:00:00Z")! }, timeZone: { TimeZone(secondsFromGMT: 0)! }),
            notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter(),
            categoryPreferences: TaskCategoryPreferences(userDefaults: reopenedDefaults))
        defer { reloaded.stopForTermination() }
        reloaded.startup()
        XCTAssertEqual(reloaded.categories, daily.categories)
        XCTAssertEqual(reloaded.notes, daily.notes)
        XCTAssertEqual(reloaded.laterTasks, daily.laterTasks)
        XCTAssertEqual(reloaded.categoryPreferences.lastUsedCategoryID, a.id)
        XCTAssertEqual(reloaded.categoryPreferences.laterLastUsedCategoryID, b.id)
        for destination in [TaskListDestination.today, .later] {
            XCTAssertTrue(reloaded.categoryPreferences.isCollapsed(.category(b.id), in: destination))
        }
        XCTAssertEqual(reopenedDefaults.persistentDomain(forName: suite) as NSDictionary?, defaultsBefore)
        XCTAssertEqual(try rawRows("PRAGMA integrity_check"), [["ok"]])
        XCTAssertEqual(try rawRows("PRAGMA user_version"), [[String(SQLiteNoteRepository.schemaVersion)]])
        XCTAssertEqual(try reopened.historyDaySnapshot(for: "2026-10-05").notes, snapshot.notes)
    }

    func testRetainedTodayHistoryReloadsAfterReorderAndCategoryMove() throws {
        let repository = try SQLiteNoteRepository(databaseURL: databaseURL)
        let work = try repository.createCategory(name: "Work")
        let a = note("A", "2026-10-06", done: false, categoryID: work.id)
        let b = note("B", "2026-10-06", done: false, categoryID: work.id)
        try repository.add(a)
        try repository.add(b)
        let (daily, presentation) = makeApp(repository: repository)
        defer { presentation.stopForTermination(); daily.stopForTermination() }
        daily.startup()
        XCTAssertTrue(presentation.showHistory(state: daily))
        let history = try XCTUnwrap(presentation.historyState)
        try history.select(GregorianDay(key: a.dayKey))
        XCTAssertEqual(history.daySnapshot?.notes.map(\.id), [a.id, b.id])
        XCTAssertTrue(presentation.showToday(state: daily))
        let revision = daily.historyRevision
        let up = try XCTUnwrap(presentation.menuMoves(for: b.id, state: daily)?.moveUp)
        guard case .changed? = daily.moveTask(up) else { return XCTFail("Expected saved reorder") }
        XCTAssertEqual(daily.historyRevision, revision + 1)
        XCTAssertTrue(presentation.showHistory(state: daily))
        XCTAssertTrue(presentation.historyState === history)
        XCTAssertEqual(history.daySnapshot?.notes.map(\.id), [b.id, a.id])
        XCTAssertTrue(presentation.showToday(state: daily))
        let move = TaskMoveRequest(taskID: b.id, expectedDayKey: b.dayKey,
                                  expectedSourceGroup: .category(work.id), destinationGroup: .general,
                                  placement: .endOfGroup)
        guard case .changed? = daily.moveTask(move) else { return XCTFail("Expected saved category move") }
        XCTAssertTrue(presentation.showHistory(state: daily))
        XCTAssertEqual(history.detailGroups.map(\.group.name), ["General", "Work"])
        XCTAssertEqual(history.detailGroups.map { $0.visibleNotes.map(\.id) }, [[b.id], [a.id]])
        XCTAssertEqual(history.progress, daily.availableProgress)
    }

    func testCountsAgreeAcrossLayersThroughTodayCategoryAndDayChanges() throws {
        let repository = try SQLiteNoteRepository(databaseURL: databaseURL)
        let work = try repository.createCategory(name: "Work")
        for (text, key, done, category) in [
            ("Leap open", "2024-02-29", false, nil), ("Leap done", "2024-02-29", true, nil),
            ("Old year done", "2025-12-31", true, nil), ("Old year done 2", "2025-12-31", true, nil),
            ("New year open", "2026-01-01", false, nil),
            ("Sep work open", "2026-09-30", false, work.id), ("Sep work done", "2026-09-30", true, work.id),
            ("Sep general done", "2026-09-30", true, nil),
            ("Yesterday work open", "2026-10-05", false, work.id), ("Yesterday open", "2026-10-05", false, nil),
            ("Yesterday done", "2026-10-05", true, nil),
            ("Saved future", "2026-10-09", false, nil),
        ] as [(String, String, Bool, UUID?)] {
            try repository.add(note(text, key, done: done, categoryID: category))
        }
        let (daily, presentation) = makeApp(repository: repository)
        defer {
            presentation.stopForTermination()
            daily.stopForTermination()
        }
        daily.startup()
        daily.draft = "Keep my draft"
        let storageBefore = try storageSnapshot()
        let defaultsBefore = defaults.persistentDomain(forName: suite) as NSDictionary?

        // Read-only journey: calendar entry → months → detail filters → Unfinished → back.
        XCTAssertTrue(presentation.showHistory(state: daily))
        let history = try XCTUnwrap(presentation.historyState)
        XCTAssertEqual(history.selectedDay?.key, "2026-10-05")
        var grid = try monthGrid(history)
        XCTAssertEqual(cell(grid, "2026-10-01")?.countText, "0/0")
        XCTAssertEqual(cell(grid, "2026-10-05")?.countText, "1/3")
        XCTAssertEqual(cell(grid, "2026-10-06")?.isToday, true)
        XCTAssertEqual(cell(grid, "2026-10-06")?.countText, "0/0")
        XCTAssertEqual(cell(grid, "2026-10-09")?.countText, "0/1")
        XCTAssertEqual(cell(grid, "2026-10-09")?.isSelectable, true)
        XCTAssertEqual(cell(grid, "2026-10-10")?.countText, "—")
        XCTAssertEqual(cell(grid, "2026-10-10")?.isSelectable, false)
        try assertEveryCellMatchesDetail(history)
        for (month, keys) in [("2026-09-01", ["2026-09-30"]), ("2026-01-01", ["2026-01-01"]),
                              ("2025-12-01", ["2025-12-31"]), ("2024-02-01", ["2024-02-29"])] {
            try history.changeMonth(containing: GregorianDay(key: month))
            XCTAssertEqual(history.monthSummaries?.map(\.dayKey), keys)
            try assertEveryCellMatchesDetail(history)
        }
        try history.select(GregorianDay(key: "2026-09-30"))
        XCTAssertEqual(history.detailGroups.map(\.group.name), ["General", "Work"])
        XCTAssertEqual(history.detailGroups.map(\.group.progress),
                       [NoteProgress(completed: 1, total: 1), NoteProgress(completed: 1, total: 2)])

        XCTAssertTrue(presentation.showUnfinished(state: daily))
        let unfinished = try XCTUnwrap(presentation.unfinishedState)
        XCTAssertEqual(unfinished.summaries?.map(\.dayKey), ["2026-10-05", "2026-09-30", "2026-01-01", "2024-02-29"])
        XCTAssertFalse(unfinished.hasMore)
        for summary in unfinished.summaries ?? [] {
            XCTAssertTrue(presentation.showUnfinishedDay(summary.day, state: daily))
            XCTAssertEqual(history.progress, summary.progress, summary.dayKey)
            XCTAssertEqual(history.detailGroups.flatMap(\.visibleNotes).count, summary.incomplete, summary.dayKey)
            XCTAssertNil(unfinished.selectionIssue)
            presentation.backToUnfinished(state: daily)
        }
        presentation.backToHistory(state: daily)
        XCTAssertTrue(presentation.showToday(state: daily))

        XCTAssertEqual(try storageSnapshot(), storageBefore)
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, defaultsBefore)
        XCTAssertEqual(daily.draft, "Keep my draft")
        XCTAssertEqual(daily.todayKey, "2026-10-06")
        XCTAssertEqual(try SQLiteNoteRepository(databaseURL: databaseURL).historyDaySnapshot(for: "2026-09-30"),
                       try daily.historyDaySnapshot(for: "2026-09-30"))

        // Today's committed writes reach the calendar, detail, and saved progress.
        XCTAssertTrue(presentation.showHistory(state: daily))
        try history.thisMonth()
        func refreshed() throws -> HistoryCalendarDay? {
            presentation.refreshBrowser(state: daily)
            let today = try XCTUnwrap(cell(try monthGrid(history), "2026-10-06"))
            XCTAssertEqual(today.availability.progress, daily.availableProgress)
            XCTAssertEqual(history.progress, daily.availableProgress)
            return today
        }
        XCTAssertEqual(daily.add(text: "Today A", categoryID: work.id), .added)
        XCTAssertEqual(daily.add(text: "Today B"), .added)
        XCTAssertEqual(daily.add(text: "Today C"), .added)
        XCTAssertEqual(try refreshed()?.countText, "0/3")
        let ids = daily.notes.map(\.id)
        XCTAssertTrue(daily.setCompleted(id: ids[0], completed: true))
        daily.beginEditing(id: ids[1])
        daily.editDraft = "Today B edited"
        XCTAssertTrue(daily.saveEdit())
        XCTAssertTrue(daily.delete(id: ids[2]))
        XCTAssertEqual(try refreshed()?.countText, "1/2")
        XCTAssertEqual(history.detailGroups.flatMap(\.visibleNotes).map(\.text), ["Today B edited", "Today A"])

        // Rejected writes do not publish a revision or change counts.
        let revision = daily.historyRevision
        XCTAssertEqual(daily.add(text: "   "), .empty)
        XCTAssertNil(daily.createCategory(name: "work"))
        XCTAssertEqual(daily.historyRevision, revision)
        XCTAssertEqual(try refreshed()?.countText, "1/2")

        // History labels follow the current catalog; counts and order do not change.
        XCTAssertNotNil(daily.renameCategory(id: work.id, name: "Projects"))
        presentation.refreshBrowser(state: daily)
        try history.select(GregorianDay(key: "2026-09-30"))
        XCTAssertEqual(history.detailGroups.map(\.group.name), ["General", "Projects"])
        XCTAssertTrue(daily.removeCategory(id: work.id))
        presentation.refreshBrowser(state: daily)
        XCTAssertEqual(history.detailGroups.map(\.group.name), ["General"])
        XCTAssertEqual(history.detailGroups.first?.visibleNotes.map(\.text),
                       ["Sep work open", "Sep work done", "Sep general done"])
        XCTAssertEqual(history.progress, NoteProgress(completed: 2, total: 3))
        try history.changeMonth(containing: GregorianDay(key: "2026-10-01"))
        XCTAssertEqual(cell(try monthGrid(history), "2026-10-05")?.countText, "1/3")
        try assertEveryCellMatchesDetail(history)

        // Day change moves the cutoff and Today marker; civil selection is kept.
        try history.select(GregorianDay(key: "2026-10-05"), filter: .completed)
        clock.now = "2026-10-07T12:00:00Z"
        daily.refreshIfDayChanged()
        presentation.refreshBrowser(state: daily)
        XCTAssertEqual(history.today.key, "2026-10-07")
        XCTAssertEqual(history.selectedDay?.key, "2026-10-05")
        XCTAssertEqual(history.filter, .completed)
        grid = try monthGrid(history)
        XCTAssertEqual(cell(grid, "2026-10-06")?.isToday, false)
        XCTAssertEqual(cell(grid, "2026-10-07")?.isToday, true)
        XCTAssertEqual(cell(grid, "2026-10-06")?.countText, "1/2")
        XCTAssertTrue(presentation.showUnfinished(state: daily))
        XCTAssertEqual(unfinished.summaries?.first?.dayKey, "2026-10-06")
        XCTAssertEqual(unfinished.summaries?.first?.progress, NoteProgress(completed: 1, total: 2))
        XCTAssertEqual(try repository.notes(for: "2026-10-06").map(\.text), ["Today A", "Today B edited"])
    }

    /// Measures the bounded reads on a multi-year personal history. Bounds are
    /// deliberately loose; the printed timings are the evidence.
    func testMultiYearHistoryReadsStayBoundedAndExact() throws {
        let repository = try SQLiteNoteRepository(databaseURL: databaseURL)
        // 2023-10-07 ... 2026-10-05: 1,095 days × 10 tasks, completed = index % 11.
        var expectedUnfinishedDays = 0
        var keys: [String] = []
        var date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2023-10-07T12:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        while formatter.string(from: date) < "2026-10-06" {
            keys.append(formatter.string(from: date))
            date = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: date))
        }
        var statements = ["BEGIN;"]
        for (index, key) in keys.enumerated() {
            let completed = index % 11
            if completed < 10 { expectedUnfinishedDays += 1 }
            for task in 0..<10 {
                // Schema v4 requires a unique saved rank per day.
                statements.append("INSERT INTO notes (id, text, day_key, created_at, completed_at, display_order) VALUES ('\(UUID().uuidString)', 'Task \(task)', '\(key)', \(1_700_000_000 + index * 100 + task), \(task < completed ? "1700000000" : "NULL"), \(task));")
            }
        }
        statements.append("COMMIT;")
        try executeRaw(statements.joined(separator: "\n"))
        let rows = keys.count * 10
        let storageBefore = try storageSnapshot()
        let (daily, _) = makeApp(repository: repository)
        defer { daily.stopForTermination() }
        daily.startup()

        let timer = ContinuousClock()
        var monthSummaries: [DayTaskSummary] = []
        let month = try HistoryDayRange.month(containing: GregorianDay(key: "2026-09-01"))
        let monthTime = try timer.measure { monthSummaries = try daily.daySummaries(in: month) }
        XCTAssertEqual(monthSummaries.count, 30)
        var snapshot: HistoryDaySnapshot?
        let dayTime = try timer.measure { snapshot = try daily.historyDaySnapshot(for: "2026-09-30") }
        XCTAssertEqual(snapshot?.progress, monthSummaries.last?.progress)
        var firstPage: UnfinishedDayPage?
        let cutoff = try GregorianDay(key: "2026-10-06")
        let firstPageTime = try timer.measure { firstPage = try daily.unfinishedDayPage(before: cutoff, limit: 31) }
        XCTAssertEqual(firstPage?.summaries.count, 31)
        var pages = 0
        var unfinishedDays = 0
        let walkTime = try timer.measure {
            var before: GregorianDay? = cutoff
            while let current = before {
                let page = try daily.unfinishedDayPage(before: current, limit: 31)
                pages += 1
                unfinishedDays += page.summaries.count
                before = page.nextBefore
            }
        }
        XCTAssertEqual(unfinishedDays, expectedUnfinishedDays)
        XCTAssertEqual(try storageSnapshot(), storageBefore)
        print("TASK-013 history read timings: rows=\(rows) days=\(keys.count) unfinishedDays=\(unfinishedDays) "
              + "month=\(monthTime) daySnapshot=\(dayTime) firstUnfinishedPage=\(firstPageTime) "
              + "allUnfinishedPages=\(walkTime) pages=\(pages)")
        XCTAssertLessThan(monthTime, .milliseconds(250))
        XCTAssertLessThan(dayTime, .milliseconds(250))
        XCTAssertLessThan(firstPageTime, .milliseconds(250))
    }

    // MARK: - Helpers

    private func makeApp(repository: SQLiteNoteRepository) -> (DailyNotesState, TaskWindowPresentation) {
        let clock = clock
        let noteDay = NoteDay(now: { ISO8601DateFormatter().date(from: clock.now)! },
                              timeZone: { TimeZone(secondsFromGMT: 0)! })
        let daily = DailyNotesState(repositoryFactory: { repository }, day: noteDay,
                                    notificationCenter: NotificationCenter(),
                                    workspaceNotificationCenter: NotificationCenter(),
                                    categoryPreferences: TaskCategoryPreferences(userDefaults: defaults))
        let presentation = TaskWindowPresentation()
        presentation.setWindowVisible(true, state: daily)
        return (daily, presentation)
    }

    private func note(_ text: String, _ key: String, done: Bool, categoryID: UUID?) -> Note {
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        return Note(id: UUID(), text: text, dayKey: key, createdAt: created,
                    completedAt: done ? created : nil, categoryID: categoryID)
    }

    private func monthGrid(_ history: TaskHistoryState) throws -> HistoryMonthGrid {
        try HistoryMonthGrid(month: history.month, today: history.today,
                             selectedDay: history.selectedDay, summaries: history.monthSummaries)
    }

    private func cell(_ grid: HistoryMonthGrid, _ key: String) -> HistoryCalendarDay? {
        for case let .day(day) in grid.cells where day.day.key == key { return day }
        return nil
    }

    /// Every selectable cell's count equals its full-day detail under each
    /// filter, and filtering never changes the grid.
    private func assertEveryCellMatchesDetail(_ history: TaskHistoryState,
                                              file: StaticString = #filePath, line: UInt = #line) throws {
        let selection = history.selectedDay
        let filter = history.filter
        let summaries = history.monthSummaries
        let grid = try monthGrid(history)
        for case let .day(day) in grid.cells where day.isSelectable {
            for filter in [HistoryTaskFilter.all, .unfinished, .completed] {
                try history.select(day.day, filter: filter)
                XCTAssertEqual(history.progress, day.availability.progress, day.id, file: file, line: line)
                XCTAssertEqual(history.daySnapshot?.groups.reduce(0) { $0 + $1.progress.total },
                               day.availability.progress?.total, day.id, file: file, line: line)
                let filtered = try XCTUnwrap(history.daySnapshot?.filteredNotes(filter), file: file, line: line)
                XCTAssertEqual(Set(history.detailGroups.flatMap(\.visibleNotes).map(\.id)),
                               Set(filtered.map(\.id)), day.id, file: file, line: line)
                for detail in history.detailGroups {
                    XCTAssertEqual(detail.visibleNotes,
                                   filtered.filter { TaskGroupID(categoryID: $0.categoryID) == detail.group.id },
                                   day.id, file: file, line: line)
                }
                XCTAssertEqual(history.monthSummaries, summaries, day.id, file: file, line: line)
            }
            XCTAssertEqual(try monthGrid(history).cells.map(\.id), grid.cells.map(\.id), file: file, line: line)
        }
        if let selection { try history.select(selection, filter: filter) }
    }

    private func storageSnapshot() throws -> [[String?]] {
        try rawRows("SELECT rowid, id, text, day_key, quote(created_at), quote(completed_at), category_id FROM notes ORDER BY rowid")
            + rawRows("SELECT rowid, id, name, name_key, creation_order FROM categories ORDER BY rowid")
            + rawRows("SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name")
            + rawRows("PRAGMA user_version")
    }

    private func executeRaw(_ sql: String) throws {
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &connection), SQLITE_OK)
        let database = try XCTUnwrap(connection)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK,
                       String(cString: sqlite3_errmsg(database)))
    }

    private func rawRows(_ sql: String) throws -> [[String?]] {
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(databaseURL.path, &connection, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        let database = try XCTUnwrap(connection)
        defer { sqlite3_close(database) }
        var prepared: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, sql, -1, &prepared, nil), SQLITE_OK, sql)
        let statement = try XCTUnwrap(prepared)
        defer { sqlite3_finalize(statement) }
        var rows: [[String?]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                sqlite3_column_text(statement, column).map { String(cString: $0) }
            })
        }
        return rows
    }
}
