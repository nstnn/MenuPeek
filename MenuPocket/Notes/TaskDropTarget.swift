import AppKit
import SwiftUI

/// Resolves identity-based placement against the current saved snapshot.
enum TaskDropRouting {
    static func request(payload: TaskDragSession.Payload, group: TaskGroupID,
                        anchor: UUID?, upperHalf: Bool, dayKey: String,
                        notes: [Note], categories: [TaskCategory]) -> TaskMoveRequest? {
        guard anchor != payload.taskID else { return nil }
        let request = TaskMoveRequest(taskID: payload.taskID, expectedDayKey: payload.dayKey,
                                      expectedSourceGroup: payload.sourceGroup,
                                      destinationGroup: group,
                                      placement: anchor.map { upperHalf ? .before($0) : .after($0) } ?? .endOfGroup)
        guard case .changed = TaskMovePlanner.plan(request, dayKey: dayKey, notes: notes, categories: categories) else {
            return nil
        }
        return request
    }
}

/// Header, row and footer targets are siblings, never nested destinations.
/// The overlay is transparent to ordinary clicks and text selection.
struct TaskDropTarget: NSViewRepresentable {
    let state: DailyNotesState
    let session: TaskDragSession
    let group: TaskGroupID
    let anchor: UUID?

    func makeNSView(context: Context) -> TaskDropTargetView {
        TaskDropTargetView(frame: .zero)
    }

    func updateNSView(_ view: TaskDropTargetView, context: Context) {
        view.state = state
        view.session = session
        view.group = group
        view.anchor = anchor
        view.feedback = session.hoveredRequest
        view.needsDisplay = true
    }

    static func dismantleNSView(_ view: TaskDropTargetView, coordinator: ()) {
        view.clearFeedback()
        view.unregisterDraggedTypes()
    }
}

@MainActor
final class TaskDropTargetView: NSView {
    weak var state: DailyNotesState?
    var session: TaskDragSession?
    var group: TaskGroupID = .general
    var anchor: UUID?
    var feedback: TaskMoveRequest?
    private var offeredRequest: TaskMoveRequest?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([TaskDragSession.pasteboardType])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // During a native drag AppKit can discover this registered destination;
        // outside that session the SwiftUI controls underneath own all input.
        guard session?.isDragging == true else { return nil }
        return super.hitTest(point)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { clearFeedback() }
    override func draggingEnded(_ sender: any NSDraggingInfo) { clearFeedback() }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        update(sender) == .move
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { session?.cancel(); clearFeedback() }
        guard let state, let session,
              let payload = session.validatedPayload(for: sender, state: state),
              let request = resolvedRequest(sender, payload: payload),
              session.consume(payload) else { return false }
        // Consume before dispatch: even a duplicate native callback cannot save twice.
        guard case .changed = state.moveTask(request) else { return false }
        return true
    }

    private func resolvedRequest(_ sender: any NSDraggingInfo,
                                 payload: TaskDragSession.Payload) -> TaskMoveRequest? {
        guard let state, let dayKey = state.todayKey, window != nil,
              sender.draggingSourceOperationMask.contains(.move) else { return nil }
        let point = convert(sender.draggingLocation, from: nil)
        guard bounds.contains(point) else { return nil }
        return TaskDropRouting.request(payload: payload, group: group, anchor: anchor,
                                       upperHalf: point.y < bounds.midY, dayKey: dayKey,
                                       notes: state.notes, categories: state.categories)
    }

    private func update(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let state, let session,
              let payload = session.validatedPayload(for: sender, state: state),
              let request = resolvedRequest(sender, payload: payload) else {
            clearFeedback()
            return []
        }
        offeredRequest = request
        session.hoveredRequest = request
        feedback = request
        needsDisplay = true
        return .move
    }

    func clearFeedback() {
        if let offeredRequest, session?.hoveredRequest == offeredRequest {
            session?.hoveredRequest = nil
        }
        offeredRequest = nil
        feedback = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard session?.active != nil, let feedback, feedback.destinationGroup == group else { return }
        NSColor.controlAccentColor.setStroke()
        switch feedback.placement {
        case .endOfGroup where anchor == nil:
            NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            path.fill()
            path.lineWidth = 1
            path.stroke()
        case let .before(id) where id == anchor, let .after(id) where id == anchor:
            let y: CGFloat = feedback.placement == .before(id) ? 1 : bounds.maxY - 1
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 0, y: y))
            line.line(to: NSPoint(x: bounds.maxX, y: y))
            line.lineWidth = 2
            line.stroke()
        default: break
        }
    }
}
