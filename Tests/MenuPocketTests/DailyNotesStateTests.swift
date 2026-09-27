import Foundation
import Observation
import XCTest
@testable import MenuPocket

@MainActor
final class DailyNotesStateTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Toronto")!

    func testRefreshAndReopenPublishSavedDailySnapshot() {
        let today = note("Today", day: "2026-09-27", createdAt: 2)
        let finished = note("Finished", day: "2026-09-27", createdAt: 3,
                            completedAt: Date(timeIntervalSince1970: 4))
        let yesterday = note("Yesterday", day: "2026-09-26", createdAt: 1)
        let store = FakeNoteRepository(notes: [today, finished, yesterday])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })

        state.panelDidOpen()
        XCTAssertEqual(state.notes, [today, finished])
        XCTAssertEqual(state.progress, NoteProgress(completed: 1, total: 2))
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        XCTAssertNil(state.issue)

        let newest = note("New", day: "2026-09-27", createdAt: 5)
        store.saved.append(newest)
        state.panelDidOpen()
        XCTAssertEqual(state.notes, [newest, today, finished])
        XCTAssertEqual(state.progress, NoteProgress(completed: 1, total: 3))
    }

    func testDayChangeMovesOldNotesIntoYesterdayCountWithoutCarryover() {
        let previous = note("Unfinished", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [previous])
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = makeState(store: store, now: { current })

        state.panelDidOpen()
        XCTAssertEqual(state.notes, [previous])
        state.draft = "Keep this draft"
        state.beginEditing(id: previous.id)
        current = instant("2026-09-28T00:01:00-04:00")
        state.refreshIfDayChanged()
        XCTAssertEqual(state.todayKey, "2026-09-28")
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertEqual(state.progress, NoteProgress(completed: 0, total: 0))
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        XCTAssertEqual(state.draft, "Keep this draft")
        XCTAssertNil(state.editingNoteID)
        XCTAssertEqual(state.editDraft, "")
    }

    func testCalendarNotificationRefreshesObservableDay() async {
        let store = FakeNoteRepository()
        let center = NotificationCenter()
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = DailyNotesState(repositoryFactory: { store }, day: makeDay(now: { current }),
                                    notificationCenter: center)
        state.panelDidOpen()
        let changed = expectation(description: "Observable day changed")
        withObservationTracking {
            _ = state.todayKey
        } onChange: {
            changed.fulfill()
        }

        current = instant("2026-09-28T00:01:00-04:00")
        center.post(name: .NSCalendarDayChanged, object: nil)
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(state.todayKey, "2026-09-28")
    }

    func testReadFailureDoesNotPublishPartialSnapshotOrOldDayAsToday() {
        let old = note("Old", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [old])
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = makeState(store: store, now: { current })
        state.panelDidOpen()

        store.failCount = true
        state.refresh()
        XCTAssertEqual(state.notes, [old])
        XCTAssertEqual(state.yesterdayIncompleteCount, 0)
        XCTAssertEqual(state.issue, .load)

        current = instant("2026-09-28T00:01:00-04:00")
        state.refreshIfDayChanged()
        XCTAssertEqual(state.todayKey, "2026-09-28")
        XCTAssertFalse(state.hasLoadedToday)
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertEqual(state.yesterdayIncompleteCount, 0)
        XCTAssertEqual(state.issue, .load)

        store.failCount = false
        state.panelDidOpen()
        XCTAssertTrue(state.hasLoadedToday)
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        XCTAssertNil(state.issue)
    }

    func testOpenFailureCanBeRetried() {
        let store = FakeNoteRepository()
        var shouldFail = true
        let state = DailyNotesState(repositoryFactory: {
            if shouldFail { throw FakeFailure.failed }
            return store
        }, day: makeDay(now: { self.instant("2026-09-27T12:00:00-04:00") }),
        notificationCenter: NotificationCenter())

        state.panelDidOpen()
        XCTAssertEqual(state.issue, .load)
        XCTAssertFalse(state.hasLoadedToday)
        shouldFail = false
        state.panelDidOpen()
        XCTAssertTrue(state.hasLoadedToday)
        XCTAssertNil(state.issue)
    }

    func testFailedAddKeepsDraftAndSuccessfulRetryPublishesOnlySavedNote() {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.panelDidOpen()
        state.draft = "  Book dentist  "
        store.failWrite = .add

        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(state.draft, "  Book dentist  ")
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertEqual(state.issue, .add)

        store.failWrite = nil
        XCTAssertTrue(state.addDraft())
        XCTAssertEqual(state.notes.map(\.text), ["Book dentist"])
        XCTAssertEqual(store.saved, state.notes)
        XCTAssertEqual(state.draft, "")
        XCTAssertNil(state.issue)

        state.draft = "  \n "
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(store.saved.count, 1)
    }

    func testFailedCompletionEditAndDeleteNeverChangeSavedDisplay() {
        let original = note("Original", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [original])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.panelDidOpen()

        store.failWrite = .complete
        XCTAssertFalse(state.setCompleted(id: original.id, completed: true))
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(state.progress, NoteProgress(completed: 0, total: 1))
        XCTAssertEqual(state.issue, .complete)

        state.beginEditing(id: original.id)
        state.editDraft = "  Corrected  "
        store.failWrite = .edit
        XCTAssertFalse(state.saveEdit())
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(state.editDraft, "  Corrected  ")
        XCTAssertEqual(state.editingNoteID, original.id)
        XCTAssertEqual(state.issue, .edit)

        store.failWrite = .delete
        XCTAssertFalse(state.delete(id: original.id))
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(state.editDraft, "  Corrected  ")
        XCTAssertEqual(state.issue, .delete)

        store.failWrite = nil
        XCTAssertTrue(state.saveEdit())
        XCTAssertEqual(state.notes.map(\.text), ["Corrected"])
        XCTAssertTrue(state.setCompleted(id: original.id, completed: true))
        XCTAssertEqual(state.progress, NoteProgress(completed: 1, total: 1))
        XCTAssertTrue(state.delete(id: original.id))
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertTrue(store.saved.isEmpty)
    }

    func testNoteChangesPersistAcrossFreshStateWithSQLite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DailyNotesStateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("notes.sqlite")
        let makeState = {
            DailyNotesState(
                repositoryFactory: { try SQLiteNoteRepository(databaseURL: databaseURL) },
                day: self.makeDay(now: { self.instant("2026-09-27T12:00:00-04:00") }),
                notificationCenter: NotificationCenter()
            )
        }

        let firstSession = makeState()
        firstSession.panelDidOpen()
        firstSession.draft = "  First note  "
        XCTAssertTrue(firstSession.addDraft())
        firstSession.draft = "Second note"
        XCTAssertTrue(firstSession.addDraft())
        let firstID = try XCTUnwrap(firstSession.notes.first(where: { $0.text == "First note" })?.id)
        XCTAssertTrue(firstSession.setCompleted(id: firstID, completed: true))
        XCTAssertEqual(firstSession.progress, NoteProgress(completed: 1, total: 2))
        XCTAssertEqual(firstSession.notes.last?.id, firstID)

        let secondSession = makeState()
        secondSession.panelDidOpen()
        XCTAssertEqual(secondSession.notes.map(\.text), ["Second note", "First note"])
        XCTAssertEqual(secondSession.progress, NoteProgress(completed: 1, total: 2))
        XCTAssertTrue(secondSession.notes.last?.isCompleted == true)
        XCTAssertTrue(secondSession.setCompleted(id: firstID, completed: false))

        let thirdSession = makeState()
        thirdSession.panelDidOpen()
        XCTAssertEqual(thirdSession.progress, NoteProgress(completed: 0, total: 2))
        XCTAssertFalse(try XCTUnwrap(thirdSession.notes.first(where: { $0.id == firstID })).isCompleted)
        thirdSession.beginEditing(id: firstID)
        thirdSession.editDraft = "  Updated note  "
        XCTAssertTrue(thirdSession.saveEdit())
        let secondID = try XCTUnwrap(thirdSession.notes.first(where: { $0.text == "Second note" })?.id)
        XCTAssertTrue(thirdSession.delete(id: secondID))

        let fourthSession = makeState()
        fourthSession.panelDidOpen()
        XCTAssertEqual(fourthSession.notes.map(\.text), ["Updated note"])
        XCTAssertEqual(fourthSession.notes.first?.id, firstID)
    }

    private func makeState(store: FakeNoteRepository, now: @escaping () -> Date) -> DailyNotesState {
        DailyNotesState(repositoryFactory: { store }, day: makeDay(now: now),
                        notificationCenter: NotificationCenter())
    }

    private func makeDay(now: @escaping () -> Date) -> NoteDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return NoteDay(calendar: calendar, now: now)
    }

    private func instant(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func note(_ text: String, day: String, createdAt: TimeInterval,
                      completedAt: Date? = nil) -> Note {
        Note(id: UUID(), text: text, dayKey: day,
             createdAt: Date(timeIntervalSince1970: createdAt), completedAt: completedAt)
    }
}

