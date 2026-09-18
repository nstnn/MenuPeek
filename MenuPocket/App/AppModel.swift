import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var preferences: AppPreferences
    private(set) var preferenceWarning: PreferencesWarning?
    private(set) var isPreferenceEditingAllowed: Bool
    private(set) var preferenceSaveError: String?
    private(set) var runtimeStates: [ModuleDescriptor.ID: ModuleRuntimeState]
    private(set) var demoScenarios: [ModuleDescriptor.ID: DemoScenario]

    @ObservationIgnored private let store: any PreferencesStoring
    @ObservationIgnored private let descriptorsByID: [ModuleDescriptor.ID: ModuleDescriptor]
    @ObservationIgnored private let providersByID: [ModuleDescriptor.ID: any ModuleProvider]
    @ObservationIgnored private var activeLoads: [ModuleDescriptor.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingReloads: Set<ModuleDescriptor.ID> = []

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

    // TASK-016 will replace this placeholder with the pinned module's runtime value.
    var menuBarDisplayText: String? {
        guard preferences.menuBarDisplayMode == .iconAndInformation,
              let pinnedID = preferences.pinnedModuleID,
              enabledPinnableModulesInOrder.contains(where: { $0.id == pinnedID }) else {
            return nil
        }
        return "Demo: …"
    }

    init(
        store: any PreferencesStoring = PreferencesStore(),
        catalog: [ModuleDescriptor] = ModuleCatalog.defaultModules,
        providers: [any ModuleProvider] = [DemoTasksProvider(), DemoStatusProvider()]
    ) {
        self.store = store
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
        if changed && enabled {
            _ = requestLoad(id)
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
        if let task = activeLoads[id] {
            await task.value
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
        guard preferences.enabledModuleIDs.contains(id),
              let provider = providersByID[id],
              descriptorsByID[id] != nil else { return false }

        if activeLoads[id] != nil {
            // A later explicit trigger is not lost while this module is loading.
            // TASK-014 will cancel/supersede the old request and reject late results.
            pendingReloads.insert(id)
            return true
        }

        var state = runtimeStates[id] ?? ModuleRuntimeState()
        state.isLoading = true
        state.lastError = nil
        runtimeStates[id] = state

        let scenario = demoScenarios[id] ?? .normal
        activeLoads[id] = Task { [weak self] in
            do {
                let snapshot = try await provider.load(scenario: scenario)
                self?.finishLoad(of: id, result: .success(snapshot))
            } catch is CancellationError {
                self?.finishCancelledLoad(of: id)
            } catch {
                self?.finishLoad(of: id, result: .failure(error))
            }
        }
        return true
    }

    private func finishLoad(
        of id: ModuleDescriptor.ID,
        result: Result<ModuleSnapshot?, any Error>
    ) {
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
        finishTaskBookkeeping(for: id)
    }

    private func finishCancelledLoad(of id: ModuleDescriptor.ID) {
        var state = runtimeStates[id] ?? ModuleRuntimeState()
        state.isLoading = false
        runtimeStates[id] = state
        finishTaskBookkeeping(for: id)
    }

    private func finishTaskBookkeeping(for id: ModuleDescriptor.ID) {
        activeLoads[id] = nil
        if pendingReloads.remove(id) != nil,
           preferences.enabledModuleIDs.contains(id) {
            _ = requestLoad(id)
        }
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
        "Không thể lưu cài đặt. Thay đổi chưa được áp dụng; hãy thử lại."
}
