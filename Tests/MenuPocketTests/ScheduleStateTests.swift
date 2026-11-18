import Foundation
import XCTest
@testable import MenuPocket

@MainActor
final class ScheduleStateTests: XCTestCase {
    private enum Failure: Error { case storage }

    /// In-memory store with the repository's ordering and injectable failures.
    private final class FakeScheduleRepository: ScheduleRepository {
        var saved: [UUID: ScheduleBlock] = [:]
        var reads: [HistoryDayRange] = []
        var writes = 0
        var failRead = false
        var failWrite = false
        /// Returned instead of the real read, to simulate a malformed result.
        var readOverride: [ScheduleBlock]?

        func scheduleBlocks(in range: HistoryDayRange) throws -> [ScheduleBlock] {
            reads.append(range)
            if failRead { throw Failure.storage }
            if let readOverride { return readOverride }
            return saved.values.filter { range.contains($0.day) }.sorted(by: ScheduleBlock.isOrderedBefore)
        }

        func addScheduleBlock(_ block: ScheduleBlock) throws {
            writes += 1
            if failWrite { throw Failure.storage }
            guard saved[block.id] == nil else { throw ScheduleRepositoryError.duplicateID(block.id) }
            saved[block.id] = block
        }

        func updateScheduleBlock(id: UUID, to content: ScheduleBlockContent) throws -> ScheduleBlock {
            writes += 1
            if failWrite { throw Failure.storage }
            guard let block = saved[id] else { throw ScheduleRepositoryError.notFound(id) }
            let updated = block.replacingContent(content)
            saved[id] = updated
            return updated
        }

        func deleteScheduleBlock(id: UUID) throws {
            writes += 1
            if failWrite { throw Failure.storage }
            guard saved.removeValue(forKey: id) != nil else { throw ScheduleRepositoryError.notFound(id) }
        }
    }

    private final class Clock { var now = "2026-11-18T12:00:00Z" }

    private let clock = Clock()
    private let repository = FakeScheduleRepository()

    private var noteDay: NoteDay {
        let clock = clock
        return NoteDay(now: { ISO8601DateFormatter().date(from: clock.now)! },
                       timeZone: { TimeZone(secondsFromGMT: 0)! })
    }

    private func makeState() throws -> ScheduleState {
        let repository = repository
        return try ScheduleState(noteDay: noteDay, repository: { repository })
    }

    private func day(_ key: String) throws -> GregorianDay { try GregorianDay(key: key) }

    private func range(_ start: String, _ end: String) throws -> HistoryDayRange {
        try HistoryDayRange(start: day(start), end: day(end))
    }

    private func content(_ title: String, _ key: String, _ start: Int, _ end: Int) throws -> ScheduleBlockContent {
        try ScheduleBlockContent(title: title, day: day(key), startMinute: start, endMinute: end)
    }

    @discardableResult
    private func seed(_ title: String, _ key: String, _ start: Int, _ end: Int) throws -> ScheduleBlock {
        let block = try ScheduleBlock(id: UUID(), content: content(title, key, start, end),
                                      createdAt: Date(timeIntervalSince1970: 1_790_000_000))
        repository.saved[block.id] = block
        return block
    }

    // MARK: - Loading and visibility

    func testStartsOnThisWeekAndReadsOnlyWhileVisible() throws {
        let state = try makeState()
        XCTAssertEqual(state.mode, .week)
        XCTAssertEqual(state.today.key, "2026-11-18")
        XCTAssertEqual(state.period.range, try range("2026-11-16", "2026-11-23"))
        XCTAssertEqual(state.content, .notLoaded)
        XCTAssertTrue(repository.reads.isEmpty)

        state.setVisible(false)
        XCTAssertTrue(state.showNext())
        XCTAssertTrue(repository.reads.isEmpty, "a hidden Calendar must not read")

        state.setVisible(true)
        XCTAssertEqual(repository.reads, [try range("2026-11-23", "2026-11-30")])
        XCTAssertEqual(state.blocks, [])

        state.setVisible(false)
        state.setVisible(true)
        XCTAssertEqual(repository.reads.count, 1, "a clean period is not read again")
    }

