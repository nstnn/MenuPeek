import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var preferences: AppPreferences
    private(set) var preferenceWarning: PreferencesWarning?
    private(set) var isPreferenceEditingAllowed: Bool
    private(set) var preferenceSaveError: String?

    @ObservationIgnored private let store: any PreferencesStoring
    @ObservationIgnored private let descriptorsByID: [ModuleDescriptor.ID: ModuleDescriptor]

    var enabledModuleIDsInOrder: [ModuleDescriptor.ID] {
        preferences.moduleOrder.filter { preferences.enabledModuleIDs.contains($0) }
    }

    init(
        store: any PreferencesStoring = PreferencesStore(),
        catalog: [ModuleDescriptor] = ModuleCatalog.defaultModules
    ) {
        self.store = store
        descriptorsByID = Dictionary(
            catalog.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
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
        return commit { candidate in
            if enabled {
                candidate.enabledModuleIDs.insert(id)
            } else {
                candidate.enabledModuleIDs.remove(id)
                if candidate.pinnedModuleID == id {
                    candidate.pinnedModuleID = nil
                }
            }
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
