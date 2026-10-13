import AppKit
import Observation

enum CategoryReorderContext: Equatable, Sendable {
    case list(TaskListDestination)
    case manager
}

/// Transient authorization. Only the native source-end callback releases ownership.
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

    static let pasteboardType = NSPasteboard.PasteboardType("local.menupocket.category-move")
    private(set) var active: Payload?
    private(set) var isDragging = false
    var hoveredRequest: CategoryMoveRequest?
    @ObservationIgnored private var nativeToken: UUID?
    @ObservationIgnored private var nativeSource: CategoryDragSourceView?
    @ObservationIgnored private var consumed: Payload?

    func canBegin(categoryID: UUID, context: CategoryReorderContext, state: DailyNotesState) -> Bool {
        nativeToken == nil &&
            state.taskWindowPresentation.canReorderCategories(in: context, state: state) &&
            state.categories.contains { $0.id == categoryID } &&
            isVisible(categoryID, in: context, state: state)
    }

    func begin(categoryID: UUID, context: CategoryReorderContext, state: DailyNotesState,
               source: CategoryDragSourceView? = nil) -> Payload? {
        guard nativeToken == nil,
              state.taskWindowPresentation.canReorderCategories(in: context, state: state),
              state.categories.contains(where: { $0.id == categoryID }),
              isVisible(categoryID, in: context, state: state) else { return nil }
        let payload = Payload(token: UUID(), categoryID: categoryID, context: context, catalog: state.categories)
        nativeSource = source
        nativeToken = payload.token
        isDragging = true
        active = payload
        return payload
    }

    /// A copied/external token is insufficient: the native source identity must match.
    func validatedPayload(source: AnyObject?, pasteboard: NSPasteboard, state: DailyNotesState) -> Payload? {
        validate(state: state)
        guard let payload = active, nativeToken == payload.token,
              let nativeSource, source === nativeSource,
              let items = pasteboard.pasteboardItems, items.count == 1,
              items[0].types == [Self.pasteboardType],
              items[0].string(forType: Self.pasteboardType) == payload.token.uuidString else { return nil }
        return payload
    }

    func validatedPayload(for info: any NSDraggingInfo, state: DailyNotesState) -> Payload? {
        validatedPayload(source: info.draggingSource as AnyObject?, pasteboard: info.draggingPasteboard, state: state)
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
        nativeSource = nil
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
