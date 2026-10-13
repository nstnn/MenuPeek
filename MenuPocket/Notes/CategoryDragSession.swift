import Foundation
import Observation

enum CategoryReorderContext: Equatable, Sendable {
    case list(TaskListDestination)
    case manager
}

/// Transient authorization only. Native sources added by TASK-006 must retain
/// this owner and release the reservation solely from their source-end callback.
@MainActor
@Observable
final class CategoryDragSession {
    struct Payload: Equatable {
        let token: UUID
        let categoryID: UUID
        let context: CategoryReorderContext
        let catalog: [TaskCategory]

        func request(_ placement: CategoryMovePlacement) -> CategoryMoveRequest {
            CategoryMoveRequest(categoryID: categoryID, expectedOrderIDs: catalog.map(\.id), placement: placement)
        }
    }

    private(set) var active: Payload?
    private(set) var isDragging = false
    var hoveredRequest: CategoryMoveRequest?
    @ObservationIgnored private var nativeToken: UUID?
    @ObservationIgnored private var consumed: Payload?

    func begin(categoryID: UUID, context: CategoryReorderContext, state: DailyNotesState) -> Payload? {
        guard nativeToken == nil,
              state.taskWindowPresentation.canReorderCategories(in: context, state: state),
              state.categories.contains(where: { $0.id == categoryID }),
              isVisible(categoryID, in: context, state: state) else { return nil }
        let payload = Payload(token: UUID(), categoryID: categoryID, context: context, catalog: state.categories)
        nativeToken = payload.token
        isDragging = true
        active = payload
        return payload
    }

    func validate(state: DailyNotesState) {
        guard let payload = active ?? consumed else { return }
        if !isValid(payload, state: state) { cancel() }
    }

    /// Consume once before dispatch. AppKit's reservation remains in place even
    /// after feedback/authorization is cleared or the source view unmounts.
    func consume(_ payload: Payload, state: DailyNotesState) -> Bool {
        guard active == payload, nativeToken == payload.token, isValid(payload, state: state) else {
            validate(state: state)
            return false
        }
        active = nil
        hoveredRequest = nil
        consumed = payload
        return true
    }

    func authorizesSave(_ request: CategoryMoveRequest, context: CategoryReorderContext) -> Bool {
        guard nativeToken != nil else { return true }
        guard let payload = consumed, payload.context == context,
              payload.categoryID == request.categoryID,
              payload.catalog.map(\.id) == request.expectedOrderIDs else { return false }
        consumed = nil
        return true
    }

    func cancel() {
        active = nil
        consumed = nil
        hoveredRequest = nil
    }

    func ended(token: UUID) {
        guard nativeToken == token else { return }
        cancel()
        nativeToken = nil
        isDragging = false
    }

    private func isValid(_ payload: Payload, state: DailyNotesState) -> Bool {
        state.categories == payload.catalog &&
            state.taskWindowPresentation.canReorderCategories(in: payload.context, state: state) &&
            isVisible(payload.categoryID, in: payload.context, state: state)
    }

    private func isVisible(_ id: UUID, in context: CategoryReorderContext, state: DailyNotesState) -> Bool {
        switch context {
        case .manager: true
        case .list(.today): state.groups.contains { $0.id == .category(id) }
        case .list(.later): state.laterGroups.contains { $0.id == .category(id) }
        }
    }
}
