import AppKit

// AppKit owns the windows and status item; there is no SwiftUI scene that can
// independently create or restore a second task window.
@main
struct MenuPocketApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
