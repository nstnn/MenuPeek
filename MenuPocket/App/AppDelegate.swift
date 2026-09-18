import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    private(set) var settingsWindowController: SettingsWindowController?
    private let onboardingStore: any OnboardingStoring

    init(
        model: AppModel,
        onboardingStore: any OnboardingStoring = UserDefaultsOnboardingStore()
    ) {
        self.model = model
        self.onboardingStore = onboardingStore
        super.init()
    }

    override convenience init() {
        self.init(model: AppModel())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.startInitialLoads()
        openSettingsOnFirstLaunchIfNeeded { tab in
            showSettings(initialTab: tab)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.cancelLoadsForTermination()
    }

    // The decision is independent of preference recovery and of window visibility.
    func openSettingsOnFirstLaunchIfNeeded(present: (SettingsTab) -> Void) {
        guard !onboardingStore.hasCompletedOnboarding else { return }
        present(.general)
        onboardingStore.markOnboardingCompleted()
    }

    func showSettings(initialTab: SettingsTab = .content) {
        let controller = settingsWindowController ?? makeSettingsWindowController(initialTab: initialTab)
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

    private func makeSettingsWindowController(initialTab: SettingsTab) -> SettingsWindowController {
        let controller = SettingsWindowController(model: model, initialTab: initialTab)
        settingsWindowController = controller
        return controller
    }
}
