import Observation
import XCTest
@testable import MenuPocket

@MainActor
final class TaskCategoryPreferencesTests: XCTestCase {
    private let lastUsedKey = TaskCategoryPreferences.lastUsedCategoryIDKey
    private let collapsedKey = TaskCategoryPreferences.collapsedGroupIDsKey

    func testMissingValuesMeanGeneralAndExpandedWithoutWritingKeys() {
        let defaults = isolatedDefaults()
        let preferences = TaskCategoryPreferences(userDefaults: defaults)

        XCTAssertNil(preferences.lastUsedCategoryID)
        XCTAssertEqual(preferences.collapsedGroupIDs, [])
        XCTAssertFalse(preferences.isCollapsed(.general))
        preferences.prune(keeping: [])
        preferences.rememberLastUsed(nil)
        preferences.setCollapsed(false, for: .general)
        XCTAssertNil(defaults.object(forKey: lastUsedKey))
        XCTAssertNil(defaults.object(forKey: collapsedKey))
    }

    func testChoicesSurviveANewOwnerAndClearIndependently() {
        let defaults = isolatedDefaults()
        let work = UUID()
        let preferences = TaskCategoryPreferences(userDefaults: defaults)
        preferences.rememberLastUsed(work)
        preferences.setCollapsed(true, for: .category(work))
        preferences.setCollapsed(true, for: .general)

        let reopened = TaskCategoryPreferences(userDefaults: defaults)
        XCTAssertEqual(reopened.lastUsedCategoryID, work)
        XCTAssertEqual(reopened.collapsedGroupIDs, [.category(work), .general])

        reopened.setCollapsed(false, for: .category(work))
        reopened.rememberLastUsed(nil)
        let again = TaskCategoryPreferences(userDefaults: defaults)
        XCTAssertNil(again.lastUsedCategoryID)
        XCTAssertNil(defaults.object(forKey: lastUsedKey))
        XCTAssertTrue(again.isCollapsed(.general))
        XCTAssertFalse(again.isCollapsed(.category(work)))
    }