    func testLoadedBlocksFollowRepositoryOrderAndGroupByDay() throws {
        let late = try seed("Late", "2026-11-18", 600, 660)
        let early = try seed("Early", "2026-11-18", 480, 540)
        let monday = try seed("Monday", "2026-11-16", 900, 960)
        try seed("Next week", "2026-11-23", 480, 540)
        let state = try makeState()
        state.setVisible(true)
        XCTAssertEqual(state.blocks, [monday, early, late])
        XCTAssertEqual(state.blocks(on: try day("2026-11-18")), [early, late])
        XCTAssertEqual(state.blocks(on: try day("2026-11-17")), [])
    }

    func testFailedReadPublishesUnavailableNotEmptyAndRetryRecovers() throws {
        let block = try seed("Standup", "2026-11-18", 540, 555)
        repository.failRead = true
        let state = try makeState()
        state.setVisible(true)
        XCTAssertEqual(state.content, .unavailable)
        XCTAssertNil(state.blocks)
        XCTAssertTrue(state.isUnavailable)
        XCTAssertEqual(state.loadMessage, "Could not load this week. Try again.")

        state.retry()
        XCTAssertEqual(state.content, .unavailable, "Retry while storage still fails stays unavailable")

        repository.failRead = false
        state.retry()
        XCTAssertEqual(state.content, .loaded([block]))
        XCTAssertNil(state.loadMessage)
        XCTAssertEqual(repository.reads.count, 3)
    }

    func testUnavailableMessageNamesTheVisiblePeriod() throws {
        repository.failRead = true
        let state = try makeState()
        state.setVisible(true)
        state.setMode(.month)
        XCTAssertEqual(state.loadMessage, "Could not load this month. Try again.")
        state.setMode(.day)
        XCTAssertEqual(state.loadMessage, "Could not load this day. Try again.")
    }

    func testReadOutsideThePeriodIsUnavailable() throws {
        let outside = try ScheduleBlock(id: UUID(), content: content("Elsewhere", "2026-12-01", 0, 60),
                                        createdAt: Date())
        repository.readOverride = [outside]
        let state = try makeState()
        state.setVisible(true)
        XCTAssertEqual(state.content, .unavailable)
    }

    func testOpeningTheStoreFailsAsUnavailable() throws {
        let state = try ScheduleState(noteDay: noteDay, repository: { throw Failure.storage })
        state.setVisible(true)
        XCTAssertEqual(state.content, .unavailable)
        let added = try state.add(content("Plan", "2026-11-18", 0, 60))
        XCTAssertEqual(added.failure, .add)
    }

    // MARK: - Navigation

    func testPreviousNextTodayAndModeSwitchesLoadExactlyTheNewPeriod() throws {
        let state = try makeState()
        state.setVisible(true)
        XCTAssertTrue(state.showPrevious())
        XCTAssertTrue(state.showNext())
        XCTAssertTrue(state.showNext())
        XCTAssertTrue(state.showToday())
        XCTAssertTrue(state.setMode(.month))
        XCTAssertTrue(state.showNext())
        XCTAssertTrue(state.setMode(.day))
        XCTAssertTrue(state.showPrevious())
        XCTAssertTrue(state.setMode(.week))
        XCTAssertEqual(repository.reads, [
            try range("2026-11-16", "2026-11-23"),
            try range("2026-11-09", "2026-11-16"),
            try range("2026-11-16", "2026-11-23"),
            try range("2026-11-23", "2026-11-30"),
            try range("2026-11-16", "2026-11-23"),
            try range("2026-11-01", "2026-12-01"),
            try range("2026-12-01", "2027-01-01"),
            // Today is outside December, so Day keeps the anchor (December 18).
            try range("2026-12-18", "2026-12-19"),
            try range("2026-12-17", "2026-12-18"),
            try range("2026-12-14", "2026-12-21")
        ])
        XCTAssertEqual(state.header.text, "December 2026 · Week 51")
    }

    func testSwitchingToTheSameModeOrPeriodDoesNotReload() throws {
        let state = try makeState()
        state.setVisible(true)
        XCTAssertTrue(state.setMode(.week))
        XCTAssertTrue(state.showToday())
        XCTAssertEqual(repository.reads.count, 1)
    }

