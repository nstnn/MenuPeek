import Foundation
import Observation

/// Category presentation choices on this Mac: the category of the last new
/// task saved from Today, and collapsed Today groups. Kept in their own keys,
/// apart from the versioned AppPreferences envelope and from saved tasks. A
/// missing, malformed, or obsolete value means General or an expanded group.
@MainActor
@Observable
final class TaskCategoryPreferences {
    nonisolated static let lastUsedCategoryIDKey = "local.menupocket.app.taskCategories.lastUsedCategoryID"
    nonisolated static let collapsedGroupIDsKey = "local.menupocket.app.taskCategories.collapsedGroupIDs"

    /// nil is General.
    private(set) var lastUsedCategoryID: UUID?
    private(set) var collapsedGroupIDs: Set<TaskGroupID>

    @ObservationIgnored private let userDefaults: UserDefaults

    /// Reads without writing, so a malformed value stays untouched until that
    /// choice changes.
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        lastUsedCategoryID = (userDefaults.object(forKey: Self.lastUsedCategoryIDKey) as? String)
            .flatMap(UUID.init(uuidString:))
        let storedGroups = userDefaults.object(forKey: Self.collapsedGroupIDsKey) as? [Any] ?? []
        collapsedGroupIDs = Set(storedGroups.compactMap { ($0 as? String).flatMap(TaskGroupID.init(storageKey:)) })
    }

    func isCollapsed(_ group: TaskGroupID) -> Bool {
        collapsedGroupIDs.contains(group)
    }

    func setCollapsed(_ collapsed: Bool, for group: TaskGroupID) {
        var groups = collapsedGroupIDs
        if collapsed { groups.insert(group) } else { groups.remove(group) }
        storeCollapsed(groups)
    }

    /// Record only a new task saved from Today; edits, cancelled or rejected
    /// drafts, and Quick Add leave this unchanged.
    func rememberLastUsed(_ categoryID: UUID?) {
        storeLastUsed(categoryID)
    }

    /// Forgets custom categories missing from a completely loaded catalog.
    /// General is never obsolete. Writes only when a value changes.
    func prune(keeping categoryIDs: Set<UUID>) {
        if let id = lastUsedCategoryID, !categoryIDs.contains(id) { storeLastUsed(nil) }
        storeCollapsed(collapsedGroupIDs.filter { group in
            guard case let .category(id) = group else { return true }
            return categoryIDs.contains(id)
        })
    }

    private func storeLastUsed(_ categoryID: UUID?) {
        guard categoryID != lastUsedCategoryID else { return }
        lastUsedCategoryID = categoryID
        if let categoryID {
            userDefaults.set(categoryID.uuidString, forKey: Self.lastUsedCategoryIDKey)
        } else {
            userDefaults.removeObject(forKey: Self.lastUsedCategoryIDKey)
        }
    }

    private func storeCollapsed(_ groups: Set<TaskGroupID>) {
        guard groups != collapsedGroupIDs else { return }
        collapsedGroupIDs = groups
        userDefaults.set(groups.map(\.storageKey).sorted(), forKey: Self.collapsedGroupIDsKey)
    }
}
