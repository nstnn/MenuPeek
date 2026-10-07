import XCTest
@testable import MenuPocket

final class MenuBarGlanceTests: XCTestCase {
    private let day = "2026-10-07"

    // MARK: Header

    func testHeaderShowsShortDateCountBarAndOneSpokenLabel() {
        let glance = glance(progress: NoteProgress(completed: 4, total: 7))

        XCTAssertEqual(glance.header.dateLabel, "Wed 7 Oct")
        XCTAssertEqual(glance.header.countLabel, "4 of 7 done")
        XCTAssertEqual(glance.header.fraction ?? -1, 4.0 / 7.0, accuracy: 1e-9)
        XCTAssertEqual(glance.header.accessibilityLabel, "Wednesday 7 October, 4 of 7 tasks done")
    }

    func testDateLabelsCrossMonthAndYearBoundariesIndependentOfTimeZone() {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        let expected = ["2026-01-31": "Sat 31 Jan", "2026-02-01": "Sun 1 Feb",
                        "2026-12-31": "Thu 31 Dec", "2027-01-01": "Fri 1 Jan",
                        "2024-02-29": "Thu 29 Feb", "2026-10-07": "Wed 7 Oct"]

        for zone in ["Pacific/Kiritimati", "Pacific/Pago_Pago", "Asia/Ho_Chi_Minh", "UTC"] {
            NSTimeZone.default = TimeZone(identifier: zone)!
            for (key, label) in expected {
                XCTAssertEqual(glance(dayKey: key, progress: NoteProgress(completed: 0, total: 0))
                    .header.dateLabel, label, "\(key) in \(zone)")
            }
        }
    }

    func testUnparsableDayKeyFallsBackToTheRawKey() {
        for key in ["", "2026-02-30", "2026-10-7", "not a day"] {
            let glance = glance(dayKey: key, progress: NoteProgress(completed: 1, total: 2))
            XCTAssertEqual(glance.header.dateLabel, key)
            XCTAssertEqual(glance.header.accessibilityLabel, "\(key), 1 of 2 tasks done")
        }
    }

    // MARK: States

    func testEmptyDayHasZeroCountEmptyBarAndNoRows() {
        let glance = glance(progress: NoteProgress(completed: 0, total: 0))

        XCTAssertEqual(glance.header.countLabel, "0 of 0 done")
        XCTAssertEqual(glance.header.fraction, 0)
        XCTAssertEqual(glance.body, .empty)
        XCTAssertTrue(glance.canAddTask)
    }

    func testAllDoneDayHasFullBarAndNoRows() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let notes = [note("A", work, completed: true), note("B", nil, completed: true)]

        let glance = glance(notes: notes, categories: [work])

