import Carbon.HIToolbox
import XCTest
@testable import MenuPocket

@MainActor
final class HotKeyServiceTests: XCTestCase {
    func testQuickAddCombinationIsControlOptionN() {
        XCTAssertEqual(HotKeyCombination.quickAdd.keyCode, UInt32(kVK_ANSI_N))
        XCTAssertEqual(HotKeyCombination.quickAdd.modifiers, UInt32(controlKey | optionKey))
    }

    func testConstructionTouchesNothing() {
        let system = FakeHotKeySystem()
        _ = CarbonHotKeyService(system: system)

        XCTAssertEqual(system.calls, [])
    }

    func testRegisterInstallsHandlerAndRegistersExclusively() throws {
        let system = FakeHotKeySystem()
        let service = CarbonHotKeyService(system: system)

        try service.register(.quickAdd) {}

        XCTAssertEqual(system.calls, [.installHandler, .register(.quickAdd, id: 1, exclusive: true)])
        XCTAssertEqual(system.registeredIDs, [1])
    }

    func testRegisterThenUnregisterReleasesKeyAndHandler() throws {
        let system = FakeHotKeySystem()
        let service = CarbonHotKeyService(system: system)
        try service.register(.quickAdd) {}
        system.calls.removeAll()

        service.unregister()

        XCTAssertEqual(system.calls, [.unregister(id: 1), .removeHandler])
        XCTAssertEqual(system.registeredIDs, [])
        XCTAssertFalse(system.handlerInstalled)
    }

    func testUnregisterWithoutRegistrationDoesNothing() {
        let system = FakeHotKeySystem()
        let service = CarbonHotKeyService(system: system)

        service.unregister()

        XCTAssertEqual(system.calls, [])
    }

