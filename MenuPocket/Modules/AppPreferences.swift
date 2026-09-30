import Foundation

enum MenuBarDisplayMode: String, Codable, CaseIterable, Sendable {
    case iconOnly
    case iconAndInformation
}

enum AppTheme: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
}

struct AppPreferences: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var moduleOrder: [ModuleDescriptor.ID]
    var enabledModuleIDs: Set<ModuleDescriptor.ID>
    var pinnedModuleID: ModuleDescriptor.ID?
    var menuBarDisplayMode: MenuBarDisplayMode
    var theme: AppTheme

    static let defaultValue = AppPreferences(
        schemaVersion: currentSchemaVersion,
        moduleOrder: ModuleCatalog.defaultModules.map(\.id),
        enabledModuleIDs: Set(ModuleCatalog.defaultModules.map(\.id)),
        pinnedModuleID: ModuleCatalog.tasksID,
        menuBarDisplayMode: .iconAndInformation,
        theme: .system
    )
}

// Declared in an extension so the memberwise initializer remains available.
extension AppPreferences {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        moduleOrder = try container.decode([ModuleDescriptor.ID].self, forKey: .moduleOrder)
        enabledModuleIDs = try container.decode(Set<ModuleDescriptor.ID>.self, forKey: .enabledModuleIDs)
        pinnedModuleID = try container.decodeIfPresent(ModuleDescriptor.ID.self, forKey: .pinnedModuleID)
        menuBarDisplayMode = try container.decode(MenuBarDisplayMode.self, forKey: .menuBarDisplayMode)
        // Schema 1 preferences saved before the theme existed have no value.
        // A missing or unrecognized theme falls back to the default instead of
        // making the whole value unreadable, which would discard other fields.
        theme = try container.decodeIfPresent(String.self, forKey: .theme)
            .flatMap(AppTheme.init(rawValue:)) ?? Self.defaultValue.theme
    }
}