        XCTAssertEqual(glance.header.countLabel, "2 of 2 done")
        XCTAssertEqual(glance.header.fraction, 1)
        XCTAssertEqual(glance.body, .allDone)
    }

    func testUnavailableTodayShowsDashNoBarAndIgnoresStaleRows() {
        let stale = TaskGroup.groups(categories: [], notes: [note("Stale", nil)])

        let glance = MenuBarGlance(dayKey: day, progress: nil, groups: stale,
                                   laterRemainingCount: 3, canAddTask: true)

        XCTAssertEqual(glance.header.dateLabel, "Wed 7 Oct")
        XCTAssertEqual(glance.header.countLabel, "—")
        XCTAssertNil(glance.header.fraction)
        XCTAssertEqual(glance.header.accessibilityLabel, "Wednesday 7 October, tasks are unavailable")
        XCTAssertEqual(glance.body, .unavailable)
        XCTAssertFalse(glance.canAddTask, "Add Task… targets Today, which cannot be read")
        XCTAssertEqual(glance.laterRemainingCount, 3, "A Today read failure does not hide Later")
    }

    func testAddAvailabilityFollowsTheCallerWhenTodayIsAvailable() {
        XCTAssertTrue(glance(progress: NoteProgress(completed: 0, total: 0), canAddTask: true).canAddTask)
        XCTAssertFalse(glance(progress: NoteProgress(completed: 0, total: 0), canAddTask: false).canAddTask)
        XCTAssertFalse(MenuBarGlance(dayKey: day, progress: nil, groups: [],
                                     laterRemainingCount: nil, canAddTask: false).canAddTask)
    }

    // MARK: Rows and overflow

    func testRowCountsAndOverflowAroundTheLimit() {
        for (unfinished, listed, overflow) in [(1, 1, nil), (5, 5, nil), (6, 5, 1), (12, 5, 7)] as [(Int, Int, Int?)] {
            let notes = (0..<unfinished).map { note("Task \($0)", nil) } + [note("Done", nil, completed: true)]

            let glance = glance(notes: notes)

            guard case let .tasks(rows, overflowCount) = glance.body else {
                return XCTFail("Expected rows for \(unfinished) unfinished tasks")
            }
            XCTAssertEqual(rows.map(\.title), (0..<listed).map { "Task \($0)" })
            XCTAssertEqual(overflowCount, overflow, "\(unfinished) unfinished")
            XCTAssertEqual(glance.header.countLabel, "1 of \(unfinished + 1) done")
        }
    }

    func testRowsFollowTheTodayWindowGroupOrderAndSkipCompletedTasks() throws {
        let home = try TaskCategory(name: "Home", creationOrder: 4)
        let work = try TaskCategory(name: "Work", creationOrder: 1)
        let notes = [note("Buy oat milk", home), note("Reply to Minh", work), note("Standup", nil),
                     note("Old report", work, completed: true), note("Review PR 48", work),
                     note("Call the bank", home), note("Water plants", nil)]
        let groups = TaskGroup.groups(categories: [home, work], notes: notes)

        let glance = MenuBarGlance(dayKey: day, progress: NoteProgress(notes: notes, for: day),
                                   groups: groups, laterRemainingCount: nil, canAddTask: true)

        let windowOrder = groups.flatMap(\.notes).filter { !$0.isCompleted }
        guard case let .tasks(rows, overflowCount) = glance.body else { return XCTFail("Expected rows") }
        XCTAssertEqual(rows.map(\.id), Array(windowOrder.prefix(5).map(\.id)))
        XCTAssertEqual(rows.map(\.title), ["Reply to Minh", "Review PR 48", "Buy oat milk",
                                           "Call the bank", "Standup"])
        XCTAssertEqual(rows.map(\.categoryName), ["Work", "Work", "Home", "Home", "General"])
        XCTAssertEqual(overflowCount, 1)
    }

    func testCategoryNamesAppearOnlyWhenTasksSpanMoreThanOneGroup() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)

        let generalOnly = glance(notes: [note("A", nil), note("B", nil)], categories: [work])
        let workOnly = glance(notes: [note("A", work)], categories: [work])
        // A group with only completed tasks still counts as a second group.
        let mixed = glance(notes: [note("A", work), note("B", nil, completed: true)], categories: [work])

        XCTAssertEqual(rows(generalOnly).map(\.categoryName), [nil, nil])
        XCTAssertEqual(rows(workOnly).map(\.categoryName), [nil])
        XCTAssertEqual(rows(mixed).map(\.categoryName), ["Work"])
    }

    func testCollapsedGroupsAreListedBecauseTheModelTakesNoCollapseInput() throws {
        // `DailyNotesState.groups` includes collapsed groups, and the glance has
        // no collapse input, so every group passed in is listed.
        let work = try TaskCategory(name: "Work", creationOrder: 0)

        let glance = glance(notes: [note("Hidden in Work", work), note("Hidden in General", nil)],
                            categories: [work])

        XCTAssertEqual(rows(glance).map(\.title), ["Hidden in Work", "Hidden in General"])
    }

    func testLongAndMultilineTextIsOneTruncatedLineWithTheFullTextAsTooltip() {
        let long = String(repeating: "word ", count: 30).trimmingCharacters(in: .whitespaces)
        let multiline = "First line\nsecond\tline"
        let exact = String(repeating: "x", count: MenuBarGlance.titleLimit)

        let rows = rows(glance(notes: [note(long, nil), note(multiline, nil), note(exact, nil), note("Short", nil)]))

        XCTAssertEqual(rows[0].title.count, MenuBarGlance.titleLimit)
        XCTAssertTrue(rows[0].title.hasSuffix("word…"), "No space before the ellipsis: \(rows[0].title)")
        XCTAssertEqual(rows[0].fullText, long)
        XCTAssertEqual(rows[0].toolTip, long)
        XCTAssertEqual(rows[1].title, "First line second line")
        XCTAssertEqual(rows[1].toolTip, multiline)
        XCTAssertEqual(rows[2].title, exact)
        XCTAssertNil(rows[2].toolTip)
        XCTAssertNil(rows[3].toolTip)
    }

    func testTruncationDropsASpaceBeforeTheEllipsis() {
        // The 59th character is a space, so the cut would leave "word …".
        let text = "abc" + String(repeating: " word", count: 20)

        let title = MenuBarGlance.title(for: text)

        XCTAssertEqual(title, "abc" + String(repeating: " word", count: 11) + "…")
    }

    func testTruncationKeepsWholeGraphemes() {
        let text = String(repeating: "👩‍💻", count: MenuBarGlance.titleLimit + 5)

        let title = MenuBarGlance.title(for: text)

        XCTAssertEqual(title.count, MenuBarGlance.titleLimit)
        XCTAssertEqual(title, String(repeating: "👩‍💻", count: MenuBarGlance.titleLimit - 1) + "…")
    }

    // MARK: Later line

    func testLaterLineAppearsOnlyForAPositiveAvailableCountInEveryTodayState() {
        let states: [(String, NoteProgress?, [Note])] = [
            ("tasks", NoteProgress(completed: 0, total: 1), [note("A", nil)]),
            ("empty", NoteProgress(completed: 0, total: 0), []),
            ("all done", NoteProgress(completed: 1, total: 1), [note("A", nil, completed: true)]),
            ("unavailable", nil, []),
        ]
        for (name, progress, notes) in states {
            for (later, expected) in [(nil, nil), (0, nil), (1, 1), (3, 3)] as [(Int?, Int?)] {
                let glance = MenuBarGlance(dayKey: day, progress: progress,
                                           groups: TaskGroup.groups(categories: [], notes: notes),
                                           laterRemainingCount: later, canAddTask: true)
                XCTAssertEqual(glance.laterRemainingCount, expected, "\(name), Later \(String(describing: later))")
                XCTAssertEqual(glance.header.progress, progress, "Later never changes Today's header")
            }
        }
    }

    // MARK: Helpers

    private func glance(dayKey: String? = nil, progress: NoteProgress, canAddTask: Bool = true) -> MenuBarGlance {
        MenuBarGlance(dayKey: dayKey ?? day, progress: progress, groups: [],
                      laterRemainingCount: nil, canAddTask: canAddTask)
    }

    private func glance(notes: [Note], categories: [TaskCategory] = []) -> MenuBarGlance {
        MenuBarGlance(dayKey: day, progress: NoteProgress(notes: notes, for: day),
                      groups: TaskGroup.groups(categories: categories, notes: notes),
                      laterRemainingCount: nil, canAddTask: true)
    }

    private func rows(_ glance: MenuBarGlance) -> [MenuBarGlance.Row] {
        guard case let .tasks(rows, _) = glance.body else {
            XCTFail("Expected rows, got \(glance.body)")
            return []
        }
        return rows
    }

    private func note(_ text: String, _ category: TaskCategory?, completed: Bool = false) -> Note {
        let instant = Date(timeIntervalSince1970: 1_790_000_000)
        return Note(id: UUID(), text: text, dayKey: day, createdAt: instant,
                    completedAt: completed ? instant : nil, categoryID: category?.id)
    }
}
