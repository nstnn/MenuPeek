import AppKit
import XCTest
@testable import MenuPocket

@MainActor
final class TaskWindowZoomTests: XCTestCase {
    private let key = TaskWindowZoom.storageKey

    func testMissingOrUnrecognizedValueMeansActualSizeWithoutWriting() {
        let defaults = isolatedDefaults()
        XCTAssertEqual(TaskWindowZoom(userDefaults: defaults).scale, 1.0)
        XCTAssertNil(defaults.object(forKey: key))

        defaults.set(3.7, forKey: key)
        XCTAssertEqual(TaskWindowZoom(userDefaults: defaults).scale, 1.0)
        XCTAssertEqual(defaults.double(forKey: key), 3.7)

        defaults.set("big", forKey: key)
        XCTAssertEqual(TaskWindowZoom(userDefaults: defaults).scale, 1.0)
    }

    func testZoomStepsThroughLevelsAndStopsAtTheEnds() {
        let zoom = TaskWindowZoom(userDefaults: isolatedDefaults())
        XCTAssertTrue(zoom.zoomIn())
        XCTAssertEqual(zoom.scale, 1.1)
        XCTAssertTrue(zoom.zoomIn())
        XCTAssertTrue(zoom.zoomIn())
        XCTAssertEqual(zoom.scale, 1.5)
        XCTAssertFalse(zoom.zoomIn())
        XCTAssertEqual(zoom.scale, 1.5)

        XCTAssertTrue(zoom.resetToActualSize())
        XCTAssertFalse(zoom.resetToActualSize())
        XCTAssertTrue(zoom.zoomOut())
        XCTAssertTrue(zoom.zoomOut())
        XCTAssertEqual(zoom.scale, 0.8)
        XCTAssertFalse(zoom.zoomOut())
    }

    func testZoomInRespectsTheFitCheck() {
        let zoom = TaskWindowZoom(userDefaults: isolatedDefaults())
        XCTAssertFalse(zoom.zoomIn(fits: { $0 <= 1.0 }))
        XCTAssertEqual(zoom.scale, 1.0)
        XCTAssertTrue(zoom.zoomIn(fits: { $0 <= 1.1 }))
        XCTAssertFalse(zoom.zoomIn(fits: { $0 <= 1.1 }))
        XCTAssertEqual(zoom.scale, 1.1)
    }

    func testZoomSurvivesANewOwnerAndActualSizeClearsTheKey() {
        let defaults = isolatedDefaults()
        let zoom = TaskWindowZoom(userDefaults: defaults)
        zoom.zoomOut()
        XCTAssertEqual(TaskWindowZoom(userDefaults: defaults).scale, 0.9)

        zoom.zoomIn()
        XCTAssertNil(defaults.object(forKey: key))
        XCTAssertEqual(TaskWindowZoom(userDefaults: defaults).scale, 1.0)
    }

    func testControllerRaisesTheContentFloorWithTheZoom() throws {
        let defaults = isolatedDefaults()
        defaults.set(1.25, forKey: key)
        let state = DailyNotesState(repositoryFactory: { throw CocoaError(.fileNoSuchFile) },
                                    notificationCenter: NotificationCenter(),
                                    workspaceNotificationCenter: NotificationCenter(),
                                    categoryPreferences: isolatedCategoryPreferences())
        let controller = TaskWindowController(state: state, zoom: TaskWindowZoom(userDefaults: defaults),
                                              onSettings: {})
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.contentMinSize, NSSize(width: 1000, height: 700))
        XCTAssertEqual(controller.minimumContentSize, NSSize(width: 1000, height: 700))
        XCTAssertGreaterThanOrEqual(window.contentRect(forFrameRect: window.frame).width, 1000)

        XCTAssertTrue(controller.canZoomOut)
        controller.zoomOut()
        XCTAssertEqual(controller.zoom.scale, 1.1)
        XCTAssertEqual(window.contentMinSize, NSSize(width: 880, height: 616))
        controller.resetZoom()
        XCTAssertEqual(window.contentMinSize, TaskWindowController.minimumContentSize)
        XCTAssertNil(defaults.object(forKey: key))
        window.close()
    }
}
