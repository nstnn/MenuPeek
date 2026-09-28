import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let dailyNotesState: DailyNotesState
    private(set) var taskWindowController: TaskWindowController?
    private(set) var taskStatusItemController: TaskStatusItemController?
    private(set) var settingsWindowController: SettingsWindowController?
    private let onboardingStore: any OnboardingStoring

    init(
        model: AppModel,
        dailyNotesState: DailyNotesState = DailyNotesState(),
        onboardingStore: any OnboardingStoring = UserDefaultsOnboardingStore()
    ) {
        self.model = model
        self.dailyNotesState = dailyNotesState
        self.onboardingStore = onboardingStore
        super.init()
    }

    override convenience init() {
        self.init(model: AppModel())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        installApplicationMenu()
        taskStatusItemController = TaskStatusItemController { [weak self] in
            self?.showTasks()
        }
        openSettingsOnFirstLaunchIfNeeded {
            showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        taskStatusItemController?.remove()
        model.cancelLoadsForTermination()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshLoginItemStatus()
    }

    // The decision is independent of preference recovery and of window visibility.
    func openSettingsOnFirstLaunchIfNeeded(present: () -> Void) {
        guard !onboardingStore.hasCompletedOnboarding else { return }
        present()
        onboardingStore.markOnboardingCompleted()
    }

    @objc func showTasks() {
        if taskWindowController == nil {
            taskWindowController = TaskWindowController(state: dailyNotesState) { [weak self] in
                self?.showSettings()
            }
        }
        taskWindowController?.showTasks()
    }

    @objc func showSettings() {
        let controller = settingsWindowController ?? makeSettingsWindowController()
        controller.showSettings()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showTasks()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installApplicationMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "MenuPocket")
        let tasks = appMenu.addItem(withTitle: "Show Tasks", action: #selector(showTasks), keyEquivalent: "")
        tasks.target = self
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit MenuPocket", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)
        NSApplication.shared.mainMenu = menu
    }

    private func makeSettingsWindowController() -> SettingsWindowController {
        let controller = SettingsWindowController(model: model)
        settingsWindowController = controller
        return controller
    }
}
