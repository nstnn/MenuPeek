import AppKit
import Foundation
import XCTest
@testable import MenuPocket

@MainActor
final class AppModelLoadingTests: XCTestCase {
    func testPanelPhaseDistinguishesLoadingReadyEmptyAndFailureStates() {
        let snapshot = makeSnapshot("3 tasks", at: 1_700_000_000)

        XCTAssertEqual(ModulePanelPhase(state: ModuleRuntimeState()), .loading)
        XCTAssertEqual(
            ModulePanelPhase(state: ModuleRuntimeState(isLoading: true)),
            .loading
        )
        XCTAssertEqual(
            ModulePanelPhase(state: ModuleRuntimeState(
                snapshot: snapshot,
                hasCompletedAttempt: true
            )),
            .ready(snapshot)
        )
        XCTAssertEqual(
            ModulePanelPhase(state: ModuleRuntimeState(
                snapshot: snapshot,
                isLoading: true,
                hasCompletedAttempt: true
            )),
            .refreshing(snapshot)
        )
        XCTAssertEqual(
            ModulePanelPhase(state: ModuleRuntimeState(hasCompletedAttempt: true)),
            .empty
        )
        XCTAssertEqual(
            ModulePanelPhase(state: ModuleRuntimeState(
                lastError: "Provider implementation detail",
                hasCompletedAttempt: true
            )),
            .initialFailure
        )
        XCTAssertEqual(
            ModulePanelPhase(state: ModuleRuntimeState(
                snapshot: snapshot,
                lastError: "Provider implementation detail",
                hasCompletedAttempt: true
            )),
            .stale(snapshot)
        )
    }

