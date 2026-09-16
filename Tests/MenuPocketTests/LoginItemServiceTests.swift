import Foundation
import ServiceManagement
import XCTest
@testable import MenuPocket

final class LoginItemServiceTests: XCTestCase {
    func testRegisterReturnsFreshEnabledStatus() {
        let system = FakeLoginItemSystem()
        system.status = .notRegistered
        system.statusAfterRegister = .enabled
        let service = SystemLoginItemService(system: system)

        XCTAssertEqual(service.readStatus(), .disabled)
        XCTAssertEqual(system.registerCount, 0)
        XCTAssertEqual(service.register(), .init(status: .enabled, failure: nil))
        XCTAssertEqual(system.registerCount, 1)
        XCTAssertEqual(system.statusReadCount, 2)
    }

    func testApprovalRequiredIsNotReportedAsEnabled() {
        let system = FakeLoginItemSystem()
        system.statusAfterRegister = .requiresApproval

        let result = SystemLoginItemService(system: system).register()

        XCTAssertEqual(result, .init(status: .requiresApproval, failure: nil))
        XCTAssertNotEqual(result.status, .enabled)
    }

    func testRegistrationFailureRetainsActualStatus() {
        let system = FakeLoginItemSystem()
        system.status = .notRegistered
        system.registerError = FakeError.failed

        let result = SystemLoginItemService(system: system).register()

        XCTAssertEqual(result, .init(status: .disabled, failure: .registrationFailed))
        XCTAssertFalse(result.failure?.message.isEmpty ?? true)
        XCTAssertEqual(system.statusReadCount, 1)
    }

    func testUnregisterSuccessAndFailureRereadSystemStatus() {
        let system = FakeLoginItemSystem()
        system.status = .enabled
        system.unregisterError = FakeError.failed
        let service = SystemLoginItemService(system: system)

        XCTAssertEqual(service.unregister(), .init(status: .enabled, failure: .unregistrationFailed))
        XCTAssertEqual(system.statusReadCount, 1)

        system.unregisterError = nil
        system.statusAfterUnregister = .notRegistered
        XCTAssertEqual(service.unregister(), .init(status: .disabled, failure: nil))
        XCTAssertEqual(system.unregisterCount, 2)
        XCTAssertEqual(system.statusReadCount, 2)
    }

    func testReadStatusAlwaysReflectsExternalChangeAndUnavailableState() {
        let system = FakeLoginItemSystem()
        let service = SystemLoginItemService(system: system)

        XCTAssertEqual(service.readStatus(), .disabled)
        system.status = .requiresApproval
        XCTAssertEqual(service.readStatus(), .requiresApproval)
        system.status = .notFound
        XCTAssertEqual(service.readStatus(), .unavailable)
        XCTAssertEqual(system.statusReadCount, 3)
        XCTAssertEqual(system.registerCount, 0)
        XCTAssertEqual(system.unregisterCount, 0)
    }
}

private enum FakeError: Error {
    case failed
}

private final class FakeLoginItemSystem: LoginItemSystemAccess {
    private var storedStatus: SMAppService.Status = .notRegistered
    var status: SMAppService.Status {
        get {
            statusReadCount += 1
            return storedStatus
        }
        set {
            storedStatus = newValue
        }
    }
    var statusAfterRegister: SMAppService.Status?
    var statusAfterUnregister: SMAppService.Status?
    var registerError: Error?
    var unregisterError: Error?
    private(set) var statusReadCount = 0
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        if let statusAfterRegister { status = statusAfterRegister }
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregisterError { throw unregisterError }
        if let statusAfterUnregister { status = statusAfterUnregister }
    }
}
