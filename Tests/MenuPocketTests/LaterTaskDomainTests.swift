import XCTest
@testable import MenuPocket

final class LaterTaskDomainTests: XCTestCase {
    func testLaterTaskHasNoCalendarAssignment() {
        let task = LaterTask(id: UUID(), text: "Learn SQLite", createdAt: Date(timeIntervalSince1970: 1),
                             completedAt: nil)
        // Adding a day, deadline, or planned date must be a deliberate contract change.
        XCTAssertEqual(Mirror(reflecting: task).children.compactMap(\.label),
                       ["id", "text", "createdAt", "completedAt", "categoryID"])
        XCTAssertNil(task.categoryID)
    }

    func testCompletionToggleRetainsIdentityTextCategoryAndCreation() {
        let category = UUID()
        let open = LaterTask(id: UUID(), text: "Review the portfolio",
                             createdAt: Date(timeIntervalSince1970: 10), completedAt: nil,
                             categoryID: category)
        let done = LaterTask(id: open.id, text: open.text, createdAt: open.createdAt,
                             completedAt: Date(timeIntervalSince1970: 500), categoryID: open.categoryID)
        let reopened = LaterTask(id: done.id, text: done.text, createdAt: done.createdAt,
                                 completedAt: nil, categoryID: done.categoryID)

        XCTAssertFalse(open.isCompleted)
        XCTAssertTrue(done.isCompleted)
        XCTAssertEqual(done.id, open.id)
        XCTAssertEqual(done.text, open.text)
        XCTAssertEqual(done.categoryID, category)
        XCTAssertEqual(done.createdAt, open.createdAt)
        XCTAssertEqual(reopened, open)
    }

    func testActionTargetsWithTheSameIDStayScopedToTheirList() {
        let id = UUID()
        let daily = TaskActionTarget.daily(id: id, dayKey: "2026-10-05")
        let later = TaskActionTarget.later(id: id)

        XCTAssertNotEqual(daily, later)
        XCTAssertEqual(daily.id, later.id)
        XCTAssertEqual(daily.destination, .today)
        XCTAssertEqual(later.destination, .later)
        XCTAssertNotEqual(daily, .daily(id: id, dayKey: "2026-10-06"))
    }

    func testSQLiteTransferFailsExplicitlyUntilImplementedAndLeavesBothListsUnchanged() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaterTaskDomainTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteNoteRepository(databaseURL: directory.appendingPathComponent("notes.sqlite"))
        let today = Note(id: UUID(), text: "Today", dayKey: "2026-10-05",
                         createdAt: Date(timeIntervalSince1970: 1), completedAt: nil)
        try store.add(today)
        let task = LaterTask(id: UUID(), text: "Later", createdAt: Date(timeIntervalSince1970: 2),
                             completedAt: nil)
        try store.addLater(task)

        XCTAssertThrowsError(try store.moveLaterToToday(id: task.id, dayKey: today.dayKey)) {
            XCTAssertEqual($0 as? LaterTaskRepositoryError, .unsupported("moveLaterToToday"))
        }
        XCTAssertEqual(try store.notes(for: today.dayKey), [today])
        XCTAssertEqual(try store.laterTasks(), [task])
    }
}
