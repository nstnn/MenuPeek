import Carbon.HIToolbox
import Foundation
import OSLog

/// A key code and Carbon modifier mask for one global hotkey.
struct HotKeyCombination: Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    /// Quick Add's fixed shortcut, Control-Option-N.
    static let quickAdd = HotKeyCombination(
        keyCode: UInt32(kVK_ANSI_N),
        modifiers: UInt32(controlKey | optionKey)
    )
}

enum HotKeyRegistrationError: Error, Equatable, Sendable {
    /// Carbon reported that another exclusive registration already holds the combination.
    case alreadyInUse
    case systemError(OSStatus)

    var message: String {
        switch self {
        case .alreadyInUse:
            "Another app is already using this shortcut."
        case .systemError(let status):
            "The shortcut could not be turned on (error \(status))."
        }
    }
}

@MainActor
protocol HotKeyService: AnyObject {
    /// Registers `combination`, replacing any earlier registration. A refusal leaves nothing registered.
    func register(
        _ combination: HotKeyCombination,
        onPress: @escaping @MainActor () -> Void
    ) throws(HotKeyRegistrationError)
    func unregister()
}

// This narrow boundary lets tests exercise the service without claiming a real global hotkey.
@MainActor
protocol HotKeySystemAccess: AnyObject {
    func installPressedHandler(_ handler: @escaping @MainActor (_ id: UInt32) -> Void) -> OSStatus
    func removePressedHandler()
    func registerHotKey(_ combination: HotKeyCombination, id: UInt32, exclusive: Bool) -> OSStatus
    func unregisterHotKey(id: UInt32)
}

final class CarbonHotKeyService: HotKeyService {
    private static let logger = Logger(
        subsystem: "local.menupocket.app",
        category: "HotKey"
    )

    private let system: any HotKeySystemAccess
    private var handlerInstalled = false
    private var nextID: UInt32 = 1
    private var registeredID: UInt32?
    private var onPress: (@MainActor () -> Void)?

    // Construction never touches Carbon; only `register` does.
    init(system: any HotKeySystemAccess) {
        self.system = system
    }

    convenience init() {
        self.init(system: CarbonHotKeySystem())
    }

    func register(
        _ combination: HotKeyCombination,
        onPress: @escaping @MainActor () -> Void
    ) throws(HotKeyRegistrationError) {
        // An exclusive registration of the same combination would conflict with itself, so release first.
        releaseKey()

        if !handlerInstalled {
            let status = system.installPressedHandler { [weak self] id in
                self?.handlePressed(id: id)
            }
            guard status == noErr else {
                Self.logger.error("Hotkey handler installation failed: \(status, privacy: .public)")
                throw .systemError(status)
            }
            handlerInstalled = true
        }

        let id = nextID
        nextID &+= 1
        let status = system.registerHotKey(combination, id: id, exclusive: true)
        guard status == noErr else {
            Self.logger.error("Hotkey registration failed: \(status, privacy: .public)")
            removeHandler()
            throw status == OSStatus(eventHotKeyExistsErr) ? .alreadyInUse : .systemError(status)
        }
        registeredID = id
        self.onPress = onPress
    }

    // There is no deinit fallback: Carbon hotkey calls are not thread safe, and deinit is not
    // main-actor isolated under the CI toolchain. The owner unregisters explicitly at termination.
    func unregister() {
        releaseKey()
        removeHandler()
    }

    private func releaseKey() {
        if let registeredID {
            system.unregisterHotKey(id: registeredID)
        }
        registeredID = nil
        onPress = nil
    }

    private func removeHandler() {
        guard handlerInstalled else { return }
        system.removePressedHandler()
        handlerInstalled = false
    }

    private func handlePressed(id: UInt32) {
        guard id == registeredID else { return }
        onPress?()
    }
}

/// Carbon `RegisterEventHotKey` access. Needs no Accessibility or Input Monitoring permission.
private final class CarbonHotKeySystem: HotKeySystemAccess {
    // 'MPqa': identifies MenuPocket's hotkeys in pressed events.
    private static let signature: OSType = 0x4D50_7161

    private var handlerRef: EventHandlerRef?
    private var pressedHandler: (@MainActor (UInt32) -> Void)?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]

    func installPressedHandler(_ handler: @escaping @MainActor (UInt32) -> Void) -> OSStatus {
        guard handlerRef == nil else { return noErr }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // Retained while installed so Carbon never holds a dangling pointer; released on removal.
        let userData = Unmanaged.passRetained(self).toOpaque()
        var ref: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let system = Unmanaged<CarbonHotKeySystem>.fromOpaque(userData).takeUnretainedValue()
                // Application event target handlers run on the main thread. Calling directly,
                // rather than through a Task, keeps two quick presses in order.
                return MainActor.assumeIsolated {
                    system.handlePressed(hotKeyID)
                }
            },
            1,
            &eventType,
            userData,
            &ref
        )
        guard status == noErr, let ref else {
            Unmanaged<CarbonHotKeySystem>.fromOpaque(userData).release()
            return status == noErr ? OSStatus(eventInternalErr) : status
        }
        handlerRef = ref
        pressedHandler = handler
        return noErr
    }

    func removePressedHandler() {
        guard let handlerRef else { return }
        RemoveEventHandler(handlerRef)
        self.handlerRef = nil
        pressedHandler = nil
        Unmanaged.passUnretained(self).release()
    }

    func registerHotKey(_ combination: HotKeyCombination, id: UInt32, exclusive: Bool) -> OSStatus {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combination.keyCode,
            combination.modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            OptionBits(exclusive ? kEventHotKeyExclusive : kEventHotKeyNoOptions),
            &ref
        )
        guard status == noErr, let ref else {
            return status == noErr ? OSStatus(eventInternalErr) : status
        }
        hotKeyRefs[id] = ref
        return noErr
    }

    func unregisterHotKey(id: UInt32) {
        guard let ref = hotKeyRefs.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(ref)
    }

    private func handlePressed(_ hotKeyID: EventHotKeyID) -> OSStatus {
        guard hotKeyID.signature == Self.signature, let pressedHandler else {
            return OSStatus(eventNotHandledErr)
        }
        pressedHandler(hotKeyID.id)
        return noErr
    }
}
