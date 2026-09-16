import Foundation

enum MenuBarDisplayMode: String, Codable, CaseIterable, Sendable {
    case iconOnly
    case iconAndInformation
}

struct AppPreferences: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var moduleOrder: [ModuleDescriptor.ID]
    var enabledModuleIDs: Set<ModuleDescriptor.ID>
    var pinnedModuleID: ModuleDescriptor.ID?
    var menuBarDisplayMode: MenuBarDisplayMode

    static let defaultValue = AppPreferences(
        schemaVersion: currentSchemaVersion,
        moduleOrder: ModuleCatalog.defaultModules.map(\.id),
        enabledModuleIDs: Set(ModuleCatalog.defaultModules.map(\.id)),
        pinnedModuleID: ModuleCatalog.tasksID,
        menuBarDisplayMode: .iconAndInformation
    )
}
