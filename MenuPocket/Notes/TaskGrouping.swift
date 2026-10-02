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

/// Presentation derived from the saved snapshot on each read; groups and their
/// counts are never saved.
struct TaskGroup: Identifiable, Equatable {
    let id: TaskGroupID
    let name: String
    /// Every task in the group in saved insertion order, whether or not the
    /// group is collapsed.
    let notes: [Note]

    var progress: NoteProgress {
        NoteProgress(completed: notes.count(where: \.isCompleted), total: notes.count)
    }

    /// Custom categories in saved creation order, then General. Only groups
    /// with tasks appear. Each group filters the canonical task array, so a
    /// reassigned task takes its original relative position in its new group.
    /// The state never publishes a task whose category is missing from the
    /// catalog, so every task lands in exactly one group.
    static func groups(categories: [TaskCategory], notes: [Note]) -> [TaskGroup] {
        let custom = categories
            .sorted { $0.creationOrder < $1.creationOrder }
            .compactMap { category -> TaskGroup? in
                let rows = notes.filter { $0.categoryID == category.id }
                return rows.isEmpty ? nil : TaskGroup(id: .category(category.id), name: category.name, notes: rows)
            }
        let general = notes.filter { $0.categoryID == nil }
        guard !general.isEmpty else { return custom }
        return custom + [TaskGroup(id: .general, name: TaskCategoryName.general, notes: general)]
    }
}