    func testAppLaunchPreservesPreferencesWithoutStartingDemoLoads() async {
        var preferences = AppPreferences.defaultValue
        preferences.enabledModuleIDs = [ModuleCatalog.tasksID]
        preferences.menuBarDisplayMode = .iconAndInformation
        let store = LoadingPreferencesStore(preferences: preferences)
        let tasks = ControlledProvider(id: ModuleCatalog.tasksID)
        let status = ControlledProvider(id: ModuleCatalog.statusID)
        let model = AppModel(store: store, providers: [tasks, status])

        let delegate = AppDelegate(model: model, onboardingStore: CompletedOnboardingStore())
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        XCTAssertTrue(delegate.model === model)
        XCTAssertEqual(model.preferences, preferences)
        XCTAssertTrue(store.savedPreferences.isEmpty)
        XCTAssertEqual(model.currentLoadCount, 0)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.isLoading, false)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.statusID]?.isLoading, false)
        await assertRequests(tasks, [])
        await assertRequests(status, [])
    }

    func testEnableLoadsOnlyAfterSavedChangeAndUsesSessionScenario() async {
        var preferences = AppPreferences.defaultValue
        preferences.enabledModuleIDs = []
        preferences.pinnedModuleID = nil
        let store = LoadingPreferencesStore(preferences: preferences)
        let tasks = ControlledProvider(id: ModuleCatalog.tasksID)
        let status = ControlledProvider(id: ModuleCatalog.statusID)
        let model = AppModel(store: store, providers: [tasks, status])

        model.startInitialLoads()
        XCTAssertTrue(model.setDemoScenario(.noData, for: ModuleCatalog.statusID))
        await assertRequests(status, [])
        XCTAssertTrue(model.setModuleEnabled(ModuleCatalog.statusID, enabled: true))
        await status.waitForRequestCount(1)
        await assertRequests(status, [.noData])
        await status.completeNext(with: nil)
        await model.waitForCurrentLoad(of: ModuleCatalog.statusID)
        XCTAssertTrue(store.savedPreferences.last?.enabledModuleIDs.contains(ModuleCatalog.statusID) == true)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.statusID]?.hasCompletedAttempt, true)

        XCTAssertFalse(model.setModuleEnabled(ModuleCatalog.statusID, enabled: true))
        await assertRequests(status, [.noData])
        await assertRequests(tasks, [])

        store.saveOutcome = .writeProtected(
            .newerSchema(storedVersion: 2, supportedVersion: 1)
        )
        XCTAssertFalse(model.setModuleEnabled(ModuleCatalog.tasksID, enabled: true))
        await assertRequests(tasks, [])
        XCTAssertFalse(model.preferences.enabledModuleIDs.contains(ModuleCatalog.tasksID))
    }

    func testCompletedEmptyAndFailureAreNotReloadedByPanelOpen() async {
        let tasks = ControlledProvider(id: ModuleCatalog.tasksID)
        let status = ControlledProvider(id: ModuleCatalog.statusID)
        let model = makeModel(tasks: tasks, status: status)

        model.panelDidOpen()
        await tasks.waitForRequestCount(1)
        await status.waitForRequestCount(1)
        model.panelDidOpen()
        await tasks.completeNext(with: nil)
        await status.failNext()
        await model.waitForCurrentLoad(of: ModuleCatalog.tasksID)
        await model.waitForCurrentLoad(of: ModuleCatalog.statusID)

        let empty = model.runtimeStates[ModuleCatalog.tasksID]
        XCTAssertNil(empty?.snapshot)
        XCTAssertNil(empty?.lastError)
        XCTAssertEqual(empty?.hasCompletedAttempt, true)
        let failed = model.runtimeStates[ModuleCatalog.statusID]
        XCTAssertNil(failed?.snapshot)
        XCTAssertNotNil(failed?.lastError)
        XCTAssertEqual(failed?.hasCompletedAttempt, true)

        model.panelDidOpen()
        await assertRequests(tasks, [.normal])
        await assertRequests(status, [.normal])
        XCTAssertTrue(model.retryModule(ModuleCatalog.statusID))
        await status.waitForRequestCount(2)
        await status.completeNext(with: makeSnapshot("Ready", at: 1_700_000_100))
        await model.waitForCurrentLoad(of: ModuleCatalog.statusID)
        XCTAssertNil(model.runtimeStates[ModuleCatalog.statusID]?.lastError)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.statusID]?.snapshot?.primaryValue,
                       "Ready")
    }

    func testRefreshKeepsOldDataDuringLoadingAndFailureThenEmptyClearsIt() async {
        let tasks = ControlledProvider(id: ModuleCatalog.tasksID)
        let model = makeModel(tasks: tasks)
        let original = makeSnapshot("3 tasks", at: 1_700_000_000)

        XCTAssertEqual(model.menuBarDisplayText, "Demo: …")
        model.startInitialLoads()
        await tasks.waitForRequestCount(1)
        await tasks.completeNext(with: original)
        await model.waitForCurrentLoad(of: ModuleCatalog.tasksID)
        XCTAssertEqual(model.menuBarDisplayText, "Demo: 3 tasks")
        XCTAssertEqual(model.menuBarAccessibilityLabel, "MenuPocket, Demo: 3 tasks.")

        XCTAssertTrue(model.refreshModule(ModuleCatalog.tasksID))
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.snapshot, original)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.isLoading, true)
        XCTAssertNil(model.runtimeStates[ModuleCatalog.tasksID]?.lastError)
        XCTAssertEqual(model.menuBarDisplayText, "Demo: 3 tasks")
        XCTAssertEqual(
            model.menuBarAccessibilityLabel,
            "MenuPocket, Demo: 3 tasks. Refreshing demo data."
        )
        await tasks.waitForRequestCount(2)
        await tasks.failNext()
        await model.waitForCurrentLoad(of: ModuleCatalog.tasksID)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.snapshot, original)
        XCTAssertNotNil(model.runtimeStates[ModuleCatalog.tasksID]?.lastError)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.hasCompletedAttempt, true)
        XCTAssertEqual(model.menuBarDisplayText, "Demo: 3 tasks ⚠︎")
        XCTAssertEqual(
            model.menuBarAccessibilityLabel,
            "MenuPocket, Demo: 3 tasks. Warning: could not refresh; showing previous data."
        )

        XCTAssertTrue(model.retryModule(ModuleCatalog.tasksID))
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.snapshot, original)
        XCTAssertNil(model.runtimeStates[ModuleCatalog.tasksID]?.lastError)
        XCTAssertEqual(model.menuBarDisplayText, "Demo: 3 tasks")
        await tasks.waitForRequestCount(3)
        await tasks.completeNext(with: nil)
        await model.waitForCurrentLoad(of: ModuleCatalog.tasksID)
        XCTAssertNil(model.runtimeStates[ModuleCatalog.tasksID]?.snapshot)
        XCTAssertNil(model.runtimeStates[ModuleCatalog.tasksID]?.lastError)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.hasCompletedAttempt, true)
        XCTAssertEqual(model.menuBarDisplayText, "Demo: —")
        XCTAssertEqual(model.menuBarAccessibilityLabel, "MenuPocket, no demo data.")
    }

    func testModulesStayIndependentAndScenarioChangeReloadsOnlyItsModule() async {
        let tasks = ControlledProvider(id: ModuleCatalog.tasksID)
        let status = ControlledProvider(id: ModuleCatalog.statusID)
        let model = makeModel(tasks: tasks, status: status)
        let statusSnapshot = makeSnapshot("Ready", at: 1_700_000_100)

        model.startInitialLoads()
        await tasks.waitForRequestCount(1)
        await status.waitForRequestCount(1)
        await tasks.failNext()
        await status.completeNext(with: statusSnapshot)
        await model.waitForCurrentLoad(of: ModuleCatalog.tasksID)
        await model.waitForCurrentLoad(of: ModuleCatalog.statusID)
        XCTAssertNotNil(model.runtimeStates[ModuleCatalog.tasksID]?.lastError)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.statusID]?.snapshot, statusSnapshot)
        XCTAssertNil(model.runtimeStates[ModuleCatalog.statusID]?.lastError)

        XCTAssertFalse(model.setDemoScenario(.normal, for: ModuleCatalog.tasksID))
        XCTAssertTrue(model.setDemoScenario(.error, for: ModuleCatalog.tasksID))
        await tasks.waitForRequestCount(2)
        await assertRequests(tasks, [.normal, .error])
        await tasks.failNext()
        await model.waitForCurrentLoad(of: ModuleCatalog.tasksID)
        await assertRequests(status, [.normal])
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.statusID]?.snapshot, statusSnapshot)
    }

    func testGlobalRefreshTargetsEnabledModulesAndRetryTargetsOnlyItsModule() async {
        let tasks = ControlledProvider(id: ModuleCatalog.tasksID)
        let status = ControlledProvider(id: ModuleCatalog.statusID)
        let model = makeModel(tasks: tasks, status: status)

        model.startInitialLoads()
        await tasks.waitForRequestCount(1)
        await status.waitForRequestCount(1)
        await tasks.completeNext(with: makeSnapshot("3 tasks", at: 1_700_000_000))
        await status.completeNext(with: makeSnapshot("Ready", at: 1_700_000_100))
        await model.waitForCurrentLoad(of: ModuleCatalog.tasksID)
        await model.waitForCurrentLoad(of: ModuleCatalog.statusID)

        model.refreshEnabledModules()
        await tasks.waitForRequestCount(2)
        await status.waitForRequestCount(2)
        await tasks.completeNext(with: makeSnapshot("3 tasks", at: 1_700_000_200))
        await status.completeNext(with: makeSnapshot("Ready", at: 1_700_000_300))
        await model.waitForCurrentLoad(of: ModuleCatalog.tasksID)
        await model.waitForCurrentLoad(of: ModuleCatalog.statusID)
        await assertRequests(tasks, [.normal, .normal])
        await assertRequests(status, [.normal, .normal])

        XCTAssertTrue(model.retryModule(ModuleCatalog.tasksID))
        await tasks.waitForRequestCount(3)
        await tasks.completeNext(with: makeSnapshot("3 tasks", at: 1_700_000_400))
        await model.waitForCurrentLoad(of: ModuleCatalog.tasksID)
        await assertRequests(tasks, [.normal, .normal, .normal])
        await assertRequests(status, [.normal, .normal])
    }

    func testNewSessionResetsScenariosWhileRestoringProductPreferences() {
        var preferences = AppPreferences.defaultValue
        preferences.enabledModuleIDs = []
        preferences.pinnedModuleID = nil
        let store = LoadingPreferencesStore(preferences: preferences)
        let firstSession = AppModel(store: store, providers: [])

        XCTAssertTrue(firstSession.setDemoScenario(.error, for: ModuleCatalog.tasksID))
        XCTAssertTrue(firstSession.setDemoScenario(.slowResponse, for: ModuleCatalog.statusID))
        XCTAssertTrue(firstSession.moveModuleDown(ModuleCatalog.tasksID))
        XCTAssertTrue(firstSession.setMenuBarDisplayMode(.iconOnly))
        XCTAssertEqual(firstSession.demoScenarios[ModuleCatalog.tasksID], .error)
        XCTAssertEqual(firstSession.demoScenarios[ModuleCatalog.statusID], .slowResponse)

        let secondSession = AppModel(store: store, providers: [])

        XCTAssertEqual(secondSession.demoScenarios[ModuleCatalog.tasksID], .normal)
        XCTAssertEqual(secondSession.demoScenarios[ModuleCatalog.statusID], .normal)
        XCTAssertEqual(secondSession.preferences.moduleOrder,
                       [ModuleCatalog.statusID, ModuleCatalog.tasksID])
        XCTAssertEqual(secondSession.preferences.menuBarDisplayMode, .iconOnly)
        XCTAssertTrue(secondSession.preferences.enabledModuleIDs.isEmpty)
        XCTAssertNil(secondSession.preferences.pinnedModuleID)
    }

    func testNewRequestFinishesBeforeOldNoncooperativeResult() async {
        let tasks = ControlledProvider(id: ModuleCatalog.tasksID)
        let model = makeModel(tasks: tasks)
        let oldSnapshot = makeSnapshot("Old", at: 1_700_000_000)
        let newSnapshot = makeSnapshot("New", at: 1_700_000_100)

        model.startInitialLoads()
        await tasks.waitForRequestCount(1)
        let oldTask = model.currentLoadTask(of: ModuleCatalog.tasksID)
        XCTAssertTrue(model.setDemoScenario(.error, for: ModuleCatalog.tasksID))
        await tasks.waitForRequestCount(2)
        await assertRequests(tasks, [.normal, .error])
        XCTAssertEqual(model.currentLoadCount, 1)

        await tasks.complete(1, with: newSnapshot)
        await model.waitForCurrentLoad(of: ModuleCatalog.tasksID)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.snapshot, newSnapshot)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.isLoading, false)

        await tasks.complete(0, with: oldSnapshot)
        await oldTask?.value
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.snapshot, newSnapshot)
        XCTAssertNil(model.runtimeStates[ModuleCatalog.tasksID]?.lastError)
        XCTAssertEqual(model.currentLoadCount, 0)
        let cancelled = await tasks.cancelledRequestIndices()
        XCTAssertTrue(cancelled.contains(0))
    }

    func testOldFailureCannotClearNewRequestLoadingState() async {
        let tasks = ControlledProvider(id: ModuleCatalog.tasksID)
        let model = makeModel(tasks: tasks)
        let newSnapshot = makeSnapshot("New", at: 1_700_000_100)

        model.startInitialLoads()
        await tasks.waitForRequestCount(1)
        let oldTask = model.currentLoadTask(of: ModuleCatalog.tasksID)
        XCTAssertTrue(model.refreshModule(ModuleCatalog.tasksID))
        await tasks.waitForRequestCount(2)

        await tasks.fail(0)
        await oldTask?.value
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.isLoading, true)
        XCTAssertNil(model.runtimeStates[ModuleCatalog.tasksID]?.lastError)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.hasCompletedAttempt, false)
        XCTAssertEqual(model.currentLoadCount, 1)

        await tasks.complete(1, with: newSnapshot)
        await model.waitForCurrentLoad(of: ModuleCatalog.tasksID)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.snapshot, newSnapshot)
        XCTAssertEqual(model.currentLoadCount, 0)
    }

    func testDisablingSlowPinnedModuleRejectsLateResult() async {
        var preferences = AppPreferences.defaultValue
        preferences.enabledModuleIDs = [ModuleCatalog.tasksID]
        let tasks = ControlledProvider(id: ModuleCatalog.tasksID)
        let model = makeModel(preferences: preferences, tasks: tasks)

        XCTAssertTrue(model.setDemoScenario(.slowResponse, for: ModuleCatalog.tasksID))
        await tasks.waitForRequestCount(1)
        let oldTask = model.currentLoadTask(of: ModuleCatalog.tasksID)
        XCTAssertTrue(model.setModuleEnabled(ModuleCatalog.tasksID, enabled: false))
        XCTAssertNil(model.preferences.pinnedModuleID)
        XCTAssertNil(model.menuBarDisplayText)
        XCTAssertTrue(model.enabledModulesInOrder.isEmpty)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.isLoading, false)
        XCTAssertEqual(model.currentLoadCount, 0)

        await tasks.complete(0, with: makeSnapshot("Late", at: 1_700_000_000))
        await oldTask?.value
        XCTAssertNil(model.runtimeStates[ModuleCatalog.tasksID]?.snapshot)
        XCTAssertNil(model.runtimeStates[ModuleCatalog.tasksID]?.lastError)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.hasCompletedAttempt, false)
        let cancelled = await tasks.cancelledRequestIndices()
        XCTAssertTrue(cancelled.contains(0))
    }

    func testReenableRejectsResultFromBeforeDisable() async {
        var preferences = AppPreferences.defaultValue
        preferences.enabledModuleIDs = [ModuleCatalog.tasksID]
        let tasks = ControlledProvider(id: ModuleCatalog.tasksID)
        let model = makeModel(preferences: preferences, tasks: tasks)
        let newSnapshot = makeSnapshot("Reenabled", at: 1_700_000_100)

        model.startInitialLoads()
        await tasks.waitForRequestCount(1)
        let oldTask = model.currentLoadTask(of: ModuleCatalog.tasksID)
        XCTAssertTrue(model.setModuleEnabled(ModuleCatalog.tasksID, enabled: false))
        XCTAssertTrue(model.setModuleEnabled(ModuleCatalog.tasksID, enabled: true))
        await tasks.waitForRequestCount(2)

        await tasks.complete(0, with: makeSnapshot("Old", at: 1_700_000_000))
        await oldTask?.value
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.isLoading, true)
        XCTAssertNil(model.runtimeStates[ModuleCatalog.tasksID]?.snapshot)
        XCTAssertEqual(model.currentLoadCount, 1)

        await tasks.complete(1, with: newSnapshot)
        await model.waitForCurrentLoad(of: ModuleCatalog.tasksID)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.snapshot, newSnapshot)
    }

    func testQuitCancelsCurrentLoadsAndSuppressesLateErrors() async {
        let tasks = ControlledProvider(id: ModuleCatalog.tasksID)
        let status = ControlledProvider(id: ModuleCatalog.statusID)
        let model = makeModel(tasks: tasks, status: status)
        let delegate = AppDelegate(model: model, onboardingStore: CompletedOnboardingStore())

        model.startInitialLoads()
        await tasks.waitForRequestCount(1)
        await status.waitForRequestCount(1)
        let tasksLoad = model.currentLoadTask(of: ModuleCatalog.tasksID)
        let statusLoad = model.currentLoadTask(of: ModuleCatalog.statusID)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        XCTAssertEqual(model.currentLoadCount, 0)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.isLoading, false)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.statusID]?.isLoading, false)
        XCTAssertFalse(model.refreshModule(ModuleCatalog.tasksID))

        await tasks.fail(0)
        await status.complete(0, with: makeSnapshot("Late", at: 1_700_000_000))
        await tasksLoad?.value
        await statusLoad?.value
        XCTAssertNil(model.runtimeStates[ModuleCatalog.tasksID]?.lastError)
        XCTAssertNil(model.runtimeStates[ModuleCatalog.statusID]?.snapshot)
        XCTAssertEqual(model.currentLoadCount, 0)
        let tasksCancelled = await tasks.cancelledRequestIndices()
        let statusCancelled = await status.cancelledRequestIndices()
        XCTAssertTrue(tasksCancelled.contains(0))
        XCTAssertTrue(statusCancelled.contains(0))
    }

    func testRejectedDisableLeavesCurrentLoadAndPinIntact() async {
        var preferences = AppPreferences.defaultValue
        preferences.enabledModuleIDs = [ModuleCatalog.tasksID]
        let store = LoadingPreferencesStore(preferences: preferences)
        let tasks = ControlledProvider(id: ModuleCatalog.tasksID)
        let model = AppModel(store: store, providers: [tasks])
        let snapshot = makeSnapshot("3 tasks", at: 1_700_000_000)

        model.startInitialLoads()
        await tasks.waitForRequestCount(1)
        store.saveOutcome = .writeProtected(
            .newerSchema(storedVersion: 2, supportedVersion: 1)
        )
        XCTAssertFalse(model.setModuleEnabled(ModuleCatalog.tasksID, enabled: false))
        XCTAssertEqual(model.preferences.pinnedModuleID, ModuleCatalog.tasksID)
        XCTAssertTrue(model.preferences.enabledModuleIDs.contains(ModuleCatalog.tasksID))
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.isLoading, true)
        XCTAssertEqual(model.currentLoadCount, 1)

        await tasks.complete(0, with: snapshot)
        await model.waitForCurrentLoad(of: ModuleCatalog.tasksID)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.snapshot, snapshot)
        let cancelled = await tasks.cancelledRequestIndices()
        XCTAssertFalse(cancelled.contains(0))
    }

    func testCurrentCancellationIsNeitherErrorNorCompletedAttempt() async {
        let tasks = ControlledProvider(id: ModuleCatalog.tasksID)
        let model = makeModel(tasks: tasks)

        model.startInitialLoads()
        await tasks.waitForRequestCount(1)
        await tasks.cancel(0)
        await model.waitForCurrentLoad(of: ModuleCatalog.tasksID)
        XCTAssertNil(model.runtimeStates[ModuleCatalog.tasksID]?.lastError)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.isLoading, false)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.hasCompletedAttempt, false)
        XCTAssertEqual(model.currentLoadCount, 0)

        model.panelDidOpen()
        await tasks.waitForRequestCount(2)
        await tasks.complete(1, with: nil)
        await model.waitForCurrentLoad(of: ModuleCatalog.tasksID)
        XCTAssertEqual(model.runtimeStates[ModuleCatalog.tasksID]?.hasCompletedAttempt, true)
    }

    private func makeModel(
        preferences: AppPreferences = .defaultValue,
        tasks: ControlledProvider,
        status: ControlledProvider? = nil
    ) -> AppModel {
        AppModel(
            store: LoadingPreferencesStore(preferences: preferences),
            providers: [tasks] + (status.map { [$0] } ?? [])
        )
    }

    private func makeSnapshot(_ value: String, at time: TimeInterval) -> ModuleSnapshot {
        ModuleSnapshot(
            primaryValue: value,
            description: "Sample data",
            pinnedLabel: "Demo: \(value)",
            updatedAt: Date(timeIntervalSince1970: time)
        )
    }

    private func assertRequests(
        _ provider: ControlledProvider,
        _ expected: [DemoScenario],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let actual = await provider.requestedScenarios()
        XCTAssertEqual(actual, expected, file: file, line: line)
    }
}

