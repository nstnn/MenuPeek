import Foundation

/// A Today group's identity. Custom categories use their saved UUID; General
/// has a fixed presentation identity because it has no category row.
enum TaskGroupID: Hashable, Sendable {
    case category(UUID)
    case general

    private static let generalKey = "general"

    /// The group a task with this category belongs to; nil is General.
    init(categoryID: UUID?) {
        self = categoryID.map(Self.category) ?? .general
    }

    /// Stable text for presentation preferences. General's key never parses as a UUID.
    var storageKey: String {
        switch self {
        case let .category(id): id.uuidString
        case .general: Self.generalKey
        }
    }

    init?(storageKey: String) {
        if storageKey == Self.generalKey {
            self = .general
        } else if let id = UUID(uuidString: storageKey) {
            self = .category(id)
        } else {
            return nil
        }
    }
}

/// One presentation order for groups, pickers, the manager, and Move To menus.
/// General is fixed first; the custom-only saved catalog remains unchanged.
enum TaskCategoryOption: Identifiable, Equatable {
    case general
    case custom(TaskCategory)

    var id: TaskGroupID { TaskGroupID(categoryID: categoryID) }

    var categoryID: UUID? {
        switch self {
        case .general: nil
        case let .custom(category): category.id
        }
    }

    var name: String {
        switch self {
        case .general: TaskCategoryName.general
        case let .custom(category): category.name
        }
    }

    static func ordered(categories: [TaskCategory]) -> [Self] {
        [.general] + categories.sorted { $0.creationOrder < $1.creationOrder }.map(Self.custom)
    }
}

/// Presentation derived from the saved snapshot on each read; groups and their
/// counts are never saved.
struct TaskGroup: Identifiable, Equatable {
    let id: TaskGroupID
    let name: String
    /// Every task in the group in saved display order, whether or not the
    /// group is collapsed.
    let notes: [Note]

    var progress: NoteProgress {
        NoteProgress(completed: notes.count(where: \.isCompleted), total: notes.count)
    }

    /// General first, then custom categories in saved rank order. Only groups
    /// with tasks appear unless a live drag requests transient empty targets.
    /// Each group filters the canonical task array. An
    /// explicit move follows its saved rank; Edit reassignment retains its rank.
    /// The state never publishes a task whose category is missing from the
    /// catalog, so every task lands in exactly one group.
    static func groups(categories: [TaskCategory], notes: [Note], includeEmpty: Bool = false) -> [TaskGroup] {
        TaskCategoryOption.ordered(categories: categories).compactMap { option in
            let rows = notes.filter { $0.categoryID == option.categoryID }
            return rows.isEmpty && !includeEmpty ? nil : TaskGroup(id: option.id, name: option.name, notes: rows)
        }
    }
}

/// Presentation derived from the saved Later snapshot on each read; groups and
/// their counts are never saved.
struct LaterTaskGroup: Identifiable, Equatable {
    let id: TaskGroupID
    let name: String
    /// Every task in the group in saved insertion order, whether or not the
    /// group is collapsed.
    let tasks: [LaterTask]

    /// Unfinished tasks in this group. Groups containing only completed rows
    /// remain visible with zero remaining.
    var remainingCount: Int {
        tasks.count { !$0.isCompleted }
    }

    /// General first, then custom categories in saved rank order. Only groups
    /// with tasks appear. Each group filters the canonical task array, so a
    /// reassigned task takes its original relative position in its new group.
    /// The state never publishes a task whose category is missing from the
    /// catalog, so every task lands in exactly one group.
    static func groups(categories: [TaskCategory], tasks: [LaterTask]) -> [LaterTaskGroup] {
        TaskCategoryOption.ordered(categories: categories).compactMap { option in
            let rows = tasks.filter { $0.categoryID == option.categoryID }
            return rows.isEmpty ? nil : LaterTaskGroup(id: option.id, name: option.name, tasks: rows)
        }
    }
}