private enum FakeFailure: Error { case failed }

private final class FakeNoteRepository: NoteRepository {
    var saved: [Note]
    var failCount = false
    var failWrite: DailyNotesIssue?

    init(notes: [Note] = []) { saved = notes }

    func notes(for dayKey: String) throws -> [Note] {
        NoteOrder.sorted(saved.filter { $0.dayKey == dayKey })
    }

    func incompleteCount(for dayKey: String) throws -> Int {
        if failCount { throw FakeFailure.failed }
        return saved.count { $0.dayKey == dayKey && !$0.isCompleted }
    }

    func add(_ note: Note) throws {
        if failWrite == .add { throw FakeFailure.failed }
        saved.append(note)
    }

    func setCompleted(id: UUID, completedAt: Date?) throws {
        if failWrite == .complete { throw FakeFailure.failed }
        try mutate(id: id) { note in
            Note(id: note.id, text: note.text, dayKey: note.dayKey,
                 createdAt: note.createdAt, completedAt: completedAt)
        }
    }

    func updateText(id: UUID, text: String) throws {
        if failWrite == .edit { throw FakeFailure.failed }
        try mutate(id: id) { note in
            Note(id: note.id, text: text, dayKey: note.dayKey,
                 createdAt: note.createdAt, completedAt: note.completedAt)
        }
    }

    func delete(id: UUID) throws {
        if failWrite == .delete { throw FakeFailure.failed }
        guard saved.contains(where: { $0.id == id }) else { throw FakeFailure.failed }
        saved.removeAll { $0.id == id }
    }

    private func mutate(id: UUID, change: (Note) -> Note) throws {
        guard let index = saved.firstIndex(where: { $0.id == id }) else { throw FakeFailure.failed }
        saved[index] = change(saved[index])
    }
}
