import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let dailyNotesState: DailyNotesState
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
        openSettingsOnFirstLaunchIfNeeded {
            showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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
