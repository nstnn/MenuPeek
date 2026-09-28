import AppKit
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
        let delegate = AppDelegate(model: AppModel(store: PreferencesStore(userDefaults: defaults)), dailyNotesState: state)
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
    func testAppDelegateReusesItsSettingsWindow() throws {
        let suiteName = "local.menupocket.tests.AppConfigurationTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(store: PreferencesStore(userDefaults: userDefaults))
        let delegate = AppDelegate(model: model)

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

    @MainActor
    func testFirstLaunchUsesSeparatePersistentMarkerAndOpensSettingsOnlyOnce() throws {
        let suiteName = "local.menupocket.tests.Onboarding.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let onboarding = UserDefaultsOnboardingStore(userDefaults: defaults)
        let first = AppDelegate(
            model: AppModel(store: PreferencesStore(userDefaults: defaults)),
            onboardingStore: onboarding
        )
        var presentations = 0

        XCTAssertNotNil(defaults.data(forKey: PreferencesStore.storageKey))
        XCTAssertFalse(onboarding.hasCompletedOnboarding)
        first.openSettingsOnFirstLaunchIfNeeded { presentations += 1 }
        XCTAssertEqual(presentations, 1)
        XCTAssertTrue(onboarding.hasCompletedOnboarding)

        let second = AppDelegate(
            model: AppModel(store: PreferencesStore(userDefaults: defaults)),
            onboardingStore: UserDefaultsOnboardingStore(userDefaults: defaults)
        )
        second.openSettingsOnFirstLaunchIfNeeded { presentations += 1 }
        XCTAssertEqual(presentations, 1)
        XCTAssertNil(second.settingsWindowController)
    }

    @MainActor
    func testCorruptPreferencesDoNotResetCompletedOnboarding() throws {
        let suiteName = "local.menupocket.tests.OnboardingRecovery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let onboarding = UserDefaultsOnboardingStore(userDefaults: defaults)
        onboarding.markOnboardingCompleted()
        let corruptData = Data("invalid".utf8)
        defaults.set(corruptData, forKey: PreferencesStore.storageKey)

        let delegate = AppDelegate(
            model: AppModel(store: PreferencesStore(userDefaults: defaults)),
            onboardingStore: onboarding
        )
        var presentations = 0
        delegate.openSettingsOnFirstLaunchIfNeeded { presentations += 1 }

        XCTAssertEqual(presentations, 0)
        XCTAssertEqual(delegate.model.preferenceWarning, .corruptData)
        XCTAssertTrue(delegate.model.isPreferenceEditingAllowed)
        XCTAssertEqual(defaults.data(forKey: PreferencesStore.storageKey), corruptData)
    }
}

private final class TaskWindowReadFixture: NoteRepository {
    var saved: [Note] = []
    var failRead = false

    func notes(for dayKey: String) throws -> [Note] {
        if failRead { throw CocoaError(.fileReadUnknown) }
        return saved.filter { $0.dayKey == dayKey }
    }

    func incompleteCount(for dayKey: String) throws -> Int {
        saved.filter { $0.dayKey == dayKey && !$0.isCompleted }.count
    }

    func add(_ note: Note) throws { throw CocoaError(.fileWriteNoPermission) }
    func setCompleted(id: UUID, completedAt: Date?) throws { throw CocoaError(.fileWriteNoPermission) }
    func updateText(id: UUID, text: String) throws { throw CocoaError(.fileWriteNoPermission) }
    func delete(id: UUID) throws { throw CocoaError(.fileWriteNoPermission) }
}
