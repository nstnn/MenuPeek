import Foundation
import Observation

struct MenuBarPresentation: Equatable {
    let displayText: String?
    let accessibilityLabel: String

    static let iconOnly = MenuBarPresentation(
        displayText: nil,
        accessibilityLabel: "MenuPocket"
    )

    init(pinnedState state: ModuleRuntimeState) {
        if let snapshot = state.snapshot {
            if state.lastError != nil {
                displayText = "\(snapshot.pinnedLabel) ⚠︎"
                accessibilityLabel =
                    "MenuPocket, \(snapshot.pinnedLabel). Warning: could not refresh; showing previous data."
            } else if state.isLoading {
                displayText = snapshot.pinnedLabel
                accessibilityLabel =
                    "MenuPocket, \(snapshot.pinnedLabel). Refreshing demo data."
            } else {
                displayText = snapshot.pinnedLabel
                accessibilityLabel = "MenuPocket, \(snapshot.pinnedLabel)."
            }
        } else if state.isLoading || !state.hasCompletedAttempt {
            displayText = "Demo: …"
            accessibilityLabel = "MenuPocket, loading demo data."
        } else if state.lastError != nil {
            displayText = "Demo: !"
            accessibilityLabel = "MenuPocket, could not load demo data."
        } else {
            // The source requires clearing stale data but does not prescribe the
            // compact empty label. An em dash keeps the result short and distinct.
            displayText = "Demo: —"
            accessibilityLabel = "MenuPocket, no demo data."
        }
    }

    private init(displayText: String?, accessibilityLabel: String) {
        self.displayText = displayText
        self.accessibilityLabel = accessibilityLabel
    }
}

@MainActor
@Observable
final class AppModel {
    private struct ActiveLoad {
        let requestID: UUID
        let task: Task<Void, Never>
    }

    private(set) var preferences: AppPreferences
    private(set) var preferenceWarning: PreferencesWarning?
    private(set) var isPreferenceEditingAllowed: Bool
    private(set) var preferenceSaveError: String?
    private(set) var runtimeStates: [ModuleDescriptor.ID: ModuleRuntimeState]
    private(set) var demoScenarios: [ModuleDescriptor.ID: DemoScenario]
    private(set) var loginItemStatus: LoginItemStatus
    private(set) var loginItemOperationFailure: LoginItemOperationFailure?

    @ObservationIgnored private let store: any PreferencesStoring
    @ObservationIgnored private let loginItemService: any LoginItemService
    @ObservationIgnored private let descriptorsByID: [ModuleDescriptor.ID: ModuleDescriptor]
    @ObservationIgnored private let providersByID: [ModuleDescriptor.ID: any ModuleProvider]
    @ObservationIgnored private var activeLoads: [ModuleDescriptor.ID: ActiveLoad] = [:]
    @ObservationIgnored private var isTerminating = false

    var currentLoadCount: Int { activeLoads.count }

    var modulesInOrder: [ModuleDescriptor] {
        preferences.moduleOrder.compactMap { descriptorsByID[$0] }
    }

    var enabledModulesInOrder: [ModuleDescriptor] {
        modulesInOrder.filter { preferences.enabledModuleIDs.contains($0.id) }
    }

    var enabledPinnableModulesInOrder: [ModuleDescriptor] {
        enabledModulesInOrder.filter(\.canBePinned)
    }

    var enabledModuleIDsInOrder: [ModuleDescriptor.ID] {
        enabledModulesInOrder.map(\.id)
    }

    var menuBarPresentation: MenuBarPresentation {
        guard preferences.menuBarDisplayMode == .iconAndInformation,
              let pinnedID = preferences.pinnedModuleID,
              enabledPinnableModulesInOrder.contains(where: { $0.id == pinnedID }) else {
            return .iconOnly
        }
        return MenuBarPresentation(
            pinnedState: runtimeStates[pinnedID] ?? ModuleRuntimeState()
        )
    }

    var menuBarDisplayText: String? { menuBarPresentation.displayText }

    var menuBarAccessibilityLabel: String { menuBarPresentation.accessibilityLabel }

    var isLoginItemEnabled: Bool { loginItemStatus == .enabled }

    var canChangeLoginItemRegistration: Bool {
        loginItemStatus == .disabled || loginItemStatus == .enabled
    }

