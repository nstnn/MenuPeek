import AppKit
import CoreServices
import Observation

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
    private(set) var quickAddPanelController: QuickAddPanelController?
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
        // Apply the saved theme before the status item or any window exists.
        applyThemeAndObserve()
        NSApplication.shared.setActivationPolicy(.regular)
        installApplicationMenu()
        dailyNotesState.startup()
        taskStatusItemController = TaskStatusItemController(state: dailyNotesState) { [weak self] in
            self?.showToday()
        }
        // Registers in both launch contexts; a press never raises a window on its own.
        model.startQuickAdd { [weak self] in self?.quickAddHotKeyPressed() }
        if context == .manual { showTasks() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        model.stopQuickAdd()
        quickAddPanelController?.dismiss()
        quickAddPanelController?.panel.close()
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
        makeTaskWindowController().showTasks()
        if taskWindowController?.window?.isVisible == true { completeOnboardingAfterPresentation() }
    }

    /// Status-item and unavailable Quick Add routes request Today without
    /// discarding a guarded interaction in the retained window.
    private func showToday() {
        guard !isTerminating else { return }
        makeTaskWindowController().showToday()
        if taskWindowController?.window?.isVisible == true { completeOnboardingAfterPresentation() }
    }

    private func makeTaskWindowController() -> TaskWindowController {
        if let taskWindowController { return taskWindowController }
        let controller = TaskWindowController(state: dailyNotesState) { [weak self] in
            self?.showSettings()
        }
        taskWindowController = controller
        return controller
    }

    @objc func addTask() {
        guard !isTerminating, canAddTask else { return }
        showTasks()
        taskWindowController?.presentation.requestNewTask(state: dailyNotesState)
    }

    /// View > Today (⌘1) and Later (⌘2). Opens the window when needed and
    /// leaves a guarded interaction in place instead of forcing the switch.
    @objc func showDestination(_ sender: NSMenuItem) {
        guard !isTerminating, let destination = Self.destination(forMenuTag: sender.tag) else { return }
        showTasks()
        taskWindowController?.presentation.selectDestination(destination, state: dailyNotesState)
    }

    private static func destination(forMenuTag tag: Int) -> TaskListDestination? {
        switch tag {
        case 1: .today
        case 2: .later
        default: nil
        }
    }

    @objc func showSettings() {
        guard !isTerminating else { return }
        let controller = settingsWindowController ?? makeSettingsWindowController()
        controller.showSettings()
        if controller.window?.isVisible == true { completeOnboardingAfterPresentation() }
    }

    /// The Quick Add hotkey toggles the capture panel. The panel needs saved
    /// data it can write to: after one refresh, unavailable data opens the
    /// Today window, which offers Retry, instead.
    func quickAddHotKeyPressed() {
        guard hasFinishedLaunching, !isTerminating else { return }
        if let controller = quickAddPanelController, controller.isShown {
            controller.dismiss()
            return
        }
        if dailyNotesState.availableProgress == nil { dailyNotesState.refresh() }
        guard dailyNotesState.availableProgress != nil else {
            showToday()
            return
        }
        let controller = quickAddPanelController ?? makeQuickAddPanelController()
        controller.show()
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
            return canAddTask
        }
        if menuItem.action == #selector(showDestination(_:)),
           let destination = Self.destination(forMenuTag: menuItem.tag) {
            // A fresh window starts at Today with nothing guarded.
            guard let presentation = taskWindowController?.presentation else {
                menuItem.state = destination == .today ? .on : .off
                return true
            }
            menuItem.state = presentation.selectedDestination == destination ? .on : .off
            return presentation.canSelectDestination(destination, state: dailyNotesState)
        }
        return true
    }

    private var canAddTask: Bool {
        if let presentation = taskWindowController?.presentation {
            return presentation.canAddTask(state: dailyNotesState)
        }
        // A fresh window starts at Today.
        return dailyNotesState.availableProgress != nil &&
            dailyNotesState.editingNoteID == nil && dailyNotesState.editingLaterTaskID == nil
    }

    static func appearance(for theme: AppTheme) -> NSAppearance? {
        switch theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    private func applyThemeAndObserve() {
        guard !isTerminating else { return }
        let theme = withObservationTracking {
            model.preferences.theme
        } onChange: { [weak self] in
            // Observation fires before mutation. Apply the settled value and
            // renew tracking on the main actor.
            Task { @MainActor [weak self] in self?.applyThemeAndObserve() }
        }
        // App-wide, so every window and menu follows it; nil follows macOS.
        NSApplication.shared.appearance = Self.appearance(for: theme)
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
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        for (tag, title, key) in [(1, "Today", "1"), (2, "Later", "2")] {
            let item = viewMenu.addItem(withTitle: title, action: #selector(showDestination(_:)), keyEquivalent: key)
            item.tag = tag
            item.target = self
        }
        viewItem.submenu = viewMenu
        menu.addItem(viewItem)
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

    private func makeQuickAddPanelController() -> QuickAddPanelController {
        // Saves through the independent write path, so the Today window's
        // draft, edit, deletion, and inline error are untouched.
        let controller = QuickAddPanelController { [weak self] text in
            guard let self, !self.isTerminating else { return .unavailable }
            return switch self.dailyNotesState.add(text: text) {
            case .added: .added
            case .empty: .empty
            case .unavailable: .unavailable
            case .writeFailed: .writeFailed
            }
        }
        quickAddPanelController = controller
        return controller
    }

    private func makeSettingsWindowController() -> SettingsWindowController {
        let controller = SettingsWindowController(model: model)
        settingsWindowController = controller
        return controller
    }
}
