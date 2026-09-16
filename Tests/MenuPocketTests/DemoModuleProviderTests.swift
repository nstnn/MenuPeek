import Foundation
import XCTest
@testable import MenuPocket

@MainActor
final class DemoModuleProviderTests: XCTestCase {
    private actor DelayRecorder {
        private var requested: [Duration] = []

        func record(_ duration: Duration) {
            requested.append(duration)
        }

        func durations() -> [Duration] {
            requested
        }
    }

    func testNormalReturnsExactFixturesWithInjectedSuccessfulLoadTime() async throws {
        let loadedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let tasks = DemoTasksProvider(clock: { loadedAt })
        let status = DemoStatusProvider(clock: { loadedAt })

        XCTAssertEqual(tasks.moduleID, "demo.tasks")
        XCTAssertEqual(status.moduleID, "demo.status")
        let taskSnapshot = try await tasks.load(scenario: .normal)
        let statusSnapshot = try await status.load(scenario: .normal)
        XCTAssertEqual(
            taskSnapshot,
            ModuleSnapshot(
                primaryValue: "3 việc",
                description: "Dữ liệu minh họa",
                pinnedLabel: "Demo: 3 việc",
                updatedAt: loadedAt
            )
        )
        XCTAssertEqual(
            statusSnapshot,
            ModuleSnapshot(
                primaryValue: "Sẵn sàng",
                description: "Dữ liệu minh họa",
                pinnedLabel: "Demo: OK",
                updatedAt: loadedAt
            )
        )
    }

    func testNoDataIsAnEmptyResultForEitherModule() async throws {
        let providers: [any ModuleProvider] = [DemoTasksProvider(), DemoStatusProvider()]
        for provider in providers {
            let result = try await provider.load(scenario: .noData)
            XCTAssertNil(result, provider.moduleID)
        }
    }

    func testErrorIsControlledForEitherModule() async {
        let providers: [any ModuleProvider] = [DemoTasksProvider(), DemoStatusProvider()]
        for provider in providers {
            do {
                _ = try await provider.load(scenario: .error)
                XCTFail("Expected the controlled demo error for \(provider.moduleID)")
            } catch {
                XCTAssertEqual(error as? DemoProviderError, .unavailable)
            }
        }
    }

    func testSlowResponseRequestsTwoSecondsWithoutWaitingAndReturnsFixtures() async throws {
        let recorder = DelayRecorder()
        let loadedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let delay: DemoDelay = { duration in await recorder.record(duration) }
        let tasks = DemoTasksProvider(clock: { loadedAt }, delay: delay)
        let status = DemoStatusProvider(clock: { loadedAt }, delay: delay)

        let taskSnapshot = try await tasks.load(scenario: .slowResponse)
        let statusSnapshot = try await status.load(scenario: .slowResponse)
        let requestedDelays = await recorder.durations()
        let normalTaskSnapshot = try await tasks.load(scenario: .normal)
        let normalStatusSnapshot = try await status.load(scenario: .normal)
        let delaysAfterNormal = await recorder.durations()

        XCTAssertEqual(requestedDelays, [.seconds(2), .seconds(2)])
        XCTAssertEqual(taskSnapshot, normalTaskSnapshot)
        XCTAssertEqual(statusSnapshot, normalStatusSnapshot)
        XCTAssertEqual(taskSnapshot?.updatedAt, loadedAt)
        XCTAssertEqual(statusSnapshot?.updatedAt, loadedAt)
        XCTAssertEqual(delaysAfterNormal, [.seconds(2), .seconds(2)])
    }

    func testCancellationIsNotConvertedIntoDemoFailureOrAResult() async {
        let delay: DemoDelay = { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            // Simulate a delay implementation that returns even after cancellation.
        }
        let provider = DemoTasksProvider(delay: delay)

        do {
            _ = try await provider.load(scenario: .slowResponse)
            XCTFail("A canceled slow response must not return a snapshot")
        } catch is CancellationError {
            // Cancellation remains distinct from the controlled demo error.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testScenarioLabelsMatchTheDemoControls() {
        XCTAssertEqual(
            DemoScenario.allCases.map(\.displayName),
            ["Bình thường", "Không có dữ liệu", "Lỗi", "Phản hồi chậm"]
        )
    }
}
