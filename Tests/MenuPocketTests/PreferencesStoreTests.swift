import Foundation
import XCTest
@testable import MenuPocket

final class PreferencesStoreTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "local.menupocket.tests.PreferencesStoreTests.\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
    }

    func testMissingPreferencesInitializeAndPersistDefaults() throws {
        let store = PreferencesStore(userDefaults: userDefaults)

        let firstLoad = try store.load()

        XCTAssertEqual(firstLoad, .initializedDefaults(.defaultValue))
        XCTAssertEqual(firstLoad.preferences, .defaultValue)
        let storedData = try XCTUnwrap(
            userDefaults.data(forKey: PreferencesStore.storageKey)
        )
        XCTAssertEqual(
            try JSONDecoder().decode(AppPreferences.self, from: storedData),
            .defaultValue
        )

        let freshStore = PreferencesStore(
            userDefaults: try XCTUnwrap(UserDefaults(suiteName: suiteName))
        )
        XCTAssertEqual(try freshStore.load(), .loaded(.defaultValue))
    }

    func testChangedPreferencesRoundTripThroughFreshStore() throws {
        let changedPreferences = AppPreferences(
            schemaVersion: AppPreferences.currentSchemaVersion,
            moduleOrder: [ModuleCatalog.statusID, ModuleCatalog.tasksID],
            enabledModuleIDs: [ModuleCatalog.statusID],
            pinnedModuleID: ModuleCatalog.statusID,
            menuBarDisplayMode: .iconOnly,
            theme: .dark,
            quickAddEnabled: true
        )
        let store = PreferencesStore(userDefaults: userDefaults)

        XCTAssertEqual(try store.save(changedPreferences), .saved)

        let freshStore = PreferencesStore(
            userDefaults: try XCTUnwrap(UserDefaults(suiteName: suiteName))
        )
        XCTAssertEqual(try freshStore.load(), .loaded(changedPreferences))
    }

    func testEncodedPreferencesContainOnlyProductPreferenceFields() throws {
        let preferences = AppPreferences(
            schemaVersion: AppPreferences.currentSchemaVersion,
            moduleOrder: [ModuleCatalog.statusID, ModuleCatalog.tasksID],
            enabledModuleIDs: [ModuleCatalog.statusID],
            pinnedModuleID: ModuleCatalog.statusID,
            menuBarDisplayMode: .iconOnly,
            theme: .light,
            quickAddEnabled: false
        )
        let store = PreferencesStore(userDefaults: userDefaults)

        try store.save(preferences)

        let data = try XCTUnwrap(
            userDefaults.data(forKey: PreferencesStore.storageKey)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(
            Set(object.keys),
            [
                "schemaVersion",
                "moduleOrder",
                "enabledModuleIDs",
                "pinnedModuleID",
                "menuBarDisplayMode",
                "theme",
                "quickAddEnabled",
            ]
        )
    }

    func testSchemaOnePreferencesSavedBeforeThemeLoadWithAllFieldsAndSystemTheme() throws {
        // The exact shape earlier builds wrote: schema 1 with no theme key.
        let earlierBuildData = Data(
            """
            {"enabledModuleIDs":["demo.status"],"menuBarDisplayMode":"iconOnly",\
            "moduleOrder":["demo.status","demo.tasks"],"pinnedModuleID":"demo.status","schemaVersion":1}
            """.utf8
        )
        userDefaults.set(earlierBuildData, forKey: PreferencesStore.storageKey)

        let outcome = try PreferencesStore(userDefaults: userDefaults).load()

        XCTAssertEqual(
            outcome,
            .loaded(
                AppPreferences(
                    schemaVersion: 1,
                    moduleOrder: [ModuleCatalog.statusID, ModuleCatalog.tasksID],
                    enabledModuleIDs: [ModuleCatalog.statusID],
                    pinnedModuleID: ModuleCatalog.statusID,
                    menuBarDisplayMode: .iconOnly,
                    theme: .system,
                    quickAddEnabled: false
                )
            )
        )
        XCTAssertNil(outcome.warning)
        XCTAssertEqual(userDefaults.data(forKey: PreferencesStore.storageKey), earlierBuildData)
    }

    func testUnrecognizedThemeUsesSystemWithoutDiscardingOtherFields() throws {
        let data = Data(
            """
            {"enabledModuleIDs":["demo.tasks"],"menuBarDisplayMode":"iconOnly",\
            "moduleOrder":["demo.status","demo.tasks"],"pinnedModuleID":null,\
            "schemaVersion":1,"theme":"sepia"}
            """.utf8
        )
        userDefaults.set(data, forKey: PreferencesStore.storageKey)

        let outcome = try PreferencesStore(userDefaults: userDefaults).load()

        XCTAssertEqual(
            outcome,
            .loaded(
                AppPreferences(
                    schemaVersion: 1,
                    moduleOrder: [ModuleCatalog.statusID, ModuleCatalog.tasksID],
                    enabledModuleIDs: [ModuleCatalog.tasksID],
                    pinnedModuleID: nil,
                    menuBarDisplayMode: .iconOnly,
                    theme: .system,
                    quickAddEnabled: false
                )
            )
        )
    }

    func testPreferencesSavedBeforeQuickAddLoadWithQuickAddOffAndKeepOtherFields() throws {
        // Schema 1 with a theme but no Quick Add key, as the theme build wrote it.
        let data = Data(
            """
            {"enabledModuleIDs":["demo.status"],"menuBarDisplayMode":"iconOnly",\
            "moduleOrder":["demo.status","demo.tasks"],"pinnedModuleID":"demo.status",\
            "schemaVersion":1,"theme":"dark"}
            """.utf8
        )
        userDefaults.set(data, forKey: PreferencesStore.storageKey)

        let outcome = try PreferencesStore(userDefaults: userDefaults).load()

        XCTAssertEqual(
            outcome,
            .loaded(
                AppPreferences(
                    schemaVersion: 1,
                    moduleOrder: [ModuleCatalog.statusID, ModuleCatalog.tasksID],
                    enabledModuleIDs: [ModuleCatalog.statusID],
                    pinnedModuleID: ModuleCatalog.statusID,
                    menuBarDisplayMode: .iconOnly,
                    theme: .dark,
                    quickAddEnabled: false
                )
            )
        )
        XCTAssertNil(outcome.warning)
        XCTAssertEqual(userDefaults.data(forKey: PreferencesStore.storageKey), data)
    }

    func testUnreadableQuickAddValueLoadsOffWithoutDiscardingOtherFields() throws {
        for value in [#""yes""#, "null", #"{"on":true}"#] {
            let data = Data(
                """
                {"enabledModuleIDs":["demo.tasks"],"menuBarDisplayMode":"iconOnly",\
                "moduleOrder":["demo.status","demo.tasks"],"pinnedModuleID":null,\
                "schemaVersion":1,"theme":"light","quickAddEnabled":\(value)}
                """.utf8
            )
            userDefaults.set(data, forKey: PreferencesStore.storageKey)

            let outcome = try PreferencesStore(userDefaults: userDefaults).load()

            XCTAssertEqual(
                outcome,
                .loaded(
                    AppPreferences(
                        schemaVersion: 1,
                        moduleOrder: [ModuleCatalog.statusID, ModuleCatalog.tasksID],
                        enabledModuleIDs: [ModuleCatalog.tasksID],
                        pinnedModuleID: nil,
                        menuBarDisplayMode: .iconOnly,
                        theme: .light,
                        quickAddEnabled: false
                    )
                ),
                "quickAddEnabled: \(value)"
            )
        }
    }

    func testReconcilerIgnoresRemovedIDsPreservesKnownOrderAndAppendsNewIDs() {
        let newModule = ModuleDescriptor(
            id: "demo.new",
            displayName: "New content",
            systemImageName: "sparkles",
            canBePinned: true
        )
        let reconciler = PreferencesReconciler(
            catalog: ModuleCatalog.defaultModules + [newModule]
        )
        let stored = AppPreferences(
            schemaVersion: 0,
            moduleOrder: ["demo.removed", ModuleCatalog.statusID, ModuleCatalog.statusID],
            enabledModuleIDs: ["demo.removed", ModuleCatalog.statusID, "demo.new"],
            pinnedModuleID: "demo.removed",
            menuBarDisplayMode: .iconOnly,
            theme: .dark,
            quickAddEnabled: true
        )

        XCTAssertEqual(
            reconciler.reconcile(stored),
            AppPreferences(
                schemaVersion: AppPreferences.currentSchemaVersion,
                moduleOrder: [ModuleCatalog.statusID, ModuleCatalog.tasksID, "demo.new"],
                enabledModuleIDs: [ModuleCatalog.statusID, "demo.new"],
                pinnedModuleID: nil,
                menuBarDisplayMode: .iconOnly,
                theme: .dark,
                quickAddEnabled: true
            )
        )
    }

    func testReconcilerClearsDisabledAndUnpinnablePins() {
        let unpinnableModule = ModuleDescriptor(
            id: "demo.unpinnable",
            displayName: "Cannot pin",
            systemImageName: "nosign",
            canBePinned: false
        )
        let reconciler = PreferencesReconciler(
            catalog: ModuleCatalog.defaultModules + [unpinnableModule]
        )
        let fixtures: [(name: String, preferences: AppPreferences)] = [
            (
                "disabled",
                AppPreferences(
                    schemaVersion: 1,
                    moduleOrder: [ModuleCatalog.tasksID, ModuleCatalog.statusID],
                    enabledModuleIDs: [ModuleCatalog.statusID],
                    pinnedModuleID: ModuleCatalog.tasksID,
                    menuBarDisplayMode: .iconAndInformation,
                    theme: .system,
                    quickAddEnabled: false
                )
            ),
            (
                "unpinnable",
                AppPreferences(
                    schemaVersion: 1,
                    moduleOrder: [ModuleCatalog.tasksID, ModuleCatalog.statusID, unpinnableModule.id],
                    enabledModuleIDs: [ModuleCatalog.tasksID, ModuleCatalog.statusID, unpinnableModule.id],
                    pinnedModuleID: unpinnableModule.id,
                    menuBarDisplayMode: .iconAndInformation,
                    theme: .system,
                    quickAddEnabled: false
                )
            ),
        ]

        for fixture in fixtures {
            XCTAssertNil(
                reconciler.reconcile(fixture.preferences).pinnedModuleID,
                fixture.name
            )
        }
    }

    func testSupportedStoredPreferencesAreReconciledAgainstCurrentCatalog() throws {
        let stored = AppPreferences(
            schemaVersion: AppPreferences.currentSchemaVersion,
            moduleOrder: ["demo.removed", ModuleCatalog.statusID],
            enabledModuleIDs: ["demo.removed", ModuleCatalog.statusID],
            pinnedModuleID: "demo.removed",
            menuBarDisplayMode: .iconOnly,
            theme: .light,
            quickAddEnabled: false
        )
        userDefaults.set(try JSONEncoder().encode(stored), forKey: PreferencesStore.storageKey)

        let outcome = try PreferencesStore(userDefaults: userDefaults).load()

        XCTAssertEqual(
            outcome,
            .loaded(
                AppPreferences(
                    schemaVersion: AppPreferences.currentSchemaVersion,
                    moduleOrder: [ModuleCatalog.statusID, ModuleCatalog.tasksID],
                    enabledModuleIDs: [ModuleCatalog.statusID],
                    pinnedModuleID: nil,
                    menuBarDisplayMode: .iconOnly,
                    theme: .light,
                    quickAddEnabled: false
                )
            )
        )
    }

    func testCorruptDataUsesDefaultsAndPreservesUnrelatedDefaults() throws {
        let corruptData = Data("not valid preferences".utf8)
        userDefaults.set(corruptData, forKey: PreferencesStore.storageKey)
        userDefaults.set("keep me", forKey: "unrelated.key")

        let outcome = try PreferencesStore(userDefaults: userDefaults).load()

        XCTAssertEqual(outcome, .recovered(.defaultValue, warning: .corruptData))
        XCTAssertEqual(outcome.warning?.message.isEmpty, false)
        XCTAssertTrue(outcome.allowsPersistence)
        XCTAssertEqual(userDefaults.data(forKey: PreferencesStore.storageKey), corruptData)
        XCTAssertEqual(userDefaults.string(forKey: "unrelated.key"), "keep me")
    }

    func testUnexpectedStoredTypeProducesControlledRecovery() throws {
        userDefaults.set("not encoded data", forKey: PreferencesStore.storageKey)

        let outcome = try PreferencesStore(userDefaults: userDefaults).load()

        XCTAssertEqual(outcome, .recovered(.defaultValue, warning: .corruptData))
        XCTAssertEqual(
            userDefaults.string(forKey: PreferencesStore.storageKey),
            "not encoded data"
        )
    }

    func testNewerSchemaRemainsByteForByteUnchangedAfterLoadAndAttemptedSave() throws {
        let newerSchemaData = Data(
            """
            {"futureOnly":{"meaning":42},"schemaVersion":\(AppPreferences.currentSchemaVersion + 1)}
            """.utf8
        )
        userDefaults.set(newerSchemaData, forKey: PreferencesStore.storageKey)
        userDefaults.set("keep me", forKey: "unrelated.key")
        let store = PreferencesStore(userDefaults: userDefaults)
        let warning = PreferencesWarning.newerSchema(
            storedVersion: AppPreferences.currentSchemaVersion + 1,
            supportedVersion: AppPreferences.currentSchemaVersion
        )

        let outcome = try store.load()

        XCTAssertEqual(outcome, .incompatibleSchema(.defaultValue, warning: warning))
        XCTAssertEqual(outcome.warning, warning)
        XCTAssertFalse(outcome.allowsPersistence)
        XCTAssertFalse(warning.message.isEmpty)
        XCTAssertEqual(try store.save(.defaultValue), .writeProtected(warning))
        XCTAssertEqual(userDefaults.data(forKey: PreferencesStore.storageKey), newerSchemaData)
        XCTAssertEqual(userDefaults.string(forKey: "unrelated.key"), "keep me")
    }

    func testSaveDetectsNewerSchemaEvenWhenLoadWasNotCalledFirst() throws {
        let newerSchemaData = Data(
            "{\"schemaVersion\":\(AppPreferences.currentSchemaVersion + 1)}".utf8
        )
        userDefaults.set(newerSchemaData, forKey: PreferencesStore.storageKey)
        let store = PreferencesStore(userDefaults: userDefaults)

        let result = try store.save(.defaultValue)

        XCTAssertEqual(
            result,
            .writeProtected(
                .newerSchema(
                    storedVersion: AppPreferences.currentSchemaVersion + 1,
                    supportedVersion: AppPreferences.currentSchemaVersion
                )
            )
        )
        XCTAssertEqual(userDefaults.data(forKey: PreferencesStore.storageKey), newerSchemaData)
    }
}
