import XCTest
@testable import MenuPocket

final class AppModelTests: XCTestCase {
    @MainActor
    func testDisablingPinnedModuleClearsPinBeforeSavingWithoutChoosingReplacement() {
        let store = FakePreferencesStore()
        let model = AppModel(store: store)

        XCTAssertTrue(model.setModuleEnabled(ModuleCatalog.tasksID, enabled: false))

        XCTAssertNil(model.preferences.pinnedModuleID)
        XCTAssertEqual(model.enabledModuleIDsInOrder, [ModuleCatalog.statusID])
        XCTAssertEqual(store.savedPreferences, [model.preferences])
        XCTAssertNil(store.savedPreferences.last?.pinnedModuleID)
    }

    @MainActor
    func testReorderingKeepsPinnedIdentityAndRejectsMoveBoundaries() {
        let store = FakePreferencesStore()
        let model = AppModel(store: store)

        XCTAssertFalse(model.moveModuleUp(ModuleCatalog.tasksID))
        XCTAssertFalse(model.moveModuleDown(ModuleCatalog.statusID))
        XCTAssertTrue(model.moveModuleDown(ModuleCatalog.tasksID))
        XCTAssertEqual(model.preferences.moduleOrder, [ModuleCatalog.statusID, ModuleCatalog.tasksID])
        XCTAssertEqual(model.preferences.pinnedModuleID, ModuleCatalog.tasksID)
        XCTAssertTrue(model.moveModuleUp(ModuleCatalog.tasksID))
        XCTAssertEqual(model.preferences.moduleOrder, [ModuleCatalog.tasksID, ModuleCatalog.statusID])
        XCTAssertEqual(store.savedPreferences.count, 2)
    }

    @MainActor
    func testPinSelectionRequiresKnownEnabledPinnableModule() {
        let unpinnable = ModuleDescriptor(
            id: "demo.unpinnable",
            displayName: "Không thể ghim",
            systemImageName: "nosign",
            canBePinned: false
        )
        var initial = AppPreferences.defaultValue
        initial.moduleOrder.append(unpinnable.id)
        initial.enabledModuleIDs.insert(unpinnable.id)
        let store = FakePreferencesStore(outcome: .loaded(initial))
        let model = AppModel(store: store, catalog: ModuleCatalog.defaultModules + [unpinnable])

        XCTAssertFalse(model.setPinnedModule("demo.unknown"))
        XCTAssertFalse(model.setPinnedModule(unpinnable.id))
        XCTAssertTrue(model.setModuleEnabled(ModuleCatalog.statusID, enabled: false))
        XCTAssertFalse(model.setPinnedModule(ModuleCatalog.statusID))
        XCTAssertEqual(model.preferences.pinnedModuleID, ModuleCatalog.tasksID)
        XCTAssertTrue(model.setPinnedModule(nil))
        XCTAssertNil(model.preferences.pinnedModuleID)
        XCTAssertEqual(store.savedPreferences.count, 2)
    }

    @MainActor
    func testDisablingAndReenablingModulesChangesOrderedPanelMembership() {
        let store = FakePreferencesStore()
        let model = AppModel(store: store)

        XCTAssertEqual(model.modulesInOrder.map(\.id), [ModuleCatalog.tasksID, ModuleCatalog.statusID])
        XCTAssertEqual(model.enabledModulesInOrder.map(\.id), [ModuleCatalog.tasksID, ModuleCatalog.statusID])
        XCTAssertTrue(model.setModuleEnabled(ModuleCatalog.tasksID, enabled: false))
        XCTAssertEqual(model.enabledModulesInOrder.map(\.id), [ModuleCatalog.statusID])
        XCTAssertTrue(model.setModuleEnabled(ModuleCatalog.statusID, enabled: false))

        XCTAssertTrue(model.preferences.enabledModuleIDs.isEmpty)
        XCTAssertTrue(model.enabledModuleIDsInOrder.isEmpty)
        XCTAssertTrue(model.enabledModulesInOrder.isEmpty)
        XCTAssertNil(model.preferences.pinnedModuleID)

        XCTAssertTrue(model.setModuleEnabled(ModuleCatalog.statusID, enabled: true))
        XCTAssertEqual(model.enabledModulesInOrder.map(\.id), [ModuleCatalog.statusID])
        XCTAssertEqual(store.savedPreferences.count, 3)
    }

