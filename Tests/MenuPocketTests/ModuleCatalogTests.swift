import XCTest
@testable import MenuPocket

final class ModuleCatalogTests: XCTestCase {
    func testDefaultCatalogDefinesStableModuleIdentities() {
        XCTAssertEqual(
            ModuleCatalog.defaultModules,
            [
                ModuleDescriptor(
                    id: "demo.tasks",
                    displayName: "Công việc mẫu",
                    systemImageName: "checklist",
                    canBePinned: true
                ),
                ModuleDescriptor(
                    id: "demo.status",
                    displayName: "Trạng thái mẫu",
                    systemImageName: "circle.grid.2x2",
                    canBePinned: true
                ),
            ]
        )
        XCTAssertEqual(ModuleCatalog.tasksID, "demo.tasks")
        XCTAssertEqual(ModuleCatalog.statusID, "demo.status")
    }

    func testDefaultPreferencesMatchFirstRunSpecification() {
        XCTAssertEqual(
            AppPreferences.defaultValue,
            AppPreferences(
                schemaVersion: 1,
                moduleOrder: ["demo.tasks", "demo.status"],
                enabledModuleIDs: ["demo.tasks", "demo.status"],
                pinnedModuleID: "demo.tasks",
                menuBarDisplayMode: .iconAndInformation
            )
        )
    }

    func testDefaultPreferencesRoundTripThroughCodable() throws {
        let data = try JSONEncoder().encode(AppPreferences.defaultValue)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)

        XCTAssertEqual(decoded, AppPreferences.defaultValue)
    }
}
