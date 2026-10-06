import XCTest
@testable import MenuPocket

final class TaskMovementTests: XCTestCase {
    private let day = "2026-10-06"
    private let workID = UUID()
    private let homeID = UUID()
    private let emptyID = UUID()

    private var categories: [TaskCategory] {
        get throws {
            try [TaskCategory(id: workID, name: "Work", creationOrder: 0),
                 TaskCategory(id: homeID, name: "Home", creationOrder: 1),
                 TaskCategory(id: emptyID, name: "Empty", creationOrder: 2)]
        }
    }

    func testWithinGroupUpAndDownPreserveAllOtherTasks() throws {
        let a = note("A", workID)
        let g = note("General", nil)
        let b = note("B", workID)
        let h = note("Home", homeID)
        let c = note("C", workID)
        let saved = [a, g, b, h, c]
        try assertMove(b, in: saved, to: .category(workID), placement: .before(a.id),
                       expected: [b.id, a.id, g.id, h.id, c.id])
        try assertMove(b, in: saved, to: .category(workID), placement: .after(c.id),
                       expected: [a.id, g.id, h.id, c.id, b.id])
    }

    func testCrossGroupBeforeAndAfterCompletedAnchor() throws {
        let a = note("Completed source", workID, completed: true)
        let g = note("General", nil)
        let b = note("Completed anchor", homeID, completed: true)
        let c = note("Other work", workID)
        let saved = [a, g, b, c]
        try assertMove(a, in: saved, to: .category(homeID), placement: .before(b.id),
                       expected: [g.id, a.id, b.id, c.id])
        try assertMove(a, in: saved, to: .category(homeID), placement: .after(b.id),
                       expected: [g.id, b.id, a.id, c.id])
    }

    func testEndOfGroupAndEmptyCategoryAppend() throws {
        let a = note("A", workID)
        let b = note("B", homeID)
        let g = note("General", nil)
        let c = note("C", workID)
        let saved = [a, b, g, c]
        try assertMove(a, in: saved, to: .category(homeID), placement: .endOfGroup,
                       expected: [b.id, a.id, g.id, c.id])
        try assertMove(a, in: saved, to: .category(emptyID), placement: .endOfGroup,
                       expected: [b.id, g.id, c.id, a.id])
        try assertMove(a, in: saved, to: .category(workID), placement: .endOfGroup,
                       expected: [b.id, g.id, c.id, a.id])
    }

    func testGeneralMovementBothWaysAndEmptyGeneral() throws {
        let a = note("A", workID)
        let g = note("General", nil)
        let b = note("B", workID)
        try assertMove(a, in: [a, g, b], to: .general, placement: .before(g.id),
                       expected: [a.id, g.id, b.id])
        try assertMove(a, in: [a, g, b], to: .general, placement: .endOfGroup,
                       expected: [g.id, a.id, b.id])
        try assertMove(g, in: [a, g, b], to: .category(workID), placement: .after(b.id),
                       expected: [a.id, b.id, g.id])
        try assertMove(a, in: [a, b], to: .general, placement: .endOfGroup,
                       expected: [b.id, a.id])
    }

    func testEquivalentVisiblePositionsAreUnchangedEvenWithInterleavedGroups() throws {
        let a = note("A", workID)
        let g = note("General", nil)
        let b = note("B", workID)
        let saved = [a, g, b]
        for (source, placement) in [(a, TaskMovePlacement.before(b.id)),
                                    (b, .after(a.id)), (b, .endOfGroup), (g, .endOfGroup)] {
            XCTAssertEqual(try plan(source, in: saved, to: TaskGroupID(categoryID: source.categoryID),
                                    placement: placement), .unchanged)
        }
        XCTAssertEqual(try plan(a, in: [a], to: .category(workID), placement: .endOfGroup), .unchanged)
    }

    func testInvalidAnchorsRejectWithoutMutatingInput() throws {
        let a = note("A", workID)
        let b = note("B", homeID)
        let saved = [a, b]
        for anchor in [a.id, b.id, UUID()] {
            for placement in [TaskMovePlacement.before(anchor), .after(anchor)] {
                XCTAssertEqual(try plan(a, in: saved, to: .category(workID), placement: placement),
                               .rejected(.invalidAnchor))
                XCTAssertEqual(saved, [a, b])
            }
        }
        let yesterday = note("Yesterday", workID, dayKey: "2026-10-05")
        XCTAssertEqual(try plan(a, in: saved, to: .category(workID), placement: .before(yesterday.id)),
                       .rejected(.invalidAnchor))
    }