    func testShowDayOpensDayViewAndKeepsTheSelectionAcrossModes() throws {
        let state = try makeState()
        state.setVisible(true)
        state.setMode(.month)
        let chosen = try day("2026-11-03")
        XCTAssertTrue(state.showDay(chosen))
        XCTAssertEqual(state.mode, .day)
        XCTAssertEqual(state.selectedDay, chosen)
        XCTAssertEqual(repository.reads.last, try range("2026-11-03", "2026-11-04"))
        state.setMode(.week)
        XCTAssertEqual(repository.reads.last, try range("2026-11-02", "2026-11-09"))
    }

    func testANewPeriodNeverShowsTheOldPeriodsBlocks() throws {
        try seed("This week", "2026-11-18", 0, 60)
        let state = try makeState()
        state.setVisible(true)
        XCTAssertEqual(state.blocks?.count, 1)

        state.setVisible(false)
        state.showNext()
        XCTAssertEqual(state.content, .notLoaded, "hidden period change drops the old blocks")

        repository.failRead = true
        state.setVisible(true)
        XCTAssertEqual(state.content, .unavailable)
        repository.failRead = false
        state.showPrevious()
        XCTAssertEqual(state.blocks?.map(\.title), ["This week"])
    }

    func testNavigationAtTheLastStorableMonthChangesNothing() throws {
        clock.now = "9999-12-25T12:00:00Z"
        let state = try ScheduleState(noteDay: noteDay, repository: { [repository] in repository })
        state.setVisible(true)
        let before = state.period
        XCTAssertFalse(state.setMode(.month))
        XCTAssertFalse(state.showNext())
        XCTAssertEqual(state.period, before)
    }

    // MARK: - Today marker

    func testCrossingMidnightMovesTheTodayMarkerWithoutTouchingBlocks() throws {
        clock.now = "2026-11-18T23:59:59Z"
        let block = try seed("Late", "2026-11-18", 1380, 1440)
        let state = try makeState()
        state.setVisible(true)
        let reads = repository.reads.count
        XCTAssertTrue(state.isToday(try day("2026-11-18")))

        clock.now = "2026-11-19T00:00:01Z"
        state.refreshToday()
        XCTAssertEqual(state.today.key, "2026-11-19")
        XCTAssertTrue(state.isToday(try day("2026-11-19")))
        XCTAssertFalse(state.isToday(try day("2026-11-18")))
        XCTAssertEqual(state.content, .loaded([block]))
        XCTAssertEqual(state.period.range, try range("2026-11-16", "2026-11-23"))
        XCTAssertEqual(repository.reads.count, reads)
        XCTAssertEqual(repository.writes, 0)
    }

    func testTodayUsesTheCurrentDayAfterMidnight() throws {
        let state = try makeState()
        state.setVisible(true)
        state.setMode(.day)
        clock.now = "2026-11-19T08:00:00Z"
        state.showToday()
        XCTAssertEqual(state.period.anchor.key, "2026-11-19")
        XCTAssertEqual(state.today.key, "2026-11-19")
    }

    // MARK: - Commands

    func testSuccessfulCommandsPublishOnlySavedBlocksInRepositoryOrder() throws {
        let ids = [UUID(), UUID()]
        var nextID = ids.makeIterator()
        let repository = repository
        let state = try ScheduleState(noteDay: noteDay, makeID: { nextID.next()! },
                                      repository: { repository })
        state.setVisible(true)

        let second = try state.add(content("Second", "2026-11-18", 600, 660)).get()
        let first = try state.add(content("First", "2026-11-18", 540, 600)).get()
        XCTAssertEqual(second.id, ids[0])
        XCTAssertEqual(first.createdAt, ISO8601DateFormatter().date(from: clock.now))
        XCTAssertEqual(state.blocks, [first, second])
        XCTAssertEqual(state.blocks, repository.saved.values.sorted(by: ScheduleBlock.isOrderedBefore))

        let moved = try state.update(id: second.id, to: content("Moved", "2026-11-17", 600, 660)).get()
        XCTAssertEqual(moved.id, second.id)
        XCTAssertEqual(moved.createdAt, second.createdAt)
        XCTAssertEqual(state.blocks, [moved, first])

        let away = try state.update(id: first.id, to: content("Next week", "2026-11-24", 0, 15)).get()
        XCTAssertEqual(state.blocks, [moved], "a block moved out of the period leaves the view")
        XCTAssertEqual(repository.saved[first.id], away)

        XCTAssertNoThrow(try state.delete(id: moved.id).get())
        XCTAssertEqual(state.blocks, [])
        XCTAssertNil(repository.saved[moved.id])
    }