    init(
        store: any PreferencesStoring = PreferencesStore(),
        catalog: [ModuleDescriptor] = ModuleCatalog.defaultModules,
        providers: [any ModuleProvider] = [],
        loginItemService: any LoginItemService = SystemLoginItemService()
    ) {
        self.store = store
        self.loginItemService = loginItemService
        loginItemStatus = loginItemService.readStatus()
        loginItemOperationFailure = nil
        descriptorsByID = Dictionary(
            catalog.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        providersByID = Dictionary(
            providers.map { ($0.moduleID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        runtimeStates = Dictionary(
            uniqueKeysWithValues: descriptorsByID.keys.map { ($0, ModuleRuntimeState()) }
        )
        demoScenarios = Dictionary(
            uniqueKeysWithValues: descriptorsByID.keys.map { ($0, DemoScenario.normal) }
        )

        do {
            let outcome = try store.load()
            preferences = outcome.preferences
            preferenceWarning = outcome.warning
            isPreferenceEditingAllowed = outcome.allowsPersistence
            preferenceSaveError = nil
        } catch {
            preferences = .defaultValue
            preferenceWarning = nil
            isPreferenceEditingAllowed = true
            preferenceSaveError = Self.saveErrorMessage
        }
    }

    @discardableResult
    func setModuleEnabled(_ id: ModuleDescriptor.ID, enabled: Bool) -> Bool {
        guard descriptorsByID[id] != nil else { return false }
        let changed = commit { candidate in
            if enabled {
                candidate.enabledModuleIDs.insert(id)
            } else {
                candidate.enabledModuleIDs.remove(id)
                if candidate.pinnedModuleID == id {
                    candidate.pinnedModuleID = nil
                }
            }
        }
        if changed {
            if enabled {
                _ = requestLoad(id)
            } else {
                cancelLoad(of: id)
            }
        }
        return changed
    }

    /// Called once from the app lifecycle, after preferences have been restored.
    func startInitialLoads() {
        loadUnattemptedEnabledModules()
    }

    /// A panel-open event is a fallback for modules that have never completed a load.
    func panelDidOpen() {
        loadUnattemptedEnabledModules()
    }

    @discardableResult
    func refreshModule(_ id: ModuleDescriptor.ID) -> Bool {
        requestLoad(id)
    }

    @discardableResult
    func retryModule(_ id: ModuleDescriptor.ID) -> Bool {
        requestLoad(id)
    }

    func refreshEnabledModules() {
        for id in enabledModuleIDsInOrder {
            _ = requestLoad(id)
        }
    }

    func refreshLoginItemStatus() {
        loginItemStatus = loginItemService.readStatus()
        loginItemOperationFailure = nil
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        guard canChangeLoginItemRegistration,
              enabled != isLoginItemEnabled else { return }

        let result = enabled ? loginItemService.register() : loginItemService.unregister()
        loginItemStatus = result.status
        loginItemOperationFailure = result.failure
    }

    func openSystemSettingsLoginItems() {
        guard loginItemStatus == .requiresApproval else { return }
        loginItemService.openSystemSettingsLoginItems()
    }

    @discardableResult
    func setDemoScenario(_ scenario: DemoScenario, for id: ModuleDescriptor.ID) -> Bool {
        guard descriptorsByID[id] != nil, demoScenarios[id] != scenario else { return false }
        demoScenarios[id] = scenario
        if preferences.enabledModuleIDs.contains(id) {
            _ = requestLoad(id)
        }
        return true
    }

    /// Lets deterministic checks await a triggered request without a timer or polling.
    func waitForCurrentLoad(of id: ModuleDescriptor.ID) async {
        if let task = activeLoads[id]?.task {
            await task.value
        }
    }

    /// Captures a specific request so race checks can await it after supersession.
    func currentLoadTask(of id: ModuleDescriptor.ID) -> Task<Void, Never>? {
        activeLoads[id]?.task
    }

    func cancelLoadsForTermination() {
        isTerminating = true
        let loads = activeLoads
        activeLoads.removeAll()
        for (id, load) in loads {
            var state = runtimeStates[id] ?? ModuleRuntimeState()
            state.isLoading = false
            runtimeStates[id] = state
            load.task.cancel()
        }
    }

    @discardableResult
    func moveModuleUp(_ id: ModuleDescriptor.ID) -> Bool {
        moveModule(id, by: -1)
    }

    @discardableResult
    func moveModuleDown(_ id: ModuleDescriptor.ID) -> Bool {
        moveModule(id, by: 1)
    }

    @discardableResult
    func setPinnedModule(_ id: ModuleDescriptor.ID?) -> Bool {
        if let id {
            guard descriptorsByID[id]?.canBePinned == true,
                  preferences.enabledModuleIDs.contains(id) else { return false }
        }
        return commit { $0.pinnedModuleID = id }
    }

    @discardableResult
    func setMenuBarDisplayMode(_ mode: MenuBarDisplayMode) -> Bool {
        commit { $0.menuBarDisplayMode = mode }
    }

    @discardableResult
    func setTheme(_ theme: AppTheme) -> Bool {
        commit { $0.theme = theme }
    }

    @discardableResult
    func setQuickAddEnabled(_ enabled: Bool) -> Bool {
        commit { $0.quickAddEnabled = enabled }
    }

    private func moveModule(_ id: ModuleDescriptor.ID, by offset: Int) -> Bool {
        guard let index = preferences.moduleOrder.firstIndex(of: id),
              preferences.moduleOrder.indices.contains(index + offset) else { return false }
        return commit { $0.moduleOrder.swapAt(index, index + offset) }
    }

    private func loadUnattemptedEnabledModules() {
        for id in enabledModuleIDsInOrder {
            guard let state = runtimeStates[id],
                  !state.hasCompletedAttempt,
                  !state.isLoading else { continue }
            _ = requestLoad(id)
        }
    }

    @discardableResult
    private func requestLoad(_ id: ModuleDescriptor.ID) -> Bool {
        guard !isTerminating,
              preferences.enabledModuleIDs.contains(id),
              let provider = providersByID[id],
              descriptorsByID[id] != nil else { return false }

        activeLoads[id]?.task.cancel()

        var state = runtimeStates[id] ?? ModuleRuntimeState()
        state.isLoading = true
        state.lastError = nil
        runtimeStates[id] = state

        let scenario = demoScenarios[id] ?? .normal
        let requestID = UUID()
        let task = Task { [weak self] in
            do {
                let snapshot = try await provider.load(scenario: scenario)
                self?.finishLoad(
                    of: id, requestID: requestID,
                    result: .success(snapshot), wasCancelled: Task.isCancelled
                )
            } catch is CancellationError {
                self?.finishCancelledLoad(of: id, requestID: requestID)
            } catch {
                self?.finishLoad(
                    of: id, requestID: requestID,
                    result: .failure(error), wasCancelled: Task.isCancelled
                )
            }
        }
        activeLoads[id] = ActiveLoad(requestID: requestID, task: task)
        return true
    }

    private func finishLoad(
        of id: ModuleDescriptor.ID,
        requestID: UUID,
        result: Result<ModuleSnapshot?, any Error>,
        wasCancelled: Bool
    ) {
        guard isCurrentLoad(of: id, requestID: requestID) else { return }
        if wasCancelled {
            finishCancelledLoad(of: id, requestID: requestID)
            return
        }

        var state = runtimeStates[id] ?? ModuleRuntimeState()
        state.isLoading = false
        state.hasCompletedAttempt = true
        switch result {
        case let .success(snapshot):
            // A nil response is completed empty data, not an error.
            state.snapshot = snapshot
            state.lastError = nil
        case let .failure(error):
            // Keep the last successful snapshot and its timestamp.
            state.lastError = error.localizedDescription
        }
        runtimeStates[id] = state
        activeLoads[id] = nil
    }

    private func finishCancelledLoad(of id: ModuleDescriptor.ID, requestID: UUID) {
        guard isCurrentLoad(of: id, requestID: requestID) else { return }
        var state = runtimeStates[id] ?? ModuleRuntimeState()
        state.isLoading = false
        runtimeStates[id] = state
        activeLoads[id] = nil
    }

    private func isCurrentLoad(of id: ModuleDescriptor.ID, requestID: UUID) -> Bool {
        !isTerminating && preferences.enabledModuleIDs.contains(id) &&
            activeLoads[id]?.requestID == requestID
    }

    private func cancelLoad(of id: ModuleDescriptor.ID) {
        let task = activeLoads[id]?.task
        activeLoads[id] = nil
        var state = runtimeStates[id] ?? ModuleRuntimeState()
        state.isLoading = false
        runtimeStates[id] = state
        task?.cancel()
    }

    private func commit(_ change: (inout AppPreferences) -> Void) -> Bool {
        guard isPreferenceEditingAllowed else { return false }

        var candidate = preferences
        change(&candidate)
        guard candidate != preferences else { return false }

        do {
            switch try store.save(candidate) {
            case .saved:
                preferences = candidate
                preferenceSaveError = nil
                return true
            case let .writeProtected(warning):
                preferenceWarning = warning
                isPreferenceEditingAllowed = false
                preferenceSaveError = nil
                return false
            }
        } catch {
            preferenceSaveError = Self.saveErrorMessage
            return false
        }
    }

    private static let saveErrorMessage =
        "Could not save preferences. The change was not applied; try again."
}