    func testMalformedValuesFallBackWithoutRewritingThemOrOtherKeys() {
        let defaults = isolatedDefaults()
        let work = UUID()
        let envelope = Data(#"{"schemaVersion":1}"#.utf8)
        defaults.set(envelope, forKey: PreferencesStore.storageKey)
        defaults.set(true, forKey: UserDefaultsOnboardingStore.storageKey)
        let malformedLastUsed: [Any] = [42, "not-a-uuid", [work.uuidString]]
        for lastUsed in malformedLastUsed {
            defaults.set(lastUsed, forKey: lastUsedKey)
            XCTAssertNil(TaskCategoryPreferences(userDefaults: defaults).lastUsedCategoryID)
        }
        defaults.set("general", forKey: collapsedKey)
        XCTAssertEqual(TaskCategoryPreferences(userDefaults: defaults).collapsedGroupIDs, [])

        let mixed: [Any] = [42, "general", "junk", work.uuidString, work.uuidString.lowercased()]
        defaults.set(mixed, forKey: collapsedKey)
        let preferences = TaskCategoryPreferences(userDefaults: defaults)
        XCTAssertEqual(preferences.collapsedGroupIDs, [.general, .category(work)])
        // Nothing obsolete is known, so the stored values stay as they were.
        preferences.prune(keeping: [work])
        XCTAssertEqual(defaults.array(forKey: collapsedKey)?.count, mixed.count)
        XCTAssertEqual(defaults.object(forKey: lastUsedKey) as? [String], [work.uuidString])

        preferences.setCollapsed(false, for: .general)
        XCTAssertEqual(defaults.stringArray(forKey: collapsedKey), [work.uuidString])
        XCTAssertEqual(defaults.data(forKey: PreferencesStore.storageKey), envelope)
        XCTAssertEqual(defaults.object(forKey: UserDefaultsOnboardingStore.storageKey) as? Bool, true)
    }

    func testPruneForgetsMissingCategoriesButKeepsGeneral() {
        let defaults = isolatedDefaults()
        let work = UUID()
        let removed = UUID()
        let preferences = TaskCategoryPreferences(userDefaults: defaults)
        preferences.rememberLastUsed(removed)
        for group in [TaskGroupID.category(work), .category(removed), .general] {
            preferences.setCollapsed(true, for: group)
        }

        preferences.prune(keeping: [work])
        XCTAssertNil(preferences.lastUsedCategoryID)
        XCTAssertEqual(preferences.collapsedGroupIDs, [.category(work), .general])
        let reopened = TaskCategoryPreferences(userDefaults: defaults)
        XCTAssertNil(reopened.lastUsedCategoryID)
        XCTAssertEqual(reopened.collapsedGroupIDs, [.category(work), .general])

        preferences.rememberLastUsed(work)
        preferences.prune(keeping: [])
        XCTAssertNil(preferences.lastUsedCategoryID)
        XCTAssertEqual(preferences.collapsedGroupIDs, [.general])
    }

    func testCollapseChangesAreObservable() {
        let preferences = TaskCategoryPreferences(userDefaults: isolatedDefaults())
        let changed = expectation(description: "Collapse state changed")
        withObservationTracking {
            _ = preferences.isCollapsed(.general)
        } onChange: {
            changed.fulfill()
        }

        preferences.setCollapsed(true, for: .general)
        wait(for: [changed], timeout: 1)
    }

    func testLaterPreferencesUseSeparateKeysAndDoNotOverwriteTodayChoices() {
        let defaults = isolatedDefaults()
        let todayCategory = UUID()
        let laterCategory = UUID()

        let preferences = TaskCategoryPreferences(userDefaults: defaults)
        preferences.rememberLastUsed(todayCategory, in: .today)
        preferences.rememberLastUsed(laterCategory, in: .later)
        preferences.setCollapsed(true, for: .category(todayCategory), in: .today)
        preferences.setCollapsed(true, for: .category(laterCategory), in: .later)

        XCTAssertEqual(preferences.lastUsedCategoryID(for: .today), todayCategory)
        XCTAssertEqual(preferences.lastUsedCategoryID(for: .later), laterCategory)
        XCTAssertTrue(preferences.isCollapsed(.category(todayCategory), in: .today))
        XCTAssertFalse(preferences.isCollapsed(.category(todayCategory), in: .later))
        XCTAssertFalse(preferences.isCollapsed(.category(laterCategory), in: .today))
        XCTAssertTrue(preferences.isCollapsed(.category(laterCategory), in: .later))

        XCTAssertEqual(defaults.object(forKey: TaskCategoryPreferences.lastUsedCategoryIDKey) as? String,
                       todayCategory.uuidString)
        XCTAssertEqual(defaults.object(forKey: TaskCategoryPreferences.laterLastUsedCategoryIDKey) as? String,
                       laterCategory.uuidString)

        let reopened = TaskCategoryPreferences(userDefaults: defaults)
        XCTAssertEqual(reopened.lastUsedCategoryID(for: .today), todayCategory)
        XCTAssertEqual(reopened.lastUsedCategoryID(for: .later), laterCategory)
        XCTAssertTrue(reopened.isCollapsed(.category(todayCategory), in: .today))
        XCTAssertTrue(reopened.isCollapsed(.category(laterCategory), in: .later))
    }

    func testLaterPreferencesMalformedValuesFallBackGracefully() {
        let defaults = isolatedDefaults()
        let laterWork = UUID()
        defaults.set("not-a-uuid", forKey: TaskCategoryPreferences.laterLastUsedCategoryIDKey)
        defaults.set([123, "not-a-valid-group"], forKey: TaskCategoryPreferences.laterCollapsedGroupIDsKey)

        let preferences = TaskCategoryPreferences(userDefaults: defaults)
        XCTAssertNil(preferences.laterLastUsedCategoryID)
        XCTAssertEqual(preferences.laterCollapsedGroupIDs, [])

        preferences.rememberLastUsed(laterWork, in: .later)
        preferences.setCollapsed(true, for: .general, in: .later)
        XCTAssertEqual(preferences.laterLastUsedCategoryID, laterWork)
        XCTAssertTrue(preferences.isCollapsed(.general, in: .later))
    }

    func testPruneCleansObsoleteCategoriesFromBothTodayAndLater() {
        let defaults = isolatedDefaults()
        let active = UUID()
        let obsoleteToday = UUID()
        let obsoleteLater = UUID()

        let preferences = TaskCategoryPreferences(userDefaults: defaults)
        preferences.rememberLastUsed(obsoleteToday, in: .today)
        preferences.rememberLastUsed(obsoleteLater, in: .later)
        preferences.setCollapsed(true, for: .category(obsoleteToday), in: .today)
        preferences.setCollapsed(true, for: .category(active), in: .today)
        preferences.setCollapsed(true, for: .category(obsoleteLater), in: .later)
        preferences.setCollapsed(true, for: .category(active), in: .later)

        preferences.prune(keeping: [active])

        XCTAssertNil(preferences.lastUsedCategoryID(for: .today))
        XCTAssertNil(preferences.lastUsedCategoryID(for: .later))
        XCTAssertFalse(preferences.isCollapsed(.category(obsoleteToday), in: .today))
        XCTAssertTrue(preferences.isCollapsed(.category(active), in: .today))
        XCTAssertFalse(preferences.isCollapsed(.category(obsoleteLater), in: .later))
        XCTAssertTrue(preferences.isCollapsed(.category(active), in: .later))
    }
}

extension XCTestCase {
    /// A unique defaults suite removed after the test. Hosted tests run in the
    /// app's sandbox container, where `UserDefaults.standard` holds the user's
    /// real choices, so no test may back its preferences with it.
    func isolatedDefaults() -> UserDefaults {
        let suiteName = "local.menupocket.tests.TaskCategoryPreferences.\(UUID().uuidString)"
        // Capture only the suite name; XCTestCase is not Sendable.
        addTeardownBlock { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        return UserDefaults(suiteName: suiteName)!
    }

    @MainActor
    func isolatedCategoryPreferences() -> TaskCategoryPreferences {
        TaskCategoryPreferences(userDefaults: isolatedDefaults())
    }
}
