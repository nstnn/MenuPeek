import AppKit
import Observation
import XCTest
@testable import MenuPocket

@MainActor
final class DailyNotesStateTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Toronto")!

    func testCatalogIsPublishedWithDailyRowsAndIncludesUnusedReusableCategories() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 2)
        let unused = try TaskCategory(name: "Unused", creationOrder: 8)
        let today = note("Today", day: "2026-09-27", createdAt: 1)
        let yesterday = note("Yesterday", day: "2026-09-26", createdAt: 2)
        let store = FakeNoteRepository(notes: [today, yesterday], categories: [unused, work])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        XCTAssertNil(state.availableCategories)
        state.startup()
        XCTAssertEqual(state.availableCategories, [work, unused])
        XCTAssertEqual(state.notes, [today])
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        let reopened = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        reopened.windowWillOpen()
        XCTAssertEqual(reopened.availableCategories, state.availableCategories)
        XCTAssertEqual(reopened.notes, [today])
    }

    func testEveryRequiredReadFailureRetainsWholeSavedSnapshotUntilRetry() throws {
        for failure in FakeSnapshotRead.allCases {
            let originalCategory = try TaskCategory(name: "Work", creationOrder: 0)
            let renamed = try TaskCategory(id: originalCategory.id, name: "Office", creationOrder: 0)
            let original = note("Original", day: "2026-09-27", createdAt: 1)
            let yesterday = note("Yesterday", day: "2026-09-26", createdAt: 2)
            let store = FakeNoteRepository(notes: [original, yesterday], categories: [originalCategory])
            defer {
                store.onCategoryRead = nil
                store.onRead = nil
            }
            let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
            state.startup()
            let replacement = Note(id: UUID(), text: "Replacement", dayKey: original.dayKey,
                                   createdAt: Date(), completedAt: Date(), categoryID: renamed.id)
            store.savedCategories = [renamed]
            store.saved = [replacement, yesterday, note("Another yesterday", day: yesterday.dayKey, createdAt: 3)]
            store.onCategoryRead = {
                XCTAssertEqual(state.categories, [originalCategory])
                XCTAssertEqual(state.notes, [original])
                XCTAssertEqual(state.yesterdayIncompleteCount, 1)
            }
            store.onRead = { _ in
                XCTAssertEqual(state.categories, [originalCategory])
                XCTAssertEqual(state.notes, [original])
            }
            store.failSnapshotRead = failure
            state.refresh()
            XCTAssertEqual(state.categories, [originalCategory], "Failed at \(failure)")
            XCTAssertEqual(state.notes, [original])
            XCTAssertEqual(state.yesterdayIncompleteCount, 1)
            XCTAssertNil(state.availableCategories)
            XCTAssertNil(state.availableProgress)
            XCTAssertEqual(state.readIssue, .load)
            store.failSnapshotRead = nil
            state.refresh()
            XCTAssertEqual(state.availableCategories, [renamed])
            XCTAssertEqual(state.notes, [replacement])
            XCTAssertEqual(state.yesterdayIncompleteCount, 2)
            XCTAssertEqual(state.availableProgress, NoteProgress(completed: 1, total: 1))
            XCTAssertNil(state.readIssue)
        }
    }

    func testInitialReadFailureAndUnknownReferenceNeverPublishPartialCatalog() throws {
        let category = try TaskCategory(name: "Work", creationOrder: 0)
        for failure in FakeSnapshotRead.allCases {
            let store = FakeNoteRepository(categories: [category])
            store.failSnapshotRead = failure
            let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
            state.startup()
            XCTAssertTrue(state.categories.isEmpty)
            XCTAssertTrue(state.notes.isEmpty)
            XCTAssertNil(state.availableCategories)
            XCTAssertNil(state.availableProgress)
            store.failSnapshotRead = nil
            state.refresh()
            XCTAssertEqual(state.availableCategories, [category])
            XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 0))
        }
        let categorized = Note(id: UUID(), text: "Orphan", dayKey: "2026-09-27",
                               createdAt: Date(), completedAt: nil, categoryID: category.id)
        // Bypass the fake's own referential checks to challenge the state boundary.
        let store = FakeNoteRepository()
        store.uncheckedNotes = [categorized]
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertNil(state.availableProgress)
        XCTAssertEqual(state.readIssue, .load)
        store.savedCategories = [category]
        state.refresh()
        XCTAssertEqual(state.notes, [categorized])
        XCTAssertEqual(state.availableCategories, [category])
    }

    func testCategoryCommandsPublishCommittedValuesWithoutRedundantReads() throws {
        let category = try TaskCategory(name: "Work", creationOrder: 2)
        let other = try TaskCategory(name: "Other", creationOrder: 8)
        let categorized = Note(id: UUID(), text: "Done", dayKey: "2026-09-27",
                               createdAt: Date(timeIntervalSince1970: 1), completedAt: Date(), categoryID: category.id)
        let general = note("General", day: categorized.dayKey, createdAt: 2)
        let historical = Note(id: UUID(), text: "Earlier", dayKey: "2026-09-26",
                              createdAt: Date(), completedAt: nil, categoryID: category.id)
        let store = FakeNoteRepository(notes: [categorized, general, historical], categories: [category, other])
        defer { store.onCategoryWrite = nil }
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let progress = state.availableProgress
        let reads = store.readAttempts
        var expectedCategories = state.categories
        store.onCategoryWrite = {
            XCTAssertEqual(state.categories, expectedCategories)
            XCTAssertEqual(state.notes, [categorized, general])
            store.failSnapshotRead = .categories
        }
        let created = try XCTUnwrap(state.createCategory(name: "  Fitness  "))
        XCTAssertEqual(created.name, "Fitness")
        XCTAssertEqual(created.creationOrder, 9)
        XCTAssertEqual(state.categories, store.savedCategories)
        expectedCategories = state.categories
        let renamed = try XCTUnwrap(state.renameCategory(id: category.id, name: "Office"))
        XCTAssertEqual(renamed.id, category.id)
        XCTAssertEqual(renamed.creationOrder, category.creationOrder)
        XCTAssertEqual(state.categories, [renamed, other, created])
        XCTAssertEqual(state.notes, [categorized, general])
        expectedCategories = state.categories
        XCTAssertTrue(state.removeCategory(id: category.id))
        XCTAssertEqual(state.categories, [other, created])
        let uncategorized = Note(id: categorized.id, text: categorized.text, dayKey: categorized.dayKey,
                                 createdAt: categorized.createdAt, completedAt: categorized.completedAt)
        XCTAssertEqual(state.notes, [uncategorized, general])
        XCTAssertNil(store.saved.last?.categoryID)
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        XCTAssertEqual(state.availableProgress, progress)
        XCTAssertEqual(store.readAttempts, reads)
        XCTAssertNil(state.categoryIssue)
        XCTAssertNil(state.readIssue)
    }

    func testFailedCategoryWritesPreserveSavedSnapshotTaskErrorsAndBothDrafts() throws {
        let category = try TaskCategory(name: "Work", creationOrder: 0)
        let original = Note(id: UUID(), text: "Original", dayKey: "2026-09-27",
                            createdAt: Date(), completedAt: nil, categoryID: category.id)
        let store = FakeNoteRepository(notes: [original], categories: [category])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "New task draft"
        state.beginEditing(id: original.id)
        state.editDraft = "Unsaved edit"
        store.failWrite = .edit
        XCTAssertFalse(state.saveEdit())
        for failure in [CategoryCommandIssue.create, .rename, .remove] {
            store.failCategoryCommand = failure
            switch failure {
            case .create: XCTAssertNil(state.createCategory(name: "Fitness"))
            case .rename: XCTAssertNil(state.renameCategory(id: category.id, name: "Office"))
            case .remove: XCTAssertFalse(state.removeCategory(id: category.id))
            default: XCTFail("Unexpected write fixture")
            }
            XCTAssertEqual(state.categoryIssue, failure)
            XCTAssertEqual(state.categories, [category])
            XCTAssertEqual(state.notes, [original])
            XCTAssertEqual(store.savedCategories, [category])
            XCTAssertEqual(store.saved, [original])
            XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 1))
            XCTAssertEqual(state.taskIssue, .edit)
            XCTAssertEqual(state.issue, .edit)
            XCTAssertEqual(state.draft, "New task draft")
            XCTAssertEqual(state.editingNoteID, original.id)
            XCTAssertEqual(state.editDraft, "Unsaved edit")
        }
        store.failCategoryCommand = nil
        XCTAssertNotNil(state.createCategory(name: "Fitness"))
        XCTAssertNotNil(state.renameCategory(id: category.id, name: "Office"))
        XCTAssertEqual(state.taskIssue, .edit)
        XCTAssertEqual(state.editDraft, "Unsaved edit")
        // Removing the edit's own selected category cancels that edit for recovery.
        XCTAssertTrue(state.removeCategory(id: category.id))
        XCTAssertNil(state.categoryIssue)
        XCTAssertNil(state.editingNoteID)
        XCTAssertNil(state.taskIssue)
        XCTAssertEqual(state.recoveredEdit,
                       DailyNotesState.RecoveredEdit(text: "Unsaved edit", categoryID: category.id,
                                                     categoryName: "Office"))
        XCTAssertEqual(state.draft, "New task draft")
    }

    func testNameValidationAndUsageErrorsHaveIndependentBoundaries() throws {
        let category = try TaskCategory(name: "Work", creationOrder: 0)
        let olderDone = Note(id: UUID(), text: "Older done", dayKey: "2026-09-20",
                             createdAt: Date(), completedAt: Date(), categoryID: category.id)
        let yesterday = Note(id: UUID(), text: "Yesterday", dayKey: "2026-09-26",
                             createdAt: Date(), completedAt: nil, categoryID: category.id)
        let store = FakeNoteRepository(notes: [olderDone, yesterday], categories: [category])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "Keep this draft"
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        let reads = store.readAttempts
        for (input, error) in [("  ", TaskCategoryNameError.blank), ("A\nB", .multiline), ("general", .reserved)] {
            XCTAssertNil(state.createCategory(name: input))
            XCTAssertEqual(state.categoryNameIssue, .invalid(error))
            XCTAssertNil(state.categoryIssue)
            XCTAssertEqual(state.taskIssue, .add)
        }
        XCTAssertEqual(store.readAttempts, reads)
        // Renaming the same category to a case variant is valid.
        XCTAssertNotNil(state.renameCategory(id: category.id, name: "WORK"))
        XCTAssertNil(state.categoryNameIssue)
        XCTAssertNil(state.createCategory(name: "work"))
        XCTAssertEqual(state.categoryNameIssue, .duplicate)
        XCTAssertEqual(state.categoryUsageCount(id: category.id), 2)
        XCTAssertEqual(state.categoryNameIssue, .duplicate)
        store.failCategoryCommand = .usage
        XCTAssertNil(state.categoryUsageCount(id: category.id))
        XCTAssertEqual(state.categoryIssue, .usage)
        XCTAssertEqual(state.categoryNameIssue, .duplicate)
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 0))
        store.failCategoryCommand = nil
        XCTAssertEqual(state.categoryUsageCount(id: category.id), 2)
        XCTAssertNil(state.categoryIssue)
        let missing = UUID()
        XCTAssertNil(state.categoryUsageCount(id: missing))
        XCTAssertEqual(state.categoryIssue, .notFound)
        XCTAssertNil(state.renameCategory(id: missing, name: "Missing"))
        XCTAssertEqual(state.categoryIssue, .notFound)
        XCTAssertFalse(state.removeCategory(id: missing))
        XCTAssertEqual(state.categoryIssue, .notFound)
        XCTAssertEqual(state.taskIssue, .add)
        XCTAssertEqual(state.draft, "Keep this draft")
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        XCTAssertEqual(store.saved, [olderDone, yesterday])

        let last = try TaskCategory(name: "Last", creationOrder: .max)
        store.savedCategories.append(last)
        state.refresh()
        XCTAssertNil(state.createCategory(name: "Overflow"))
        XCTAssertEqual(state.categoryIssue, .orderExhausted)
        XCTAssertEqual(state.categories, store.savedCategories)
        XCTAssertEqual(state.taskIssue, .add)
    }

    func testReadRetryPreservesPendingTaskErrorAndCategoryValidation() {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "Unsaved"
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        XCTAssertNil(state.createCategory(name: "General"))
        store.failSnapshotRead = .categories
        state.refresh()
        XCTAssertEqual(state.issue, .load)
        XCTAssertEqual(state.taskIssue, .add)
        XCTAssertEqual(state.categoryNameIssue, .invalid(.reserved))
        XCTAssertNil(state.createCategory(name: "Work"))
        XCTAssertNil(state.renameCategory(id: UUID(), name: "Office"))
        XCTAssertFalse(state.removeCategory(id: UUID()))
        XCTAssertEqual(store.categoryWriteAttempts, 0)
        XCTAssertEqual(state.draft, "Unsaved")
        store.failSnapshotRead = nil
        XCTAssertNotNil(state.createCategory(name: "Work"))
        XCTAssertNil(state.readIssue)
        XCTAssertEqual(state.issue, .add)
        XCTAssertEqual(state.draft, "Unsaved")
        store.failWrite = nil
        XCTAssertTrue(state.addDraft())
        XCTAssertNil(state.issue)
    }

    func testDayChangeKeepsGlobalCatalogAndAllCategoryYesterdayCounts() throws {
        let category = try TaskCategory(name: "Work", creationOrder: 0)
        let unused = try TaskCategory(name: "Unused", creationOrder: 3)
        let old = Note(id: UUID(), text: "Old", dayKey: "2026-09-27",
                       createdAt: Date(), completedAt: nil, categoryID: category.id)
        let general = note("General", day: old.dayKey, createdAt: 2)
        let finished = note("Finished", day: old.dayKey, createdAt: 3, completedAt: Date())
        let today = note("New day", day: "2026-09-28", createdAt: 4)
        let store = FakeNoteRepository(notes: [old, general, finished, today], categories: [category, unused])
        defer { store.onCategoryRead = nil }
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = makeState(store: store, now: { current })
        state.startup()
        state.draft = "Retain new draft"
        state.beginEditing(id: old.id)
        state.editDraft = "Recover edit"
        store.failWrite = .edit
        XCTAssertFalse(state.saveEdit())
        XCTAssertEqual(state.taskIssue, .edit)
        current = instant("2026-09-28T00:01:00-04:00")
        store.onCategoryRead = {
            XCTAssertEqual(state.categories, [category, unused])
            XCTAssertNil(state.availableCategories)
            XCTAssertNil(state.availableProgress)
            XCTAssertTrue(state.notes.isEmpty)
        }
        store.failSnapshotRead = .count
        state.refreshIfDayChanged()
        XCTAssertNil(state.availableProgress)
        XCTAssertEqual(state.categories, [category, unused])
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertEqual(state.recoveredEditDraft, "Recover edit")
        XCTAssertNil(state.taskIssue)
        XCTAssertEqual(state.draft, "Retain new draft")
        store.failSnapshotRead = nil
        state.refresh()
        XCTAssertEqual(state.availableCategories, [category, unused])
        XCTAssertEqual(state.notes, [today])
        XCTAssertEqual(state.yesterdayIncompleteCount, 2)
        XCTAssertEqual(store.saved, [old, general, finished, today])
    }

    func testSQLiteBackedCategoryCommandsPreserveAllDaysAcrossReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DailyCatalog-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.sqlite")
        let current = instant("2026-09-27T12:00:00-04:00")
        let original: [Note]
        let category: TaskCategory
        do {
            let store = try SQLiteNoteRepository(databaseURL: url)
            category = try store.createCategory(name: "Work")
            original = ["2026-09-27", "2026-09-26", "2026-09-20"].map { key in
                Note(id: UUID(), text: key, dayKey: key, createdAt: current,
                     completedAt: key == "2026-09-20" ? current : nil, categoryID: category.id)
            }
            for note in original { try store.add(note) }
        }
        let state = DailyNotesState(repositoryFactory: { try SQLiteNoteRepository(databaseURL: url) },
                                   day: makeDay(now: { current }), notificationCenter: NotificationCenter(),
                                   workspaceNotificationCenter: NotificationCenter(),
                                   categoryPreferences: isolatedCategoryPreferences())
        state.startup()
        XCTAssertEqual(state.categories, [category])
        let survivor = try XCTUnwrap(state.createCategory(name: "Unused"))
        XCTAssertNotNil(state.renameCategory(id: category.id, name: "Office"))
        XCTAssertEqual(state.categoryUsageCount(id: category.id), 3)
        XCTAssertTrue(state.removeCategory(id: category.id))
        XCTAssertEqual(state.availableCategories, [survivor])
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 1))
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        state.stopForTermination()
        XCTAssertNil(state.createCategory(name: "After Quit"))
        XCTAssertFalse(state.removeCategory(id: survivor.id))
        let reopened = try SQLiteNoteRepository(databaseURL: url)
        XCTAssertEqual(try reopened.categories(), [survivor])
        for note in original {
            let expected = Note(id: note.id, text: note.text, dayKey: note.dayKey,
                                createdAt: note.createdAt, completedAt: note.completedAt)
            XCTAssertEqual(try reopened.notes(for: note.dayKey), [expected])
        }
    }

    func testCategorizedTaskRetainsAssociationAndOrderAcrossCompletionEditingAndRefresh() throws {
        let current = instant("2026-09-27T12:00:00-04:00")
        let category = try TaskCategory(name: "Work", creationOrder: 7)
        let original = Note(id: UUID(), text: "Categorized", dayKey: "2026-09-27",
                            createdAt: current, completedAt: nil, categoryID: category.id)
        let general = note("General task", day: original.dayKey, createdAt: 1)
        let store = FakeNoteRepository(notes: [original, general], categories: [category])
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

    func testRejectedCategorizedTaskWritesPreserveAssociationAndEditDraft() throws {
        let current = instant("2026-09-27T12:00:00-04:00")
        let category = try TaskCategory(name: "Work", creationOrder: 0)
        let original = Note(id: UUID(), text: "Original", dayKey: "2026-09-27",
                            createdAt: current, completedAt: nil, categoryID: category.id)
        let store = FakeNoteRepository(notes: [original], categories: [category])
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

    func testNewAndEditCategoryDraftsStayIndependentAndSaveAtomically() throws {
        let current = instant("2026-09-27T12:00:00-04:00")
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let original = Note(id: UUID(), text: "Original", dayKey: "2026-09-27",
                            createdAt: Date(timeIntervalSince1970: 1), completedAt: current,
                            categoryID: work.id)
        let later = note("Later", day: original.dayKey, createdAt: 2)
        let store = FakeNoteRepository(notes: [original, later], categories: [work, home])
        let state = makeState(store: store, now: { current })
        state.startup()
        XCTAssertNil(state.draftCategoryID)
        state.draft = "New task"
        state.draftCategoryID = home.id
        state.beginEditing(id: original.id)
        XCTAssertEqual(state.editCategoryID, work.id)

        // Same-day window reuse keeps both drafts and both selections.
        state.windowWillOpen()
        XCTAssertEqual(state.editingNoteID, original.id)
        XCTAssertEqual(state.editCategoryID, work.id)
        XCTAssertEqual(state.draftCategoryID, home.id)

        // A category-only edit saves; identity, completion, day, and order stay.
        state.editCategoryID = nil
        XCTAssertTrue(state.saveEdit())
        let reassigned = Note(id: original.id, text: original.text, dayKey: original.dayKey,
                              createdAt: original.createdAt, completedAt: current)
        XCTAssertEqual(state.notes, [reassigned, later])
        XCTAssertEqual(store.saved, state.notes)
        XCTAssertNil(state.editingNoteID)
        XCTAssertNil(state.editCategoryID)
        XCTAssertEqual(state.progress, NoteProgress(completed: 1, total: 2))
        XCTAssertEqual(state.draft, "New task")
        XCTAssertEqual(state.draftCategoryID, home.id)

        // The capture panel's add path stays General and leaves the window draft alone.
        XCTAssertEqual(state.add(text: "Captured"), .added)
        XCTAssertNil(store.saved.last?.categoryID)
        XCTAssertEqual(state.draftCategoryID, home.id)

        XCTAssertTrue(state.addDraft())
        XCTAssertEqual(store.saved.last?.text, "New task")
        XCTAssertEqual(store.saved.last?.categoryID, home.id)
        XCTAssertEqual(state.notes, store.saved)
        XCTAssertEqual(state.draft, "")
        XCTAssertNil(state.draftCategoryID)
    }

    func testFailedCategorizedSavesKeepTextAndSelectionAndCancelClearsOnlyItsDraft() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let original = note("Original", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [original], categories: [work, home])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "New task"
        state.draftCategoryID = work.id
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(state.taskIssue, .add)
        XCTAssertEqual(state.draft, "New task")
        XCTAssertEqual(state.draftCategoryID, work.id)

        state.beginEditing(id: original.id)
        XCTAssertNil(state.editCategoryID)
        state.editDraft = "Edited"
        state.editCategoryID = home.id
        store.failWrite = .edit
        XCTAssertFalse(state.saveEdit())
        XCTAssertEqual(state.taskIssue, .edit)
        XCTAssertEqual(state.editingNoteID, original.id)
        XCTAssertEqual(state.editDraft, "Edited")
        XCTAssertEqual(state.editCategoryID, home.id)
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(store.saved, [original])

        state.cancelEditing()
        XCTAssertNil(state.editCategoryID)
        XCTAssertEqual(state.draft, "New task")
        XCTAssertEqual(state.draftCategoryID, work.id)
        state.cancelDraft()
        XCTAssertEqual(state.draft, "")
        XCTAssertNil(state.draftCategoryID)
        XCTAssertNil(state.taskIssue)
        XCTAssertNil(state.refreshNotice)
        XCTAssertEqual(store.saved, [original])
    }

    func testSelectionOutsideTheCatalogIsNeverSavedOrPublished() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let original = note("Original", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [original], categories: [work])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let unknown = UUID()
        state.draft = "Keep me"
        state.draftCategoryID = unknown
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(store.saved, [original])
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(state.draft, "Keep me")
        XCTAssertNil(state.draftCategoryID)
        XCTAssertNil(state.taskIssue)
        XCTAssertNotNil(state.refreshNotice)
        XCTAssertEqual(state.add(text: "Panel", categoryID: unknown), .unavailable)
        XCTAssertEqual(store.saved, [original])

        state.beginEditing(id: original.id)
        state.editDraft = "Edited"
        state.editCategoryID = unknown
        XCTAssertFalse(state.saveEdit())
        XCTAssertEqual(store.saved, [original])
        XCTAssertEqual(state.notes, [original])
        XCTAssertNil(state.editingNoteID)
        XCTAssertEqual(state.recoveredEdit,
                       DailyNotesState.RecoveredEdit(text: "Edited", categoryID: unknown, categoryName: nil))

        // Storage that no longer has a loaded category rejects the write; nothing is published.
        store.savedCategories = []
        state.draftCategoryID = work.id
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(state.taskIssue, .add)
        XCTAssertEqual(state.draft, "Keep me")
        XCTAssertEqual(state.draftCategoryID, work.id)
        state.beginEditing(id: original.id)
        state.editCategoryID = work.id
        XCTAssertFalse(state.saveEdit())
        XCTAssertEqual(state.taskIssue, .edit)
        XCTAssertEqual(state.editingNoteID, original.id)
        XCTAssertEqual(state.editCategoryID, work.id)
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(store.saved, [original])
    }

    func testRemovingSelectedCategoriesFallsBackNewDraftAndRecoversEdit() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let categorized = Note(id: UUID(), text: "Categorized", dayKey: "2026-09-27",
                               createdAt: Date(timeIntervalSince1970: 1), completedAt: nil,
                               categoryID: work.id)
        let general = note("General", day: categorized.dayKey, createdAt: 2)
        let store = FakeNoteRepository(notes: [categorized, general], categories: [work, home])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "New task"
        state.draftCategoryID = work.id
        state.beginEditing(id: general.id)
        state.editDraft = "Edited"
        state.editCategoryID = work.id

        // An unrelated removal and a rename keep both drafts intact.
        XCTAssertTrue(state.removeCategory(id: home.id))
        XCTAssertNotNil(state.renameCategory(id: work.id, name: "Office"))
        XCTAssertEqual(state.draftCategoryID, work.id)
        XCTAssertEqual(state.editingNoteID, general.id)
        XCTAssertEqual(state.editCategoryID, work.id)
        XCTAssertNil(state.refreshNotice)

        XCTAssertTrue(state.removeCategory(id: work.id))
        XCTAssertEqual(state.draft, "New task")
        XCTAssertNil(state.draftCategoryID)
        XCTAssertNil(state.editingNoteID)
        XCTAssertEqual(state.recoveredEdit,
                       DailyNotesState.RecoveredEdit(text: "Edited", categoryID: work.id, categoryName: "Office"))
        XCTAssertNotNil(state.refreshNotice)
        XCTAssertEqual(store.saved.map(\.text), ["Categorized", "General"])
        XCTAssertTrue(store.saved.allSatisfy { $0.categoryID == nil })
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 2))
        XCTAssertTrue(state.addDraft())
        XCTAssertNil(store.saved.last?.categoryID)
    }

    func testRefreshAppliesRemovedCategoryOnlyAfterACompleteRead() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let original = Note(id: UUID(), text: "Original", dayKey: "2026-09-27",
                            createdAt: Date(), completedAt: nil, categoryID: work.id)
        let store = FakeNoteRepository(notes: [original], categories: [work])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "New task"
        state.draftCategoryID = work.id
        state.beginEditing(id: original.id)
        state.editDraft = "Edited"
        // Storage changes outside this state; a failed read must not guess.
        try store.removeCategory(id: work.id)
        store.failSnapshotRead = .count
        state.refresh()
        XCTAssertNil(state.availableCategories)
        XCTAssertEqual(state.draftCategoryID, work.id)
        XCTAssertEqual(state.editingNoteID, original.id)
        XCTAssertEqual(state.editCategoryID, work.id)
        XCTAssertFalse(state.saveEdit())
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(store.saved.map(\.text), ["Original"])
        XCTAssertEqual(state.draftCategoryID, work.id)
        XCTAssertEqual(state.editingNoteID, original.id)

        store.failSnapshotRead = nil
        state.refresh()
        XCTAssertEqual(state.availableCategories, [])
        XCTAssertEqual(state.draft, "New task")
        XCTAssertNil(state.draftCategoryID)
        XCTAssertNil(state.editingNoteID)
        XCTAssertEqual(state.recoveredEdit,
                       DailyNotesState.RecoveredEdit(text: "Edited", categoryID: work.id, categoryName: "Work"))
        XCTAssertNotNil(state.refreshNotice)
    }

    func testRolloverRecoversEditCategoryAndKeepsNewDraftSelection() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let old = Note(id: UUID(), text: "Old", dayKey: "2026-09-27",
                       createdAt: Date(), completedAt: nil, categoryID: work.id)
        let store = FakeNoteRepository(notes: [old], categories: [work, home])
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = makeState(store: store, now: { current })
        state.startup()
        state.draft = "Tomorrow"
        state.draftCategoryID = home.id
        state.beginEditing(id: old.id)
        state.editDraft = "Unsaved"
        state.editCategoryID = home.id
        current = instant("2026-09-28T00:01:00-04:00")
        store.failCount = true
        XCTAssertFalse(state.saveEdit())
        XCTAssertNil(state.editingNoteID)
        XCTAssertNil(state.editCategoryID)
        XCTAssertEqual(state.recoveredEdit,
                       DailyNotesState.RecoveredEdit(text: "Unsaved", categoryID: home.id, categoryName: "Home"))
        XCTAssertEqual(store.saved, [old])
        XCTAssertEqual(state.draftCategoryID, home.id)

        store.failCount = false
        XCTAssertTrue(state.addDraft())
        let added = try XCTUnwrap(store.saved.last)
        XCTAssertEqual(added.text, "Tomorrow")
        XCTAssertEqual(added.dayKey, "2026-09-28")
        XCTAssertEqual(added.categoryID, home.id)
        XCTAssertEqual(store.saved.first, old)
    }

    func testSQLiteBackedCategorizedAddAndCategoryOnlyEditSurviveReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DailyCategoryDrafts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.sqlite")
        let current = instant("2026-09-27T12:00:00-04:00")
        let makeState = {
            DailyNotesState(repositoryFactory: { try SQLiteNoteRepository(databaseURL: url) },
                            day: self.makeDay(now: { current }), notificationCenter: NotificationCenter(),
                            workspaceNotificationCenter: NotificationCenter(),
                            categoryPreferences: self.isolatedCategoryPreferences())
        }
        let state = makeState()
        state.startup()
        let work = try XCTUnwrap(state.createCategory(name: "Work"))
        let home = try XCTUnwrap(state.createCategory(name: "Home"))
        state.draft = "First"
        state.draftCategoryID = work.id
        XCTAssertTrue(state.addDraft())
        // A successful add resets the selection, so this task is General.
        state.draft = "Second"
        XCTAssertTrue(state.addDraft())
        let first = try XCTUnwrap(state.notes.first)
        XCTAssertTrue(state.setCompleted(id: first.id, completed: true))
        state.beginEditing(id: first.id)
        XCTAssertEqual(state.editCategoryID, work.id)
        state.editCategoryID = home.id
        XCTAssertTrue(state.saveEdit())
        let expected = state.notes
        XCTAssertEqual(expected.map(\.text), ["First", "Second"])
        XCTAssertEqual(expected.map(\.categoryID), [home.id, nil])
        XCTAssertEqual(expected.first?.id, first.id)
        XCTAssertEqual(expected.first?.createdAt, first.createdAt)
        XCTAssertEqual(expected.first?.completedAt, current)
        state.stopForTermination()

        let reopened = makeState()
        reopened.startup()
        XCTAssertEqual(reopened.notes, expected)
        XCTAssertEqual(reopened.availableCategories, [work, home])
        XCTAssertEqual(reopened.progress, NoteProgress(completed: 1, total: 2))
    }

    func testGroupsFollowSavedSnapshotAndKeepDailyProgressThroughCategoryChanges() throws {
        let current = instant("2026-09-27T12:00:00-04:00")
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let report = Note(id: UUID(), text: "Report", dayKey: "2026-09-27",
                          createdAt: Date(timeIntervalSince1970: 1), completedAt: current, categoryID: work.id)
        let groceries = note("Groceries", day: report.dayKey, createdAt: 2)
        let reply = Note(id: UUID(), text: "Reply", dayKey: report.dayKey,
                         createdAt: Date(timeIntervalSince1970: 3), completedAt: nil, categoryID: work.id)
        let desk = note("Desk", day: report.dayKey, createdAt: 4, completedAt: current)
        let store = FakeNoteRepository(notes: [report, groceries, reply, desk], categories: [work, home])
        let state = makeState(store: store, now: { current })
        state.startup()
        let daily = NoteProgress(completed: 2, total: 4)

        // Home has no tasks today, so only Work and then General appear.
        XCTAssertEqual(state.availableCategories, [work, home])
        XCTAssertEqual(state.groups.map(\.id), [.category(work.id), .general])
        XCTAssertEqual(groupTexts(state), [["Report", "Reply"], ["Groceries", "Desk"]])
        assertGroupCounts(state, equal: daily)

        // Collapsing changes no group or daily count.
        state.categoryPreferences.setCollapsed(true, for: .category(work.id))
        XCTAssertEqual(state.groups.map(\.progress), [NoteProgress(completed: 1, total: 2),
                                                      NoteProgress(completed: 1, total: 2)])
        assertGroupCounts(state, equal: daily)

        // A reassigned task joins General at its original relative position.
        state.beginEditing(id: reply.id)
        state.editCategoryID = nil
        XCTAssertTrue(state.saveEdit())
        XCTAssertEqual(groupTexts(state), [["Report"], ["Groceries", "Reply", "Desk"]])
        assertGroupCounts(state, equal: daily)

        XCTAssertNotNil(state.renameCategory(id: work.id, name: "Office"))
        XCTAssertEqual(state.groups.first?.id, .category(work.id))
        XCTAssertEqual(state.groups.first?.name, "Office")
        XCTAssertTrue(state.categoryPreferences.isCollapsed(.category(work.id)))

        XCTAssertTrue(state.removeCategory(id: work.id))
        XCTAssertEqual(state.groups.map(\.id), [.general])
        XCTAssertEqual(groupTexts(state), [["Report", "Groceries", "Reply", "Desk"]])
        assertGroupCounts(state, equal: daily)

        state.refresh()
        XCTAssertEqual(groupTexts(state), [["Report", "Groceries", "Reply", "Desk"]])
    }

    func testOnlyASavedNewTaskFromTodaySetsTheLastUsedCategory() throws {
        let current = instant("2026-09-27T12:00:00-04:00")
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let original = note("Original", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [original], categories: [work, home])
        let defaults = isolatedDefaults()
        let state = makeState(store: store, now: { current },
                              preferences: TaskCategoryPreferences(userDefaults: defaults))
        state.startup()
        let preferences = state.categoryPreferences
        XCTAssertNil(preferences.lastUsedCategoryID)

        state.draft = "First"
        state.draftCategoryID = home.id
        XCTAssertTrue(state.addDraft())
        XCTAssertEqual(preferences.lastUsedCategoryID, home.id)
        XCTAssertNil(state.draftCategoryID)

        // Cancelled, rejected, and unavailable drafts leave it unchanged.
        state.draft = "Cancelled"
        state.draftCategoryID = work.id
        state.cancelDraft()
        state.draft = "Rejected"
        state.draftCategoryID = work.id
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        store.failWrite = nil
        state.draftCategoryID = UUID()
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(preferences.lastUsedCategoryID, home.id)

        // Edits and Quick Add's General saves are not new-task choices.
        state.cancelDraft()
        state.beginEditing(id: original.id)
        state.editCategoryID = work.id
        XCTAssertTrue(state.saveEdit())
        XCTAssertEqual(state.add(text: "Captured"), .added)
        XCTAssertEqual(preferences.lastUsedCategoryID, home.id)

        state.draft = "General task"
        XCTAssertTrue(state.addDraft())
        XCTAssertNil(preferences.lastUsedCategoryID)
        XCTAssertNil(defaults.object(forKey: TaskCategoryPreferences.lastUsedCategoryIDKey))

        state.draft = "Work task"
        state.draftCategoryID = work.id
        XCTAssertTrue(state.addDraft())
        XCTAssertEqual(TaskCategoryPreferences(userDefaults: defaults).lastUsedCategoryID, work.id)
    }

    func testNewDraftStartsFromSavedLastUsedCategoryOrGeneral() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let store = FakeNoteRepository(categories: [work])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let preferences = state.categoryPreferences

        // No remembered category starts in General, even with saved categories.
        state.startNewDraft()
        XCTAssertNil(state.draftCategoryID)

        preferences.rememberLastUsed(work.id)
        state.startNewDraft()
        XCTAssertEqual(state.draftCategoryID, work.id)
        state.draft = "General task"
        state.draftCategoryID = nil
        XCTAssertTrue(state.addDraft())
        XCTAssertNil(store.saved.last?.categoryID)

        // A remembered ID missing from the catalog never becomes a selection.
        preferences.rememberLastUsed(UUID())
        state.draftCategoryID = work.id
        state.startNewDraft()
        XCTAssertNil(state.draftCategoryID)

        // Starting a new draft never changes an active edit's selection.
        let task = try XCTUnwrap(store.saved.last)
        preferences.rememberLastUsed(work.id)
        state.beginEditing(id: task.id)
        state.startNewDraft()
        XCTAssertNil(state.editCategoryID)
        XCTAssertEqual(state.draftCategoryID, work.id)
    }

    func testSavedAddOrReassignmentExpandsOnlyItsCollapsedDestination() throws {
        let current = instant("2026-09-27T12:00:00-04:00")
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let general = note("General task", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [general], categories: [work, home])
        let state = makeState(store: store, now: { current })
        state.startup()
        let preferences = state.categoryPreferences
        let all: Set<TaskGroupID> = [.category(work.id), .category(home.id), .general]
        for group in all { preferences.setCollapsed(true, for: group) }

        // Rejected, unavailable, and Quick Add saves change no disclosure.
        state.draft = "Rejected"
        state.draftCategoryID = work.id
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        store.failWrite = nil
        XCTAssertEqual(state.add(text: "Captured"), .added)
        XCTAssertEqual(preferences.collapsedGroupIDs, all)

        XCTAssertTrue(state.addDraft())
        XCTAssertEqual(preferences.collapsedGroupIDs, [.category(home.id), .general])
        let saved = try XCTUnwrap(state.notes.last)
        XCTAssertEqual(saved.categoryID, work.id)

        // A text-only edit leaves its own collapsed group alone.
        state.beginEditing(id: general.id)
        state.editDraft = "General task, edited"
        XCTAssertTrue(state.saveEdit())
        XCTAssertTrue(preferences.isCollapsed(.general))

        state.beginEditing(id: general.id)
        state.editCategoryID = home.id
        store.failWrite = .edit
        XCTAssertFalse(state.saveEdit())
        XCTAssertTrue(preferences.isCollapsed(.category(home.id)))
        store.failWrite = nil
        XCTAssertTrue(state.saveEdit())
        XCTAssertEqual(preferences.collapsedGroupIDs, [.general])
        XCTAssertEqual(groupTexts(state), [["Rejected"], ["General task, edited"], ["Captured"]])

        // Moving a task back into a collapsed General shows General too.
        state.beginEditing(id: saved.id)
        state.editCategoryID = nil
        XCTAssertTrue(state.saveEdit())
        XCTAssertEqual(preferences.collapsedGroupIDs, [])
    }

    func testCategoryPreferencesForgetCategoriesOnlyAfterACompleteReadOrCommittedRemoval() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let missing = UUID()
        let defaults = isolatedDefaults()
        let preferences = TaskCategoryPreferences(userDefaults: defaults)
        preferences.rememberLastUsed(missing)
        let collapsed: Set<TaskGroupID> = [.category(work.id), .category(home.id), .category(missing), .general]
        for group in collapsed { preferences.setCollapsed(true, for: group) }
        let store = FakeNoteRepository(categories: [work, home])
        store.failSnapshotRead = .categories
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") },
                              preferences: preferences)

        // A failed read cannot tell which categories are gone.
        state.startup()
        XCTAssertNil(state.availableCategories)
        XCTAssertEqual(preferences.lastUsedCategoryID, missing)
        XCTAssertEqual(preferences.collapsedGroupIDs, collapsed)

        // A complete read keeps every saved category and General, even with no tasks today.
        store.failSnapshotRead = nil
        state.refresh()
        XCTAssertEqual(state.groups, [])
        XCTAssertNil(preferences.lastUsedCategoryID)
        XCTAssertEqual(preferences.collapsedGroupIDs, [.category(work.id), .category(home.id), .general])

        // Removal forgets a category only after storage commits it.
        preferences.rememberLastUsed(home.id)
        store.failCategoryCommand = .remove
        XCTAssertFalse(state.removeCategory(id: home.id))
        XCTAssertEqual(preferences.lastUsedCategoryID, home.id)
        XCTAssertTrue(preferences.isCollapsed(.category(home.id)))
        store.failCategoryCommand = nil
        XCTAssertTrue(state.removeCategory(id: home.id))
        let reopened = TaskCategoryPreferences(userDefaults: defaults)
        XCTAssertNil(reopened.lastUsedCategoryID)
        XCTAssertEqual(reopened.collapsedGroupIDs, [.category(work.id), .general])
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
        for failure in FakeSnapshotRead.allCases {
            store.failSnapshotRead = failure
            state.refresh()
            try await waitForStatusTitle("—", controller: controller)
            XCTAssertEqual(state.notes, [saved])
            XCTAssertNil(state.availableCategories)
            XCTAssertTrue(controller.statusItem?.button?.accessibilityLabel()?.contains("unavailable") == true)
            store.failSnapshotRead = nil
            store.failWrite = nil
            state.refresh()
            try await waitForStatusTitle("0/1", controller: controller)
        }
    }

    func testStatusItemRefreshesClosedWindowDayAndExactMultiDigitCounts() async throws {
        let saved = (0..<12).map { note("Task \($0)", day: "2026-09-27", createdAt: Double($0), completedAt: Date()) }
        let store = FakeNoteRepository(notes: saved)
        var current = instant("2026-09-27T23:59:00-04:00")
        let center = NotificationCenter()
        let state = DailyNotesState(repositoryFactory: { store }, day: makeDay(now: { current }),
                                    notificationCenter: center, workspaceNotificationCenter: NotificationCenter(),
                                    categoryPreferences: isolatedCategoryPreferences())
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
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        state.beginEditing(id: previous.id)
        current = instant("2026-09-28T00:01:00-04:00")
        state.refreshIfDayChanged()
        XCTAssertEqual(state.todayKey, "2026-09-28")
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertEqual(state.progress, NoteProgress(completed: 0, total: 0))
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        XCTAssertEqual(state.draft, "Keep this draft")
        XCTAssertEqual(state.taskIssue, .add)
        XCTAssertNil(state.editingNoteID)
        XCTAssertEqual(state.editDraft, "")
    }

    func testCalendarNotificationRefreshesObservableDay() async throws {
        let category = try TaskCategory(name: "Reusable", creationOrder: 0)
        let store = FakeNoteRepository(categories: [category])
        let center = NotificationCenter()
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = DailyNotesState(repositoryFactory: { store }, day: makeDay(now: { current }),
                                    notificationCenter: center, categoryPreferences: isolatedCategoryPreferences())
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
        XCTAssertEqual(state.availableCategories, [category])
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
        notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter(),
        categoryPreferences: isolatedCategoryPreferences())

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
                notificationCenter: NotificationCenter(),
                categoryPreferences: self.isolatedCategoryPreferences()
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

    func testSQLiteBackedTextEditPreservesCategoryThroughCompletionRefreshAndReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DailyNotesStateCategories-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("notes.sqlite")
        let current = instant("2026-09-27T12:00:00-04:00")
        let original: Note
        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            let category = try store.createCategory(name: "Work")
            original = Note(id: UUID(), text: "Original", dayKey: "2026-09-27",
                            createdAt: current, completedAt: nil, categoryID: category.id)
            try store.add(original)
        }
        let makeState = {
            DailyNotesState(repositoryFactory: { try SQLiteNoteRepository(databaseURL: databaseURL) },
                            day: self.makeDay(now: { current }),
                            notificationCenter: NotificationCenter(),
                            workspaceNotificationCenter: NotificationCenter(),
                            categoryPreferences: self.isolatedCategoryPreferences())
        }
        do {
            let state = makeState()
            state.startup()
            XCTAssertEqual(state.notes, [original])
            XCTAssertTrue(state.setCompleted(id: original.id, completed: true))
            state.beginEditing(id: original.id)
            state.editDraft = "  Updated  "
            XCTAssertTrue(state.saveEdit())
            state.refresh()
            XCTAssertEqual(state.notes.first?.categoryID, original.categoryID)
            XCTAssertEqual(state.notes.first?.text, "Updated")
            XCTAssertEqual(state.progress, NoteProgress(completed: 1, total: 1))
        }
        let reopened = makeState()
        reopened.startup()
        XCTAssertEqual(reopened.notes, [
            Note(id: original.id, text: "Updated", dayKey: original.dayKey,
                 createdAt: original.createdAt, completedAt: current, categoryID: original.categoryID)
        ])
        XCTAssertTrue(reopened.setCompleted(id: original.id, completed: false))
        reopened.refresh()
        XCTAssertEqual(reopened.notes.first?.categoryID, original.categoryID)
        XCTAssertEqual(reopened.progress, NoteProgress(completed: 0, total: 1))
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

    func testWakeAndClockNotificationsRefreshWithoutOpeningWindow() async throws {
        let old = note("Yesterday", day: "2026-09-27", createdAt: 1)
        let category = try TaskCategory(name: "Reusable", creationOrder: 0)
        let store = FakeNoteRepository(notes: [old], categories: [category])
        let center = NotificationCenter()
        let workspace = NotificationCenter()
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = DailyNotesState(repositoryFactory: { store }, day: makeDay(now: { current }),
                                    notificationCenter: center, workspaceNotificationCenter: workspace,
                                    categoryPreferences: isolatedCategoryPreferences())
        state.startup()
        for (eventCenter, name) in [(workspace, NSWorkspace.didWakeNotification),
                                    (center, Notification.Name.NSSystemClockDidChange)] {
            let changed = expectation(description: "Closed-window event refreshed day")
            withObservationTracking { _ = state.todayKey } onChange: { changed.fulfill() }
            current = current.addingTimeInterval(86400)
            store.savedCategories.append(try TaskCategory(name: "Day \(current.timeIntervalSince1970)",
                                                         creationOrder: Int64(store.savedCategories.count)))
            eventCenter.post(name: name, object: nil)
            await fulfillment(of: [changed], timeout: 2)
            XCTAssertEqual(state.todayKey, makeDay(now: { current }).keys().today)
            XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 0))
            XCTAssertEqual(state.availableCategories, store.savedCategories)
        }
    }

    func testTimeZoneNotificationRecalculatesDayWithoutReassigningSavedRows() async throws {
        let saved = note("Assigned day", day: "2026-09-26", createdAt: 1)
        let category = try TaskCategory(name: "Reusable", creationOrder: 0)
        let store = FakeNoteRepository(notes: [saved], categories: [category])
        let center = NotificationCenter()
        var zone = TimeZone(identifier: "America/Toronto")!
        let day = NoteDay(now: { self.instant("2026-09-27T00:30:00Z") }, timeZone: { zone })
        let state = DailyNotesState(repositoryFactory: { store }, day: day,
                                    notificationCenter: center, workspaceNotificationCenter: NotificationCenter(),
                                    categoryPreferences: isolatedCategoryPreferences())
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
        XCTAssertEqual(state.availableCategories, [category])
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
            notificationCenter: center, workspaceNotificationCenter: workspace,
            categoryPreferences: isolatedCategoryPreferences())
        state?.startup()
        weak var released = state
        state = nil
        XCTAssertNil(released)
        store.onRead = { _ in XCTFail("Released state should not read") }
        center.post(name: .NSCalendarDayChanged, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        await Task.yield()
    }

    private func makeState(store: FakeNoteRepository, now: @escaping () -> Date,
                           preferences: TaskCategoryPreferences? = nil) -> DailyNotesState {
        DailyNotesState(repositoryFactory: { store }, day: makeDay(now: now),
                        notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter(),
                        categoryPreferences: preferences ?? isolatedCategoryPreferences())
    }

    private func groupTexts(_ state: DailyNotesState) -> [[String]] {
        state.groups.map { $0.notes.map(\.text) }
    }

    private func assertGroupCounts(_ state: DailyNotesState, equal daily: NoteProgress,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let groups = state.groups
        XCTAssertEqual(state.availableProgress, daily, file: file, line: line)
        XCTAssertEqual(NoteProgress(completed: groups.map(\.progress.completed).reduce(0, +),
                                    total: groups.map(\.progress.total).reduce(0, +)),
                       daily, file: file, line: line)
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

private enum FakeSnapshotRead: CaseIterable {
    case categories, notes, count
}

private final class FakeNoteRepository: NoteRepository {
    var saved: [Note]
    var savedCategories: [TaskCategory]
    var onRead: ((String) -> Void)?
    var onCategoryRead: (() -> Void)?
    var onCategoryWrite: (() -> Void)?
    var uncheckedNotes: [Note]?
    var failSnapshotRead: FakeSnapshotRead?
    var failCategoryCommand: CategoryCommandIssue?
    var readAttempts = 0
    var categoryWriteAttempts = 0
    var failCount = false
    var failWrite: DailyNotesIssue?

    init(notes: [Note] = [], categories: [TaskCategory] = []) {
        saved = notes
        savedCategories = categories
    }

    func categories() throws -> [TaskCategory] {
        readAttempts += 1
        onCategoryRead?()
        if failSnapshotRead == .categories { throw FakeFailure.failed }
        return savedCategories.sorted { $0.creationOrder < $1.creationOrder }
    }

    func createCategory(name: String) throws -> TaskCategory {
        categoryWriteAttempts += 1
        if failCategoryCommand == .create { throw FakeFailure.failed }
        let name = try TaskCategoryName.validate(name)
        guard !savedCategories.contains(where: { $0.nameKey == TaskCategoryName.key(for: name) }) else {
            throw TaskCategoryRepositoryError.duplicateName
        }
        let next = (savedCategories.map(\.creationOrder).max() ?? -1).addingReportingOverflow(1)
        guard !next.overflow else { throw TaskCategoryRepositoryError.orderExhausted }
        let category = try TaskCategory(name: name, creationOrder: next.partialValue)
        savedCategories.append(category)
        onCategoryWrite?()
        return category
    }

    func renameCategory(id: UUID, name: String) throws -> TaskCategory {
        categoryWriteAttempts += 1
        if failCategoryCommand == .rename { throw FakeFailure.failed }
        let name = try TaskCategoryName.validate(name)
        let original = try requireCategory(id)
        guard !savedCategories.contains(where: { $0.id != id && $0.nameKey == TaskCategoryName.key(for: name) }) else {
            throw TaskCategoryRepositoryError.duplicateName
        }
        let category = try TaskCategory(id: id, name: name, creationOrder: original.creationOrder)
        savedCategories[savedCategories.firstIndex(where: { $0.id == id })!] = category
        onCategoryWrite?()
        return category
    }

    func categoryUsageCount(id: UUID) throws -> Int {
        if failCategoryCommand == .usage { throw FakeFailure.failed }
        _ = try requireCategory(id)
        return saved.count { $0.categoryID == id }
    }

    func removeCategory(id: UUID) throws {
        categoryWriteAttempts += 1
        if failCategoryCommand == .remove { throw FakeFailure.failed }
        _ = try requireCategory(id)
        saved = saved.map { note in
            Note(id: note.id, text: note.text, dayKey: note.dayKey,
                 createdAt: note.createdAt, completedAt: note.completedAt,
                 categoryID: note.categoryID == id ? nil : note.categoryID)
        }
        savedCategories.removeAll { $0.id == id }
        onCategoryWrite?()
    }

    func notes(for dayKey: String) throws -> [Note] {
        readAttempts += 1
        onRead?(dayKey)
        if failSnapshotRead == .notes { throw FakeFailure.failed }
        if let uncheckedNotes { return uncheckedNotes }
        let notes = saved.filter { $0.dayKey == dayKey }
        for note in notes {
            if let id = note.categoryID { _ = try requireCategory(id) }
        }
        return notes
    }

    func incompleteCount(for dayKey: String) throws -> Int {
        readAttempts += 1
        if failCount || failSnapshotRead == .count { throw FakeFailure.failed }
        return saved.count { $0.dayKey == dayKey && !$0.isCompleted }
    }

    func add(_ note: Note) throws {
        if failWrite == .add { throw FakeFailure.failed }
        if let id = note.categoryID { _ = try requireCategory(id) }
        guard !saved.contains(where: { $0.id == note.id }) else { throw FakeFailure.failed }
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

    func update(id: UUID, text: String, categoryID: UUID?) throws {
        if failWrite == .edit { throw FakeFailure.failed }
        if let categoryID { _ = try requireCategory(categoryID) }
        try mutate(id: id) { note in
            Note(id: note.id, text: text, dayKey: note.dayKey,
                 createdAt: note.createdAt, completedAt: note.completedAt,
                 categoryID: categoryID)
        }
    }

    private func requireCategory(_ id: UUID) throws -> TaskCategory {
        guard let category = savedCategories.first(where: { $0.id == id }) else {
            throw TaskCategoryRepositoryError.notFound(id)
        }
        return category
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
