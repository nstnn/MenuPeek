import Foundation

struct PreferencesReconciler {
    private let catalog: [ModuleDescriptor]

    init(catalog: [ModuleDescriptor] = ModuleCatalog.defaultModules) {
        self.catalog = catalog
    }

    func reconcile(_ storedPreferences: AppPreferences) -> AppPreferences {
        let descriptorsByID = Dictionary(
            catalog.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let catalogIDs = catalog.map(\.id)
        let knownIDs = Set(catalogIDs)

        var seenIDs = Set<ModuleDescriptor.ID>()
        var reconciledOrder = storedPreferences.moduleOrder.filter { id in
            knownIDs.contains(id) && seenIDs.insert(id).inserted
        }
        reconciledOrder.append(contentsOf: catalogIDs.filter { seenIDs.insert($0).inserted })

        let reconciledEnabledIDs = storedPreferences.enabledModuleIDs.intersection(knownIDs)
        let reconciledPinnedID: ModuleDescriptor.ID? = storedPreferences.pinnedModuleID.flatMap { id in
            guard
                reconciledEnabledIDs.contains(id),
                descriptorsByID[id]?.canBePinned == true
            else {
                return nil
            }
            return id
        }

        return AppPreferences(
            schemaVersion: AppPreferences.currentSchemaVersion,
            moduleOrder: reconciledOrder,
            enabledModuleIDs: reconciledEnabledIDs,
            pinnedModuleID: reconciledPinnedID,
            menuBarDisplayMode: storedPreferences.menuBarDisplayMode,
            theme: storedPreferences.theme,
            quickAddEnabled: storedPreferences.quickAddEnabled
        )
    }
}
