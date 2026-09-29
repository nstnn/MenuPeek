import AppKit
import CoreServices

enum AppLaunchContext: Equatable {
    case manual, login

    init(appleEvent: NSAppleEventDescriptor?) {
        // Read synchronously while AppKit is handling the launch event. Login
        // registration says nothing about the origin of this particular launch.
        if let event = appleEvent,
           event.eventClass == kCoreEventClass, event.eventID == kAEOpenApplication,
           event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            self = .login
        } else {
            self = .manual
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let model: AppModel
    let dailyNotesState: DailyNotesState
    private(set) var taskWindowController: TaskWindowController?
    private(set) var taskStatusItemController: TaskStatusItemController?
    private(set) var settingsWindowController: SettingsWindowController?
    private let onboardingStore: any OnboardingStoring
    private let launchContext: () -> AppLaunchContext
    private var hasFinishedLaunching = false
    private var isTerminating = false

    init(
        model: AppModel,
        dailyNotesState: DailyNotesState = DailyNotesState(),
        onboardingStore: any OnboardingStoring = UserDefaultsOnboardingStore(),
        launchContext: @escaping () -> AppLaunchContext = {
            AppLaunchContext(appleEvent: NSAppleEventManager.shared().currentAppleEvent)
        }
    ) {
        self.model = model
        self.dailyNotesState = dailyNotesState
        self.onboardingStore = onboardingStore
        self.launchContext = launchContext
        super.init()
    }

    override convenience init() {
        self.init(model: AppModel())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !hasFinishedLaunching, !isTerminating else { return }
        let context = launchContext()
        hasFinishedLaunching = true
        NSApplication.shared.setActivationPolicy(.regular)
        installApplicationMenu()
        dailyNotesState.startup()
        taskStatusItemController = TaskStatusItemController(state: dailyNotesState) { [weak self] in
            self?.showTasks()
        }
        if context == .manual { showTasks() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        dailyNotesState.stopForTermination()
        taskStatusItemController?.remove()
        taskStatusItemController = nil
        model.cancelLoadsForTermination()
        taskWindowController?.close()
        settingsWindowController?.close()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !isTerminating else { return }
        model.refreshLoginItemStatus()
        if hasFinishedLaunching { dailyNotesState.refresh() }
    }

    @objc func showTasks() {
        guard !isTerminating else { return }
        if taskWindowController == nil {
            taskWindowController = TaskWindowController(state: dailyNotesState) { [weak self] in
                self?.showSettings()
            }
        }
        taskWindowController?.showTasks()
        if taskWindowController?.window?.isVisible == true { completeOnboardingAfterPresentation() }
    }

    @objc func addTask() {
        guard !isTerminating else { return }
        showTasks()
        taskWindowController?.presentation.requestNewTask(state: dailyNotesState)
    }

    @objc func showSettings() {
        guard !isTerminating else { return }
        let controller = settingsWindowController ?? makeSettingsWindowController()
        controller.showSettings()
        if controller.window?.isVisible == true { completeOnboardingAfterPresentation() }
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

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard !isTerminating else { return false }
        if menuItem.action == #selector(addTask) {
            return dailyNotesState.availableProgress != nil && dailyNotesState.editingNoteID == nil &&
                taskWindowController?.presentation.deletionTarget == nil
        }
        return true
    }

    private func completeOnboardingAfterPresentation() {
        if !onboardingStore.hasCompletedOnboarding { onboardingStore.markOnboardingCompleted() }
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
        appMenu.addItem(withTitle: "Hide MenuPocket", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit MenuPocket", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let add = fileMenu.addItem(withTitle: "Add Task", action: #selector(addTask), keyEquivalent: "n")
        add.target = self
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApplication.shared.mainMenu = menu
        NSApplication.shared.windowsMenu = windowMenu
    }

    private func makeSettingsWindowController() -> SettingsWindowController {
        let controller = SettingsWindowController(model: model)
        settingsWindowController = controller
        return controller
    }
}
