import Foundation

/// The complete custom-category order from the displayed catalog, including
/// hidden/unused categories. UUID-only sources/anchors cannot represent General.
/// State and storage must revalidate this expectation before saving.
struct CategoryMoveRequest: Equatable, Sendable {
    let categoryID: UUID
    let expectedOrderIDs: [UUID]
    let placement: CategoryMovePlacement
}

enum CategoryMovePlacement: Equatable, Sendable {
    case before(UUID)
    case after(UUID)
}

enum CategoryMoveRejection: Equatable, Sendable {
    case invalidSnapshot
    case invalidExpectedOrder
    case catalogChanged
    case categoryNotFound
    case invalidAnchor
}

/// A planner's changed catalog is only a proposal. Storage may return it as
/// saved only after COMMIT; unchanged/rejected outcomes must never write.
enum CategoryMoveOutcome: Equatable, Sendable {
    case changed([TaskCategory])
    case unchanged
    case rejected(CategoryMoveRejection)
}

enum CategoryMovePlanner {
    /// Plan against the full catalog in saved-rank order, independent of task
    /// membership, collapse state, and input array order. Unique Int64 ranks,
    /// including sparse/negative legacy ranks, are valid. Storage must rerun
    /// this validation on its fresh transaction snapshot, never a UI proposal.
    static func plan(_ request: CategoryMoveRequest, categories: [TaskCategory]) -> CategoryMoveOutcome {
        guard Set(categories.map(\.id)).count == categories.count,
              Set(categories.map(\.creationOrder)).count == categories.count else {
            return .rejected(.invalidSnapshot)
        }
        guard Set(request.expectedOrderIDs).count == request.expectedOrderIDs.count else {
            return .rejected(.invalidExpectedOrder)
        }
        let ordered = categories.sorted { $0.creationOrder < $1.creationOrder }
        let orderIDs = ordered.map(\.id)
        guard request.expectedOrderIDs == orderIDs else { return .rejected(.catalogChanged) }
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == request.categoryID }) else {
            return .rejected(.categoryNotFound)
        }

        var result = ordered
        let source = result.remove(at: sourceIndex)
        let insertionIndex: Int
        switch request.placement {
        case let .before(anchorID), let .after(anchorID):
            // Removing the source also makes self-anchors invalid.
            guard let anchorIndex = result.firstIndex(where: { $0.id == anchorID }) else {
                return .rejected(.invalidAnchor)
            }
            insertionIndex = anchorIndex + (request.placement == .after(anchorID) ? 1 : 0)
        }
        result.insert(source, at: insertionIndex)

        // Equivalent placement must not compact existing sparse/legacy ranks.
        guard result.map(\.id) != orderIDs else { return .unchanged }
        return .changed(result.enumerated().map { index, category in
            TaskCategory(category, creationOrder: Int64(index))
        })
    }
}
