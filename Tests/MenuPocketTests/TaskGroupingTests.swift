import XCTest
@testable import MenuPocket

final class TaskGroupingTests: XCTestCase {
    private let day = "2026-09-27"

    func testSavedRankChangeAgreesAcrossGroupsHistoryGlanceAndCategoryOptions() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 8)
        let personal = try TaskCategory(name: "Personal", creationOrder: 20)
        let empty = try TaskCategory(name: "Empty", creationOrder: 40)
        let catalog = [empty, personal, work]
        let saved = [note("W1", work), note("G1", nil), note("P1", personal),
                     note("W2", work, completed: true)]
        let later = [laterTask("W1", work), laterTask("G1", nil), laterTask("P1", personal)]
        let original = TaskGroup.groups(categories: catalog, notes: saved)
        XCTAssertEqual(original.map(\.name), ["General", "Work", "Personal"])

        // The same UUID/name now has an earlier saved rank; input array and
        // names are not the ordering authority. Empty stays selectable.
        let reordered = [empty, TaskCategory(personal, creationOrder: -5), work]
        let options = TaskCategoryOption.ordered(categories: reordered)
        XCTAssertEqual(options.map(\.name), ["General", "Personal", "Work", "Empty"])
        XCTAssertEqual(options.map(\.categoryID), [nil, personal.id, work.id, empty.id])
        XCTAssertEqual(options.map(\.id), [.general, .category(personal.id), .category(work.id), .category(empty.id)])
        XCTAssertEqual(TaskCategoryOption.ordered(categories: []), [.general])

        let groups = TaskGroup.groups(categories: reordered, notes: saved)
        let history = try HistoryDaySnapshot(dayKey: day, notes: saved, categories: reordered)
        let laterGroups = LaterTaskGroup.groups(categories: reordered, tasks: later)
        XCTAssertEqual(groups.map(\.name), ["General", "Personal", "Work"])
        XCTAssertEqual(history.groups, groups)
        XCTAssertEqual(laterGroups.map(\.id), groups.map(\.id))
        XCTAssertEqual(groups.map(\.notes), [[saved[1]], [saved[2]], [saved[0], saved[3]]])
        XCTAssertEqual(laterGroups.map(\.tasks), [[later[1]], [later[2]], [later[0]]])
        XCTAssertEqual(history.notes, saved)
        XCTAssertEqual(history.progress, NoteProgress(completed: 1, total: 4))
        let glance = MenuBarGlance(dayKey: day, progress: history.progress, groups: groups,
                                   laterRemainingCount: 3, canAddTask: true)
        guard case let .tasks(rows, overflow) = glance.body else { return XCTFail("Expected glance rows") }
        XCTAssertEqual(rows.map(\.id), [saved[1].id, saved[2].id, saved[0].id])
        XCTAssertNil(overflow)
        XCTAssertEqual(glance.laterRemainingCount, 3)
        XCTAssertEqual(catalog, [empty, personal, work], "Presentation cannot rewrite the catalog")
    }

    func testGroupsFollowSavedCategoryRankAndKeepSavedTaskOrderWithGeneralFirst() throws {
        let school = try TaskCategory(name: "School", creationOrder: 0)
        let work = try TaskCategory(name: "Work", creationOrder: 2)
        let fitness = try TaskCategory(name: "Fitness", creationOrder: 5)
        let reply = note("Reply to client", work, completed: true)
        let groceries = note("Buy groceries", nil)
        let math = note("Finish math", school, completed: true)
        let report = note("Finish report", work)
        let desk = note("Clean desk", nil)
        let biology = note("Read biology", school)
        let saved = [reply, groceries, math, report, desk, biology]

        // Catalog input order and gaps in saved order do not change the result.
        let groups = TaskGroup.groups(categories: [fitness, work, school], notes: saved)

        XCTAssertEqual(groups.map(\.id), [.general, .category(school.id), .category(work.id)])
        XCTAssertEqual(groups.map(\.name), ["General", "School", "Work"])
        XCTAssertEqual(groups.map(\.notes), [[groceries, desk], [math, biology], [reply, report]])
        XCTAssertEqual(groups.map(\.progress), [NoteProgress(completed: 0, total: 2),
                                                NoteProgress(completed: 1, total: 2),
                                                NoteProgress(completed: 1, total: 2)])
    }

    func testReassignedTaskTakesItsOriginalRelativePositionInTheDestination() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let first = note("A", work)
        let second = note("B", nil)
        let third = note("C", work)
        let fourth = note("D", nil)
        // A saved reassignment keeps the task's position in the canonical array.
        let reassigned = Note(id: third.id, text: third.text, dayKey: third.dayKey,
                              createdAt: third.createdAt, completedAt: nil, categoryID: nil)

        let groups = TaskGroup.groups(categories: [work], notes: [first, second, reassigned, fourth])

        XCTAssertEqual(groups.map(\.id), [.general, .category(work.id)])
        XCTAssertEqual(groups.map(\.notes), [[second, reassigned, fourth], [first]])
    }

    func testGroupCountsSumToDailyProgress() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let saved = [note("1", work, completed: true), note("2", home), note("3", nil, completed: true),
                     note("4", work), note("5", home, completed: true), note("6", nil)]

        let groups = TaskGroup.groups(categories: [work, home], notes: saved)

        XCTAssertEqual(groups.map(\.progress.completed).reduce(0, +), 3)
        XCTAssertEqual(groups.map(\.progress.total).reduce(0, +), 6)
        XCTAssertEqual(NoteProgress(notes: saved, for: day), NoteProgress(completed: 3, total: 6))
        XCTAssertEqual(Set(groups.flatMap(\.notes).map(\.id)), Set(saved.map(\.id)))
    }

    func testOnlyPopulatedGroupsAppearAndGeneralNeedsNoCategoryRow() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)

        XCTAssertEqual(TaskGroup.groups(categories: [], notes: []), [])
        XCTAssertEqual(TaskGroup.groups(categories: [work], notes: []), [])

        let uncategorized = [note("Only General", nil)]
        let groups = TaskGroup.groups(categories: [work], notes: uncategorized)
        XCTAssertEqual(groups, [TaskGroup(id: .general, name: "General", notes: uncategorized)])

        let categorized = [note("Only Work", work)]
        XCTAssertEqual(TaskGroup.groups(categories: [work], notes: categorized).map(\.id),
                       [.category(work.id)])
    }

    func testGroupIdentityIgnoresNamesAndHasStableStorageKeys() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 3)
        let renamed = try TaskCategory(id: work.id, name: "Office", creationOrder: work.creationOrder)
        let saved = [note("Task", work)]

        let before = try XCTUnwrap(TaskGroup.groups(categories: [work], notes: saved).first)
        let after = try XCTUnwrap(TaskGroup.groups(categories: [renamed], notes: saved).first)
        XCTAssertEqual(before.id, after.id)
        XCTAssertEqual(after.name, "Office")
        XCTAssertEqual(TaskGroupID(categoryID: work.id), before.id)
        XCTAssertEqual(TaskGroupID(categoryID: nil), .general)

        for id in [TaskGroupID.general, .category(work.id)] {
            XCTAssertEqual(TaskGroupID(storageKey: id.storageKey), id)
        }
        XCTAssertEqual(TaskGroupID(storageKey: work.id.uuidString.lowercased()), .category(work.id))
        XCTAssertNil(UUID(uuidString: TaskGroupID.general.storageKey))
        for invalid in ["", "General", "not-a-uuid"] {
            XCTAssertNil(TaskGroupID(storageKey: invalid))
        }
    }

    func testDragDestinationsIncludeEmptyGroupsWithoutChangingCountsOrNormalPresentation() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 2)
        let empty = try TaskCategory(name: "Empty", creationOrder: 0)
        let saved = [note("Saved", work, completed: true)]
        let normal = TaskGroup.groups(categories: [work, empty], notes: saved)
        let dragging = TaskGroup.groups(categories: [work, empty], notes: saved, includeEmpty: true)
        XCTAssertEqual(dragging.map(\.id), [.general, .category(empty.id), .category(work.id)])
        XCTAssertEqual(dragging.map(\.progress), [NoteProgress(completed: 0, total: 0),
                                                NoteProgress(completed: 0, total: 0),
                                                NoteProgress(completed: 1, total: 1)])
        XCTAssertEqual(dragging.flatMap(\.notes), saved)
        XCTAssertEqual(TaskGroup.groups(categories: [work, empty], notes: saved), normal)
    }

    func testLaterGroupsFollowSavedCategoryRankAndKeepSavedOrderWithGeneralFirst() throws {
        let school = try TaskCategory(name: "School", creationOrder: 0)
        let work = try TaskCategory(name: "Work", creationOrder: 2)
        let reply = laterTask("Reply to client", work, completed: true)
        let groceries = laterTask("Buy groceries", nil)
        let math = laterTask("Finish math", school, completed: true)
        let report = laterTask("Finish report", work)
        let desk = laterTask("Clean desk", nil)
        let biology = laterTask("Read biology", school)
        let saved = [reply, groceries, math, report, desk, biology]

        let groups = LaterTaskGroup.groups(categories: [work, school], tasks: saved)

        XCTAssertEqual(groups.map(\.id), [.general, .category(school.id), .category(work.id)])
        XCTAssertEqual(groups.map(\.name), ["General", "School", "Work"])
        XCTAssertEqual(groups.map(\.tasks), [[groceries, desk], [math, biology], [reply, report]])
        XCTAssertEqual(groups.map(\.remainingCount), [2, 1, 1])
    }

    func testLaterGroupsWithOnlyCompletedTasksRemainVisibleWithZeroRemaining() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let completedWork = laterTask("Done work", work, completed: true)
        let pendingGeneral = laterTask("Pending general", nil, completed: false)

        let groups = LaterTaskGroup.groups(categories: [work], tasks: [completedWork, pendingGeneral])

        XCTAssertEqual(groups.map(\.id), [.general, .category(work.id)])
        XCTAssertEqual(groups[0].remainingCount, 1)
        XCTAssertEqual(groups[0].tasks.count, 1)
        XCTAssertEqual(groups[1].remainingCount, 0)
    }

    func testLaterEmptyGroupsDoNotAppear() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let task = laterTask("Only work", work)

        let groups = LaterTaskGroup.groups(categories: [work, home], tasks: [task])

        XCTAssertEqual(groups.map(\.id), [.category(work.id)])
        XCTAssertEqual(groups.map(\.name), ["Work"])
    }

    private func note(_ text: String, _ category: TaskCategory?, completed: Bool = false) -> Note {
        let instant = Date(timeIntervalSince1970: 1_790_000_000)
        return Note(id: UUID(), text: text, dayKey: day, createdAt: instant,
                    completedAt: completed ? instant : nil, categoryID: category?.id)
    }

    private func laterTask(_ text: String, _ category: TaskCategory?, completed: Bool = false) -> LaterTask {
        let instant = Date(timeIntervalSince1970: 1_790_000_000)
        return LaterTask(id: UUID(), text: text, createdAt: instant,
                         completedAt: completed ? instant : nil, categoryID: category?.id)
    }
}
