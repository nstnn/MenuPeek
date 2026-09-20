import AppKit
import XCTest
@testable import MenuPocket

final class LoginItemSettingsTests: XCTestCase {
    @MainActor
    func testInitialReadDoesNotMutateLoginItemRegistration() {
        let service = FakeLoginItemService(status: .disabled)
        let model = makeModel(service: service)

        XCTAssertEqual(model.loginItemStatus, .disabled)
        XCTAssertFalse(model.isLoginItemEnabled)
        XCTAssertTrue(model.canChangeLoginItemRegistration)
        XCTAssertEqual(service.readCount, 1)
        XCTAssertEqual(service.registerCount, 0)
        XCTAssertEqual(service.unregisterCount, 0)
    }

    @MainActor
    func testEnableUsesRereadStatusInsteadOfAssumingSuccess() {
        let service = FakeLoginItemService(status: .disabled)
        service.registerResult = .init(status: .requiresApproval, failure: nil)
        let model = makeModel(service: service)

        model.setLoginItemEnabled(true)

        XCTAssertEqual(service.registerCount, 1)
        XCTAssertEqual(model.loginItemStatus, .requiresApproval)
        XCTAssertFalse(model.isLoginItemEnabled)
        XCTAssertFalse(model.canChangeLoginItemRegistration)
        XCTAssertNil(model.loginItemOperationFailure)
    }

    @MainActor
    func testSuccessfulEnableAndDisableFollowReturnedSystemState() {
        let service = FakeLoginItemService(status: .disabled)
        service.registerResult = .init(status: .enabled, failure: nil)
        service.unregisterResult = .init(status: .disabled, failure: nil)
        let model = makeModel(service: service)

        model.setLoginItemEnabled(true)
        XCTAssertTrue(model.isLoginItemEnabled)

        model.setLoginItemEnabled(false)
        XCTAssertFalse(model.isLoginItemEnabled)
        XCTAssertEqual(service.registerCount, 1)
        XCTAssertEqual(service.unregisterCount, 1)
    }

    @MainActor
    func testOperationFailuresKeepSwitchAlignedWithActualStatus() {
        let registrationService = FakeLoginItemService(status: .disabled)
        registrationService.registerResult = .init(
            status: .disabled,
            failure: .registrationFailed
        )
        let registrationModel = makeModel(service: registrationService)

        registrationModel.setLoginItemEnabled(true)

        XCTAssertFalse(registrationModel.isLoginItemEnabled)
        XCTAssertEqual(registrationModel.loginItemOperationFailure, .registrationFailed)

        let unregistrationService = FakeLoginItemService(status: .enabled)
        unregistrationService.unregisterResult = .init(
            status: .enabled,
            failure: .unregistrationFailed
        )
        let unregistrationModel = makeModel(service: unregistrationService)

        unregistrationModel.setLoginItemEnabled(false)

        XCTAssertTrue(unregistrationModel.isLoginItemEnabled)
        XCTAssertEqual(unregistrationModel.loginItemOperationFailure, .unregistrationFailed)
    }

    @MainActor
    func testRefreshReflectsExternalChangeAndClearsObsoleteFailure() {
        let service = FakeLoginItemService(status: .disabled)
        service.registerResult = .init(status: .disabled, failure: .registrationFailed)
        let model = makeModel(service: service)
        model.setLoginItemEnabled(true)
        XCTAssertNotNil(model.loginItemOperationFailure)

        service.status = .enabled
        model.refreshLoginItemStatus()

        XCTAssertEqual(model.loginItemStatus, .enabled)
        XCTAssertTrue(model.isLoginItemEnabled)
        XCTAssertNil(model.loginItemOperationFailure)
        XCTAssertEqual(service.readCount, 2)
    }

    @MainActor
    func testApprovalActionUsesInjectedServiceOnlyWhenApprovalIsRequired() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let model = makeModel(service: service)

        model.setLoginItemEnabled(true)
        XCTAssertEqual(service.registerCount, 0)

