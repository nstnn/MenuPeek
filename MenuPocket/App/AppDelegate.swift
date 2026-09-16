import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    private(set) var settingsWindowController: SettingsWindowController?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    override convenience init() {
        self.init(model: AppModel())
    }

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
        let controller = SettingsWindowController(model: model)
        settingsWindowController = controller
        return controller
    }
}
