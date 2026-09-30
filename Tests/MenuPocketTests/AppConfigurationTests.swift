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
        let host = try XCTUnwrap(window.contentViewController as? NSHostingController<TaskWindowView>)
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
                                   workspaceNotificationCenter: NotificationCenter())
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
        let note = Note(id: UUID(), text: "Original task", dayKey: day.keys().today,
                        createdAt: instant, completedAt: nil)
        store.saved = [note]
        let state = DailyNotesState(repositoryFactory: { store }, day: day,
                                   notificationCenter: NotificationCenter(),
                                   workspaceNotificationCenter: NotificationCenter())
        let controller = TaskWindowController(state: state, onSettings: {})
        defer { controller.window?.close() }
        controller.showTasks()
        state.draft = "Separate new draft"
        state.beginEditing(id: note.id)
        state.editDraft = "Retain this edit"
        controller.presentation.requestDeletion(id: note.id, state: state)
        XCTAssertNotNil(controller.presentation.deletionTarget)
        controller.window?.close()
        XCTAssertNil(controller.presentation.deletionTarget)
        XCTAssertFalse(controller.presentation.confirmDeletion(state: state))
        controller.showTasks()
        XCTAssertEqual(state.editingNoteID, note.id)
        XCTAssertEqual(state.editDraft, "Retain this edit")
        XCTAssertEqual(state.draft, "Separate new draft")
        XCTAssertEqual(store.saved, [note])
        XCTAssertEqual(store.deleteAttempts, 0)
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
                                   workspaceNotificationCenter: NotificationCenter())
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
                                   workspaceNotificationCenter: NotificationCenter())
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
                notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter()),
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
        let note = Note(id: UUID(), text: "Original", dayKey: NoteDay().keys().today,
                        createdAt: Date(), completedAt: nil)
        fixture.repository.saved = [note]
        fixture.repository.allowAdd = true
        fixture.launch()
        await waitForStatusTitle("0/1", fixture: fixture)
        fixture.state.draft = "Window draft"
        fixture.state.beginEditing(id: note.id)
        fixture.state.editDraft = "Unsaved edit"

        fixture.hotKeys.simulatePress()
        let panel = try XCTUnwrap(fixture.delegate.quickAddPanelController)
        XCTAssertTrue(panel.isShown)
        XCTAssertNil(fixture.delegate.taskWindowController)
        panel.model.text = "  Captured task  "
        panel.submit()

        XCTAssertFalse(panel.isShown)
        XCTAssertEqual(fixture.repository.saved.map(\.text), ["Original", "Captured task"])
        XCTAssertNil(fixture.repository.saved.last?.categoryID)
        await waitForStatusTitle("0/2", fixture: fixture)
        XCTAssertEqual(fixture.state.draft, "Window draft")
        XCTAssertEqual(fixture.state.editingNoteID, note.id)
        XCTAssertEqual(fixture.state.editDraft, "Unsaved edit")
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
    var failRead = false
    var failDelete = false
    var deleteAttempts = 0
    var onDelete: (() -> Void)?
    var readAttempts = 0
    var allowAdd = false

    func notes(for dayKey: String) throws -> [Note] {
        readAttempts += 1
        if failRead { throw CocoaError(.fileReadUnknown) }
        return saved.filter { $0.dayKey == dayKey }
    }

    func incompleteCount(for dayKey: String) throws -> Int {
        saved.filter { $0.dayKey == dayKey && !$0.isCompleted }.count
    }

    func add(_ note: Note) throws {
        guard allowAdd else { throw CocoaError(.fileWriteNoPermission) }
        saved.append(note)
    }
    func setCompleted(id: UUID, completedAt: Date?) throws { throw CocoaError(.fileWriteNoPermission) }
    func updateText(id: UUID, text: String) throws { throw CocoaError(.fileWriteNoPermission) }
    func delete(id: UUID) throws {
        deleteAttempts += 1
        onDelete?()
        if failDelete { throw CocoaError(.fileWriteNoPermission) }
        guard saved.contains(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        saved.removeAll { $0.id == id }
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
                                workspaceNotificationCenter: NotificationCenter())
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