    func testFailedWritesLeavePublishedBlocksUnchangedAndReturnTheFailure() throws {
        let block = try seed("Keep", "2026-11-18", 540, 600)
        let state = try makeState()
        state.setVisible(true)
        let before = state.content
        let reads = repository.reads.count
        repository.failWrite = true

        XCTAssertEqual(try state.add(content("New", "2026-11-18", 0, 60)).failure, .add)
        XCTAssertEqual(state.content, before)
        XCTAssertEqual(try state.update(id: block.id, to: content("Edit", "2026-11-18", 0, 60)).failure, .update)
        XCTAssertEqual(state.content, before)
        XCTAssertEqual(state.delete(id: block.id).failure, .delete)
        XCTAssertEqual(state.content, before)

        XCTAssertEqual(repository.writes, 3)
        XCTAssertEqual(repository.reads.count, reads, "a failed write does not reload")
        XCTAssertEqual(repository.saved, [block.id: block])
    }

    func testMissingBlockIsReportedAndPublishedBlocksStay() throws {
        let block = try seed("Keep", "2026-11-18", 540, 600)
        let state = try makeState()
        state.setVisible(true)
        let missing = UUID()
        XCTAssertEqual(try state.update(id: missing, to: content("X", "2026-11-18", 0, 60)).failure, .missing)
        XCTAssertEqual(state.delete(id: missing).failure, .missing)
        XCTAssertEqual(state.content, .loaded([block]))
    }

    func testDuplicateIDOnAddIsAnAddFailure() throws {
        let block = try seed("Taken", "2026-11-18", 540, 600)
        let state = try ScheduleState(noteDay: noteDay, makeID: { block.id }, repository: { [repository] in repository })
        state.setVisible(true)
        XCTAssertEqual(try state.add(content("Clash", "2026-11-18", 0, 60)).failure, .add)
        XCTAssertEqual(state.content, .loaded([block]))
    }

    func testWriteWhileHiddenDefersTheReloadUntilVisible() throws {
        let state = try makeState()
        state.setVisible(true)
        state.setVisible(false)
        let added = try state.add(content("Later read", "2026-11-18", 0, 60)).get()
        XCTAssertEqual(repository.reads.count, 1)
        state.setVisible(true)
        XCTAssertEqual(repository.reads.count, 2)
        XCTAssertEqual(state.blocks, [added])
    }

    func testFailureMessages() {
        XCTAssertEqual(ScheduleCommandFailure.add.message, "Could not save block. Try again.")
        XCTAssertEqual(ScheduleCommandFailure.update.message, "Could not save block changes. Try again.")
        XCTAssertEqual(ScheduleCommandFailure.delete.message, "Could not delete block. Try again.")
        XCTAssertEqual(ScheduleCommandFailure.missing.message, "This block no longer exists.")
    }

    // MARK: - Factory

    func testFactorySharesTheTaskStoreAndClock() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "ScheduleStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try SQLiteNoteRepository(databaseURL: directory.appendingPathComponent("notes.sqlite"))
        let daily = DailyNotesState(repositoryFactory: { store }, day: noteDay,
                                    notificationCenter: NotificationCenter(),
                                    workspaceNotificationCenter: NotificationCenter(),
                                    categoryPreferences: TaskCategoryPreferences(userDefaults: defaults))
        let state = try daily.makeScheduleState()
        XCTAssertEqual(state.today.key, "2026-11-18")
        state.setVisible(true)
        XCTAssertEqual(state.blocks, [])

        let saved = try state.add(content("Shared", "2026-11-18", 540, 600)).get()
        XCTAssertEqual(state.blocks, [saved])
        XCTAssertEqual(try store.scheduleBlocks(in: state.period.range), [saved])

        daily.stopForTermination()
        state.retry()
        XCTAssertEqual(state.content, .unavailable, "a terminated store reads as unavailable")
    }

}

private extension Result {
    var failure: Failure? {
        if case let .failure(failure) = self { failure } else { nil }
    }
}
