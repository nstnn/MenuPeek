import Foundation

struct ModuleDescriptor: Identifiable, Equatable, Sendable {
    typealias ID = String

    let id: ID
    let displayName: String
    let systemImageName: String
    let canBePinned: Bool
}

enum ModuleCatalog {
    static let tasksID: ModuleDescriptor.ID = "demo.tasks"
    static let statusID: ModuleDescriptor.ID = "demo.status"

    static let defaultModules: [ModuleDescriptor] = [
        ModuleDescriptor(
            id: tasksID,
            displayName: "Sample tasks",
            systemImageName: "checklist",
            canBePinned: true
        ),
        ModuleDescriptor(
            id: statusID,
            displayName: "Sample status",
            systemImageName: "circle.grid.2x2",
            canBePinned: true
        ),
    ]
}
