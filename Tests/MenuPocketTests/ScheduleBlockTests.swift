import XCTest
@testable import MenuPocket

final class ScheduleBlockTests: XCTestCase {
    private let day = try! GregorianDay(key: "2026-11-16")
    private let created = Date(timeIntervalSince1970: 1_000)

    private func content(_ title: String = "Deep work", start: Int, end: Int) throws
        -> ScheduleBlockContent {
        try ScheduleBlockContent(title: title, day: day, startMinute: start, endMinute: end)
    }

    private func assertRejected(start: Int, end: Int, as expected: ScheduleBlockError,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try content(start: start, end: end), file: file, line: line) {
            XCTAssertEqual($0 as? ScheduleBlockError, expected, file: file, line: line)
        }
    }

    // MARK: Times

    func testBoundaryBlocksAreAccepted() throws {
        let first = try content(start: 0, end: 15)
        XCTAssertEqual(first.durationMinutes, 15)
        let last = try content(start: 1425, end: 1440)
        XCTAssertEqual(last.startMinute, 1425)
        XCTAssertEqual(last.endMinute, 1440)
        let wholeDay = try content(start: 0, end: 1440)
        XCTAssertEqual(wholeDay.durationMinutes, 1440)
        XCTAssertEqual(try content(start: 540, end: 615).durationMinutes, 75)
    }

    func testZeroLengthAndReversedTimesAreRejected() {
        assertRejected(start: 60, end: 60, as: .endNotAfterStart(start: 60, end: 60))
        assertRejected(start: 120, end: 60, as: .endNotAfterStart(start: 120, end: 60))
        assertRejected(start: 1425, end: 1425, as: .endNotAfterStart(start: 1425, end: 1425))
    }

    func testOffGridTimesAreRejected() {
        assertRejected(start: 7, end: 60, as: .offGrid(7))
        assertRejected(start: 0, end: 59, as: .offGrid(59))
        assertRejected(start: 14, end: 15, as: .offGrid(14))
    }

    func testNegativeAndPastMidnightTimesAreRejected() {
        assertRejected(start: -15, end: 15, as: .startOutOfRange(-15))
        assertRejected(start: 1440, end: 1455, as: .startOutOfRange(1440))
        assertRejected(start: 1425, end: 1455, as: .endOutOfRange(1455))
        assertRejected(start: 0, end: 0, as: .endOutOfRange(0))
        assertRejected(start: 0, end: -15, as: .endOutOfRange(-15))
    }

    // MARK: Title

    func testTitleIsTrimmedAndBlankTitlesAreRejected() throws {
        XCTAssertEqual(try content("  Standup \n", start: 0, end: 15).title, "Standup")
        for blank in ["", "   ", "\n\t "] {
            XCTAssertThrowsError(try content(blank, start: 0, end: 15)) {
                XCTAssertEqual($0 as? ScheduleBlockError, .blankTitle)
            }
        }
    }

    func testTitleMustBeOneLine() {
        for multiline in ["Plan\nReview", "Plan\r\nReview", "Plan\u{2028}Review"] {
            XCTAssertThrowsError(try content(multiline, start: 0, end: 15)) {
                XCTAssertEqual($0 as? ScheduleBlockError, .multilineTitle)
            }
        }
    }

    func testTitleIsCheckedBeforeTimes() {
        XCTAssertThrowsError(try content(" ", start: 60, end: 0)) {
            XCTAssertEqual($0 as? ScheduleBlockError, .blankTitle)
        }
    }

    // MARK: Block

    func testBlockExposesValidatedContent() throws {
        let id = UUID()
        let block = try ScheduleBlock(id: id, title: " Lunch ", day: day,
                                      startMinute: 720, endMinute: 780, createdAt: created)
        XCTAssertEqual(block.id, id)
        XCTAssertEqual(block.title, "Lunch")
        XCTAssertEqual(block.dayKey, "2026-11-16")
        XCTAssertEqual(block.startMinute, 720)
        XCTAssertEqual(block.endMinute, 780)
        XCTAssertEqual(block.durationMinutes, 60)
        XCTAssertEqual(block.createdAt, created)
    }

    func testBlockInitialiserRejectsInvalidContent() {
        XCTAssertThrowsError(try ScheduleBlock(id: UUID(), title: "Gym", day: day,
                                               startMinute: 600, endMinute: 600,
                                               createdAt: created)) {
            XCTAssertEqual($0 as? ScheduleBlockError, .endNotAfterStart(start: 600, end: 600))
        }
    }

    func testReplacingContentKeepsIdentityAndCreation() throws {
        let block = try ScheduleBlock(id: UUID(), title: "Gym", day: day,
                                      startMinute: 600, endMinute: 660, createdAt: created)
        let nextDay = try GregorianDay(key: "2026-11-17")
        let moved = block.replacingContent(
            try ScheduleBlockContent(title: "Run", day: nextDay, startMinute: 420, endMinute: 465))
        XCTAssertEqual(moved.id, block.id)
        XCTAssertEqual(moved.createdAt, block.createdAt)
        XCTAssertEqual(moved.title, "Run")
        XCTAssertEqual(moved.day, nextDay)
        XCTAssertEqual(moved.startMinute, 420)
        XCTAssertEqual(moved.endMinute, 465)
    }

    func testBlockHasNoTaskCategoryOrRepetitionFields() throws {
        let block = try ScheduleBlock(id: UUID(), title: "Gym", day: day,
                                      startMinute: 600, endMinute: 660, createdAt: created)
        // Adding a link, colour or repetition must be a deliberate contract change.
        XCTAssertEqual(Mirror(reflecting: block).children.compactMap(\.label),
                       ["id", "content", "createdAt"])
        XCTAssertEqual(Mirror(reflecting: block.content).children.compactMap(\.label),
                       ["title", "day", "startMinute", "endMinute"])
    }

    func testDisplayOrderIsDayStartEndCreationThenID() throws {
        func make(_ dayKey: String, _ start: Int, _ end: Int, _ seconds: TimeInterval,
                  _ id: String) throws -> ScheduleBlock {
            try ScheduleBlock(id: UUID(uuidString: id)!, title: "B",
                              day: GregorianDay(key: dayKey), startMinute: start,
                              endMinute: end, createdAt: Date(timeIntervalSince1970: seconds))
        }
        let a = try make("2026-11-16", 60, 120, 5, "00000000-0000-0000-0000-00000000000A")
        let b = try make("2026-11-16", 60, 120, 5, "00000000-0000-0000-0000-00000000000B")
        let c = try make("2026-11-16", 60, 120, 9, "00000000-0000-0000-0000-000000000001")
        let d = try make("2026-11-16", 60, 180, 1, "00000000-0000-0000-0000-000000000002")
        let e = try make("2026-11-16", 90, 105, 1, "00000000-0000-0000-0000-000000000003")
        let f = try make("2026-11-17", 0, 15, 0, "00000000-0000-0000-0000-000000000004")
        let expected = [a, b, c, d, e, f]
        XCTAssertEqual(expected.reversed().sorted(by: ScheduleBlock.isOrderedBefore), expected)
        XCTAssertEqual([d, f, b, e, a, c].sorted(by: ScheduleBlock.isOrderedBefore), expected)
    }

    // MARK: Formatting and contract

    func testClockTextUsesTwentyFourHourFormat() {
        XCTAssertEqual(ScheduleBlockContent.clockText(minute: 0), "00:00")
        XCTAssertEqual(ScheduleBlockContent.clockText(minute: 15), "00:15")
        XCTAssertEqual(ScheduleBlockContent.clockText(minute: 765), "12:45")
        XCTAssertEqual(ScheduleBlockContent.clockText(minute: 1425), "23:45")
        XCTAssertEqual(ScheduleBlockContent.clockText(minute: 1440), "24:00")
    }

    func testHistoryDayRangeServesAWeek() throws {
        let range = try HistoryDayRange(start: GregorianDay(key: "2026-11-16"),
                                        end: GregorianDay(key: "2026-11-23"))
        XCTAssertTrue(range.contains(try GregorianDay(key: "2026-11-16")))
        XCTAssertTrue(range.contains(try GregorianDay(key: "2026-11-22")))
        XCTAssertFalse(range.contains(try GregorianDay(key: "2026-11-23")))
    }

    func testRepositoryContractCompilesAgainstAFake() throws {
        let repository: ScheduleRepository = FakeScheduleRepository()
        let block = try ScheduleBlock(id: UUID(), title: "Gym", day: day,
                                      startMinute: 600, endMinute: 660, createdAt: created)
        try repository.addScheduleBlock(block)
        XCTAssertThrowsError(try repository.addScheduleBlock(block)) {
            XCTAssertEqual($0 as? ScheduleRepositoryError, .duplicateID(block.id))
        }
        let missing = UUID()
        XCTAssertThrowsError(try repository.deleteScheduleBlock(id: missing)) {
            XCTAssertEqual($0 as? ScheduleRepositoryError, .notFound(missing))
        }
        let saved = try repository.updateScheduleBlock(
            id: block.id, to: ScheduleBlockContent(title: "Swim", day: day,
                                                   startMinute: 615, endMinute: 690))
        XCTAssertEqual(saved, block.replacingContent(saved.content))
        let week = try HistoryDayRange(start: day, end: GregorianDay(key: "2026-11-23"))
        XCTAssertEqual(try repository.scheduleBlocks(in: week), [saved])
        try repository.deleteScheduleBlock(id: block.id)
        XCTAssertEqual(try repository.scheduleBlocks(in: week), [])
    }
}

/// Minimal in-memory implementation that pins the protocol shape and errors.
private final class FakeScheduleRepository: ScheduleRepository {
    private var blocks: [UUID: ScheduleBlock] = [:]

    func scheduleBlocks(in range: HistoryDayRange) throws -> [ScheduleBlock] {
        blocks.values.filter { range.contains($0.day) }.sorted(by: ScheduleBlock.isOrderedBefore)
    }

    func addScheduleBlock(_ block: ScheduleBlock) throws {
        guard blocks[block.id] == nil else { throw ScheduleRepositoryError.duplicateID(block.id) }
        blocks[block.id] = block
    }

    func updateScheduleBlock(id: UUID, to content: ScheduleBlockContent) throws -> ScheduleBlock {
        guard let block = blocks[id] else { throw ScheduleRepositoryError.notFound(id) }
        let saved = block.replacingContent(content)
        blocks[id] = saved
        return saved
    }

    func deleteScheduleBlock(id: UUID) throws {
        guard blocks.removeValue(forKey: id) != nil else {
            throw ScheduleRepositoryError.notFound(id)
        }
    }
}
