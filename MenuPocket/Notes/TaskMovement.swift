import Foundation

/// Stable identities from the displayed snapshot; General uses `.general`.
/// Both state and storage must revalidate these expectations before saving.
struct TaskMoveRequest: Equatable, Sendable {
    let taskID: UUID
    let expectedDayKey: String
    let expectedSourceGroup: TaskGroupID
    let destinationGroup: TaskGroupID
    let placement: TaskMovePlacement
}

enum TaskMovePlacement: Equatable, Sendable {
    case before(UUID)
    case after(UUID)
    case endOfGroup
}

enum TaskMoveRejection: Equatable, Sendable {
    case dayChanged
    case invalidSnapshot
    case taskNotFound
    case sourceChanged
    case destinationNotFound
    case invalidAnchor
}

/// A planner's changed snapshot is a proposal, not evidence of persistence.
/// The repository may return it only after COMMIT; unchanged/rejected never write.
enum TaskMoveOutcome: Equatable, Sendable {
    case changed([Note])
    case unchanged
    case rejected(TaskMoveRejection)
}

enum TaskMovePlanner {
    /// `dayKey` is the caller's authorized action-time Today key. `notes` must
    /// be that day's complete canonical sequence, not a filtered visible group.
    /// Storage uses its transaction's fresh snapshot; UI previews never save it.
    static func plan(_ request: TaskMoveRequest, dayKey: String,
                     notes: [Note], categories: [TaskCategory]) -> TaskMoveOutcome {
        guard request.expectedDayKey == dayKey else { return .rejected(.dayChanged) }
        let categoryIDs = Set(categories.map(\.id))
        guard categoryIDs.count == categories.count,
              Set(notes.map(\.id)).count == notes.count,
              notes.allSatisfy({ note in
                  note.dayKey == dayKey && note.categoryID.map(categoryIDs.contains) != false
              }) else { return .rejected(.invalidSnapshot) }
        guard let sourceIndex = notes.firstIndex(where: { $0.id == request.taskID }) else {
            return .rejected(.taskNotFound)
        }
        let source = notes[sourceIndex]
        guard TaskGroupID(categoryID: source.categoryID) == request.expectedSourceGroup else {
            return .rejected(.sourceChanged)
        }
        let destinationCategoryID: UUID?
        switch request.destinationGroup {
        case .general:
            destinationCategoryID = nil
        case let .category(id):
            guard categoryIDs.contains(id) else { return .rejected(.destinationNotFound) }
            destinationCategoryID = id
        }

        var result = notes
        result.remove(at: sourceIndex)
        let insertionIndex: Int
        switch request.placement {
        case let .before(anchorID), let .after(anchorID):
            guard let anchorIndex = result.firstIndex(where: { $0.id == anchorID }),
                  result[anchorIndex].categoryID == destinationCategoryID else {
                return .rejected(.invalidAnchor)
            }
            insertionIndex = anchorIndex + (request.placement == .after(anchorID) ? 1 : 0)
        case .endOfGroup:
            // An empty destination appends to the canonical day sequence.
            insertionIndex = result.lastIndex(where: { $0.categoryID == destinationCategoryID })
                .map { $0 + 1 } ?? result.endIndex
        }
        let moved = Note(id: source.id, text: source.text, dayKey: source.dayKey,
                         createdAt: source.createdAt, completedAt: source.completedAt,
                         categoryID: destinationCategoryID)
        result.insert(moved, at: insertionIndex)

        // Other groups can lie between adjacent visible rows. If the task's
        // group and visible position are unchanged, do not rewrite daily ranks.
        if source.categoryID == destinationCategoryID,
           notes.filter({ $0.categoryID == destinationCategoryID }).map(\.id)
            == result.filter({ $0.categoryID == destinationCategoryID }).map(\.id) {
            return .unchanged
        }
        return .changed(result)
    }
}
