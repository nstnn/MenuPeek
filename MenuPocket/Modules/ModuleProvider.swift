import Foundation

struct ModuleSnapshot: Equatable, Sendable {
    let primaryValue: String
    let description: String
    let pinnedLabel: String
    /// The time this local fixture was loaded successfully, not an external update time.
    let updatedAt: Date
}

protocol ModuleProvider: Sendable {
    var moduleID: ModuleDescriptor.ID { get }

    /// A nil result is a completed, non-error empty response.
    func load(scenario: DemoScenario) async throws -> ModuleSnapshot?
}
