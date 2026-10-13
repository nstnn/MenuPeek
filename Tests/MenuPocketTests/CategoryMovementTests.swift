import XCTest
@testable import MenuPocket

final class CategoryMovementTests: XCTestCase {
    private let workID = UUID()
    private let emptyID = UUID()
    private let personalID = UUID()
    private let learningID = UUID()

    private var categories: [TaskCategory] {
        get throws {
            try [TaskCategory(id: workID, name: "Work", creationOrder: 10),
                 TaskCategory(id: emptyID, name: "Unused", creationOrder: 30),
                 TaskCategory(id: personalID, name: "Cafe\u{301}", creationOrder: 80),
                 TaskCategory(id: learningID, name: String(repeating: "Learning ", count: 20), creationOrder: 120)]
        }
    }

    func testBeforeAfterAndFirstLastPlacementsPreserveCategoryFields() throws {
        let saved = try categories
        let cases: [(UUID, CategoryMovePlacement, [UUID])] = [
            (learningID, .before(workID), [learningID, workID, emptyID, personalID]),
            (workID, .after(learningID), [emptyID, personalID, learningID, workID]),
            (personalID, .before(emptyID), [workID, personalID, emptyID, learningID]),
            (emptyID, .after(personalID), [workID, personalID, emptyID, learningID]),
            (learningID, .after(workID), [workID, learningID, emptyID, personalID]),
            (workID, .before(learningID), [emptyID, personalID, workID, learningID])
        ]
        for (source, placement, expected) in cases {
            try assertMove(source, in: saved, placement: placement, expected: expected)
        }
    }

    func testVisibleSubsetAnchorsKeepHiddenCategoriesInTheFullCatalog() throws {
        let saved = Array(try categories.prefix(3)) // Work, Unused, Personal
        try assertMove(personalID, in: saved, placement: .before(workID),
                       expected: [personalID, workID, emptyID])
        try assertMove(workID, in: saved, placement: .after(personalID),
                       expected: [emptyID, personalID, workID])
    }

    func testEquivalentPositionsDoNotCompactSparseOrExtremeLegacyRanks() throws {
        let original = try categories
        let saved = zip(original, [Int64.min, -10, 700, Int64.max]).map {
            TaskCategory($0.0, creationOrder: $0.1)
        }
        for (source, placement) in [(workID, CategoryMovePlacement.before(emptyID)),
                                    (emptyID, .after(workID)),
                                    (personalID, .before(learningID)),
                                    (learningID, .after(personalID))] {
            XCTAssertEqual(plan(source, in: saved, placement: placement), .unchanged)
            XCTAssertEqual(saved.map(\.creationOrder), [Int64.min, -10, 700, Int64.max])
        }
    }

    func testSavedRanksDefineOrderRegardlessOfInputArrayOrder() throws {
        let original = try categories
        let ordered = zip(original, [Int64.min, -1, 42, Int64.max]).map {
            TaskCategory($0.0, creationOrder: $0.1)
        }
        let shuffled = [ordered[2], ordered[0], ordered[3], ordered[1]]
        try assertMove(learningID, in: shuffled, expectedOrder: ordered.map(\.id),
                       placement: .before(workID), expected: [learningID, workID, emptyID, personalID])
        XCTAssertEqual(plan(workID, in: shuffled, expectedOrder: ordered.map(\.id),
                            placement: .before(emptyID)), .unchanged)
        XCTAssertEqual(plan(workID, in: shuffled, placement: .after(learningID)), .rejected(.catalogChanged))
    }

    func testStaleIncompleteAndExtraExpectedCatalogsReject() throws {
        let saved = try categories
        let ids = saved.map(\.id)
        for expected in [[], Array(ids.dropLast()), ids + [UUID()],
                         [personalID, workID, emptyID, learningID]] {
            XCTAssertEqual(plan(workID, in: saved, expectedOrder: expected, placement: .after(learningID)),
                           .rejected(.catalogChanged))
        }
    }

    func testDuplicateExpectedIdentitiesRejectBeforeCatalogAgreement() throws {
        let saved = try categories
        XCTAssertEqual(plan(workID, in: saved, expectedOrder: [workID, workID, personalID, learningID],
                            placement: .after(learningID)), .rejected(.invalidExpectedOrder))
    }

    func testMissingSourceAndMissingOrSelfAnchorsRejectWithoutChangingInput() throws {
        let saved = try categories
        let original = saved
        XCTAssertEqual(plan(UUID(), in: saved, placement: .before(workID)), .rejected(.categoryNotFound))
        for anchor in [UUID(), workID] {
            for placement in [CategoryMovePlacement.before(anchor), .after(anchor)] {
                XCTAssertEqual(plan(workID, in: saved, placement: placement), .rejected(.invalidAnchor))
            }
        }
        XCTAssertEqual(saved, original)
    }

    func testDuplicateCatalogIdentitiesOrRanksRejectRatherThanRepair() throws {
        let saved = try categories
        let duplicateID = try TaskCategory(id: workID, name: "Other", creationOrder: 200)
        let duplicateRank = TaskCategory(saved[1], creationOrder: saved[0].creationOrder)
        for malformed in [saved + [duplicateID], [saved[0], duplicateRank, saved[2], saved[3]]] {
            let original = malformed
            XCTAssertEqual(plan(workID, in: malformed, placement: .after(learningID)),
                           .rejected(.invalidSnapshot))
            XCTAssertEqual(malformed, original)
        }
    }

    func testEmptyAndSingleCategoryCatalogsCannotSupplyAValidDistinctAnchor() throws {
        XCTAssertEqual(plan(workID, in: [], placement: .before(emptyID)), .rejected(.categoryNotFound))
        let single = [try categories[0]]
        for anchor in [workID, emptyID] {
            for placement in [CategoryMovePlacement.before(anchor), .after(anchor)] {
                XCTAssertEqual(plan(workID, in: single, placement: placement), .rejected(.invalidAnchor))
            }
        }
        XCTAssertEqual(single[0].creationOrder, 10)
    }

    private func plan(_ source: UUID, in saved: [TaskCategory], expectedOrder: [UUID]? = nil,
                      placement: CategoryMovePlacement) -> CategoryMoveOutcome {
        CategoryMovePlanner.plan(CategoryMoveRequest(categoryID: source,
                                                     expectedOrderIDs: expectedOrder ?? saved.map(\.id),
                                                     placement: placement), categories: saved)
    }

    private func assertMove(_ source: UUID, in saved: [TaskCategory], expectedOrder: [UUID]? = nil,
                            placement: CategoryMovePlacement, expected: [UUID],
                            file: StaticString = #filePath, line: UInt = #line) throws {
        let original = saved
        guard case let .changed(result) = plan(source, in: saved, expectedOrder: expectedOrder,
                                              placement: placement) else {
            return XCTFail("Expected changed catalog", file: file, line: line)
        }
        XCTAssertEqual(result.map(\.id), expected, file: file, line: line)
        XCTAssertEqual(result.map(\.creationOrder), Array(0..<Int64(saved.count)), file: file, line: line)
        let ordered = saved.sorted { $0.creationOrder < $1.creationOrder }
        XCTAssertEqual(result.filter { $0.id != source }.map(\.id),
                       ordered.filter { $0.id != source }.map(\.id), file: file, line: line)
        for category in result {
            let before = try XCTUnwrap(saved.first { $0.id == category.id }, file: file, line: line)
            XCTAssertEqual(category.name, before.name, file: file, line: line)
            XCTAssertEqual(category.nameKey, before.nameKey, file: file, line: line)
        }
        XCTAssertEqual(saved, original, file: file, line: line)
    }
}