    @MainActor
    func testDisplayModeAndEnablementUseTheSamePersistedPreferences() {
        let store = FakePreferencesStore()
        let model = AppModel(store: store)

        XCTAssertTrue(model.setMenuBarDisplayMode(.iconOnly))
        XCTAssertTrue(model.setModuleEnabled(ModuleCatalog.statusID, enabled: false))
        XCTAssertEqual(model.preferences.menuBarDisplayMode, .iconOnly)
        XCTAssertEqual(model.enabledModuleIDsInOrder, [ModuleCatalog.tasksID])
        XCTAssertEqual(store.savedPreferences.last, model.preferences)
    }

    @MainActor
    func testOrderingPinChoicesAndMenuBarPresentationFollowSavedIDs() {
        let store = FakePreferencesStore()
        let model = AppModel(store: store)

        XCTAssertEqual(model.enabledPinnableModulesInOrder.map(\.id),
                       [ModuleCatalog.tasksID, ModuleCatalog.statusID])
        XCTAssertEqual(model.menuBarDisplayText, "Demo: …")
        XCTAssertEqual(model.menuBarAccessibilityLabel, "MenuPocket, đang tải dữ liệu demo.")
        XCTAssertFalse(model.moveModuleUp(ModuleCatalog.tasksID))
        XCTAssertFalse(model.moveModuleDown(ModuleCatalog.statusID))

        XCTAssertTrue(model.moveModuleUp(ModuleCatalog.statusID))
        XCTAssertEqual(model.enabledModulesInOrder.map(\.id),
                       [ModuleCatalog.statusID, ModuleCatalog.tasksID])
        XCTAssertEqual(model.preferences.pinnedModuleID, ModuleCatalog.tasksID)

        XCTAssertTrue(model.setPinnedModule(ModuleCatalog.statusID))
        XCTAssertTrue(model.setModuleEnabled(ModuleCatalog.statusID, enabled: false))
        XCTAssertEqual(model.enabledPinnableModulesInOrder.map(\.id), [ModuleCatalog.tasksID])
        XCTAssertNil(model.preferences.pinnedModuleID)
        XCTAssertNil(model.menuBarDisplayText)
        XCTAssertEqual(model.menuBarAccessibilityLabel, "MenuPocket")
        XCTAssertFalse(model.setPinnedModule(ModuleCatalog.statusID))

        XCTAssertTrue(model.setPinnedModule(ModuleCatalog.tasksID))
        XCTAssertEqual(model.menuBarDisplayText, "Demo: …")
        XCTAssertTrue(model.setMenuBarDisplayMode(.iconOnly))
        XCTAssertNil(model.menuBarDisplayText)
        XCTAssertEqual(model.menuBarAccessibilityLabel, "MenuPocket")
        XCTAssertTrue(model.setMenuBarDisplayMode(.iconAndInformation))
        XCTAssertEqual(model.menuBarDisplayText, "Demo: …")
        XCTAssertTrue(model.setPinnedModule(nil))
        XCTAssertNil(model.menuBarDisplayText)
        XCTAssertEqual(model.menuBarAccessibilityLabel, "MenuPocket")
        XCTAssertEqual(store.savedPreferences.count, 7)
        XCTAssertEqual(store.savedPreferences.last, model.preferences)
    }

