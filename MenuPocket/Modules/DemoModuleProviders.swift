import Foundation

enum DemoScenario: String, CaseIterable, Sendable {
    case normal
    case noData
    case error
    case slowResponse

    var displayName: String {
        switch self {
        case .normal: "Bình thường"
        case .noData: "Không có dữ liệu"
        case .error: "Lỗi"
        case .slowResponse: "Phản hồi chậm"
        }
    }
}

enum DemoProviderError: Error, Equatable, Sendable {
    case unavailable
}

typealias DemoDelay = @Sendable (Duration) async throws -> Void

private struct DemoFixtureProvider: Sendable {
    let primaryValue: String
    let pinnedLabel: String
    let clock: @Sendable () -> Date
    let delay: DemoDelay

    func load(scenario: DemoScenario) async throws -> ModuleSnapshot? {
        try Task.checkCancellation()

        switch scenario {
        case .noData:
            return nil
        case .error:
            throw DemoProviderError.unavailable
        case .slowResponse:
            try await delay(.seconds(2))
        case .normal:
            break
        }

        try Task.checkCancellation()
        return ModuleSnapshot(
            primaryValue: primaryValue,
            description: "Dữ liệu minh họa",
            pinnedLabel: pinnedLabel,
            updatedAt: clock()
        )
    }
}

struct DemoTasksProvider: ModuleProvider {
    let moduleID = ModuleCatalog.tasksID
    private let fixture: DemoFixtureProvider

    init(
        clock: @escaping @Sendable () -> Date = { Date() },
        delay: @escaping DemoDelay = { try await Task.sleep(for: $0) }
    ) {
        fixture = DemoFixtureProvider(
            primaryValue: "3 việc",
            pinnedLabel: "Demo: 3 việc",
            clock: clock,
            delay: delay
        )
    }

    func load(scenario: DemoScenario) async throws -> ModuleSnapshot? {
        try await fixture.load(scenario: scenario)
    }
}

struct DemoStatusProvider: ModuleProvider {
    let moduleID = ModuleCatalog.statusID
    private let fixture: DemoFixtureProvider

    init(
        clock: @escaping @Sendable () -> Date = { Date() },
        delay: @escaping DemoDelay = { try await Task.sleep(for: $0) }
    ) {
        fixture = DemoFixtureProvider(
            primaryValue: "Sẵn sàng",
            pinnedLabel: "Demo: OK",
            clock: clock,
            delay: delay
        )
    }

    func load(scenario: DemoScenario) async throws -> ModuleSnapshot? {
        try await fixture.load(scenario: scenario)
    }
}
