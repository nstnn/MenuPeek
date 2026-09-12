import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var settingsWindowController: SettingsWindowController?

    func showSettings() {
        let controller = settingsWindowController ?? makeSettingsWindowController()
        controller.showSettings()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func makeSettingsWindowController() -> SettingsWindowController {
        let controller = SettingsWindowController()
        settingsWindowController = controller
        return controller
    }
}
