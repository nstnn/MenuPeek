import AppKit
import Observation
import XCTest
@testable import MenuPocket

@MainActor
final class DailyNotesStateTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Toronto")!

    func testCategorizedTaskRetainsAssociationAndOrderAcrossCompletionEditingAndRefresh() throws {
        let current = instant("2026-09-27T12:00:00-04:00")
        let category = try TaskCategory(name: "Work", creationOrder: 7)
        let original = Note(id: UUID(), text: "Categorized", dayKey: "2026-09-27",
                            createdAt: current, completedAt: nil, categoryID: category.id)
        let general = note("General task", day: original.dayKey, createdAt: 1)
        let store = FakeNoteRepository(notes: [original, general])
        let state = makeState(store: store, now: { current })
        state.startup()

        XCTAssertTrue(state.setCompleted(id: original.id, completed: true))
        let completed = Note(id: original.id, text: original.text, dayKey: original.dayKey,
                             createdAt: original.createdAt, completedAt: current,
                             categoryID: category.id)
        XCTAssertEqual(state.notes, [completed, general])
        XCTAssertEqual(store.saved, state.notes)
        XCTAssertEqual(state.progress, NoteProgress(completed: 1, total: 2))

        XCTAssertTrue(state.setCompleted(id: original.id, completed: false))
        XCTAssertEqual(state.notes, [original, general])
        XCTAssertEqual(store.saved, state.notes)
        state.beginEditing(id: original.id)
        state.editDraft = "  Updated text  "
        XCTAssertTrue(state.saveEdit())
        let edited = Note(id: original.id, text: "Updated text", dayKey: original.dayKey,
                          createdAt: original.createdAt, completedAt: nil,
                          categoryID: category.id)
        XCTAssertEqual(state.notes, [edited, general])
        XCTAssertEqual(store.saved, state.notes)
        XCTAssertEqual(state.progress, NoteProgress(completed: 0, total: 2))
        state.refresh()
        XCTAssertEqual(state.notes, [edited, general])
        let reopened = makeState(store: store, now: { current })
        reopened.startup()
        XCTAssertEqual(reopened.notes, [edited, general])
    }

    func testRejectedCategorizedTaskWritesPreserveAssociationAndEditDraft() {
        let current = instant("2026-09-27T12:00:00-04:00")
        let original = Note(id: UUID(), text: "Original", dayKey: "2026-09-27",
                            createdAt: current, completedAt: nil, categoryID: UUID())
        let store = FakeNoteRepository(notes: [original])
        let state = makeState(store: store, now: { current })
        state.startup()

        store.failWrite = .complete
        XCTAssertFalse(state.setCompleted(id: original.id, completed: true))
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(store.saved, [original])

        state.beginEditing(id: original.id)
        state.editDraft = "Unsaved edit"
        store.failWrite = .edit
        XCTAssertFalse(state.saveEdit())
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(store.saved, [original])
        XCTAssertEqual(state.progress, NoteProgress(completed: 0, total: 1))
        XCTAssertEqual(state.editingNoteID, original.id)
        XCTAssertEqual(state.editDraft, "Unsaved edit")
    }

    func testStatusItemObservesSuccessiveSavedWritesWithoutAWindow() async throws {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        var clicks = 0
        let controller = TaskStatusItemController(state: state) { clicks += 1 }
        defer { controller.remove() }
        let button = try XCTUnwrap(controller.statusItem?.button)
        XCTAssertEqual(button.title, "—")
        XCTAssertNil(button.image)
        state.startup()
        try await waitForStatusTitle("0/0", controller: controller)
        state.draft = "First task"
        XCTAssertTrue(state.addDraft())
        try await waitForStatusTitle("0/1", controller: controller)
        let id = try XCTUnwrap(state.notes.first?.id)
        XCTAssertTrue(state.setCompleted(id: id, completed: true))
        try await waitForStatusTitle("1/1", controller: controller)
        XCTAssertEqual(button.accessibilityLabel(), "MenuPocket, today, 1 of 1 tasks completed")
        XCTAssertTrue(state.setCompleted(id: id, completed: false))
        try await waitForStatusTitle("0/1", controller: controller)
        XCTAssertTrue(state.delete(id: id))
        try await waitForStatusTitle("0/0", controller: controller)
        button.performClick(nil)
        button.performClick(nil)
        XCTAssertEqual(clicks, 2)
    }

    func testStatusItemDistinguishesReadFailureRetryAndRejectedWrites() async throws {
        let saved = note("Saved", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [saved])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let controller = TaskStatusItemController(state: state, showTasks: {})
        defer { controller.remove() }
        try await waitForStatusTitle("0/1", controller: controller)
        for failure in [DailyNotesIssue.add, .complete, .delete] {
            store.failWrite = failure
            switch failure {
            case .add:
                state.draft = "Rejected"
                XCTAssertFalse(state.addDraft())
            case .complete: XCTAssertFalse(state.setCompleted(id: saved.id, completed: true))
            case .delete: XCTAssertFalse(state.delete(id: saved.id))
            default: XCTFail("Unexpected fixture failure")
            }
            try await Task.sleep(for: .milliseconds(20))
            XCTAssertEqual(controller.statusItem?.button?.title, "0/1")
        }
        store.failCount = true
        state.refresh()
        try await waitForStatusTitle("—", controller: controller)
        XCTAssertEqual(state.notes, [saved])
        XCTAssertTrue(controller.statusItem?.button?.accessibilityLabel()?.contains("unavailable") == true)
        store.failCount = false
        store.failWrite = nil
        state.refresh()
        try await waitForStatusTitle("0/1", controller: controller)
    }

    func testStatusItemRefreshesClosedWindowDayAndExactMultiDigitCounts() async throws {
        let saved = (0..<12).map { note("Task \($0)", day: "2026-09-27", createdAt: Double($0), completedAt: Date()) }
        let store = FakeNoteRepository(notes: saved)
        var current = instant("2026-09-27T23:59:00-04:00")
        let center = NotificationCenter()
        let state = DailyNotesState(repositoryFactory: { store }, day: makeDay(now: { current }),
                                    notificationCenter: center, workspaceNotificationCenter: NotificationCenter())
        state.startup()
        let controller = TaskStatusItemController(state: state, showTasks: {})
        defer { controller.remove() }
        try await waitForStatusTitle("12/12", controller: controller)
        XCTAssertTrue(controller.statusItem?.button?.toolTip?.contains("12 of 12") == true)
        current = instant("2026-09-28T00:01:00-04:00")
        center.post(name: .NSCalendarDayChanged, object: nil)
        try await waitForStatusTitle("0/0", controller: controller)
        XCTAssertEqual(store.saved, saved)
    }

    func testRemovingStatusItemDoesNotRecreateItOrRetainController() async throws {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        var controller: TaskStatusItemController? = TaskStatusItemController(state: state, showTasks: {})
        weak var releasedController = controller
        state.startup() // Queue an update, then remove before it executes.
        controller?.remove()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(controller?.statusItem)
        state.draft = "After removal"
        XCTAssertTrue(state.addDraft())
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(controller?.statusItem)
        controller = nil
        XCTAssertNil(releasedController)
    }

    private func waitForStatusTitle(_ title: String, controller: TaskStatusItemController) async throws {
        for _ in 0..<100 {
            if controller.statusItem?.button?.title == title { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(controller.statusItem?.button?.title, title)
    }

    func testRefreshAndReopenPublishSavedDailySnapshot() {
        let today = note("Today", day: "2026-09-27", createdAt: 2)
        let finished = note("Finished", day: "2026-09-27", createdAt: 3,
                            completedAt: Date(timeIntervalSince1970: 4))
        let yesterday = note("Yesterday", day: "2026-09-26", createdAt: 1)
        let store = FakeNoteRepository(notes: [today, finished, yesterday])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })

        state.windowWillOpen()
        XCTAssertEqual(state.notes, [today, finished])
        XCTAssertEqual(state.progress, NoteProgress(completed: 1, total: 2))
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        XCTAssertNil(state.issue)

        let newest = note("New", day: "2026-09-27", createdAt: 5)
        store.saved.append(newest)
        state.windowWillOpen()
        XCTAssertEqual(state.notes, [today, finished, newest])
        XCTAssertEqual(state.progress, NoteProgress(completed: 1, total: 3))
    }

    func testDayChangeMovesOldNotesIntoYesterdayCountWithoutCarryover() {
        let previous = note("Unfinished", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [previous])
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = makeState(store: store, now: { current })

        state.windowWillOpen()
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
        state.windowWillOpen()
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
        state.windowWillOpen()

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
        state.windowWillOpen()
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
        notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter())

        state.windowWillOpen()
        XCTAssertEqual(state.issue, .load)
        XCTAssertFalse(state.hasLoadedToday)
        shouldFail = false
        state.windowWillOpen()
        XCTAssertTrue(state.hasLoadedToday)
        XCTAssertNil(state.issue)
    }

    func testFailedAddKeepsDraftAndSuccessfulRetryPublishesOnlySavedNote() {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.windowWillOpen()
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

    func testCancelNewDraftClearsFailedAddWithoutChangingSavedTasks() {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.windowWillOpen()
        state.draft = "Retry or discard"
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        state.windowWillOpen()
        XCTAssertEqual(state.draft, "Retry or discard")
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(state.issue, .add)
        state.cancelDraft()
        XCTAssertEqual(state.draft, "")
        XCTAssertNil(state.issue)
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 0))
    }

    func testIndependentAddReportsOutcomesWithoutChangingWindowDraftOrIssue() {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "Half-typed window task"
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(state.issue, .add)

        XCTAssertEqual(state.add(text: "Rejected panel task"), .writeFailed)
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 0))

        store.failWrite = nil
        XCTAssertEqual(state.add(text: "  \n "), .empty)
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertEqual(state.add(text: "  Panel task  "), .added)
        XCTAssertEqual(state.notes.map(\.text), ["Panel task"])
        XCTAssertEqual(state.notes.first?.dayKey, "2026-09-27")
        XCTAssertNil(state.notes.first?.categoryID)
        XCTAssertEqual(store.saved, state.notes)
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 1))
        XCTAssertEqual(state.draft, "Half-typed window task")
        XCTAssertEqual(state.issue, .add)
    }

    func testIndependentAddIsUnavailableWhenSavedDataCannotBeRead() {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        store.failCount = true
        state.refresh()
        XCTAssertEqual(state.add(text: "Unavailable"), .unavailable)
        XCTAssertTrue(store.saved.isEmpty)

        let unopened = DailyNotesState(repositoryFactory: { throw FakeFailure.failed },
                                       day: makeDay(now: { self.instant("2026-09-27T12:00:00-04:00") }),
                                       notificationCenter: NotificationCenter(),
                                       workspaceNotificationCenter: NotificationCenter())
        XCTAssertEqual(unopened.add(text: "Never loaded"), .unavailable)
        XCTAssertTrue(unopened.notes.isEmpty)

        // An unloaded state becomes ready through the same one refresh as Add task.
        store.failCount = false
        let unloaded = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        XCTAssertEqual(unloaded.add(text: "Loads first"), .added)
        XCTAssertEqual(store.saved.map(\.text), ["Loads first"])
    }

    func testIndependentAddKeepsEditTargetAndDeletionConfirmation() {
        let edited = note("Being edited", day: "2026-09-27", createdAt: 1)
        let target = note("Delete me", day: "2026-09-27", createdAt: 2)
        let store = FakeNoteRepository(notes: [edited, target])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        let presentation = TaskWindowPresentation()
        state.startup()
        state.draft = "Window draft"
        state.beginEditing(id: edited.id)
        state.editDraft = "Unsaved edit"
        presentation.requestDeletion(id: target.id, state: state)

        XCTAssertEqual(state.add(text: "Captured"), .added)
        XCTAssertEqual(state.editingNoteID, edited.id)
        XCTAssertEqual(state.editDraft, "Unsaved edit")
        XCTAssertEqual(state.draft, "Window draft")
        XCTAssertNil(state.issue)
        XCTAssertNil(state.refreshNotice)
        presentation.validateDeletion(state: state)
        XCTAssertEqual(presentation.deletionTarget?.id, target.id)

        XCTAssertTrue(presentation.confirmDeletion(state: state))
        XCTAssertTrue(state.saveEdit())
        XCTAssertEqual(state.notes.map(\.text), ["Unsaved edit", "Captured"])
        XCTAssertEqual(store.saved, state.notes)
    }

    func testAddDraftAndIndependentAddSaveIdenticalNotes() {
        let current = instant("2026-09-27T12:00:00-04:00")
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { current })
        state.startup()
        state.draft = "  Same task  "
        XCTAssertTrue(state.addDraft())
        XCTAssertEqual(state.add(text: "  Same task  "), .added)

        XCTAssertEqual(store.saved.count, 2)
        for saved in store.saved {
            XCTAssertEqual(saved.text, "Same task")
            XCTAssertEqual(saved.dayKey, "2026-09-27")
            XCTAssertEqual(saved.createdAt, current)
            XCTAssertNil(saved.completedAt)
            XCTAssertNil(saved.categoryID)
        }
        XCTAssertNotEqual(store.saved[0].id, store.saved[1].id)

        // Empty input keeps the window's earlier write error, as before.
        store.failWrite = .add
        state.draft = "Rejected"
        XCTAssertFalse(state.addDraft())
        state.draft = "   "
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(state.issue, .add)
        XCTAssertEqual(state.draft, "   ")
    }

    func testBlankEditAndCancellationKeepSavedTaskAndSeparateNewDraft() {
        let original = note("Original", day: "2026-09-27", createdAt: 1,
                            completedAt: Date(timeIntervalSince1970: 2))
        let store = FakeNoteRepository(notes: [original])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "Separate new task"
        state.beginEditing(id: original.id)
        state.editDraft = "  \n "
        XCTAssertFalse(state.saveEdit())
        XCTAssertEqual(store.saved, [original])
        state.editDraft = "Unsaved correction"
        store.failWrite = .edit
        XCTAssertFalse(state.saveEdit())
        XCTAssertEqual(state.issue, .edit)
        state.cancelEditing()
        XCTAssertNil(state.editingNoteID)
        XCTAssertEqual(state.editDraft, "")
        XCTAssertNil(state.issue)
        XCTAssertEqual(state.draft, "Separate new task")
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(store.saved, [original])
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 1, total: 1))
    }

    func testFailedCompletionEditAndDeleteNeverChangeSavedDisplay() {
        let original = note("Original", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [original])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.windowWillOpen()

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

    func testFixedInsertionOrderSurvivesTaskChangesAndFreshStateWithSQLite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DailyNotesStateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("notes.sqlite")
        var current = instant("2026-09-27T12:00:00-04:00")
        let makeState = {
            DailyNotesState(
                repositoryFactory: { try SQLiteNoteRepository(databaseURL: databaseURL) },
                day: self.makeDay(now: { current }),
                notificationCenter: NotificationCenter()
            )
        }

        let firstSession = makeState()
        firstSession.windowWillOpen()
        firstSession.draft = "  First note  "
        XCTAssertTrue(firstSession.addDraft())
        firstSession.draft = "Second note"
        XCTAssertTrue(firstSession.addDraft())
        // Equal timestamps and a clock adjustment must not affect insertion order.
        current = current.addingTimeInterval(-60)
        firstSession.draft = "Third note"
        XCTAssertTrue(firstSession.addDraft())
        XCTAssertEqual(firstSession.notes.map(\.text), ["First note", "Second note", "Third note"])
        let originalIDs = firstSession.notes.map(\.id)
        let firstID = try XCTUnwrap(firstSession.notes.first(where: { $0.text == "First note" })?.id)
        XCTAssertTrue(firstSession.setCompleted(id: firstID, completed: true))
        XCTAssertEqual(firstSession.progress, NoteProgress(completed: 1, total: 3))
        XCTAssertEqual(firstSession.notes.map(\.id), originalIDs)
        firstSession.refresh()
        XCTAssertEqual(firstSession.notes.map(\.id), originalIDs)

        let secondSession = makeState()
        secondSession.windowWillOpen()
        XCTAssertEqual(secondSession.notes.map(\.id), originalIDs)
        XCTAssertEqual(secondSession.progress, NoteProgress(completed: 1, total: 3))
        XCTAssertTrue(secondSession.notes.first?.isCompleted == true)
        XCTAssertTrue(secondSession.setCompleted(id: firstID, completed: false))
        XCTAssertEqual(secondSession.notes.map(\.id), originalIDs)

        let thirdSession = makeState()
        thirdSession.windowWillOpen()
        XCTAssertEqual(thirdSession.progress, NoteProgress(completed: 0, total: 3))
        XCTAssertEqual(thirdSession.notes.map(\.id), originalIDs)
        XCTAssertFalse(try XCTUnwrap(thirdSession.notes.first(where: { $0.id == firstID })).isCompleted)
        thirdSession.beginEditing(id: firstID)
        thirdSession.editDraft = "  Updated note  "
        XCTAssertTrue(thirdSession.saveEdit())
        XCTAssertEqual(thirdSession.notes.map(\.id), originalIDs)
        let secondID = try XCTUnwrap(thirdSession.notes.first(where: { $0.text == "Second note" })?.id)
        XCTAssertTrue(thirdSession.delete(id: secondID))
        XCTAssertEqual(thirdSession.notes.map(\.id), [originalIDs[0], originalIDs[2]])
        thirdSession.draft = "Fourth note"
        XCTAssertTrue(thirdSession.addDraft())
        XCTAssertEqual(thirdSession.notes.map(\.text), ["Updated note", "Third note", "Fourth note"])

        let fourthSession = makeState()
        fourthSession.windowWillOpen()
        XCTAssertEqual(fourthSession.notes, thirdSession.notes)
        XCTAssertEqual(fourthSession.progress, NoteProgress(completed: 0, total: 3))
        XCTAssertEqual(fourthSession.notes.first?.id, firstID)
    }

    func testAvailabilityDistinguishesEmptyReadFailureAndRejectedWrite() {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        XCTAssertNil(state.availableProgress)
        state.startup()
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 0))
        state.draft = "Unsaved"
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 0))
        store.failCount = true
        state.refresh()
        XCTAssertNil(state.availableProgress)
        XCTAssertFalse(state.hasLoadedToday)
        XCTAssertFalse(state.addDraft())
        XCTAssertTrue(store.saved.isEmpty)
        store.failCount = false
        store.failWrite = nil
        state.refresh()
        XCTAssertTrue(state.addDraft())
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 1))
    }

    func testWakeAndClockNotificationsRefreshWithoutOpeningWindow() async {
        let old = note("Yesterday", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [old])
        let center = NotificationCenter()
        let workspace = NotificationCenter()
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = DailyNotesState(repositoryFactory: { store }, day: makeDay(now: { current }),
                                    notificationCenter: center, workspaceNotificationCenter: workspace)
        state.startup()
        for (eventCenter, name) in [(workspace, NSWorkspace.didWakeNotification),
                                    (center, Notification.Name.NSSystemClockDidChange)] {
            let changed = expectation(description: "Closed-window event refreshed day")
            withObservationTracking { _ = state.todayKey } onChange: { changed.fulfill() }
            current = current.addingTimeInterval(86400)
            eventCenter.post(name: name, object: nil)
            await fulfillment(of: [changed], timeout: 2)
            XCTAssertEqual(state.todayKey, makeDay(now: { current }).keys().today)
            XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 0))
        }
    }

    func testTimeZoneNotificationRecalculatesDayWithoutReassigningSavedRows() async {
        let saved = note("Assigned day", day: "2026-09-26", createdAt: 1)
        let store = FakeNoteRepository(notes: [saved])
        let center = NotificationCenter()
        var zone = TimeZone(identifier: "America/Toronto")!
        let day = NoteDay(now: { self.instant("2026-09-27T00:30:00Z") }, timeZone: { zone })
        let state = DailyNotesState(repositoryFactory: { store }, day: day,
                                    notificationCenter: center, workspaceNotificationCenter: NotificationCenter())
        state.startup()
        XCTAssertEqual(state.notes, [saved])
        let changed = expectation(description: "Time-zone refresh")
        withObservationTracking { _ = state.todayKey } onChange: { changed.fulfill() }
        zone = TimeZone(secondsFromGMT: 0)!
        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(state.todayKey, "2026-09-27")
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        XCTAssertEqual(store.saved, [saved])
    }

    func testRolloverCancelsStaleActionsAndRecoversEditEvenWhenReadFails() {
        let old = note("Original", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [old])
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = makeState(store: store, now: { current })
        state.startup()
        state.beginEditing(id: old.id)
        state.editDraft = "Recover my changes"
        state.draft = "New draft"
        current = instant("2026-09-28T00:01:00-04:00")
        store.failCount = true
        XCTAssertFalse(state.saveEdit())
        XCTAssertNil(state.editingNoteID)
        XCTAssertEqual(state.recoveredEditDraft, "Recover my changes")
        XCTAssertNotNil(state.refreshNotice)
        XCTAssertNil(state.availableProgress)
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertFalse(state.delete(id: old.id))
        XCTAssertFalse(state.setCompleted(id: old.id, completed: true))
        XCTAssertEqual(store.saved, [old])
        store.failCount = false
        XCTAssertTrue(state.addDraft())
        XCTAssertEqual(store.saved.first(where: { $0.text == "New draft" })?.dayKey, "2026-09-28")
        XCTAssertEqual(store.saved.first(where: { $0.id == old.id }), old)
    }

    func testSameDayRefreshKeepsEditOrRecoversRemovedTarget() {
        let original = note("Original", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [original])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.beginEditing(id: original.id)
        state.editDraft = "Recover me"
        state.windowWillOpen()
        XCTAssertEqual(state.editingNoteID, original.id)
        XCTAssertEqual(state.editDraft, "Recover me")
        store.saved = []
        state.refresh()
        XCTAssertNil(state.editingNoteID)
        XCTAssertEqual(state.recoveredEditDraft, "Recover me")
        XCTAssertNotNil(state.refreshNotice)
        XCTAssertFalse(state.saveEdit())
    }

    func testRolloverClearsOldProgressBeforeRepositoryReadAndRejectsPendingDelete() {
        let old = note("Yesterday", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [old])
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = makeState(store: store, now: { current })
        state.startup()
        current = instant("2026-09-28T00:01:00-04:00")
        store.onRead = { key in
            XCTAssertEqual(key, "2026-09-28")
            XCTAssertEqual(state.todayKey, key)
            XCTAssertNil(state.availableProgress)
            XCTAssertTrue(state.notes.isEmpty)
        }
        XCTAssertFalse(state.delete(id: old.id))
        XCTAssertEqual(store.saved, [old])
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        store.onRead = nil
    }

    func testObserversDoNotRetainReleasedStateOrRefreshAfterRelease() async {
        let store = FakeNoteRepository()
        let center = NotificationCenter()
        let workspace = NotificationCenter()
        var state: DailyNotesState? = DailyNotesState(repositoryFactory: { store },
            day: makeDay(now: { self.instant("2026-09-27T12:00:00-04:00") }),
            notificationCenter: center, workspaceNotificationCenter: workspace)
        state?.startup()
        weak var released = state
        state = nil
        XCTAssertNil(released)
        store.onRead = { _ in XCTFail("Released state should not read") }
        center.post(name: .NSCalendarDayChanged, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        await Task.yield()
    }

    private func makeState(store: FakeNoteRepository, now: @escaping () -> Date) -> DailyNotesState {
        DailyNotesState(repositoryFactory: { store }, day: makeDay(now: now),
                        notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter())
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
    var onRead: ((String) -> Void)?
    var failCount = false
    var failWrite: DailyNotesIssue?

    init(notes: [Note] = []) { saved = notes }

    func notes(for dayKey: String) throws -> [Note] {
        onRead?(dayKey)
        return saved.filter { $0.dayKey == dayKey }
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
                 createdAt: note.createdAt, completedAt: completedAt,
                 categoryID: note.categoryID)
        }
    }

    func updateText(id: UUID, text: String) throws {
        if failWrite == .edit { throw FakeFailure.failed }
        try mutate(id: id) { note in
            Note(id: note.id, text: text, dayKey: note.dayKey,
                 createdAt: note.createdAt, completedAt: note.completedAt,
                 categoryID: note.categoryID)
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
