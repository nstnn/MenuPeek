import XCTest
@testable import MenuPocket

final class TaskGroupingTests: XCTestCase {
    private let day = "2026-09-27"

    func testGroupsFollowCategoryCreationOrderAndKeepSavedTaskOrderWithGeneralLast() throws {
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

        XCTAssertEqual(groups.map(\.id), [.category(school.id), .category(work.id), .general])
        XCTAssertEqual(groups.map(\.name), ["School", "Work", "General"])
        XCTAssertEqual(groups.map(\.notes), [[math, biology], [reply, report], [groceries, desk]])
        XCTAssertEqual(groups.map(\.progress), [NoteProgress(completed: 1, total: 2),
                                                NoteProgress(completed: 1, total: 2),
                                                NoteProgress(completed: 0, total: 2)])
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

        XCTAssertEqual(groups.map(\.id), [.category(work.id), .general])
        XCTAssertEqual(groups.map(\.notes), [[first], [second, reassigned, fourth]])
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

        for id in [TaskGroupID.general, .category(work.id)] {
            XCTAssertEqual(TaskGroupID(storageKey: id.storageKey), id)
        }
        XCTAssertEqual(TaskGroupID(storageKey: work.id.uuidString.lowercased()), .category(work.id))
        XCTAssertNil(UUID(uuidString: TaskGroupID.general.storageKey))
        for invalid in ["", "General", "not-a-uuid"] {
            XCTAssertNil(TaskGroupID(storageKey: invalid))
        }
    }

    private func note(_ text: String, _ category: TaskCategory?, completed: Bool = false) -> Note {
        let instant = Date(timeIntervalSince1970: 1_790_000_000)
        return Note(id: UUID(), text: text, dayKey: day, createdAt: instant,
                    completedAt: completed ? instant : nil, categoryID: category?.id)
    }
}