        model.openSystemSettingsLoginItems()
        XCTAssertEqual(service.openSettingsCount, 1)

        service.status = .disabled
        model.refreshLoginItemStatus()
        model.openSystemSettingsLoginItems()
        XCTAssertEqual(service.openSettingsCount, 1)
    }

    @MainActor
    func testUnavailableStateCannotRequestRegistration() {
        let service = FakeLoginItemService(status: .unavailable)
        let model = makeModel(service: service)

        XCTAssertFalse(model.canChangeLoginItemRegistration)
        model.setLoginItemEnabled(true)

        XCTAssertEqual(service.registerCount, 0)
        XCTAssertFalse(model.isLoginItemEnabled)
    }

    @MainActor
    func testShowingSettingsRefreshesWithoutRegistering() throws {
        let service = FakeLoginItemService(status: .disabled)
        let model = makeModel(service: service)
        let controller = SettingsWindowController(model: model, initialTab: .general)
        defer { controller.close() }

        service.status = .enabled
        controller.showSettings()

        XCTAssertEqual(model.loginItemStatus, .enabled)
        XCTAssertGreaterThanOrEqual(service.readCount, 2)
        XCTAssertEqual(service.registerCount, 0)
        XCTAssertEqual(service.unregisterCount, 0)
    }

    @MainActor
    func testBecomingActiveRereadsExternalStatusWithoutRegistering() {
        let service = FakeLoginItemService(status: .disabled)
        let model = makeModel(service: service)
        let delegate = AppDelegate(model: model)

        service.status = .requiresApproval
        delegate.applicationDidBecomeActive(
            Notification(name: NSApplication.didBecomeActiveNotification)
        )

        XCTAssertEqual(model.loginItemStatus, .requiresApproval)
        XCTAssertEqual(service.readCount, 2)
        XCTAssertEqual(service.registerCount, 0)
        XCTAssertEqual(service.unregisterCount, 0)
    }

    func testEverySystemStatusHasFriendlyVietnameseCopy() {
        XCTAssertEqual(
            LoginItemStatus.disabled.message,
            "MenuPocket sẽ không tự động mở khi bạn đăng nhập."
        )
        XCTAssertEqual(
            LoginItemStatus.enabled.message,
            "MenuPocket sẽ tự động mở sau khi bạn đăng nhập."
        )
        XCTAssertTrue(LoginItemStatus.requiresApproval.message.contains("Cài đặt hệ thống"))
        XCTAssertTrue(LoginItemStatus.unavailable.message.contains("Không thể xác định"))
    }

    @MainActor
    private func makeModel(service: FakeLoginItemService) -> AppModel {
        AppModel(store: MemoryPreferencesStore(), loginItemService: service)
    }
}

private final class FakeLoginItemService: LoginItemService {
    var status: LoginItemStatus
    var registerResult: LoginItemOperationResult?
    var unregisterResult: LoginItemOperationResult?
    private(set) var readCount = 0
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSettingsCount = 0

    init(status: LoginItemStatus) {
        self.status = status
    }

    func readStatus() -> LoginItemStatus {
        readCount += 1
        return status
    }

    func register() -> LoginItemOperationResult {
        registerCount += 1
        let result = registerResult ?? .init(status: status, failure: nil)
        status = result.status
        return result
    }

    func unregister() -> LoginItemOperationResult {
        unregisterCount += 1
        let result = unregisterResult ?? .init(status: status, failure: nil)
        status = result.status
        return result
    }

    func openSystemSettingsLoginItems() {
        openSettingsCount += 1
    }
}

private final class MemoryPreferencesStore: PreferencesStoring {
    var preferences = AppPreferences.defaultValue

    func load() throws -> PreferencesLoadOutcome {
        .loaded(preferences)
    }

    func save(_ preferences: AppPreferences) throws -> PreferencesSaveOutcome {
        self.preferences = preferences
        return .saved
    }
}
