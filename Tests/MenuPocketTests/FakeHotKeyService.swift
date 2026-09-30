@testable import MenuPocket

/// Records hotkey registration without touching Carbon. Shared so model and delegate tests never
/// register a real global hotkey.
@MainActor
final class FakeHotKeyService: HotKeyService {
    /// When set, the next and later `register` calls fail with this error until cleared.
    var registerError: HotKeyRegistrationError?
    private(set) var registeredCombination: HotKeyCombination?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private var onPress: (@MainActor () -> Void)?

    var isRegistered: Bool { registeredCombination != nil }

    func register(
        _ combination: HotKeyCombination,
        onPress: @escaping @MainActor () -> Void
    ) throws(HotKeyRegistrationError) {
        registerCount += 1
        registeredCombination = nil
        self.onPress = nil
        if let registerError { throw registerError }
        registeredCombination = combination
        self.onPress = onPress
    }

    func unregister() {
        unregisterCount += 1
        registeredCombination = nil
        onPress = nil
    }

    /// Simulates the user pressing the registered combination. Does nothing when unregistered.
    func simulatePress() {
        onPress?()
    }
}
