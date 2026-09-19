import SwiftUI
import XCTest
@testable import MenuPocket

final class AppConfigurationTests: XCTestCase {
    func testHostedApplicationMetadata() throws {
        // Read the built host, so this checks the effective Xcode configuration.
        let info = try XCTUnwrap(Bundle.main.infoDictionary)

        XCTAssertEqual(Bundle.main.bundleIdentifier, "local.menupocket.app")
        XCTAssertEqual(info["CFBundleShortVersionString"] as? String, "0.1.0")
        XCTAssertEqual(info["CFBundleVersion"] as? String, "1")
        XCTAssertEqual(info["LSMinimumSystemVersion"] as? String, "14.0")
        XCTAssertEqual(info["LSUIElement"] as? Bool, true)
    }

    @MainActor
    func testAppDelegateReusesItsSettingsWindow() throws {
        let suiteName = "local.menupocket.tests.AppConfigurationTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(store: PreferencesStore(userDefaults: userDefaults))
        let delegate = AppDelegate(model: model)

        XCTAssertNil(delegate.settingsWindowController)
        delegate.showSettings()

        let controller = try XCTUnwrap(delegate.settingsWindowController)
        let window = try XCTUnwrap(controller.window)
        let hostingController = try XCTUnwrap(
            window.contentViewController as? NSHostingController<SettingsView>
        )

        XCTAssertTrue(delegate.model === model)
        XCTAssertTrue(hostingController.rootView.model === model)
        XCTAssertEqual(
            hostingController.rootView.appVersion,
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )

        XCTAssertEqual(window.contentView?.frame.size, SettingsWindowController.initialContentSize)
        XCTAssertEqual(window.minSize, SettingsWindowController.minimumWindowSize)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.isReleasedWhenClosed)

        delegate.showSettings()
        XCTAssertTrue(controller === delegate.settingsWindowController)
        XCTAssertEqual(window.minSize, SettingsWindowController.minimumWindowSize)

        window.close()
        XCTAssertFalse(window.isVisible)

        delegate.showSettings()
        XCTAssertTrue(controller === delegate.settingsWindowController)
        XCTAssertTrue(window === controller.window)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.minSize, SettingsWindowController.minimumWindowSize)

        window.close()
    }

    @MainActor
    func testFirstLaunchUsesSeparatePersistentMarkerAndOpensGeneralOnlyOnce() throws {
        let suiteName = "local.menupocket.tests.Onboarding.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let onboarding = UserDefaultsOnboardingStore(userDefaults: defaults)
        let first = AppDelegate(
            model: AppModel(store: PreferencesStore(userDefaults: defaults)),
            onboardingStore: onboarding
        )
        var shownTabs: [SettingsTab] = []

        XCTAssertNotNil(defaults.data(forKey: PreferencesStore.storageKey))
        XCTAssertFalse(onboarding.hasCompletedOnboarding)
        first.openSettingsOnFirstLaunchIfNeeded { shownTabs.append($0) }
        XCTAssertEqual(shownTabs, [.general])
        XCTAssertTrue(onboarding.hasCompletedOnboarding)

        let second = AppDelegate(
            model: AppModel(store: PreferencesStore(userDefaults: defaults)),
            onboardingStore: UserDefaultsOnboardingStore(userDefaults: defaults)
        )
        second.openSettingsOnFirstLaunchIfNeeded { shownTabs.append($0) }
        XCTAssertEqual(shownTabs, [.general])
        XCTAssertNil(second.settingsWindowController)
        XCTAssertEqual(SettingsView.demoExplanation,
                       "Ứng dụng đang dùng dữ liệu demo. Bạn có thể chọn nội dung thật ở phiên bản sau.")
    }

    @MainActor
    func testCorruptPreferencesDoNotResetCompletedOnboarding() throws {
        let suiteName = "local.menupocket.tests.OnboardingRecovery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let onboarding = UserDefaultsOnboardingStore(userDefaults: defaults)
        onboarding.markOnboardingCompleted()
        let corruptData = Data("invalid".utf8)
        defaults.set(corruptData, forKey: PreferencesStore.storageKey)

        let delegate = AppDelegate(
            model: AppModel(store: PreferencesStore(userDefaults: defaults)),
            onboardingStore: onboarding
        )
        var presentations = 0
        delegate.openSettingsOnFirstLaunchIfNeeded { _ in presentations += 1 }

        XCTAssertEqual(presentations, 0)
        XCTAssertEqual(delegate.model.preferenceWarning, .corruptData)
        XCTAssertTrue(delegate.model.isPreferenceEditingAllowed)
        XCTAssertEqual(defaults.data(forKey: PreferencesStore.storageKey), corruptData)
    }
}
