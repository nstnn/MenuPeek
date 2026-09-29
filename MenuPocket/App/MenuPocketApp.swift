import AppKit

// AppKit owns the windows and status item; there is no SwiftUI scene that can
// independently create or restore a second task window.
@main
struct MenuPocketApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        // The hosted XCTest process supplies isolated delegates in its tests.
        // Do not open production storage or mark onboarding in the test host.
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            NSClassFromString("XCTestCase") != nil {
            application.run()
            return
        }
        #endif
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