    func testStaleDaySourceTaskAndDestinationReject() throws {
        let a = note("A", workID)
        let catalog = try categories
        func request(dayKey: String = "2026-10-06", id: UUID? = nil,
                     source: TaskGroupID? = nil, destination: TaskGroupID? = nil) -> TaskMoveRequest {
            TaskMoveRequest(taskID: id ?? a.id, expectedDayKey: dayKey,
                            expectedSourceGroup: source ?? .category(workID),
                            destinationGroup: destination ?? .general, placement: .endOfGroup)
        }
        for (request, rejection) in [
            (request(dayKey: "2026-10-05"), TaskMoveRejection.dayChanged),
            (request(id: UUID()), .taskNotFound),
            (request(source: .general), .sourceChanged),
            (request(destination: .category(UUID())), .destinationNotFound)
        ] {
            XCTAssertEqual(TaskMovePlanner.plan(request, dayKey: day, notes: [a], categories: catalog),
                           .rejected(rejection))
        }
        XCTAssertEqual(TaskMovePlanner.plan(request(), dayKey: "2026-10-07", notes: [a], categories: catalog),
                       .rejected(.dayChanged))
        XCTAssertEqual(TaskMovePlanner.plan(request(), dayKey: day, notes: [], categories: catalog),
                       .rejected(.taskNotFound))
    }

    func testMalformedSnapshotsRejectRatherThanRepair() throws {
        let a = note("A", workID)
        let catalog = try categories
        let request = TaskMoveRequest(taskID: a.id, expectedDayKey: day,
                                      expectedSourceGroup: .category(workID),
                                      destinationGroup: .general, placement: .endOfGroup)
        for saved in [[a, a], [a, note("Other day", nil, dayKey: "2026-10-05")],
                      [a, note("Dangling category", UUID())]] {
            XCTAssertEqual(TaskMovePlanner.plan(request, dayKey: day, notes: saved, categories: catalog),
                           .rejected(.invalidSnapshot))
        }
        XCTAssertEqual(TaskMovePlanner.plan(request, dayKey: day, notes: [a], categories: catalog + [catalog[0]]),
                       .rejected(.invalidSnapshot))
    }

    private func note(_ text: String, _ categoryID: UUID?, completed: Bool = false,
                      dayKey: String? = nil) -> Note {
        Note(id: UUID(), text: text, dayKey: dayKey ?? day,
             createdAt: Date(timeIntervalSince1970: 123),
             completedAt: completed ? Date(timeIntervalSince1970: 456) : nil, categoryID: categoryID)
    }

    private func plan(_ source: Note, in saved: [Note], to destination: TaskGroupID,
                      placement: TaskMovePlacement) throws -> TaskMoveOutcome {
        TaskMovePlanner.plan(TaskMoveRequest(taskID: source.id, expectedDayKey: day,
                                             expectedSourceGroup: TaskGroupID(categoryID: source.categoryID),
                                             destinationGroup: destination, placement: placement),
                             dayKey: day, notes: saved, categories: try categories)
    }

    private func assertMove(_ source: Note, in saved: [Note], to destination: TaskGroupID,
                            placement: TaskMovePlacement, expected: [UUID],
                            file: StaticString = #filePath, line: UInt = #line) throws {
        let original = saved
        guard case let .changed(result) = try plan(source, in: saved, to: destination, placement: placement) else {
            return XCTFail("Expected changed snapshot", file: file, line: line)
        }
        XCTAssertEqual(result.map(\.id), expected, file: file, line: line)
        XCTAssertEqual(result.filter { $0.id != source.id }, saved.filter { $0.id != source.id }, file: file, line: line)
        let moved = try XCTUnwrap(result.first { $0.id == source.id }, file: file, line: line)
        let categoryID: UUID?
        switch destination {
        case .general: categoryID = nil
        case let .category(id): categoryID = id
        }
        XCTAssertEqual(moved, Note(id: source.id, text: source.text, dayKey: source.dayKey,
                                   createdAt: source.createdAt, completedAt: source.completedAt,
                                   categoryID: categoryID),
                       file: file, line: line)
        XCTAssertEqual(TaskGroupID(categoryID: moved.categoryID), destination, file: file, line: line)
        XCTAssertEqual(NoteProgress(notes: result, for: day), NoteProgress(notes: saved, for: day), file: file, line: line)
        XCTAssertEqual(saved, original, file: file, line: line)
    }
}
