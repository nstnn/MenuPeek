import AppKit
import CoreServices
import SwiftUI
import XCTest
@testable import MenuPocket

final class AppConfigurationTests: XCTestCase {
    func testHostedApplicationMetadata() throws {
        // Read the built host, so this checks the effective Xcode configuration.
        let info = try XCTUnwrap(Bundle.main.infoDictionary)

        XCTAssertEqual(Bundle.main.bundleIdentifier, "local.menupocket.app")
        XCTAssertEqual(info["CFBundleShortVersionString"] as? String, "0.1.0")
        XCTAssertEqual(info["CFBundleVersion"] as? String, "1")
        XCTAssertEqual(info["CFBundleDevelopmentRegion"] as? String, "en")
        XCTAssertEqual(info["LSMinimumSystemVersion"] as? String, "14.0")
        XCTAssertEqual(info["LSUIElement"] as? Bool, false)
    }

    @MainActor
    func testBrowserRoutesRetainDraftsAndBlockEditingDeletionAndManager() throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        fixture.launch()
        let controller = try XCTUnwrap(fixture.delegate.taskWindowController)
        let window = try XCTUnwrap(controller.window)
        let presentation = controller.presentation
        fixture.state.draft = "Pending Today draft"
        XCTAssertFalse(fixture.state.addDraft())
        XCTAssertEqual(fixture.state.issue, .add)
        XCTAssertTrue(presentation.showHistory(state: fixture.state))
        XCTAssertEqual(presentation.route, .history)
        XCTAssertTrue(presentation.showUnfinished(state: fixture.state))
        XCTAssertEqual(presentation.route, .unfinished)
        presentation.backToHistory(state: fixture.state)
        XCTAssertTrue(presentation.showToday(state: fixture.state))
        XCTAssertEqual(fixture.state.draft, "Pending Today draft")
        XCTAssertEqual(fixture.state.issue, .add)
        XCTAssertTrue(controller.window === window)
        fixture.repository.allowAdd = true
        XCTAssertTrue(fixture.state.addDraft())
        let note = try XCTUnwrap(fixture.state.notes.first)
        fixture.state.beginEditing(id: note.id)
        for entry in [TaskWindowPresentation.HistoryEntry.calendar, .yesterday] {
            XCTAssertFalse(presentation.showHistory(state: fixture.state, entry: entry))
        }
        fixture.state.cancelEditing()
        presentation.requestDeletion(id: note.id, state: fixture.state)
        XCTAssertFalse(presentation.showHistory(state: fixture.state))
        XCTAssertFalse(presentation.showHistory(state: fixture.state, entry: .yesterday))
        presentation.cancelDeletion()
        XCTAssertTrue(presentation.showCategoryManager(state: fixture.state))
        XCTAssertFalse(presentation.showHistory(state: fixture.state))
        XCTAssertFalse(presentation.showHistory(state: fixture.state, entry: .yesterday))
        presentation.dismissCategoryManager()
        XCTAssertTrue(presentation.showHistory(state: fixture.state, entry: .yesterday))
        XCTAssertEqual(presentation.historyState?.selectedDay, try fixture.state.yesterdayForHistory())
        XCTAssertEqual(presentation.historyState?.filter, .unfinished)
    }

    @MainActor
    func testUnfinishedIndexOpensFilteredDayDetailAndKeepsPagesOnReturn() throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        let today = NoteDay().keys().today
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        func note(_ text: String, _ dayKey: String, done: Bool) -> Note {
            Note(id: UUID(), text: text, dayKey: dayKey, createdAt: created, completedAt: done ? created : nil)
        }
        fixture.repository.saved = [
            note("Old open", "2025-01-15", done: false), note("Old done", "2025-01-15", done: true),
            note("Old second", "2025-01-15", done: true), note("Finished day", "2025-02-03", done: true),
            note("Today open", today, done: false),
        ]
        fixture.launch()
        let presentation = try XCTUnwrap(fixture.delegate.taskWindowController).presentation
        fixture.state.draft = "Keep this draft"
        XCTAssertTrue(presentation.showHistory(state: fixture.state))
        XCTAssertTrue(presentation.showUnfinished(state: fixture.state))
        let unfinished = try XCTUnwrap(presentation.unfinishedState)
        // Only past days with unfinished work, whole-day counts, Today excluded.
        XCTAssertEqual(unfinished.summaries?.map(\.dayKey), ["2025-01-15"])
        XCTAssertEqual(unfinished.summaries?.first?.progress, NoteProgress(completed: 2, total: 3))
        XCTAssertFalse(presentation.showUnfinishedDay(try GregorianDay(key: today), state: fixture.state))
        XCTAssertFalse(presentation.showUnfinishedDay(try GregorianDay(key: "2025-02-03"), state: fixture.state))
        XCTAssertEqual(presentation.route, .unfinished)

        let generation = unfinished.generation
        let day = try GregorianDay(key: "2025-01-15")
        XCTAssertTrue(presentation.showUnfinishedDay(day, state: fixture.state))
        XCTAssertEqual(presentation.route, .unfinishedDay)
        let history = try XCTUnwrap(presentation.historyState)
        XCTAssertEqual(history.selectedDay, day)
        XCTAssertEqual(history.filter, .unfinished)
        XCTAssertEqual(history.progress, NoteProgress(completed: 2, total: 3))
        XCTAssertEqual(history.detailGroups.flatMap(\.visibleNotes).map(\.text), ["Old open"])
        XCTAssertNil(unfinished.selectionIssue)

        presentation.backToUnfinished(state: fixture.state)
        XCTAssertEqual(presentation.route, .unfinished)
        XCTAssertEqual(unfinished.generation, generation)
        XCTAssertEqual(unfinished.summaries?.map(\.dayKey), ["2025-01-15"])

        // A saved change while viewing the day resets the index and explains it.
        XCTAssertTrue(presentation.showUnfinishedDay(day, state: fixture.state))
        fixture.repository.saved[0] = note("Old open", "2025-01-15", done: true)
        fixture.state.refresh()
        presentation.refreshBrowser(state: fixture.state)
        XCTAssertEqual(history.progress, NoteProgress(completed: 3, total: 3))
        XCTAssertEqual(unfinished.selectionIssue, .noUnfinishedTasks)
        XCTAssertGreaterThan(unfinished.generation, generation)
        presentation.backToUnfinished(state: fixture.state)
        XCTAssertEqual(unfinished.summaries, [])
        presentation.backToHistory(state: fixture.state)
        XCTAssertEqual(presentation.route, .history)
        XCTAssertTrue(presentation.showToday(state: fixture.state))
        XCTAssertEqual(fixture.state.draft, "Keep this draft")
        XCTAssertEqual(fixture.state.todayKey, today)
    }

    @MainActor
    func testHistoryBelongsToTodayAndListSelectionLeavesIt() throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        fixture.launch()
        let controller = try XCTUnwrap(fixture.delegate.taskWindowController)
        let presentation = controller.presentation
        XCTAssertTrue(presentation.selectDestination(.later, state: fixture.state))
        XCTAssertFalse(presentation.canBrowse(state: fixture.state))
        XCTAssertFalse(presentation.showHistory(state: fixture.state))
        XCTAssertEqual(presentation.route, .today)

        XCTAssertTrue(presentation.selectDestination(.today, state: fixture.state))
        XCTAssertTrue(presentation.showHistory(state: fixture.state))
        XCTAssertFalse(presentation.showCategoryManager(state: fixture.state))
        XCTAssertTrue(presentation.selectDestination(.later, state: fixture.state))
        XCTAssertEqual(presentation.route, .today)
        XCTAssertEqual(presentation.selectedDestination, .later)

        XCTAssertTrue(presentation.selectDestination(.today, state: fixture.state))
        XCTAssertTrue(presentation.showHistory(state: fixture.state))
        XCTAssertTrue(presentation.showUnfinished(state: fixture.state))
        // Selecting the current list from a child screen returns to it.
        XCTAssertTrue(presentation.selectDestination(.today, state: fixture.state))
        XCTAssertEqual(presentation.route, .today)
        XCTAssertEqual(presentation.selectedDestination, .today)
    }

    @MainActor
    func testBrowserNativeTodayCommandsWindowReuseAndTermination() async throws {
        let fixture = try AppLifecycleFixture(context: .login)
        defer { fixture.cleanup() }
        fixture.launch()
        XCTAssertNil(fixture.delegate.taskWindowController)
        fixture.delegate.showTasks()
        let controller = try XCTUnwrap(fixture.delegate.taskWindowController)
        let window = try XCTUnwrap(controller.window)
        let presentation = controller.presentation
        fixture.state.draft = "Keep category and text"
        let category = try XCTUnwrap(fixture.state.createCategory(name: "Work"))
        fixture.state.draftCategoryID = category.id
        XCTAssertTrue(presentation.showHistory(state: fixture.state))
        XCTAssertTrue(presentation.showUnfinished(state: fixture.state))
        fixture.delegate.showSettings()
        XCTAssertEqual(presentation.route, .unfinished)
        window.close()
        fixture.delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true)
        XCTAssertEqual(presentation.route, .today)
        XCTAssertTrue(controller.window === window)
        XCTAssertEqual(fixture.state.draftCategoryID, category.id)
        XCTAssertTrue(presentation.showHistory(state: fixture.state))
        fixture.delegate.addTask()
        XCTAssertEqual(presentation.route, .today)
        XCTAssertNotNil(presentation.newTaskRequestID)
        XCTAssertEqual(fixture.state.draft, "Keep category and text")
        XCTAssertTrue(fixture.state.notes.isEmpty)
        presentation.consumeNewTaskRequest(in: .today)
        XCTAssertTrue(presentation.showHistory(state: fixture.state))
        let revision = fixture.state.historyRevision
        fixture.delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        fixture.delegate.showTasks()
        controller.showTasks()
        presentation.refreshBrowser(state: fixture.state)
        XCTAssertFalse(presentation.showToday(state: fixture.state))
        XCTAssertFalse(presentation.showHistory(state: fixture.state))
        XCTAssertFalse(presentation.requestNewTask(state: fixture.state))
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(fixture.state.historyRevision, revision)
    }

    @MainActor
    func testBrowserRetainsMountedComposerAndScrollThroughNativeAddCommand() async throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        fixture.repository.saved = (1...60).map {
            Note(id: UUID(), text: "Retained row \($0)", dayKey: NoteDay().keys().today,
                 createdAt: Date(timeIntervalSince1970: 1_790_000_000), completedAt: nil)
        }
        fixture.launch()
        let controller = try XCTUnwrap(fixture.delegate.taskWindowController)
        let window = try XCTUnwrap(controller.window)
        let menu = try XCTUnwrap(NSApplication.shared.mainMenu)
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("n", keyCode: 45)))
        let editor = try await focusedEditor(in: window)
        editor.insertText("Mounted composer draft", replacementRange: NSRange(location: 0, length: 0))
        func taskScroll(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, (scroll.documentView?.frame.height ?? 0) > 800 { return scroll }
            return view.subviews.lazy.compactMap { taskScroll(in: $0) }.first
        }
        let scroll = try XCTUnwrap(taskScroll(in: XCTUnwrap(window.contentView)))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 650))
        scroll.reflectScrolledClipView(scroll.contentView)
        let originalOffset = scroll.contentView.bounds.origin.y
        XCTAssertGreaterThan(originalOffset, 100)
        XCTAssertTrue(controller.presentation.showHistory(state: fixture.state))
        XCTAssertTrue(controller.presentation.showUnfinished(state: fixture.state))
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(controller.presentation.showToday(state: fixture.state))
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(scroll.contentView.bounds.origin.y, originalOffset, accuracy: 1)
        XCTAssertEqual(fixture.state.draft, "Mounted composer draft")
        XCTAssertTrue(controller.presentation.showHistory(state: fixture.state))
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("n", keyCode: 45)))
        let restoredEditor = try await focusedEditor(in: window)
        XCTAssertTrue(editor === restoredEditor)
        XCTAssertEqual(restoredEditor.string, "Mounted composer draft")
        XCTAssertEqual(controller.presentation.route, .today)
        XCTAssertEqual(fixture.repository.saved.count, 60)
    }

    @MainActor
    func testBrowserRefreshVisibilityAndMissingScrollAnchorFallback() async throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        fixture.launch()
        let controller = try XCTUnwrap(fixture.delegate.taskWindowController)
        let presentation = controller.presentation
        let category = try XCTUnwrap(fixture.state.createCategory(name: "Removed group"))
        presentation.todayScrollAnchor = TaskGroupID(categoryID: category.id)
        XCTAssertTrue(presentation.showHistory(state: fixture.state))
        let history = try XCTUnwrap(presentation.historyState)
        XCTAssertNotNil(history.monthSummaries)
        controller.window?.close()
        fixture.state.refresh()
        // Observation forwards settled revisions while the retained window is hidden.
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(history.monthDirty)
        XCTAssertNil(history.monthSummaries)
        XCTAssertTrue(fixture.state.removeCategory(id: category.id))
        controller.showTasks()
        XCTAssertEqual(presentation.todayScrollAnchor, fixture.state.groups.first?.id)
        XCTAssertNotNil(presentation.todayScrollRestoreID)
        XCTAssertTrue(history.monthDirty)
        XCTAssertTrue(presentation.showHistory(state: fixture.state))
        XCTAssertFalse(history.monthDirty)
        XCTAssertNotNil(history.monthSummaries)
        XCTAssertTrue(presentation.showUnfinished(state: fixture.state))
        let unfinished = try XCTUnwrap(presentation.unfinishedState)
        let generation = unfinished.generation
        fixture.state.refresh()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertGreaterThan(unfinished.generation, generation)
        XCTAssertFalse(unfinished.dirty)
        XCTAssertTrue(history.monthDirty)
    }

    @MainActor
    func testTaskWindowReusesWindowAndStateAcrossCloseMinimizeAndDockReopen() async throws {
        let suite = "local.menupocket.tests.TaskWindow.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = DailyNotesState(repositoryFactory: { throw CocoaError(.fileReadNoSuchFile) })
        state.draft = "Retain this draft"
        let delegate = AppDelegate(model: AppModel(store: PreferencesStore(userDefaults: defaults)),
                                   dailyNotesState: state,
                                   onboardingStore: UserDefaultsOnboardingStore(userDefaults: defaults))
        XCTAssertNil(delegate.taskWindowController)
        delegate.showTasks()
        let controller = try XCTUnwrap(delegate.taskWindowController)
        let window = try XCTUnwrap(controller.window)
        defer {
            window.close()
            delegate.settingsWindowController?.window?.close()
        }
        let host = try XCTUnwrap(window.contentViewController as? NSHostingController<TaskBrowserView>)
        XCTAssertTrue(host.rootView.state === state)
        XCTAssertTrue(controller.state === state)
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.contentMinSize, TaskWindowController.minimumContentSize)
        delegate.showTasks()
        XCTAssertTrue(delegate.taskWindowController === controller)
        window.close()
        XCTAssertFalse(window.isVisible)
        delegate.showTasks()
        XCTAssertTrue(controller.window === window)
        XCTAssertTrue(window.isVisible)
        window.miniaturize(nil)
        // Both animations can finish after the synchronous AppKit call returns.
        for _ in 0..<50 {
            if window.isMiniaturized { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(window.isMiniaturized)
        delegate.showTasks()
        for _ in 0..<50 {
            if !window.isMiniaturized && window.isVisible { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(window.isMiniaturized)
        XCTAssertTrue(window.isVisible)
        window.close()
        delegate.showSettings()
        XCTAssertTrue(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true))
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(delegate.taskWindowController === controller)
        XCTAssertEqual(state.draft, "Retain this draft")
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    @MainActor
    func testTaskWindowPresentationRefreshesSavedSnapshotAndRetriesFailedRead() throws {
        let store = TaskWindowReadFixture()
        let instant = Date(timeIntervalSince1970: 1_790_000_000)
        let day = NoteDay(now: { instant })
        let state = DailyNotesState(repositoryFactory: { store }, day: day,
                                   notificationCenter: NotificationCenter(),
                                   workspaceNotificationCenter: NotificationCenter(),
                                   categoryPreferences: isolatedCategoryPreferences())
        let controller = TaskWindowController(state: state, onSettings: {})
        defer { controller.window?.close() }
        controller.showTasks()
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 0))
        let note = Note(id: UUID(), text: "Saved task", dayKey: day.keys().today,
                        createdAt: instant, completedAt: nil)
        store.saved = [note]
        controller.window?.close()
        controller.showTasks()
        XCTAssertEqual(state.notes, [note])
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 1))
        store.failRead = true
        controller.showTasks()
        XCTAssertNil(state.availableProgress)
        XCTAssertEqual(state.notes, [note])
        store.failRead = false
        controller.showTasks()
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 1))
    }

    @MainActor
    func testClosingTaskWindowCancelsDeletionButRetainsCurrentDayEditAndNewDraft() throws {
        let store = TaskWindowReadFixture()
        let instant = Date(timeIntervalSince1970: 1_790_000_000)
        let day = NoteDay(now: { instant })
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let note = Note(id: UUID(), text: "Original task", dayKey: day.keys().today,
                        createdAt: instant, completedAt: nil, categoryID: work.id)
        store.saved = [note]
        store.savedCategories = [work, home]
        let state = DailyNotesState(repositoryFactory: { store }, day: day,
                                   notificationCenter: NotificationCenter(),
                                   workspaceNotificationCenter: NotificationCenter(),
                                   categoryPreferences: isolatedCategoryPreferences())
        let controller = TaskWindowController(state: state, onSettings: {})
        defer { controller.window?.close() }
        controller.showTasks()
        state.draft = "Separate new draft"
        state.draftCategoryID = home.id
        controller.presentation.requestDeletion(id: note.id, state: state)
        XCTAssertNotNil(controller.presentation.deletionTarget)
        controller.window?.close()
        XCTAssertNil(controller.presentation.deletionTarget)
        XCTAssertFalse(controller.presentation.confirmDeletion(state: state))
        controller.showTasks()
        state.beginEditing(id: note.id)
        XCTAssertEqual(state.editCategoryID, work.id)
        state.editDraft = "Retain this edit"
        state.editCategoryID = nil
        XCTAssertFalse(controller.presentation.requestDeletion(id: note.id, state: state))
        controller.window?.close()
        XCTAssertNil(controller.presentation.deletionTarget)
        XCTAssertFalse(controller.presentation.confirmDeletion(state: state))
        controller.showTasks()
        XCTAssertEqual(state.editingNoteID, note.id)
        XCTAssertEqual(state.editDraft, "Retain this edit")
        XCTAssertNil(state.editCategoryID)
        XCTAssertEqual(state.draft, "Separate new draft")
        XCTAssertEqual(state.draftCategoryID, home.id)
        XCTAssertNil(state.refreshNotice)
        XCTAssertEqual(store.saved, [note])
        XCTAssertEqual(store.deleteAttempts, 0)
    }

    @MainActor
    func testTabSelectionRetainsIndependentComposerDraftCategoryAndWriteErrorContexts() throws {
        let store = TaskWindowReadFixture()
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        store.savedCategories = [work]
        let state = makeTabState(store)
        state.categoryPreferences.rememberLastUsed(work.id, in: .today)
        let presentation = TaskWindowPresentation()
        XCTAssertEqual(presentation.selectedDestination, .today)
        XCTAssertTrue(presentation.showComposer(in: .today, state: state))
        XCTAssertEqual(state.draftCategoryID, work.id)
        state.draft = "Today draft"
        XCTAssertFalse(state.addDraft())
        let todayIssue = state.issue

        XCTAssertTrue(presentation.selectDestination(.later, state: state))
        XCTAssertFalse(presentation.isComposerVisible(in: .later))
        XCTAssertEqual(presentation.focusAfterSelection(state: state), .add(.later))
        XCTAssertTrue(presentation.requestNewTask(state: state))
        XCTAssertEqual(presentation.newTaskRequest?.destination, .later)
        presentation.consumeNewTaskRequest(in: .today)
        XCTAssertNotNil(presentation.newTaskRequest)
        state.laterDraftCategoryID = work.id
        // Even with empty text, the open composer's category is a pending choice.
        XCTAssertTrue(presentation.selectDestination(.today, state: state))
        XCTAssertNil(presentation.newTaskRequest)
        XCTAssertEqual(presentation.focusAfterSelection(state: state), .draft(.today))
        XCTAssertTrue(presentation.selectDestination(.later, state: state))
        XCTAssertTrue(presentation.showComposer(in: .later, state: state))
        XCTAssertEqual(state.laterDraftCategoryID, work.id)
        state.laterDraft = "Later draft"
        XCTAssertFalse(state.addLaterDraft())
        let laterIssue = state.laterIssue
        XCTAssertTrue(presentation.selectDestination(.today, state: state))
        XCTAssertEqual(state.draft, "Today draft")
        XCTAssertEqual(state.draftCategoryID, work.id)
        XCTAssertEqual(state.issue, todayIssue)
        XCTAssertEqual(state.laterDraft, "Later draft")
        XCTAssertEqual(state.laterDraftCategoryID, work.id)
        XCTAssertEqual(state.laterIssue, laterIssue)
        XCTAssertTrue(presentation.isComposerVisible(in: .today))
        XCTAssertTrue(presentation.isComposerVisible(in: .later))
        presentation.hideComposer(in: .today)
        XCTAssertFalse(presentation.isComposerVisible(in: .today))
        XCTAssertTrue(presentation.isComposerVisible(in: .later))
        XCTAssertTrue(presentation.hasNewTaskComposer(in: .today, state: state))
    }

    @MainActor
    func testTabGuardsPreserveEditsConfirmationsAndCategorySheetUntilResolved() throws {
        let store = TaskWindowReadFixture()
        let state = makeTabState(store)
        let note = Note(id: UUID(), text: "Today", dayKey: try XCTUnwrap(state.todayKey),
                        createdAt: Date(), completedAt: nil)
        let later = LaterTask(id: UUID(), text: "Later", createdAt: Date(), completedAt: nil)
        store.saved = [note]
        store.savedLater = [later]
        state.refresh()
        let presentation = TaskWindowPresentation()
        state.beginEditing(id: note.id)
        state.editDraft = "Unsaved Today edit"
        XCTAssertFalse(presentation.selectDestination(.later, state: state))
        XCTAssertFalse(presentation.requestDeletion(id: note.id, state: state))
        XCTAssertEqual(state.editDraft, "Unsaved Today edit")
        state.cancelEditing()
        XCTAssertTrue(presentation.selectDestination(.later, state: state))
        state.beginEditingLater(id: later.id)
        state.laterEditDraft = "Unsaved Later edit"
        XCTAssertFalse(presentation.selectDestination(.today, state: state))
        XCTAssertFalse(presentation.canAddTask(state: state))
        XCTAssertFalse(presentation.showCategoryManager(state: state))
        XCTAssertFalse(presentation.requestDeletion(id: later.id, state: state))
        XCTAssertEqual(state.editingLaterTaskID, later.id)
        XCTAssertEqual(state.laterEditDraft, "Unsaved Later edit")
        state.cancelEditingLater()
        XCTAssertTrue(presentation.requestDeletion(id: later.id, state: state))
        XCTAssertFalse(presentation.selectDestination(.today, state: state))
        XCTAssertFalse(presentation.requestDeletion(.daily(id: note.id, dayKey: note.dayKey), state: state))
        XCTAssertEqual(presentation.deletionTarget, .later(id: later.id))
        presentation.cancelDeletion()
        XCTAssertTrue(presentation.showCategoryManager(state: state))
        XCTAssertFalse(presentation.selectDestination(.today, state: state))
        XCTAssertTrue(presentation.isManagingCategories)
        presentation.dismissCategoryManager()
        XCTAssertTrue(presentation.selectDestination(.today, state: state))
        XCTAssertFalse(presentation.requestDeletion(.later(id: later.id), state: state))
        XCTAssertEqual(store.deleteAttempts, 0)
    }

    @MainActor
    func testLaterDeletionSurvivesMidnightAndConsumesConfirmationBeforeFailureAndRetry() throws {
        let store = TaskWindowReadFixture()
        var instant = Date(timeIntervalSince1970: 1_790_000_000)
        let state = makeTabState(store, now: { instant })
        let id = UUID()
        let daily = Note(id: id, text: "Same UUID in Today", dayKey: try XCTUnwrap(state.todayKey),
                         createdAt: instant, completedAt: nil)
        let later = LaterTask(id: id, text: "Delete Later only", createdAt: instant, completedAt: nil)
        store.saved = [daily]
        store.savedLater = [later]
        state.refresh()
        let presentation = TaskWindowPresentation()
        XCTAssertTrue(presentation.selectDestination(.later, state: state))
        XCTAssertTrue(presentation.requestDeletion(id: id, state: state))
        instant = instant.addingTimeInterval(86400)
        state.refresh()
        presentation.validateDeletion(state: state)
        XCTAssertEqual(presentation.deletionTarget, .later(id: id))
        store.onDelete = { XCTAssertNil(presentation.deletionTarget) }
        store.failDelete = true
        XCTAssertFalse(presentation.confirmDeletion(state: state))
        XCTAssertEqual(state.laterTasks, [later])
        XCTAssertEqual(state.availableLaterRemainingCount, 1)
        XCTAssertEqual(state.laterIssue, .delete)
        store.failDelete = false
        XCTAssertFalse(presentation.confirmDeletion(state: state))
        XCTAssertEqual(store.deleteAttempts, 1)
        XCTAssertTrue(presentation.requestDeletion(id: id, state: state))
        XCTAssertTrue(presentation.confirmDeletion(state: state))
        XCTAssertEqual(store.deleteAttempts, 2)
        XCTAssertEqual(store.saved, [daily])
        XCTAssertTrue(store.savedLater.isEmpty)
        XCTAssertEqual(state.availableLaterRemainingCount, 0)
    }

    @MainActor
    func testLaterConfirmationUsesScopedAvailabilityAndCancelsForMissingTargets() throws {
        let store = TaskWindowReadFixture()
        let later = LaterTask(id: UUID(), text: "Later", createdAt: Date(), completedAt: nil)
        store.savedLater = [later]
        let state = makeTabState(store)
        let presentation = TaskWindowPresentation()
        XCTAssertTrue(presentation.selectDestination(.later, state: state))
        XCTAssertTrue(presentation.requestDeletion(id: later.id, state: state))
        store.failTodayRead = true
        state.refresh()
        presentation.validateDeletion(state: state)
        XCTAssertEqual(presentation.deletionTarget, .later(id: later.id))
        presentation.cancelDeletion()
        XCTAssertTrue(presentation.canAddTask(state: state))
        XCTAssertTrue(presentation.showCategoryManager(state: state))
        presentation.dismissCategoryManager()
        XCTAssertTrue(presentation.requestDeletion(id: later.id, state: state))
        store.failLaterRead = true
        state.refresh()
        presentation.validateDeletion(state: state)
        XCTAssertNil(presentation.deletionTarget)
        XCTAssertFalse(presentation.confirmDeletion(state: state))
        XCTAssertFalse(presentation.canAddTask(state: state))
        XCTAssertEqual(presentation.focusAfterSelection(state: state), .retry(.later))
        store.failTodayRead = false
        store.failLaterRead = false
        state.refresh()
        XCTAssertTrue(presentation.requestDeletion(id: later.id, state: state))
        store.savedLater = []
        state.refresh()
        presentation.validateDeletion(state: state)
        XCTAssertNil(presentation.deletionTarget)
        XCTAssertFalse(presentation.requestDeletion(id: later.id, state: state))
        // An unrelated Later failure must not disable Today commands.
        XCTAssertTrue(presentation.selectDestination(.today, state: state))
        store.failLaterRead = true
        state.refresh()
        XCTAssertTrue(presentation.canAddTask(state: state))
        XCTAssertEqual(store.deleteAttempts, 0)
    }

    @MainActor
    func testRetainedWindowKeepsLaterSessionAndSafeTodayRequestDoesNotDiscardWork() throws {
        let store = TaskWindowReadFixture()
        let category = try TaskCategory(name: "Work", creationOrder: 0)
        let later = LaterTask(id: UUID(), text: "Later", createdAt: Date(), completedAt: nil,
                              categoryID: category.id)
        store.savedCategories = [category]
        store.savedLater = [later]
        let state = makeTabState(store)
        let controller = TaskWindowController(state: state, onSettings: {})
        defer { controller.close() }
        controller.showTasks()
        let window = try XCTUnwrap(controller.window)
        let presentation = controller.presentation
        XCTAssertTrue(presentation.showComposer(in: .today, state: state))
        state.draft = "Today draft"
        XCTAssertTrue(presentation.selectDestination(.later, state: state))
        XCTAssertTrue(presentation.showComposer(in: .later, state: state))
        state.laterDraft = "Later draft"
        state.laterDraftCategoryID = category.id
        XCTAssertTrue(presentation.requestDeletion(id: later.id, state: state))
        window.close()
        XCTAssertNil(presentation.deletionTarget)
        XCTAssertFalse(presentation.confirmDeletion(state: state))
        controller.showTasks()
        XCTAssertTrue(controller.window === window)
        XCTAssertEqual(presentation.selectedDestination, .later)
        state.beginEditingLater(id: later.id)
        state.laterEditDraft = "Unsaved Later edit"
        window.close()
        XCTAssertFalse(controller.showToday())
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(presentation.selectedDestination, .later)
        XCTAssertEqual(state.editingLaterTaskID, later.id)
        XCTAssertEqual(state.laterEditDraft, "Unsaved Later edit")
        XCTAssertEqual(state.laterEditCategoryID, category.id)
        XCTAssertEqual(state.laterDraftCategoryID, category.id)
        XCTAssertEqual(state.draft, "Today draft")
        XCTAssertEqual(state.laterDraft, "Later draft")
        XCTAssertTrue(presentation.isComposerVisible(in: .today))
        XCTAssertTrue(presentation.isComposerVisible(in: .later))
        state.cancelEditingLater()
        XCTAssertTrue(presentation.showCategoryManager(state: state))
        XCTAssertTrue(presentation.requestCategoryRemoval(id: category.id, state: state))
        XCTAssertFalse(controller.showToday())
        XCTAssertNotNil(presentation.categoryRemovalTarget)
        window.close()
        XCTAssertFalse(presentation.isManagingCategories)
        XCTAssertNil(presentation.categoryRemovalTarget)
        controller.showTasks()
        XCTAssertEqual(presentation.selectedDestination, .later)
        XCTAssertTrue(controller.showToday())
        XCTAssertEqual(presentation.selectedDestination, .today)
        XCTAssertEqual(TaskWindowPresentation().selectedDestination, .today)
        XCTAssertEqual(store.deleteAttempts, 0)
        XCTAssertEqual(store.removeAttempts, 0)
    }

    @MainActor
    func testScopedFocusFallbackUsesTheOwningListAndItsCollapsePreferences() throws {
        let store = TaskWindowReadFixture()
        let category = try TaskCategory(name: "Work", creationOrder: 0)
        let id = UUID()
        let later = LaterTask(id: id, text: "Later", createdAt: Date(), completedAt: nil,
                              categoryID: category.id)
        store.savedCategories = [category]
        store.savedLater = [later]
        let state = makeTabState(store)
        store.saved = [Note(id: id, text: "Today", dayKey: try XCTUnwrap(state.todayKey),
                            createdAt: Date(), completedAt: nil)]
        state.refresh()
        let presentation = TaskWindowPresentation()
        let target = TaskActionTarget.later(id: id)
        let group = TaskGroupID.category(category.id)
        XCTAssertEqual(presentation.focusAfterLeavingRow(target, fallbackGroup: group, state: state), .row(target))
        state.categoryPreferences.setCollapsed(true, for: group, in: .later)
        XCTAssertEqual(presentation.focusAfterLeavingRow(target, fallbackGroup: group, state: state), .group(.later, group))
        let daily = TaskActionTarget.daily(id: id, dayKey: try XCTUnwrap(state.todayKey))
        XCTAssertEqual(presentation.focusAfterLeavingRow(daily, fallbackGroup: nil, state: state), .row(daily))
        store.savedLater = [LaterTask(id: UUID(), text: "Surviving group", createdAt: Date(),
                                     completedAt: nil, categoryID: category.id)]
        state.refresh()
        XCTAssertEqual(presentation.focusAfterLeavingRow(target, fallbackGroup: group, state: state), .group(.later, group))
        store.savedLater = []
        state.refresh()
        XCTAssertEqual(presentation.focusAfterLeavingRow(target, fallbackGroup: group, state: state), .add(.later))
        store.failLaterRead = true
        state.refresh()
        XCTAssertEqual(presentation.focusAfterLeavingRow(target, fallbackGroup: group, state: state), .retry(.later))
    }

    @MainActor
    private func makeTabState(_ store: TaskWindowReadFixture, now: @escaping () -> Date = { Date() }) -> DailyNotesState {
        let state = DailyNotesState(repositoryFactory: { store }, day: NoteDay(now: now),
                                   notificationCenter: NotificationCenter(),
                                   workspaceNotificationCenter: NotificationCenter(),
                                   categoryPreferences: isolatedCategoryPreferences())
        state.startup()
        return state
    }

    @MainActor
    func testDeletionConsumesConfirmationBeforeWriteAndRequiresFreshConfirmationAfterFailure() {
        let store = TaskWindowReadFixture()
        let instant = Date(timeIntervalSince1970: 1_790_000_000)
        let day = NoteDay(now: { instant })
        let note = Note(id: UUID(), text: "Delete me", dayKey: day.keys().today,
                        createdAt: instant, completedAt: instant)
        store.saved = [note]
        let state = DailyNotesState(repositoryFactory: { store }, day: day,
                                   notificationCenter: NotificationCenter(),
                                   workspaceNotificationCenter: NotificationCenter(),
                                   categoryPreferences: isolatedCategoryPreferences())
        state.startup()
        let presentation = TaskWindowPresentation()
        store.onDelete = { XCTAssertNil(presentation.deletionTarget) }
        presentation.requestDeletion(id: note.id, state: state)
        presentation.cancelDeletion()
        XCTAssertFalse(presentation.confirmDeletion(state: state))
        XCTAssertEqual(store.deleteAttempts, 0)
        store.failDelete = true
        presentation.requestDeletion(id: note.id, state: state)
        XCTAssertFalse(presentation.confirmDeletion(state: state))
        XCTAssertEqual(state.notes, [note])
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 1, total: 1))
        XCTAssertEqual(state.issue, .delete)
        store.failDelete = false
        XCTAssertFalse(presentation.confirmDeletion(state: state))
        XCTAssertEqual(store.deleteAttempts, 1)
        presentation.requestDeletion(id: note.id, state: state)
        XCTAssertTrue(presentation.confirmDeletion(state: state))
        XCTAssertEqual(store.deleteAttempts, 2)
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 0))
        XCTAssertNil(state.issue)
    }

    @MainActor
    func testDeletionRejectsRolloverAndInvalidatesRemovedOrUnavailableTargets() {
        let store = TaskWindowReadFixture()
        var instant = Date(timeIntervalSince1970: 1_790_000_000)
        let day = NoteDay(now: { instant })
        let note = Note(id: UUID(), text: "Previous day", dayKey: day.keys().today,
                        createdAt: instant, completedAt: nil)
        store.saved = [note]
        let state = DailyNotesState(repositoryFactory: { store }, day: day,
                                   notificationCenter: NotificationCenter(),
                                   workspaceNotificationCenter: NotificationCenter(),
                                   categoryPreferences: isolatedCategoryPreferences())
        state.startup()
        let presentation = TaskWindowPresentation()
        presentation.requestDeletion(id: note.id, state: state)
        instant = instant.addingTimeInterval(86400)
        XCTAssertFalse(presentation.confirmDeletion(state: state))
        XCTAssertEqual(store.saved, [note])
        XCTAssertEqual(store.deleteAttempts, 0)
        instant = instant.addingTimeInterval(-86400)
        state.refresh()
        presentation.requestDeletion(id: note.id, state: state)
        store.saved = []
        state.refresh()
        presentation.validateDeletion(state: state)
        XCTAssertNil(presentation.deletionTarget)
        store.saved = [note]
        state.refresh()
        presentation.requestDeletion(id: note.id, state: state)
        store.failRead = true
        state.refresh()
        presentation.validateDeletion(state: state)
        XCTAssertNil(presentation.deletionTarget)
        XCTAssertFalse(presentation.confirmDeletion(state: state))
        XCTAssertEqual(store.deleteAttempts, 0)
    }

    @MainActor
    func testCategoryRemovalConsumesConfirmationRechecksCountAndRequiresFreshConfirmationAfterFailure() throws {
        let store = TaskWindowReadFixture()
        let instant = Date(timeIntervalSince1970: 1_790_000_000)
        let day = NoteDay(now: { instant })
        let keys = day.keys()
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let todayWork = Note(id: UUID(), text: "Today work", dayKey: keys.today,
                             createdAt: instant, completedAt: instant, categoryID: work.id)
        let todayHome = Note(id: UUID(), text: "Today home", dayKey: keys.today,
                             createdAt: instant, completedAt: nil, categoryID: home.id)
        let yesterdayWork = Note(id: UUID(), text: "Yesterday work", dayKey: keys.yesterday,
                                 createdAt: instant, completedAt: nil, categoryID: work.id)
        store.savedCategories = [work, home]
        store.saved = [todayWork, todayHome, yesterdayWork]
        let preferences = isolatedCategoryPreferences()
        let state = DailyNotesState(repositoryFactory: { store }, day: day,
                                   notificationCenter: NotificationCenter(),
                                   workspaceNotificationCenter: NotificationCenter(),
                                   categoryPreferences: preferences)
        state.startup()
        preferences.rememberLastUsed(work.id)
        state.draft = "Pending task"
        state.draftCategoryID = work.id
        let presentation = TaskWindowPresentation()
        typealias Target = TaskWindowPresentation.CategoryRemovalTarget

        // Removal starts only in the open manager, from the all-days count.
        XCTAssertFalse(presentation.requestCategoryRemoval(id: work.id, state: state))
        XCTAssertTrue(presentation.showCategoryManager(state: state))
        XCTAssertTrue(presentation.requestCategoryRemoval(id: work.id, state: state))
        XCTAssertEqual(presentation.categoryRemovalTarget,
                       Target(id: work.id, name: "Work", usageCount: 2, countChanged: false))
        XCTAssertTrue(TaskCategoryManagerView.removalMessage(usageCount: 2)
            .hasPrefix("2 tasks, across all saved days and Later, use this category. They will move to General"))
        presentation.cancelCategoryRemoval()
        XCTAssertEqual(presentation.confirmCategoryRemoval(state: state), .notRemoved)
        XCTAssertEqual(store.removeAttempts, 0)

        // A count that changed after the confirmation appeared asks again.
        presentation.requestCategoryRemoval(id: work.id, state: state)
        store.saved.append(Note(id: UUID(), text: "Older work", dayKey: "2000-01-01",
                                createdAt: instant, completedAt: nil, categoryID: work.id))
        XCTAssertEqual(presentation.confirmCategoryRemoval(state: state), .countChanged)
        XCTAssertEqual(presentation.categoryRemovalTarget,
                       Target(id: work.id, name: "Work", usageCount: 3, countChanged: true))
        XCTAssertEqual(store.removeAttempts, 0)

        // Confirmation is consumed before the write. A failure keeps the
        // category, assignments, and draft, and needs a fresh confirmation.
        store.onRemove = { XCTAssertNil(presentation.categoryRemovalTarget) }
        store.failRemove = true
        XCTAssertEqual(presentation.confirmCategoryRemoval(state: state), .notRemoved)
        XCTAssertEqual(store.removeAttempts, 1)
        XCTAssertEqual(state.categoryIssue, .remove)
        XCTAssertEqual(state.categories, [work, home])
        XCTAssertEqual(state.notes, [todayWork, todayHome])
        XCTAssertEqual(state.draftCategoryID, work.id)
        store.failRemove = false
        XCTAssertEqual(presentation.confirmCategoryRemoval(state: state), .notRemoved)
        XCTAssertEqual(store.removeAttempts, 1)

        // Success moves every day's tasks to General without changing counts,
        // and the pending draft keeps its text but falls back to General.
        let progress = state.availableProgress
        XCTAssertTrue(presentation.requestCategoryRemoval(id: work.id, state: state))
        XCTAssertEqual(presentation.confirmCategoryRemoval(state: state), .removed)
        XCTAssertEqual(store.removeAttempts, 2)
        XCTAssertEqual(state.categories, [home])
        XCTAssertEqual(state.notes.map(\.id), [todayWork.id, todayHome.id])
        XCTAssertEqual(state.notes.map(\.categoryID), [nil, home.id])
        XCTAssertEqual(state.availableProgress, progress)
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        XCTAssertEqual(store.saved.count, 4)
        XCTAssertFalse(store.saved.contains { $0.categoryID == work.id })
        XCTAssertEqual(state.draft, "Pending task")
        XCTAssertNil(state.draftCategoryID)
        XCTAssertEqual(state.refreshNotice, "The selected category is no longer available. The new task will use General.")
        XCTAssertNil(preferences.lastUsedCategoryID)
        XCTAssertNil(state.categoryIssue)
        XCTAssertTrue(presentation.isManagingCategories)
    }

    @MainActor
    func testCategoryRemovalCancelsForMissingOrUnavailableTargetsAndClosedManager() throws {
        let store = TaskWindowReadFixture()
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        store.savedCategories = [work, home]
        let state = DailyNotesState(repositoryFactory: { store },
                                   notificationCenter: NotificationCenter(),
                                   workspaceNotificationCenter: NotificationCenter(),
                                   categoryPreferences: isolatedCategoryPreferences())
        state.startup()
        let presentation = TaskWindowPresentation()
        XCTAssertTrue(presentation.showCategoryManager(state: state))

        presentation.requestCategoryRemoval(id: home.id, state: state)
        store.savedCategories = [work]
        state.refresh()
        presentation.validateCategoryRemoval(state: state)
        XCTAssertNil(presentation.categoryRemovalTarget)
        XCTAssertFalse(presentation.requestCategoryRemoval(id: home.id, state: state))

        presentation.requestCategoryRemoval(id: work.id, state: state)
        store.failRead = true
        state.refresh()
        presentation.validateCategoryRemoval(state: state)
        XCTAssertNil(presentation.categoryRemovalTarget)
        XCTAssertEqual(presentation.confirmCategoryRemoval(state: state), .notRemoved)
        XCTAssertFalse(presentation.canManageCategories(state: state))
        store.failRead = false
        state.refresh()

        // A failed count shows no confirmation and keeps its own error.
        store.savedCategories = []
        XCTAssertFalse(presentation.requestCategoryRemoval(id: work.id, state: state))
        XCTAssertNil(presentation.categoryRemovalTarget)
        XCTAssertEqual(state.categoryIssue, .notFound)
        store.savedCategories = [work]

        // Closing the manager cancels its confirmation; reopening clears old messages.
        presentation.requestCategoryRemoval(id: work.id, state: state)
        presentation.dismissCategoryManager()
        XCTAssertFalse(presentation.isManagingCategories)
        XCTAssertNil(presentation.categoryRemovalTarget)
        XCTAssertFalse(presentation.requestCategoryRemoval(id: work.id, state: state))
        XCTAssertNil(state.createCategory(name: "work"))
        XCTAssertEqual(state.categoryNameIssue, .duplicate)
        XCTAssertTrue(presentation.showCategoryManager(state: state))
        XCTAssertNil(state.categoryNameIssue)
        XCTAssertNil(state.categoryIssue)
        XCTAssertEqual(store.removeAttempts, 0)
        XCTAssertEqual(store.savedCategories, [work])
    }

    @MainActor
    func testCategoryManagerSheetBlocksTaskCommandsAndKeepsTheNewTaskDraft() async throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let note = Note(id: UUID(), text: "Original", dayKey: NoteDay().keys().today,
                        createdAt: Date(), completedAt: nil, categoryID: work.id)
        fixture.repository.savedCategories = [work]
        fixture.repository.saved = [note]
        fixture.launch()
        let controller = try XCTUnwrap(fixture.delegate.taskWindowController)
        let presentation = controller.presentation
        let window = try XCTUnwrap(controller.window)
        let item = NSMenuItem(title: "Add Task", action: #selector(AppDelegate.addTask), keyEquivalent: "n")

        // Not over an edit or a deletion confirmation.
        fixture.state.beginEditing(id: note.id)
        XCTAssertFalse(presentation.showCategoryManager(state: fixture.state))
        fixture.state.cancelEditing()
        presentation.requestDeletion(id: note.id, state: fixture.state)
        XCTAssertFalse(presentation.showCategoryManager(state: fixture.state))
        presentation.cancelDeletion()

        // Over a pending new-task draft, the attached sheet blocks task commands.
        fixture.state.draft = "Pending task"
        fixture.state.draftCategoryID = work.id
        XCTAssertTrue(presentation.showCategoryManager(state: fixture.state))
        await waitUntil { window.attachedSheet != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        XCTAssertFalse(fixture.delegate.validateMenuItem(item))
        fixture.delegate.addTask()
        XCTAssertNil(presentation.newTaskRequestID)
        presentation.requestDeletion(id: note.id, state: fixture.state)
        XCTAssertNil(presentation.deletionTarget)

        // Escape in the sheet's name field closes the sheet and nothing else.
        let editor = try await focusedEditor(in: sheet)
        editor.insertText("Unsaved name", replacementRange: NSRange(location: 0, length: 0))
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        await waitUntil { !presentation.isManagingCategories && window.attachedSheet == nil }
        XCTAssertEqual(fixture.state.draft, "Pending task")
        XCTAssertEqual(fixture.state.draftCategoryID, work.id)
        XCTAssertTrue(fixture.delegate.validateMenuItem(item))

        // A reopened sheet starts without the discarded name; closing Today
        // dismisses it and its pending removal.
        XCTAssertTrue(presentation.showCategoryManager(state: fixture.state))
        await waitUntil { window.attachedSheet != nil }
        let reopened = try await focusedEditor(in: XCTUnwrap(window.attachedSheet))
        XCTAssertEqual(reopened.string, "")
        XCTAssertTrue(presentation.requestCategoryRemoval(id: work.id, state: fixture.state))
        window.close()
        XCTAssertFalse(presentation.isManagingCategories)
        XCTAssertNil(presentation.categoryRemovalTarget)
        fixture.delegate.showTasks()
        await waitUntil { window.isVisible && window.attachedSheet == nil }
        XCTAssertTrue(fixture.delegate.taskWindowController === controller)
        XCTAssertTrue(controller.window === window)
        XCTAssertTrue(controller.state === fixture.state)
        XCTAssertEqual(fixture.state.draft, "Pending task")
        XCTAssertEqual(fixture.state.draftCategoryID, work.id)
        XCTAssertEqual(fixture.repository.saved, [note])
        XCTAssertEqual(fixture.repository.savedCategories, [work])
        XCTAssertEqual(fixture.repository.removeAttempts, 0)
    }

    @MainActor
    func testCategoryManagerSheetCreatesCategoriesAndKeepsInvalidNamesForCorrection() async throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        fixture.launch()
        let controller = try XCTUnwrap(fixture.delegate.taskWindowController)
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(controller.presentation.showCategoryManager(state: fixture.state))
        await waitUntil { window.attachedSheet != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)

        let editor = try await focusedEditor(in: sheet)
        editor.insertText("School", replacementRange: NSRange(location: 0, length: 0))
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        await waitUntil { fixture.state.categories.map(\.name) == ["School"] }
        await waitUntil { editor.string.isEmpty }

        // Reserved and duplicate names stay in the field with a field error.
        for (name, issue) in [(" general ", CategoryNameIssue.invalid(.reserved)), ("SCHOOL", .duplicate)] {
            editor.selectAll(nil)
            editor.insertText(name, replacementRange: editor.selectedRange())
            editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            await waitUntil { fixture.state.categoryNameIssue == issue }
            XCTAssertEqual(editor.string, name)
        }
        XCTAssertEqual(fixture.repository.savedCategories.map(\.name), ["School"])
        XCTAssertTrue(controller.presentation.isManagingCategories)
        XCTAssertTrue(fixture.repository.saved.isEmpty)
    }

    @MainActor
    func testAppDelegateReusesItsSettingsWindow() throws {
        let suiteName = "local.menupocket.tests.AppConfigurationTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(store: PreferencesStore(userDefaults: userDefaults))
        let delegate = AppDelegate(model: model,
                                   onboardingStore: UserDefaultsOnboardingStore(userDefaults: userDefaults))

        XCTAssertNil(delegate.settingsWindowController)
        delegate.showSettings()

        let controller = try XCTUnwrap(delegate.settingsWindowController)
        let window = try XCTUnwrap(controller.window)
        let hostingController = try XCTUnwrap(
            window.contentViewController as? NSHostingController<SettingsView>
        )

        XCTAssertTrue(delegate.model === model)
        XCTAssertTrue(hostingController.rootView.model === model)
        XCTAssertEqual(
            hostingController.rootView.appVersion,
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )

        XCTAssertEqual(window.contentView?.frame.size, SettingsWindowController.initialContentSize)
        XCTAssertEqual(window.minSize, SettingsWindowController.minimumWindowSize)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.isReleasedWhenClosed)

        delegate.showSettings()
        XCTAssertTrue(controller === delegate.settingsWindowController)
        XCTAssertEqual(window.minSize, SettingsWindowController.minimumWindowSize)

        window.close()
        XCTAssertFalse(window.isVisible)

        delegate.showSettings()
        XCTAssertTrue(controller === delegate.settingsWindowController)
        XCTAssertTrue(window === controller.window)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.minSize, SettingsWindowController.minimumWindowSize)

        window.close()
    }

    func testLaunchContextDecodesOnlyLoginOpenApplicationEvents() {
        XCTAssertEqual(AppLaunchContext(appleEvent: nil), .manual)
        let event = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: kAEOpenApplication,
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        XCTAssertEqual(AppLaunchContext(appleEvent: event), .manual)
        event.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)
        XCTAssertEqual(AppLaunchContext(appleEvent: event), .login)
        event.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsServiceItem), forKeyword: keyAEPropData)
        XCTAssertEqual(AppLaunchContext(appleEvent: event), .manual)
        let reopen = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: kAEReopenApplication,
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        reopen.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)
        XCTAssertEqual(AppLaunchContext(appleEvent: reopen), .manual)
    }

    @MainActor
    func testManualLaunchOpensTasksEvenWithCompletedOnboardingAndReusesReopenRoute() throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        let preferences = fixture.defaults.data(forKey: PreferencesStore.storageKey)
        fixture.launch()
        let firstWindow = try XCTUnwrap(fixture.delegate.taskWindowController?.window)
        XCTAssertTrue(firstWindow.isVisible)
        XCTAssertNil(fixture.delegate.settingsWindowController)
        XCTAssertTrue(fixture.onboarding.hasCompletedOnboarding)
        XCTAssertTrue(UserDefaultsOnboardingStore(userDefaults: fixture.defaults).hasCompletedOnboarding)
        XCTAssertEqual(fixture.defaults.data(forKey: PreferencesStore.storageKey), preferences)
        firstWindow.close()
        XCTAssertTrue(fixture.delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        XCTAssertTrue(firstWindow === fixture.delegate.taskWindowController?.window)
        XCTAssertTrue(firstWindow.isVisible)
        fixture.delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        let second = AppDelegate(model: fixture.delegate.model,
            dailyNotesState: DailyNotesState(repositoryFactory: { fixture.repository },
                notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter(),
                categoryPreferences: TaskCategoryPreferences(userDefaults: fixture.defaults)),
            onboardingStore: UserDefaultsOnboardingStore(userDefaults: fixture.defaults), launchContext: { .manual })
        defer { second.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        second.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        XCTAssertTrue(second.taskWindowController?.window?.isVisible == true)
        XCTAssertNil(second.settingsWindowController)
        XCTAssertTrue(fixture.onboarding.hasCompletedOnboarding)
        XCTAssertEqual(fixture.defaults.data(forKey: PreferencesStore.storageKey), preferences)
    }

    @MainActor
    func testLoginLaunchLoadsProgressWithoutPresentingOrCompletingOnboarding() throws {
        let fixture = try AppLifecycleFixture(context: .login)
        defer { fixture.cleanup() }
        let note = Note(id: UUID(), text: "Saved task", dayKey: NoteDay().keys().today,
                        createdAt: Date(), completedAt: Date())
        fixture.repository.saved = [note]
        let preferences = fixture.defaults.data(forKey: PreferencesStore.storageKey)
        let keyWindow = NSApplication.shared.keyWindow
        let active = NSApplication.shared.isActive
        fixture.launch()
        XCTAssertEqual(fixture.state.availableProgress, NoteProgress(completed: 1, total: 1))
        XCTAssertEqual(fixture.delegate.taskStatusItemController?.statusItem?.button?.title, "1/1")
        XCTAssertNil(fixture.delegate.taskWindowController)
        XCTAssertNil(fixture.delegate.settingsWindowController)
        XCTAssertTrue(NSApplication.shared.keyWindow === keyWindow)
        XCTAssertEqual(NSApplication.shared.isActive, active)
        XCTAssertFalse(fixture.onboarding.hasCompletedOnboarding)
        XCTAssertEqual(fixture.defaults.data(forKey: PreferencesStore.storageKey), preferences)
        XCTAssertEqual(fixture.loginService.registrationAttempts, 0)
        fixture.delegate.showTasks()
        XCTAssertTrue(fixture.delegate.taskWindowController?.window?.isVisible == true)
        XCTAssertTrue(fixture.onboarding.hasCompletedOnboarding)
        XCTAssertEqual(fixture.repository.saved, [note])
    }

    @MainActor
    func testFailedLoginReadRemainsUnavailableUntilExplicitRetry() async throws {
        let fixture = try AppLifecycleFixture(context: .login)
        defer { fixture.cleanup() }
        fixture.repository.failRead = true
        fixture.launch()
        XCTAssertNil(fixture.state.availableProgress)
        XCTAssertEqual(fixture.delegate.taskStatusItemController?.statusItem?.button?.title, "—")
        XCTAssertNil(fixture.delegate.taskWindowController)
        XCTAssertNil(fixture.delegate.settingsWindowController)
        XCTAssertFalse(fixture.onboarding.hasCompletedOnboarding)
        fixture.repository.failRead = false
        fixture.delegate.showTasks()
        await waitForStatusTitle("0/0", fixture: fixture)
        XCTAssertEqual(fixture.state.availableProgress, NoteProgress(completed: 0, total: 0))
    }

    @MainActor
    func testActivationRefreshesSavedTasksWithoutOpeningWindowsOrRegisteringLogin() async throws {
        let fixture = try AppLifecycleFixture(context: .login)
        defer { fixture.cleanup() }
        fixture.launch()
        let note = Note(id: UUID(), text: "External saved task", dayKey: NoteDay().keys().today,
                        createdAt: Date(), completedAt: nil)
        fixture.repository.saved = [note]
        fixture.delegate.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        await waitForStatusTitle("0/1", fixture: fixture)
        XCTAssertEqual(fixture.state.notes, [note])
        XCTAssertNil(fixture.delegate.taskWindowController)
        XCTAssertNil(fixture.delegate.settingsWindowController)
        XCTAssertFalse(fixture.onboarding.hasCompletedOnboarding)
        XCTAssertEqual(fixture.loginService.registrationAttempts, 0)
    }

    @MainActor
    func testLaterNativeComposerSwitchReopenFailureAndReturnUseOnlyLaterContext() async throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        fixture.launch()
        let controller = try XCTUnwrap(fixture.delegate.taskWindowController)
        let window = try XCTUnwrap(controller.window)
        fixture.state.draft = "Pending Today"
        XCTAssertTrue(controller.presentation.selectDestination(.later, state: fixture.state))
        XCTAssertTrue(controller.presentation.requestNewTask(state: fixture.state))
        let editor = try await focusedEditor(in: window)
        editor.insertText("Pending Later", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        XCTAssertEqual(fixture.state.laterDraft, "Pending Later")
        XCTAssertEqual(fixture.state.draft, "Pending Today")
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        await waitUntil { fixture.state.laterIssue == .add }
        XCTAssertEqual(fixture.state.laterDraft, "Pending Later")
        XCTAssertNil(fixture.state.issue)
        XCTAssertTrue(fixture.repository.savedLater.isEmpty)

        XCTAssertTrue(controller.presentation.selectDestination(.today, state: fixture.state))
        await waitUntil { (window.firstResponder as? NSTextView)?.string == "Pending Today" }
        XCTAssertTrue(controller.presentation.selectDestination(.later, state: fixture.state))
        await waitUntil { (window.firstResponder as? NSTextView)?.string == "Pending Later" }
        window.performClose(nil)
        controller.showTasks()
        await waitUntil { (window.firstResponder as? NSTextView)?.string == "Pending Later" }
        XCTAssertEqual(controller.presentation.selectedDestination, .later)
        fixture.repository.allowAdd = true
        try await focusedEditor(in: window).doCommand(by: #selector(NSResponder.insertNewline(_:)))
        await waitUntil { fixture.state.laterDraft.isEmpty }
        XCTAssertEqual(fixture.repository.savedLater.map(\.text), ["Pending Later"])
        XCTAssertTrue(fixture.repository.saved.isEmpty)
        XCTAssertEqual(fixture.state.draft, "Pending Today")
        XCTAssertFalse(controller.presentation.isLaterComposerVisible)
        XCTAssertNil(fixture.state.laterIssue)
    }

    @MainActor
    func testLaterInlineEditorEscapeAndReturnPreserveTodayDraftAndSavedCompletion() async throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        let task = LaterTask(id: UUID(), text: "Completed Later", createdAt: Date(),
                             completedAt: Date(), categoryID: nil)
        fixture.repository.savedLater = [task]
        fixture.launch()
        let controller = try XCTUnwrap(fixture.delegate.taskWindowController)
        let window = try XCTUnwrap(controller.window)
        fixture.state.draft = "Today draft"
        fixture.state.laterDraft = "Later draft"
        XCTAssertTrue(controller.presentation.selectDestination(.later, state: fixture.state))
        fixture.state.beginEditingLater(id: task.id)
        let editor = try await focusedEditor(in: window)
        XCTAssertEqual(editor.string, task.text)
        editor.insertText("Cancelled edit", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        XCTAssertFalse(controller.presentation.selectDestination(.today, state: fixture.state))
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        await waitUntil { fixture.state.editingLaterTaskID == nil }
        XCTAssertEqual(fixture.repository.savedLater, [task])
        XCTAssertTrue(controller.presentation.requestNewTask(state: fixture.state))
        await waitUntil { (window.firstResponder as? NSTextView)?.string == "Later draft" }
        try await focusedEditor(in: window).doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        await waitUntil { fixture.state.laterDraft.isEmpty }
        fixture.state.beginEditingLater(id: task.id)
        await waitUntil { (window.firstResponder as? NSTextView)?.string == task.text }
        let savedEditor = try await focusedEditor(in: window)
        savedEditor.insertText("Saved edit", replacementRange: NSRange(location: 0, length: savedEditor.string.utf16.count))
        savedEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        await waitUntil { fixture.state.editingLaterTaskID == nil }
        XCTAssertEqual(fixture.repository.savedLater.first?.text, "Saved edit")
        XCTAssertEqual(fixture.repository.savedLater.first?.completedAt, task.completedAt)
        XCTAssertEqual(fixture.state.draft, "Today draft")
        XCTAssertTrue(fixture.repository.saved.isEmpty)
    }

    @MainActor
    func testNativeAddAndTextCommandsFocusComposerAndPreserveDraftAcrossRepeatedRequests() async throws {
        let fixture = try AppLifecycleFixture(context: .login)
        defer { fixture.cleanup() }
        fixture.launch()
        let menu = try XCTUnwrap(NSApplication.shared.mainMenu)
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("n", keyCode: 45)))
        let window = try XCTUnwrap(fixture.delegate.taskWindowController?.window)
        let editor = try await focusedEditor(in: window)
        let clipboard = NSPasteboard.general
        let previousItems = (clipboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        defer {
            clipboard.clearContents()
            clipboard.writeObjects(previousItems)
        }
        editor.insertText("Native task text", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(fixture.state.draft, "Native task text")
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("a", keyCode: 0)))
        XCTAssertEqual(editor.selectedRange().length, editor.string.utf16.count)
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("c", keyCode: 8)))
        XCTAssertEqual(clipboard.string(forType: .string), "Native task text")
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("x", keyCode: 7)))
        XCTAssertEqual(editor.string, "")
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("v", keyCode: 9)))
        XCTAssertEqual(fixture.state.draft, "Native task text")
        fixture.delegate.showSettings()
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("n", keyCode: 45)))
        _ = try await focusedEditor(in: window)
        XCTAssertTrue(window === fixture.delegate.taskWindowController?.window)
        XCTAssertEqual(fixture.state.draft, "Native task text")
        XCTAssertTrue(fixture.repository.saved.isEmpty)
    }

    @MainActor
    func testComposerKeepsNativeUndoAcrossRepeatedRequestsAndWindowReopen() async throws {
        let fixture = try AppLifecycleFixture(context: .login)
        defer { fixture.cleanup() }
        fixture.launch()
        let menu = try XCTUnwrap(NSApplication.shared.mainMenu)
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("n", keyCode: 45)))
        let window = try XCTUnwrap(fixture.delegate.taskWindowController?.window)
        let editor = try await focusedEditor(in: window)
        editor.insertText("Undo this pending task", replacementRange: NSRange(location: 0, length: 0))
        editor.breakUndoCoalescing()
        let undo = try XCTUnwrap(editor.undoManager)
        XCTAssertTrue(undo.canUndo)

        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("n", keyCode: 45)))
        window.close()
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("n", keyCode: 45)))
        let reopenedEditor = try await focusedEditor(in: window)
        XCTAssertEqual(fixture.state.draft, "Undo this pending task")
        XCTAssertTrue(reopenedEditor.undoManager === undo)
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("z", keyCode: 6)))
        await waitUntil { fixture.state.draft.isEmpty }
        XCTAssertTrue(undo.canRedo)
        undo.redo()
        await waitUntil { fixture.state.draft == "Undo this pending task" }
        XCTAssertTrue(fixture.repository.saved.isEmpty)
    }

    @MainActor
    func testInlineEditNativeReturnFailureAndEscapePreserveSavedTaskAndAddDraft() async throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        let note = Note(id: UUID(), text: "Original task", dayKey: NoteDay().keys().today,
                        createdAt: Date(), completedAt: nil)
        fixture.repository.saved = [note]
        fixture.launch()
        fixture.state.draft = "Separate pending Add"
        fixture.state.beginEditing(id: note.id)
        let window = try XCTUnwrap(fixture.delegate.taskWindowController?.window)
        let editor = try await focusedEditor(in: window)
        XCTAssertEqual(editor.string, note.text)
        editor.insertText("Unsaved inline edit", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))

        // The fixture rejects edits: native Return must retain the editor and draft.
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        await waitUntil { fixture.state.issue == .edit }
        XCTAssertEqual(fixture.state.editingNoteID, note.id)
        XCTAssertEqual(fixture.state.editDraft, "Unsaved inline edit")
        XCTAssertEqual(fixture.repository.saved, [note])
        XCTAssertEqual(fixture.state.draft, "Separate pending Add")

        // Escape cancels this row's edit, then the independent Add field returns.
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        // Command-N can arrive before SwiftUI finishes restoring row focus.
        // The newer explicit command must win over that pending restoration.
        fixture.delegate.addTask()
        await waitUntil { fixture.state.editingNoteID == nil }
        XCTAssertNil(fixture.state.issue)
        XCTAssertEqual(fixture.repository.saved, [note])
        XCTAssertEqual(fixture.state.draft, "Separate pending Add")
        await waitUntil { (window.firstResponder as? NSTextView)?.string == "Separate pending Add" }
        let addEditor = try await focusedEditor(in: window)
        XCTAssertEqual(addEditor.string, "Separate pending Add")
        for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(20))
            XCTAssertEqual((window.firstResponder as? NSTextView)?.string, "Separate pending Add")
        }
    }

    @MainActor
    func testAddCommandDoesNotReplaceEditOrDeletionAndRejectsUnavailableData() throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        let note = Note(id: UUID(), text: "Original", dayKey: NoteDay().keys().today,
                        createdAt: Date(), completedAt: nil)
        fixture.repository.saved = [note]
        fixture.launch()
        let controller = try XCTUnwrap(fixture.delegate.taskWindowController)
        let item = NSMenuItem(title: "Add Task", action: #selector(AppDelegate.addTask), keyEquivalent: "n")
        fixture.state.draft = "Separate draft"
        fixture.state.beginEditing(id: note.id)
        fixture.state.editDraft = "Unsaved edit"
        XCTAssertFalse(fixture.delegate.validateMenuItem(item))
        fixture.delegate.addTask()
        XCTAssertNil(controller.presentation.newTaskRequestID)
        XCTAssertEqual(fixture.state.editingNoteID, note.id)
        XCTAssertEqual(fixture.state.editDraft, "Unsaved edit")
        XCTAssertEqual(fixture.state.draft, "Separate draft")
        fixture.state.cancelEditing()
        controller.presentation.requestDeletion(id: note.id, state: fixture.state)
        XCTAssertFalse(fixture.delegate.validateMenuItem(item))
        fixture.delegate.addTask()
        XCTAssertEqual(controller.presentation.deletionTarget?.id, note.id)
        XCTAssertNil(controller.presentation.newTaskRequestID)
        controller.presentation.cancelDeletion()
        fixture.repository.failRead = true
        fixture.state.refresh()
        XCTAssertFalse(fixture.delegate.validateMenuItem(item))
        fixture.delegate.addTask()
        XCTAssertNil(controller.presentation.newTaskRequestID)
        XCTAssertEqual(fixture.state.draft, "Separate draft")
        XCTAssertEqual(fixture.repository.saved, [note])
    }

    @MainActor
    func testComposerStartsNewDraftsFromLastUsedCategoryAndKeepsAPendingSelection() async throws {
        let fixture = try AppLifecycleFixture(context: .login)
        defer { fixture.cleanup() }
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        fixture.repository.savedCategories = [work, home]
        fixture.repository.allowAdd = true
        fixture.launch()
        let preferences = fixture.state.categoryPreferences
        preferences.rememberLastUsed(work.id)
        preferences.setCollapsed(true, for: .category(home.id))
        let menu = try XCTUnwrap(NSApplication.shared.mainMenu)

        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("n", keyCode: 45)))
        let controller = try XCTUnwrap(fixture.delegate.taskWindowController)
        let window = try XCTUnwrap(controller.window)
        let editor = try await focusedEditor(in: window)
        await waitUntil { controller.presentation.newTaskRequestID == nil }
        XCTAssertEqual(fixture.state.draftCategoryID, work.id)

        // The picker's choice stays with a pending draft through repeated
        // Command-N and a closed and reopened window.
        fixture.state.draftCategoryID = home.id
        editor.insertText("Categorized task", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("n", keyCode: 45)))
        await waitUntil { controller.presentation.newTaskRequestID == nil }
        window.close()
        fixture.delegate.showTasks()
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("n", keyCode: 45)))
        await waitUntil { controller.presentation.newTaskRequestID == nil }
        XCTAssertEqual(fixture.state.draft, "Categorized task")
        XCTAssertEqual(fixture.state.draftCategoryID, home.id)
        XCTAssertEqual(preferences.lastUsedCategoryID, work.id)
        XCTAssertTrue(fixture.repository.saved.isEmpty)

        // Return saves text and category together and shows the collapsed destination.
        try await focusedEditor(in: window).doCommand(by: #selector(NSResponder.insertNewline(_:)))
        await waitUntil { !fixture.repository.saved.isEmpty }
        XCTAssertEqual(fixture.repository.saved.map(\.text), ["Categorized task"])
        XCTAssertEqual(fixture.repository.saved.first?.categoryID, home.id)
        XCTAssertFalse(preferences.isCollapsed(.category(home.id)))
        XCTAssertEqual(preferences.lastUsedCategoryID, home.id)

        // The next new draft starts from the saved category. Escape discards a
        // changed selection without remembering it, so the draft after it does too.
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("n", keyCode: 45)))
        await waitUntil { controller.presentation.newTaskRequestID == nil }
        XCTAssertEqual(fixture.state.draftCategoryID, home.id)
        fixture.state.draftCategoryID = work.id
        try await focusedEditor(in: window).doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        await waitUntil { fixture.state.draftCategoryID == nil }
        XCTAssertEqual(preferences.lastUsedCategoryID, home.id)
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("n", keyCode: 45)))
        await waitUntil { controller.presentation.newTaskRequestID == nil }
        XCTAssertEqual(fixture.state.draftCategoryID, home.id)
        XCTAssertEqual(fixture.repository.saved.count, 1)
    }

    @MainActor
    func testSettingsShortcutReusesWindowAndCloseDoesNotTerminate() throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        fixture.launch()
        let menu = try XCTUnwrap(NSApplication.shared.mainMenu)
        let taskWindow = try XCTUnwrap(fixture.delegate.taskWindowController?.window)
        fixture.delegate.showSettings()
        let settings = try XCTUnwrap(fixture.delegate.settingsWindowController)
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent(",", keyCode: 43)))
        XCTAssertTrue(fixture.delegate.settingsWindowController === settings)
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("w", keyCode: 13)))
        XCTAssertFalse(settings.window?.isVisible == true)
        XCTAssertTrue(taskWindow.isVisible)
        fixture.delegate.showTasks()
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("w", keyCode: 13)))
        XCTAssertFalse(taskWindow.isVisible)
        XCTAssertNotNil(fixture.delegate.taskStatusItemController?.statusItem)
        XCTAssertFalse(fixture.delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    @MainActor
    func testTerminationClosesWindowsRemovesStatusAndStopsQueuedRefreshes() async throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        fixture.launch()
        fixture.delegate.showSettings()
        let status = try XCTUnwrap(fixture.delegate.taskStatusItemController)
        let tasks = try XCTUnwrap(fixture.delegate.taskWindowController?.window)
        let settings = try XCTUnwrap(fixture.delegate.settingsWindowController?.window)
        let reads = fixture.repository.readAttempts
        fixture.notifications.post(name: .NSCalendarDayChanged, object: nil)
        fixture.delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        fixture.notifications.post(name: .NSSystemClockDidChange, object: nil)
        fixture.state.refresh()
        fixture.delegate.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        fixture.delegate.showTasks()
        fixture.delegate.showSettings()
        fixture.delegate.addTask()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertNil(status.statusItem)
        XCTAssertNil(fixture.delegate.taskStatusItemController)
        XCTAssertFalse(tasks.isVisible)
        XCTAssertFalse(settings.isVisible)
        XCTAssertEqual(fixture.repository.readAttempts, reads)
        XCTAssertNil(fixture.delegate.taskWindowController?.presentation.newTaskRequestID)
        XCTAssertEqual(fixture.loginService.registrationAttempts, 0)
    }

    @MainActor
    func testCorruptPreferencesDoNotResetCompletedOnboardingOrPreventManualPresentation() throws {
        let suiteName = "local.menupocket.tests.OnboardingRecovery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let onboarding = UserDefaultsOnboardingStore(userDefaults: defaults)
        onboarding.markOnboardingCompleted()
        let corruptData = Data("invalid".utf8)
        defaults.set(corruptData, forKey: PreferencesStore.storageKey)
        let delegate = AppDelegate(model: AppModel(store: PreferencesStore(userDefaults: defaults)),
            dailyNotesState: DailyNotesState(repositoryFactory: { throw CocoaError(.fileReadNoSuchFile) },
                notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter()),
            onboardingStore: onboarding)
        defer { delegate.taskWindowController?.close() }
        delegate.showTasks()
        XCTAssertTrue(delegate.taskWindowController?.window?.isVisible == true)
        XCTAssertNil(delegate.settingsWindowController)
        XCTAssertTrue(onboarding.hasCompletedOnboarding)
        XCTAssertEqual(delegate.model.preferenceWarning, .corruptData)
        XCTAssertTrue(delegate.model.isPreferenceEditingAllowed)
        XCTAssertEqual(defaults.data(forKey: PreferencesStore.storageKey), corruptData)
    }

    @MainActor
    func testLaunchAppliesSavedThemeToTheAppAndItsFirstWindow() throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        XCTAssertTrue(fixture.delegate.model.setTheme(.dark))

        fixture.launch()

        XCTAssertEqual(NSApplication.shared.appearance?.name, .darkAqua)
        let window = try XCTUnwrap(fixture.delegate.taskWindowController?.window)
        XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
    }

    @MainActor
    func testLoginLaunchAppliesSavedThemeWithoutPresentingWindows() throws {
        let fixture = try AppLifecycleFixture(context: .login)
        defer { fixture.cleanup() }
        XCTAssertTrue(fixture.delegate.model.setTheme(.light))

        fixture.launch()

        XCTAssertEqual(NSApplication.shared.appearance?.name, .aqua)
        XCTAssertNil(fixture.delegate.taskWindowController)
        XCTAssertNil(fixture.delegate.settingsWindowController)
    }

    @MainActor
    func testThemeChangesApplyToOpenWindowsUntilTermination() async throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        fixture.launch()
        fixture.delegate.showSettings()
        let model = fixture.delegate.model
        let windows = [
            try XCTUnwrap(fixture.delegate.taskWindowController?.window),
            try XCTUnwrap(fixture.delegate.settingsWindowController?.window),
        ]
        XCTAssertNil(NSApplication.shared.appearance)

        XCTAssertTrue(model.setTheme(.dark))
        await waitForAppearance(.darkAqua)
        for window in windows {
            XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        }
        XCTAssertTrue(model.setTheme(.light))
        await waitForAppearance(.aqua)
        for window in windows {
            XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        }
        XCTAssertTrue(model.setTheme(.system))
        await waitForAppearance(nil)

        fixture.delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        XCTAssertTrue(model.setTheme(.dark))
        for _ in 0..<5 { await Task.yield() }
        XCTAssertNil(NSApplication.shared.appearance)
    }

    @MainActor
    func testNativeCommandNInLaterSavesOnlyLaterAndKeepsTodayDraft() async throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        fixture.repository.allowAdd = true
        fixture.launch()
        let controller = try XCTUnwrap(fixture.delegate.taskWindowController)
        fixture.state.draft = "Today draft"
        XCTAssertTrue(controller.presentation.selectDestination(.later, state: fixture.state))
        let menu = try XCTUnwrap(NSApplication.shared.mainMenu)
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("n", keyCode: 45)))
        let window = try XCTUnwrap(controller.window)
        let editor = try await focusedEditor(in: window)
        editor.insertText("Later command task", replacementRange: NSRange(location: 0, length: 0))
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        await waitUntil { fixture.repository.savedLater.count == 1 }
        XCTAssertEqual(fixture.repository.savedLater.map(\.text), ["Later command task"])
        XCTAssertTrue(fixture.repository.saved.isEmpty)
        XCTAssertEqual(fixture.state.draft, "Today draft")
        XCTAssertEqual(controller.presentation.selectedDestination, .later)
        await waitForStatusTitle("0/0", fixture: fixture)
    }

    @MainActor
    func testAppAddValidationUsesActiveAvailabilityAndGuardsBeforePresentation() throws {
        let fixture = try AppLifecycleFixture(context: .login)
        defer { fixture.cleanup() }
        fixture.repository.failTodayRead = true
        fixture.launch()
        let item = NSMenuItem(title: "Add Task", action: #selector(AppDelegate.addTask), keyEquivalent: "n")
        XCTAssertFalse(fixture.delegate.validateMenuItem(item))
        fixture.delegate.addTask()
        XCTAssertNil(fixture.delegate.taskWindowController)
        fixture.delegate.showTasks()
        let controller = try XCTUnwrap(fixture.delegate.taskWindowController)
        let presentation = controller.presentation
        XCTAssertTrue(presentation.selectDestination(.later, state: fixture.state))
        XCTAssertTrue(fixture.delegate.validateMenuItem(item))
        fixture.delegate.addTask()
        XCTAssertTrue(presentation.isComposerVisible(in: .later))
        XCTAssertFalse(presentation.isComposerVisible(in: .today))
        presentation.consumeNewTaskRequest(in: .later)
        XCTAssertTrue(presentation.showCategoryManager(state: fixture.state))
        XCTAssertFalse(fixture.delegate.validateMenuItem(item))
        fixture.delegate.addTask()
        XCTAssertNil(presentation.newTaskRequest)
        presentation.dismissCategoryManager()
        fixture.repository.failTodayRead = false
        fixture.repository.failLaterRead = true
        fixture.state.refresh()
        XCTAssertFalse(fixture.delegate.validateMenuItem(item))
        fixture.delegate.addTask()
        XCTAssertNil(presentation.newTaskRequest)
        XCTAssertTrue(presentation.selectDestination(.today, state: fixture.state))
        XCTAssertTrue(fixture.delegate.validateMenuItem(item))
    }

    @MainActor
    func testStatusClickRequestsTodayButDockAndShowTasksRetainLaterAndGuards() throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        let task = LaterTask(id: UUID(), text: "Later row", createdAt: Date(), completedAt: nil)
        fixture.repository.savedLater = [task]
        fixture.launch()
        let controller = try XCTUnwrap(fixture.delegate.taskWindowController)
        let presentation = controller.presentation
        let window = try XCTUnwrap(controller.window)
        let button = try XCTUnwrap(fixture.delegate.taskStatusItemController?.statusItem?.button)
        XCTAssertTrue(presentation.selectDestination(.later, state: fixture.state))
        fixture.state.laterDraft = "Retained Later draft"
        window.close()
        XCTAssertTrue(fixture.delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(presentation.selectedDestination, .later)
        fixture.delegate.showTasks()
        XCTAssertTrue(fixture.delegate.taskWindowController === controller)
        XCTAssertEqual(presentation.selectedDestination, .later)
        fixture.state.beginEditingLater(id: task.id)
        fixture.state.laterEditDraft = "Protected edit"
        button.performClick(nil)
        XCTAssertEqual(presentation.selectedDestination, .later)
        XCTAssertEqual(fixture.state.laterEditDraft, "Protected edit")
        fixture.state.cancelEditingLater()
        XCTAssertTrue(presentation.requestDeletion(id: task.id, state: fixture.state))
        button.performClick(nil)
        XCTAssertEqual(presentation.selectedDestination, .later)
        XCTAssertEqual(presentation.deletionTarget, .later(id: task.id))
        presentation.cancelDeletion()
        XCTAssertTrue(presentation.showCategoryManager(state: fixture.state))
        button.performClick(nil)
        XCTAssertEqual(presentation.selectedDestination, .later)
        presentation.dismissCategoryManager()
        button.performClick(nil)
        XCTAssertEqual(presentation.selectedDestination, .today)
        XCTAssertEqual(fixture.state.laterDraft, "Retained Later draft")
        XCTAssertEqual(fixture.loginService.registrationAttempts, 0)
    }

    @MainActor
    func testGlanceAddTaskTargetsTodayFromIdleLaterAndIsDisabledByEveryGuard() throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        let task = LaterTask(id: UUID(), text: "Later row", createdAt: Date(), completedAt: nil)
        fixture.repository.savedLater = [task]
        fixture.launch()
        let status = try XCTUnwrap(fixture.delegate.taskStatusItemController)
        let presentation = try XCTUnwrap(fixture.delegate.taskWindowController?.presentation)
        XCTAssertTrue(presentation.selectDestination(.later, state: fixture.state))
        fixture.state.laterDraft = "Retained Later draft"
        let reads = fixture.repository.readAttempts
        var add = try glanceItem("Add Task…", status)
        XCTAssertEqual(fixture.repository.readAttempts, reads, "Building the glance must not read storage")
        XCTAssertEqual(presentation.selectedDestination, .later)
        XCTAssertTrue(add.isEnabled)
        try performGlanceItem("Add Task…", status)
        XCTAssertEqual(presentation.selectedDestination, .today)
        XCTAssertTrue(presentation.isComposerVisible(in: .today))
        XCTAssertFalse(presentation.isComposerVisible(in: .later))
        XCTAssertEqual(presentation.newTaskRequest?.destination, .today)
        XCTAssertEqual(fixture.state.laterDraft, "Retained Later draft")

        presentation.hideComposer(in: .today)
        XCTAssertTrue(presentation.selectDestination(.later, state: fixture.state))
        fixture.state.beginEditingLater(id: task.id)
        fixture.state.laterEditDraft = "Protected edit"
        add = try glanceItem("Add Task…", status)
        XCTAssertFalse(add.isEnabled)
        try performGlanceItem("Add Task…", status)
        XCTAssertEqual(presentation.selectedDestination, .later)
        XCTAssertEqual(fixture.state.laterEditDraft, "Protected edit")
        XCTAssertNil(presentation.newTaskRequest)
        fixture.state.cancelEditingLater()
        XCTAssertTrue(presentation.requestDeletion(id: task.id, state: fixture.state))
        XCTAssertFalse(try glanceItem("Add Task…", status).isEnabled)
        presentation.cancelDeletion()
        XCTAssertTrue(presentation.showCategoryManager(state: fixture.state))
        XCTAssertFalse(try glanceItem("Add Task…", status).isEnabled)
        presentation.dismissCategoryManager()
        XCTAssertTrue(try glanceItem("Add Task…", status).isEnabled)
        fixture.repository.failTodayRead = true
        fixture.state.refresh()
        add = try glanceItem("Add Task…", status)
        XCTAssertFalse(add.isEnabled)
        try performGlanceItem("Add Task…", status)
        XCTAssertEqual(presentation.selectedDestination, .later)
        XCTAssertNil(presentation.newTaskRequest)
        XCTAssertEqual(fixture.state.laterDraft, "Retained Later draft")
    }

    @MainActor
    func testGlanceAddTaskCreatesTheWindowOnTodayAfterLoginLaunch() throws {
        let fixture = try AppLifecycleFixture(context: .login)
        defer { fixture.cleanup() }
        fixture.launch()
        let status = try XCTUnwrap(fixture.delegate.taskStatusItemController)
        XCTAssertNil(fixture.delegate.taskWindowController)
        let add = try glanceItem("Add Task…", status)
        XCTAssertNil(fixture.delegate.taskWindowController, "Building the glance must not create a window")
        XCTAssertTrue(add.isEnabled)
        try performGlanceItem("Add Task…", status)
        let controller = try XCTUnwrap(fixture.delegate.taskWindowController)
        XCTAssertTrue(controller.window?.isVisible == true)
        XCTAssertEqual(controller.presentation.selectedDestination, .today)
        XCTAssertTrue(controller.presentation.isComposerVisible(in: .today))
        XCTAssertEqual(fixture.loginService.registrationAttempts, 0)
    }

    @MainActor
    func testGlanceLaterLineOpensLaterLikeCommandTwoAndKeepsGuardedTodayEdit() throws {
        let fixture = try AppLifecycleFixture(context: .manual)
        defer { fixture.cleanup() }
        let today = Note(id: UUID(), text: "Today row", dayKey: NoteDay().keys().today,
                         createdAt: Date(), completedAt: nil)
        fixture.repository.saved = [today]
        fixture.repository.savedLater = [LaterTask(id: UUID(), text: "Later row", createdAt: Date(), completedAt: nil)]
        fixture.launch()
        let status = try XCTUnwrap(fixture.delegate.taskStatusItemController)
        let presentation = try XCTUnwrap(fixture.delegate.taskWindowController?.presentation)
        XCTAssertEqual(presentation.selectedDestination, .today)
        try performGlanceItem("Later · 1 remaining", status)
        XCTAssertEqual(presentation.selectedDestination, .later)

        XCTAssertTrue(presentation.selectDestination(.today, state: fixture.state))
        XCTAssertTrue(presentation.showHistory(state: fixture.state))
        try performGlanceItem("Later · 1 remaining", status)
        XCTAssertEqual(presentation.route, .today)
        XCTAssertEqual(presentation.selectedDestination, .later)

        XCTAssertTrue(presentation.selectDestination(.today, state: fixture.state))
        fixture.state.beginEditing(id: today.id)
        fixture.state.editDraft = "Protected Today edit"
        try performGlanceItem("Later · 1 remaining", status)
        XCTAssertEqual(presentation.selectedDestination, .today)
        XCTAssertEqual(fixture.state.editingNoteID, today.id)
        XCTAssertEqual(fixture.state.editDraft, "Protected Today edit")
        fixture.state.cancelEditing()

        // ⌘2 still uses the same route after the refactor.
        let menu = try XCTUnwrap(NSApplication.shared.mainMenu)
        XCTAssertTrue(menu.performKeyEquivalent(with: commandEvent("2", keyCode: 19)))
        XCTAssertEqual(presentation.selectedDestination, .later)
        try performGlanceItem("Today row", status)
        XCTAssertEqual(presentation.selectedDestination, .today)
    }

    @MainActor
    func testGlanceRetryRefreshesAndActionsStopOnceTerminationBegins() throws {
        let fixture = try AppLifecycleFixture(context: .login)
        defer { fixture.cleanup() }
        fixture.repository.failTodayRead = true
        fixture.repository.savedLater = [LaterTask(id: UUID(), text: "Later row", createdAt: Date(), completedAt: nil)]
        fixture.launch()
        let status = try XCTUnwrap(fixture.delegate.taskStatusItemController)
        XCTAssertTrue(try glanceItem("Retry", status).isEnabled)
        XCTAssertNil(fixture.state.availableProgress)
        fixture.repository.failTodayRead = false
        try performGlanceItem("Retry", status)
        XCTAssertNotNil(fixture.state.availableProgress)
        XCTAssertNil(fixture.delegate.taskWindowController, "Retry must not raise a window")

        // Menus captured before termination: one available (Later line), one
        // unavailable (Retry). Quit is not sent, since a missing guard would
        // terminate the test host; it shares the same isTerminating guard.
        let menu = try XCTUnwrap(status.makeGlanceMenu?())
        fixture.repository.failTodayRead = true
        fixture.state.refresh()
        let unavailableMenu = try XCTUnwrap(status.makeGlanceMenu?())
        fixture.delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        XCTAssertNil(status.makeGlanceMenu?())
        XCTAssertNil(status.statusItem)
        fixture.repository.failTodayRead = false
        let reads = fixture.repository.readAttempts
        for (captured, title) in [(menu, "Open Today"), (menu, "Add Task…"), (menu, "Settings…"),
                                  (menu, "Later · 1 remaining"), (unavailableMenu, "Retry")] {
            let index = captured.indexOfItem(withTitle: title)
            XCTAssertGreaterThanOrEqual(index, 0, title)
            if index >= 0 { captured.performActionForItem(at: index) }
        }
        XCTAssertNil(fixture.state.availableProgress, "Retry must not refresh after termination begins")
        XCTAssertNil(fixture.delegate.taskWindowController)
        XCTAssertNil(fixture.delegate.settingsWindowController)
        XCTAssertEqual(fixture.repository.readAttempts, reads)
    }

    @MainActor
    private func glanceItem(_ title: String, _ status: TaskStatusItemController,
                            file: StaticString = #filePath, line: UInt = #line) throws -> NSMenuItem {
        let menu = try XCTUnwrap(status.makeGlanceMenu?(), file: file, line: line)
        XCTAssertNil(status.statusItem?.menu, "The glance stays detached from the status item", file: file, line: line)
        return try XCTUnwrap(menu.items.first { $0.title == title }, "No glance item \(title)", file: file, line: line)
    }

    /// Sends the item's action whether or not it is enabled, to prove disabled
    /// actions are also guarded. Builds a fresh menu, as each right-click does.
    @MainActor
    private func performGlanceItem(_ title: String, _ status: TaskStatusItemController,
                                   file: StaticString = #filePath, line: UInt = #line) throws {
        let menu = try XCTUnwrap(status.makeGlanceMenu?(), file: file, line: line)
        let item = try XCTUnwrap(menu.items.first { $0.title == title }, "No glance item \(title)",
                                 file: file, line: line)
        let action = try XCTUnwrap(item.action, file: file, line: line)
        XCTAssertTrue(NSApplication.shared.sendAction(action, to: item.target, from: item), file: file, line: line)
        withExtendedLifetime(menu) {}
    }

    @MainActor
    func testQuickAddFromLaterPreservesBothDraftsCategoriesSelectionAndProgress() async throws {
        let fixture = try AppLifecycleFixture(context: .manual, quickAddEnabled: true)
        defer { fixture.cleanup() }
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let later = LaterTask(id: UUID(), text: "Later saved", createdAt: Date(), completedAt: nil,
                              categoryID: home.id)
        fixture.repository.savedCategories = [work, home]
        fixture.repository.savedLater = [later]
        fixture.repository.allowAdd = true
        fixture.launch()
        let presentation = try XCTUnwrap(fixture.delegate.taskWindowController?.presentation)
        fixture.state.categoryPreferences.rememberLastUsed(work.id, in: .today)
        fixture.state.categoryPreferences.rememberLastUsed(home.id, in: .later)
        XCTAssertTrue(presentation.showComposer(in: .today, state: fixture.state))
        fixture.state.draft = "Today pending"
        XCTAssertTrue(presentation.selectDestination(.later, state: fixture.state))
        XCTAssertTrue(presentation.showComposer(in: .later, state: fixture.state))
        fixture.state.laterDraft = "Later pending"
        fixture.state.beginEditingLater(id: later.id)
        fixture.state.laterEditDraft = "Later edit"
        fixture.hotKeys.simulatePress()
        let panel = try XCTUnwrap(fixture.delegate.quickAddPanelController)
        panel.model.text = "Captured for Today"
        panel.submit()
        XCTAssertFalse(panel.isShown)
        XCTAssertEqual(fixture.repository.saved.map(\.text), ["Captured for Today"])
        XCTAssertEqual(fixture.repository.saved.first?.dayKey, fixture.state.todayKey)
        XCTAssertNil(fixture.repository.saved.first?.categoryID)
        XCTAssertEqual(fixture.repository.savedLater, [later])
        XCTAssertEqual(fixture.state.availableLaterRemainingCount, 1)
        XCTAssertEqual(presentation.selectedDestination, .later)
        XCTAssertEqual(fixture.state.draft, "Today pending")
        XCTAssertEqual(fixture.state.draftCategoryID, work.id)
        XCTAssertEqual(fixture.state.laterDraft, "Later pending")
        XCTAssertEqual(fixture.state.laterDraftCategoryID, home.id)
        XCTAssertEqual(fixture.state.laterEditDraft, "Later edit")
        XCTAssertEqual(fixture.state.editingLaterTaskID, later.id)
        XCTAssertEqual(fixture.state.categoryPreferences.lastUsedCategoryID, work.id)
        XCTAssertEqual(fixture.state.categoryPreferences.laterLastUsedCategoryID, home.id)
        await waitForStatusTitle("0/1", fixture: fixture)
    }

    @MainActor
    func testUnavailableQuickAddFromLaterRequestsTodayUnlessInteractionIsGuarded() throws {
        let fixture = try AppLifecycleFixture(context: .manual, quickAddEnabled: true)
        defer { fixture.cleanup() }
        let later = LaterTask(id: UUID(), text: "Later saved", createdAt: Date(), completedAt: nil)
        fixture.repository.savedLater = [later]
        fixture.launch()
        let controller = try XCTUnwrap(fixture.delegate.taskWindowController)
        let presentation = controller.presentation
        XCTAssertTrue(presentation.selectDestination(.later, state: fixture.state))
        fixture.state.laterDraft = "Later pending"
        fixture.state.beginEditingLater(id: later.id)
        fixture.state.laterEditDraft = "Protected edit"
        fixture.repository.failTodayRead = true
        fixture.state.refresh()
        fixture.hotKeys.simulatePress()
        XCTAssertNil(fixture.delegate.quickAddPanelController)
        XCTAssertEqual(presentation.selectedDestination, .later)
        XCTAssertEqual(fixture.state.laterEditDraft, "Protected edit")
        fixture.state.cancelEditingLater()
        fixture.hotKeys.simulatePress()
        XCTAssertEqual(presentation.selectedDestination, .today)
        XCTAssertTrue(controller.window?.isVisible == true)
        XCTAssertNil(fixture.state.availableProgress)
        XCTAssertEqual(fixture.state.laterDraft, "Later pending")
        XCTAssertNil(fixture.delegate.quickAddPanelController)
    }

    @MainActor
    func testQuickAddRegistersOnceAtLoginLaunchWithoutPresentingWindows() throws {
        let fixture = try AppLifecycleFixture(context: .login, quickAddEnabled: true)
        defer { fixture.cleanup() }
        let keyWindow = NSApplication.shared.keyWindow
        fixture.launch()
        fixture.launch()
        XCTAssertEqual(fixture.hotKeys.registerCount, 1)
        XCTAssertEqual(fixture.hotKeys.registeredCombination, .quickAdd)
        XCTAssertTrue(fixture.delegate.model.isQuickAddRegistered)
        XCTAssertNil(fixture.delegate.taskWindowController)
        XCTAssertNil(fixture.delegate.settingsWindowController)
        XCTAssertNil(fixture.delegate.quickAddPanelController)
        XCTAssertTrue(NSApplication.shared.keyWindow === keyWindow)
        XCTAssertFalse(fixture.onboarding.hasCompletedOnboarding)
    }

    @MainActor
    func testQuickAddStaysUnregisteredWhenOffAndFollowsTheSetting() throws {
        let fixture = try AppLifecycleFixture(context: .login)
        defer { fixture.cleanup() }
        fixture.launch()
        XCTAssertEqual(fixture.hotKeys.registerCount, 0)
        XCTAssertTrue(fixture.delegate.model.setQuickAddEnabled(true))
        XCTAssertTrue(fixture.hotKeys.isRegistered)
        XCTAssertTrue(fixture.delegate.model.setQuickAddEnabled(false))
        XCTAssertFalse(fixture.hotKeys.isRegistered)
        XCTAssertFalse(fixture.delegate.model.isQuickAddRegistered)
    }

    @MainActor
    func testQuickAddPanelSavesTaskWithoutChangingTheWindowsDraftEditOrError() async throws {
        let fixture = try AppLifecycleFixture(context: .login, quickAddEnabled: true)
        defer { fixture.cleanup() }
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let note = Note(id: UUID(), text: "Original", dayKey: NoteDay().keys().today,
                        createdAt: Date(), completedAt: nil)
        fixture.repository.saved = [note]
        fixture.repository.savedCategories = [work]
        fixture.repository.allowAdd = true
        fixture.launch()
        await waitForStatusTitle("0/1", fixture: fixture)
        fixture.state.draft = "Window draft"
        fixture.state.draftCategoryID = work.id
        fixture.state.beginEditing(id: note.id)
        fixture.state.editDraft = "Unsaved edit"
        fixture.state.editCategoryID = work.id

        fixture.hotKeys.simulatePress()
        let panel = try XCTUnwrap(fixture.delegate.quickAddPanelController)
        XCTAssertTrue(panel.isShown)
        XCTAssertNil(fixture.delegate.taskWindowController)
        panel.model.text = "  Captured task  "
        panel.submit()

        XCTAssertFalse(panel.isShown)
        // The fixture rejects any category on add, so this also proves General.
        XCTAssertEqual(fixture.repository.saved.map(\.text), ["Original", "Captured task"])
        XCTAssertNil(fixture.repository.saved.last?.categoryID)
        await waitForStatusTitle("0/2", fixture: fixture)
        XCTAssertEqual(fixture.state.draft, "Window draft")
        XCTAssertEqual(fixture.state.draftCategoryID, work.id)
        XCTAssertEqual(fixture.state.editingNoteID, note.id)
        XCTAssertEqual(fixture.state.editDraft, "Unsaved edit")
        XCTAssertEqual(fixture.state.editCategoryID, work.id)
        XCTAssertNil(fixture.state.issue)
        XCTAssertNil(fixture.delegate.taskWindowController)

        // One panel is reused, and a second press closes it and discards its text.
        fixture.hotKeys.simulatePress()
        XCTAssertTrue(fixture.delegate.quickAddPanelController === panel)
        XCTAssertTrue(panel.isShown)
        XCTAssertEqual(panel.model.text, "")
        panel.model.text = "Discarded"
        fixture.hotKeys.simulatePress()
        XCTAssertFalse(panel.isShown)
        XCTAssertEqual(panel.model.text, "")
        XCTAssertEqual(fixture.repository.saved.count, 2)
    }

    @MainActor
    func testQuickAddRejectedWriteKeepsTextAndErrorInThePanelOnly() throws {
        let fixture = try AppLifecycleFixture(context: .login, quickAddEnabled: true)
        defer { fixture.cleanup() }
        fixture.launch()
        fixture.state.draft = "Window draft"
        fixture.hotKeys.simulatePress()
        let panel = try XCTUnwrap(fixture.delegate.quickAddPanelController)
        panel.model.text = "Rejected"
        panel.submit()
        XCTAssertTrue(panel.isShown)
        XCTAssertEqual(panel.model.text, "Rejected")
        XCTAssertEqual(panel.model.errorMessage, QuickAddSubmitResult.writeFailed.message)
        XCTAssertEqual(fixture.state.draft, "Window draft")
        XCTAssertNil(fixture.state.issue)
        XCTAssertTrue(fixture.repository.saved.isEmpty)
    }

    @MainActor
    func testQuickAddWithUnavailableDataRefreshesOnceThenShowsPanelOrOpensToday() throws {
        let fixture = try AppLifecycleFixture(context: .login, quickAddEnabled: true)
        defer { fixture.cleanup() }
        fixture.repository.failRead = true
        fixture.launch()
        XCTAssertNil(fixture.state.availableProgress)

        // Still unavailable after one refresh: the Today window offers Retry.
        fixture.hotKeys.simulatePress()
        XCTAssertNil(fixture.delegate.quickAddPanelController)
        XCTAssertTrue(fixture.delegate.taskWindowController?.window?.isVisible == true)
        fixture.delegate.taskWindowController?.window?.close()

        // A refresh that succeeds shows the panel instead.
        XCTAssertNil(fixture.state.availableProgress)
        fixture.repository.failRead = false
        let reads = fixture.repository.readAttempts
        fixture.hotKeys.simulatePress()
        XCTAssertEqual(fixture.repository.readAttempts, reads + 1)
        XCTAssertTrue(fixture.delegate.quickAddPanelController?.isShown == true)
        XCTAssertNotNil(fixture.state.availableProgress)
    }

    @MainActor
    func testQuickAddShowsPanelWhileTheTodayWindowIsOpen() throws {
        let fixture = try AppLifecycleFixture(context: .manual, quickAddEnabled: true)
        defer { fixture.cleanup() }
        fixture.launch()
        let window = try XCTUnwrap(fixture.delegate.taskWindowController?.window)
        fixture.hotKeys.simulatePress()
        let panel = try XCTUnwrap(fixture.delegate.quickAddPanelController)
        XCTAssertTrue(panel.isShown)
        XCTAssertTrue(window.isVisible)
        panel.dismiss()
        XCTAssertFalse(panel.isShown)
        XCTAssertTrue(window.isVisible)
    }

    @MainActor
    func testRefusedQuickAddRegistrationIsReportedAndRetriedByTogglingOffAndOn() throws {
        let fixture = try AppLifecycleFixture(context: .login, quickAddEnabled: true)
        defer { fixture.cleanup() }
        fixture.hotKeys.registerError = .alreadyInUse
        fixture.launch()
        let model = fixture.delegate.model
        XCTAssertEqual(model.quickAddRegistrationFailure, .alreadyInUse)
        XCTAssertFalse(model.isQuickAddRegistered)
        XCTAssertTrue(model.preferences.quickAddEnabled)
        XCTAssertNil(fixture.delegate.taskWindowController)

        fixture.hotKeys.registerError = nil
        XCTAssertTrue(model.setQuickAddEnabled(false))
        XCTAssertNil(model.quickAddRegistrationFailure)
        XCTAssertTrue(model.setQuickAddEnabled(true))
        XCTAssertTrue(model.isQuickAddRegistered)
        XCTAssertNil(model.quickAddRegistrationFailure)
        XCTAssertTrue(fixture.hotKeys.isRegistered)
    }

    @MainActor
    func testTerminationUnregistersQuickAddAndClosesThePanel() throws {
        let fixture = try AppLifecycleFixture(context: .login, quickAddEnabled: true)
        defer { fixture.cleanup() }
        fixture.launch()
        fixture.hotKeys.simulatePress()
        let panel = try XCTUnwrap(fixture.delegate.quickAddPanelController)
        XCTAssertTrue(panel.isShown)
        fixture.delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        XCTAssertEqual(fixture.hotKeys.unregisterCount, 1)
        XCTAssertFalse(fixture.hotKeys.isRegistered)
        XCTAssertFalse(panel.isShown)
        fixture.delegate.quickAddHotKeyPressed()
        XCTAssertFalse(panel.isShown)
        XCTAssertNil(fixture.delegate.taskWindowController)
        // A saved change after termination no longer touches registration.
        XCTAssertTrue(fixture.delegate.model.setQuickAddEnabled(false))
        XCTAssertTrue(fixture.delegate.model.setQuickAddEnabled(true))
        XCTAssertEqual(fixture.hotKeys.registerCount, 1)
        XCTAssertEqual(fixture.hotKeys.unregisterCount, 1)
    }

    @MainActor
    private func waitForAppearance(_ name: NSAppearance.Name?) async {
        for _ in 0..<50 {
            if NSApplication.shared.appearance?.name == name { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(NSApplication.shared.appearance?.name, name)
    }

    @MainActor
    private func commandEvent(_ key: String, keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: NSApplication.shared.keyWindow?.windowNumber ?? 0,
            context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode)!
    }

    @MainActor
    private func focusedEditor(in window: NSWindow) async throws -> NSTextView {
        for _ in 0..<50 {
            if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor { return editor }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Task composer must receive native text focus")
        return try XCTUnwrap(window.firstResponder as? NSTextView)
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<50 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    @MainActor
    private func waitForStatusTitle(_ title: String, fixture: AppLifecycleFixture) async {
        for _ in 0..<50 {
            if fixture.delegate.taskStatusItemController?.statusItem?.button?.title == title { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(fixture.delegate.taskStatusItemController?.statusItem?.button?.title, title)
    }

}

private final class TaskWindowReadFixture: NoteRepository {
    var saved: [Note] = []
    var savedLater: [LaterTask] = []
    var savedCategories: [TaskCategory] = []
    var failRead = false
    var failTodayRead = false
    var failLaterRead = false
    var failDelete = false
    var deleteAttempts = 0
    var onDelete: (() -> Void)?
    var readAttempts = 0
    var allowAdd = false
    var failRemove = false
    var removeAttempts = 0
    var onRemove: (() -> Void)?

    func historyDaySnapshot(for dayKey: String) throws -> HistoryDaySnapshot {
        _ = try GregorianDay(key: dayKey)
        let catalog = try categories()
        return try HistoryDaySnapshot(dayKey: dayKey, notes: notes(for: dayKey), categories: catalog)
    }

    func unfinishedDayPage(before: GregorianDay, limit: Int) throws -> UnfinishedDayPage {
        guard limit > 0, limit < Int.max else { throw TaskHistoryDomainError.invalidPage }
        if failRead { throw CocoaError(.fileReadUnknown) }
        let notes = try saved.filter { try GregorianDay(key: $0.dayKey) < before }
        let summaries = try Dictionary(grouping: notes, by: \.dayKey).keys.sorted(by: >).map { dayKey in
            try DayTaskSummary(dayKey: dayKey, progress: NoteProgress(notes: notes, for: dayKey))
        }.filter { $0.incomplete > 0 }
        return try UnfinishedDayPage(before: before, limit: limit,
                                     summaries: Array(summaries.prefix(limit)),
                                     hasMore: summaries.count > limit)
    }

    func daySummaries(in range: HistoryDayRange) throws -> [DayTaskSummary] {
        if failRead { throw CocoaError(.fileReadUnknown) }
        let notes = try saved.filter { range.contains(try GregorianDay(key: $0.dayKey)) }
        return try Dictionary(grouping: notes, by: \.dayKey).keys.sorted().map { dayKey in
            try DayTaskSummary(dayKey: dayKey, progress: NoteProgress(notes: notes, for: dayKey))
        }
    }

    func categories() throws -> [TaskCategory] {
        if failRead { throw CocoaError(.fileReadUnknown) }
        return savedCategories
    }
    func createCategory(name: String) throws -> TaskCategory {
        let name = try TaskCategoryName.validate(name)
        guard !savedCategories.contains(where: { $0.nameKey == TaskCategoryName.key(for: name) }) else {
            throw TaskCategoryRepositoryError.duplicateName
        }
        let category = try TaskCategory(name: name,
                                        creationOrder: (savedCategories.map(\.creationOrder).max() ?? -1) + 1)
        savedCategories.append(category)
        return category
    }
    func renameCategory(id: UUID, name: String) throws -> TaskCategory { throw CocoaError(.fileWriteNoPermission) }
    /// Counts every saved day, like the store.
    func categoryUsageCount(id: UUID) throws -> Int {
        guard savedCategories.contains(where: { $0.id == id }) else { throw TaskCategoryRepositoryError.notFound(id) }
        return saved.count { $0.categoryID == id } + savedLater.count { $0.categoryID == id }
    }
    func removeCategory(id: UUID) throws {
        removeAttempts += 1
        onRemove?()
        if failRemove { throw CocoaError(.fileWriteNoPermission) }
        guard savedCategories.contains(where: { $0.id == id }) else { throw TaskCategoryRepositoryError.notFound(id) }
        savedCategories.removeAll { $0.id == id }
        saved = saved.map { note in
            Note(id: note.id, text: note.text, dayKey: note.dayKey, createdAt: note.createdAt,
                 completedAt: note.completedAt, categoryID: note.categoryID == id ? nil : note.categoryID)
        }
        savedLater = savedLater.map { task in
            LaterTask(id: task.id, text: task.text, createdAt: task.createdAt,
                      completedAt: task.completedAt, categoryID: task.categoryID == id ? nil : task.categoryID)
        }
    }

    func notes(for dayKey: String) throws -> [Note] {
        readAttempts += 1
        if failRead || failTodayRead { throw CocoaError(.fileReadUnknown) }
        return saved.filter { $0.dayKey == dayKey }
    }

    func incompleteCount(for dayKey: String) throws -> Int {
        saved.filter { $0.dayKey == dayKey && !$0.isCompleted }.count
    }

    func add(_ note: Note) throws {
        guard allowAdd else { throw CocoaError(.fileWriteNoPermission) }
        if let id = note.categoryID, !savedCategories.contains(where: { $0.id == id }) {
            throw TaskCategoryRepositoryError.notFound(id)
        }
        guard !saved.contains(where: { $0.id == note.id }) else { throw CocoaError(.fileWriteUnknown) }
        saved.append(note)
    }
    func setCompleted(id: UUID, completedAt: Date?) throws { throw CocoaError(.fileWriteNoPermission) }
    func update(id: UUID, text: String, categoryID: UUID?) throws { throw CocoaError(.fileWriteNoPermission) }
    func delete(id: UUID) throws {
        deleteAttempts += 1
        onDelete?()
        if failDelete { throw CocoaError(.fileWriteNoPermission) }
        guard saved.contains(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        saved.removeAll { $0.id == id }
    }

    func laterTasks() throws -> [LaterTask] {
        if failRead || failLaterRead { throw CocoaError(.fileReadUnknown) }
        return savedLater
    }
    func addLater(_ task: LaterTask) throws {
        guard allowAdd else { throw CocoaError(.fileWriteNoPermission) }
        try requireLaterCategory(task.categoryID)
        guard !savedLater.contains(where: { $0.id == task.id }) else { throw CocoaError(.fileWriteUnknown) }
        savedLater.append(task)
    }
    func setLaterCompleted(id: UUID, completedAt: Date?) throws {
        try mutateLater(id: id) { task in
            LaterTask(id: task.id, text: task.text, createdAt: task.createdAt,
                      completedAt: completedAt, categoryID: task.categoryID)
        }
    }
    func updateLater(id: UUID, text: String, categoryID: UUID?) throws {
        try requireLaterCategory(categoryID)
        try mutateLater(id: id) { task in
            LaterTask(id: task.id, text: text, createdAt: task.createdAt,
                      completedAt: task.completedAt, categoryID: categoryID)
        }
    }
    func deleteLater(id: UUID) throws {
        deleteAttempts += 1
        onDelete?()
        if failDelete { throw CocoaError(.fileWriteNoPermission) }
        guard savedLater.contains(where: { $0.id == id }) else { throw LaterTaskRepositoryError.notFound(id) }
        savedLater.removeAll { $0.id == id }
    }
    func moveLaterToToday(id: UUID, dayKey: String) throws -> Note {
        guard let task = savedLater.first(where: { $0.id == id }) else { throw LaterTaskRepositoryError.notFound(id) }
        guard !task.isCompleted else { throw LaterTaskRepositoryError.alreadyCompleted(id) }
        try requireLaterCategory(task.categoryID)
        guard !saved.contains(where: { $0.id == id }) else { throw LaterTaskRepositoryError.idCollision(id) }
        let note = Note(id: id, text: task.text, dayKey: dayKey, createdAt: task.createdAt,
                        completedAt: nil, categoryID: task.categoryID)
        saved.append(note)
        savedLater.removeAll { $0.id == id }
        return note
    }

    private func requireLaterCategory(_ id: UUID?) throws {
        if let id, !savedCategories.contains(where: { $0.id == id }) { throw TaskCategoryRepositoryError.notFound(id) }
    }

    private func mutateLater(id: UUID, change: (LaterTask) -> LaterTask) throws {
        guard let index = savedLater.firstIndex(where: { $0.id == id }) else { throw LaterTaskRepositoryError.notFound(id) }
        savedLater[index] = change(savedLater[index])
    }
}


@MainActor
private final class AppLifecycleFixture {
    let suite = "local.menupocket.tests.Lifecycle.\(UUID().uuidString)"
    let defaults: UserDefaults
    let onboarding: UserDefaultsOnboardingStore
    let repository = TaskWindowReadFixture()
    let notifications = NotificationCenter()
    let state: DailyNotesState
    let loginService = LifecycleLoginItemService()
    let hotKeys = FakeHotKeyService()
    let delegate: AppDelegate
    private let previousMenu = NSApplication.shared.mainMenu
    private let previousWindowsMenu = NSApplication.shared.windowsMenu
    private let previousAppearance = NSApplication.shared.appearance

    init(context: AppLaunchContext, quickAddEnabled: Bool = false) throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        if quickAddEnabled {
            var preferences = AppPreferences.defaultValue
            preferences.quickAddEnabled = true
            _ = try PreferencesStore(userDefaults: defaults).save(preferences)
        }
        onboarding = UserDefaultsOnboardingStore(userDefaults: defaults)
        let repository = repository
        state = DailyNotesState(repositoryFactory: { repository }, notificationCenter: notifications,
                                workspaceNotificationCenter: NotificationCenter(),
                                categoryPreferences: TaskCategoryPreferences(userDefaults: defaults))
        delegate = AppDelegate(model: AppModel(store: PreferencesStore(userDefaults: defaults),
                                              loginItemService: loginService, hotKeyService: hotKeys),
                               dailyNotesState: state, onboardingStore: onboarding, launchContext: { context })
    }

    func launch() {
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    }

    func cleanup() {
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        NSApplication.shared.mainMenu = previousMenu
        NSApplication.shared.windowsMenu = previousWindowsMenu
        NSApplication.shared.appearance = previousAppearance
        defaults.removePersistentDomain(forName: suite)
    }
}

private final class LifecycleLoginItemService: LoginItemService {
    private(set) var registrationAttempts = 0
    func readStatus() -> LoginItemStatus { .enabled }
    func register() -> LoginItemOperationResult {
        registrationAttempts += 1
        return LoginItemOperationResult(status: .enabled, failure: nil)
    }
    func unregister() -> LoginItemOperationResult {
        registrationAttempts += 1
        return LoginItemOperationResult(status: .disabled, failure: nil)
    }
    func openSystemSettingsLoginItems() { XCTFail("Lifecycle must not open system Settings") }
}