    func testReregisterReplacesEarlierRegistrationAndHandler() throws {
        let system = FakeHotKeySystem()
        let service = CarbonHotKeyService(system: system)
        var first = 0
        var second = 0
        try service.register(.quickAdd) { first += 1 }
        system.calls.removeAll()

        try service.register(.quickAdd) { second += 1 }

        // The earlier key is released first, and the handler is not installed twice.
        XCTAssertEqual(system.calls, [.unregister(id: 1), .register(.quickAdd, id: 2, exclusive: true)])
        XCTAssertEqual(system.registeredIDs, [2])

        system.press(id: 1)
        system.press(id: 2)
        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 1)
    }

    func testPressReachesCurrentHandlerInOrder() throws {
        let system = FakeHotKeySystem()
        let service = CarbonHotKeyService(system: system)
        var presses = 0
        try service.register(.quickAdd) { presses += 1 }

        system.press(id: 1)
        system.press(id: 1)

        XCTAssertEqual(presses, 2)
    }

    func testPressAfterUnregisterIsIgnored() throws {
        let system = FakeHotKeySystem()
        let service = CarbonHotKeyService(system: system)
        var presses = 0
        try service.register(.quickAdd) { presses += 1 }
        let handler = try XCTUnwrap(system.handler)

        service.unregister()
        handler(1)

        XCTAssertEqual(presses, 0)
    }

    func testExistingExclusiveRegistrationIsReportedAsInUse() {
        let system = FakeHotKeySystem()
        system.registerStatus = OSStatus(eventHotKeyExistsErr)
        let service = CarbonHotKeyService(system: system)

        XCTAssertThrowsError(try service.register(.quickAdd) {}) { error in
            XCTAssertEqual(error as? HotKeyRegistrationError, .alreadyInUse)
        }
        XCTAssertEqual(system.registeredIDs, [])
        XCTAssertFalse(system.handlerInstalled)
        XCTAssertFalse(HotKeyRegistrationError.alreadyInUse.message.isEmpty)
    }

    func testOtherRegistrationFailureKeepsStatus() {
        let system = FakeHotKeySystem()
        system.registerStatus = OSStatus(paramErr)
        let service = CarbonHotKeyService(system: system)

        XCTAssertThrowsError(try service.register(.quickAdd) {}) { error in
            XCTAssertEqual(error as? HotKeyRegistrationError, .systemError(OSStatus(paramErr)))
        }
        XCTAssertFalse(system.handlerInstalled)
    }

    func testRefusedReplacementLeavesNothingRegistered() throws {
        let system = FakeHotKeySystem()
        let service = CarbonHotKeyService(system: system)
        var presses = 0
        try service.register(.quickAdd) { presses += 1 }
        let handler = try XCTUnwrap(system.handler)
        system.registerStatus = OSStatus(eventHotKeyExistsErr)

        XCTAssertThrowsError(try service.register(.quickAdd) {})

        XCTAssertEqual(system.registeredIDs, [])
        XCTAssertFalse(system.handlerInstalled)
        handler(1)
        XCTAssertEqual(presses, 0)
    }

    func testRetryAfterRefusalSucceeds() throws {
        let system = FakeHotKeySystem()
        system.registerStatus = OSStatus(eventHotKeyExistsErr)
        let service = CarbonHotKeyService(system: system)
        var presses = 0
        XCTAssertThrowsError(try service.register(.quickAdd) {})

        system.registerStatus = noErr
        try service.register(.quickAdd) { presses += 1 }
        system.press(id: 2)

        XCTAssertEqual(system.registeredIDs, [2])
        XCTAssertEqual(presses, 1)
    }

    func testHandlerInstallationFailureRegistersNothing() {
        let system = FakeHotKeySystem()
        system.installStatus = OSStatus(eventInternalErr)
        let service = CarbonHotKeyService(system: system)

        XCTAssertThrowsError(try service.register(.quickAdd) {}) { error in
            XCTAssertEqual(error as? HotKeyRegistrationError, .systemError(OSStatus(eventInternalErr)))
        }
        XCTAssertEqual(system.calls, [.installHandler])
    }

    func testFakeServiceRecordsRegistrationRefusalAndPresses() throws {
        let service = FakeHotKeyService()
        var presses = 0

        try service.register(.quickAdd) { presses += 1 }
        service.simulatePress()
        XCTAssertEqual(service.registeredCombination, .quickAdd)
        XCTAssertEqual(presses, 1)

        service.unregister()
        service.simulatePress()
        XCTAssertFalse(service.isRegistered)
        XCTAssertEqual(presses, 1)

        service.registerError = .alreadyInUse
        XCTAssertThrowsError(try service.register(.quickAdd) {}) { error in
            XCTAssertEqual(error as? HotKeyRegistrationError, .alreadyInUse)
        }
        XCTAssertFalse(service.isRegistered)
        XCTAssertEqual(service.registerCount, 2)
        XCTAssertEqual(service.unregisterCount, 1)
    }
}

@MainActor
private final class FakeHotKeySystem: HotKeySystemAccess {
    enum Call: Equatable {
        case installHandler
        case removeHandler
        case register(HotKeyCombination, id: UInt32, exclusive: Bool)
        case unregister(id: UInt32)
    }

    var installStatus: OSStatus = noErr
    var registerStatus: OSStatus = noErr
    var calls: [Call] = []
    private(set) var handler: (@MainActor (UInt32) -> Void)?
    private(set) var registeredIDs: Set<UInt32> = []

    var handlerInstalled: Bool { handler != nil }

    func installPressedHandler(_ handler: @escaping @MainActor (UInt32) -> Void) -> OSStatus {
        calls.append(.installHandler)
        guard installStatus == noErr else { return installStatus }
        self.handler = handler
        return noErr
    }

    func removePressedHandler() {
        calls.append(.removeHandler)
        handler = nil
    }

    func registerHotKey(_ combination: HotKeyCombination, id: UInt32, exclusive: Bool) -> OSStatus {
        calls.append(.register(combination, id: id, exclusive: exclusive))
        guard registerStatus == noErr else { return registerStatus }
        registeredIDs.insert(id)
        return noErr
    }

    func unregisterHotKey(id: UInt32) {
        calls.append(.unregister(id: id))
        registeredIDs.remove(id)
    }

    /// Delivers a pressed event as Carbon would, only while the key and handler are installed.
    func press(id: UInt32) {
        guard registeredIDs.contains(id) else { return }
        handler?(id)
    }
}