private final class LoadingPreferencesStore: PreferencesStoring {
    var preferences: AppPreferences
    var saveOutcome: PreferencesSaveOutcome = .saved
    private(set) var savedPreferences: [AppPreferences] = []

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    func load() throws -> PreferencesLoadOutcome { .loaded(preferences) }

    func save(_ preferences: AppPreferences) throws -> PreferencesSaveOutcome {
        savedPreferences.append(preferences)
        if saveOutcome == .saved { self.preferences = preferences }
        return saveOutcome
    }
}

@MainActor
private final class CompletedOnboardingStore: OnboardingStoring {
    let hasCompletedOnboarding = true
    func markOnboardingCompleted() {}
}

private actor ControlledProvider: ModuleProvider {
    nonisolated let moduleID: ModuleDescriptor.ID
    private var scenarios: [DemoScenario] = []
    private var pending: [Int: CheckedContinuation<ModuleSnapshot?, any Error>] = [:]
    private var cancelledRequests: Set<Int> = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(id: ModuleDescriptor.ID) {
        moduleID = id
    }

    func load(scenario: DemoScenario) async throws -> ModuleSnapshot? {
        let index = scenarios.count
        scenarios.append(scenario)
        defer {
            if Task.isCancelled { cancelledRequests.insert(index) }
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending[index] = continuation
            let ready = waiters.filter { scenarios.count >= $0.0 }
            waiters.removeAll { scenarios.count >= $0.0 }
            for (_, waiter) in ready { waiter.resume() }
        }
    }

    func requestedScenarios() -> [DemoScenario] { scenarios }
    func cancelledRequestIndices() -> Set<Int> { cancelledRequests }

    func waitForRequestCount(_ count: Int) async {
        if scenarios.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func completeNext(with snapshot: ModuleSnapshot?) {
        complete(pending.keys.min()!, with: snapshot)
    }

    func failNext() {
        fail(pending.keys.min()!)
    }

    func complete(_ index: Int, with snapshot: ModuleSnapshot?) {
        guard let continuation = pending.removeValue(forKey: index) else {
            preconditionFailure("No pending request at index \(index)")
        }
        continuation.resume(returning: snapshot)
    }

    func fail(_ index: Int) {
        guard let continuation = pending.removeValue(forKey: index) else {
            preconditionFailure("No pending request at index \(index)")
        }
        continuation.resume(throwing: DemoProviderError.unavailable)
    }

    func cancel(_ index: Int) {
        guard let continuation = pending.removeValue(forKey: index) else {
            preconditionFailure("No pending request at index \(index)")
        }
        continuation.resume(throwing: CancellationError())
    }
}