    @MainActor
    func testMenuBarPresentationStateTable() {
        let tasks = ModuleSnapshot(
            primaryValue: "3 việc",
            description: "Dữ liệu minh họa",
            pinnedLabel: "Demo: 3 việc",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let status = ModuleSnapshot(
            primaryValue: "Sẵn sàng",
            description: "Dữ liệu minh họa",
            pinnedLabel: "Demo: OK",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let cases: [(String, ModuleRuntimeState, String, String)] = [
            (
                "before first load", ModuleRuntimeState(), "Demo: …",
                "MenuPocket, đang tải dữ liệu demo."
            ),
            (
                "initial loading", ModuleRuntimeState(isLoading: true), "Demo: …",
                "MenuPocket, đang tải dữ liệu demo."
            ),
            (
                "tasks ready",
                ModuleRuntimeState(snapshot: tasks, hasCompletedAttempt: true),
                "Demo: 3 việc", "MenuPocket, Demo: 3 việc."
            ),
            (
                "status ready",
                ModuleRuntimeState(snapshot: status, hasCompletedAttempt: true),
                "Demo: OK", "MenuPocket, Demo: OK."
            ),
            (
                "refreshing after success",
                ModuleRuntimeState(snapshot: tasks, isLoading: true, hasCompletedAttempt: true),
                "Demo: 3 việc", "MenuPocket, Demo: 3 việc. Đang cập nhật dữ liệu demo."
            ),
            (
                "initial failure",
                ModuleRuntimeState(lastError: "Provider detail", hasCompletedAttempt: true),
                "Demo: !", "MenuPocket, không tải được dữ liệu demo."
            ),
            (
                "stale data after failure",
                ModuleRuntimeState(
                    snapshot: tasks,
                    lastError: "Provider detail",
                    hasCompletedAttempt: true
                ),
                "Demo: 3 việc ⚠︎",
                "MenuPocket, Demo: 3 việc. Cảnh báo: không cập nhật được; đang hiển thị dữ liệu trước đó."
            ),
            (
                "completed empty result",
                ModuleRuntimeState(hasCompletedAttempt: true),
                "Demo: —", "MenuPocket, không có dữ liệu demo."
            ),
        ]

        for (name, state, displayText, accessibilityLabel) in cases {
            let presentation = MenuBarPresentation(pinnedState: state)
            XCTAssertEqual(presentation.displayText, displayText, name)
            XCTAssertEqual(presentation.accessibilityLabel, accessibilityLabel, name)
        }
    }

    @MainActor
    func testPinChoicesExcludeUnpinnableModules() {
        let unpinnable = ModuleDescriptor(
            id: "demo.unpinnable",
            displayName: "Không thể ghim",
            systemImageName: "nosign",
            canBePinned: false
        )
        var initial = AppPreferences.defaultValue
        initial.moduleOrder.append(unpinnable.id)
        initial.enabledModuleIDs.insert(unpinnable.id)
        let model = AppModel(
            store: FakePreferencesStore(outcome: .loaded(initial)),
            catalog: ModuleCatalog.defaultModules + [unpinnable]
        )

        XCTAssertEqual(model.enabledPinnableModulesInOrder.map(\.id),
                       [ModuleCatalog.tasksID, ModuleCatalog.statusID])
        XCTAssertFalse(model.setPinnedModule(unpinnable.id))
    }

    @MainActor
    func testChangesRestoreFromASecondPreferencesStore() throws {
        let suiteName = "local.menupocket.tests.AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(store: PreferencesStore(userDefaults: defaults))
        XCTAssertTrue(model.moveModuleDown(ModuleCatalog.tasksID))
        XCTAssertTrue(model.setPinnedModule(ModuleCatalog.statusID))
        XCTAssertTrue(model.setMenuBarDisplayMode(.iconOnly))

        let restored = AppModel(store: PreferencesStore(userDefaults: defaults))
        XCTAssertEqual(restored.preferences, model.preferences)
        XCTAssertEqual(restored.enabledModuleIDsInOrder, [ModuleCatalog.statusID, ModuleCatalog.tasksID])
        XCTAssertEqual(restored.preferences.pinnedModuleID, ModuleCatalog.statusID)
    }

    @MainActor
    func testFutureSchemaBlocksChangesAndDoesNotCallSave() {
        let warning = PreferencesWarning.newerSchema(storedVersion: 2, supportedVersion: 1)
        let store = FakePreferencesStore(
            outcome: .incompatibleSchema(.defaultValue, warning: warning)
        )
        let model = AppModel(store: store)

        XCTAssertFalse(model.isPreferenceEditingAllowed)
        XCTAssertEqual(model.preferenceWarning, warning)
        XCTAssertFalse(model.setModuleEnabled(ModuleCatalog.tasksID, enabled: false))
        XCTAssertFalse(model.setMenuBarDisplayMode(.iconOnly))
        XCTAssertEqual(model.preferences, .defaultValue)
        XCTAssertTrue(store.savedPreferences.isEmpty)
    }

    @MainActor
    func testWriteProtectionDiscoveredDuringSaveDoesNotPublishCandidate() {
        let warning = PreferencesWarning.newerSchema(storedVersion: 2, supportedVersion: 1)
        let store = FakePreferencesStore(saveOutcome: .writeProtected(warning))
        let model = AppModel(store: store)

        XCTAssertFalse(model.moveModuleDown(ModuleCatalog.tasksID))
        XCTAssertEqual(model.preferences, .defaultValue)
        XCTAssertEqual(model.preferenceWarning, warning)
        XCTAssertFalse(model.isPreferenceEditingAllowed)
        XCTAssertEqual(store.savedPreferences.count, 1)
        XCTAssertFalse(model.setPinnedModule(nil))
        XCTAssertEqual(store.savedPreferences.count, 1)
    }

    @MainActor
    func testIsolatedCorruptAndNewerSchemaWarningsKeepTheirOwnWritePolicies() throws {
        let suiteName = "local.menupocket.tests.SettingsWarnings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Data("corrupt".utf8), forKey: PreferencesStore.storageKey)
        let recovered = AppModel(store: PreferencesStore(userDefaults: defaults))
        XCTAssertEqual(recovered.preferenceWarning, .corruptData)
        XCTAssertTrue(recovered.isPreferenceEditingAllowed)
        XCTAssertTrue(recovered.preferenceWarning?.message.contains("using defaults") == true)

        let futureData = Data("{\"schemaVersion\":2,\"futureOnly\":true}".utf8)
        defaults.set(futureData, forKey: PreferencesStore.storageKey)
        let protected = AppModel(store: PreferencesStore(userDefaults: defaults))
        XCTAssertEqual(protected.preferenceWarning,
                       .newerSchema(storedVersion: 2, supportedVersion: 1))
        XCTAssertFalse(protected.isPreferenceEditingAllowed)
        XCTAssertTrue(protected.preferenceWarning?.message.contains("protected from changes") == true)
        XCTAssertFalse(protected.setPinnedModule(nil))
        XCTAssertEqual(defaults.data(forKey: PreferencesStore.storageKey), futureData)
    }
}

private final class FakePreferencesStore: PreferencesStoring {
    var outcome: PreferencesLoadOutcome
    var saveOutcome: PreferencesSaveOutcome
    private(set) var savedPreferences: [AppPreferences] = []

    init(
        outcome: PreferencesLoadOutcome = .loaded(.defaultValue),
        saveOutcome: PreferencesSaveOutcome = .saved
    ) {
        self.outcome = outcome
        self.saveOutcome = saveOutcome
    }

    func load() throws -> PreferencesLoadOutcome { outcome }

    func save(_ preferences: AppPreferences) throws -> PreferencesSaveOutcome {
        savedPreferences.append(preferences)
        return saveOutcome
    }
}
