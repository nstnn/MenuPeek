import AppKit
import Observation
import SwiftUI

/// Presentation only. The pasteboard carries an opaque token, never task text.
/// AppKit's source-end callback owns releasing the native-session reservation.
@MainActor
@Observable
final class TaskDragSession {
    struct Payload: Equatable {
        let token: UUID
        let taskID: UUID
        let dayKey: String
        let sourceGroup: TaskGroupID
    }

    static let pasteboardType = NSPasteboard.PasteboardType("local.menupocket.today-task-move")
    private(set) var active: Payload?
    private(set) var isDragging = false
    var hoveredRequest: TaskMoveRequest?
    @ObservationIgnored private var scrollTimer: Timer?
    @ObservationIgnored private weak var scrollView: NSScrollView?
    @ObservationIgnored private weak var dragState: DailyNotesState?
    @ObservationIgnored private var nativeToken: UUID?
    @ObservationIgnored private weak var nativeSource: TaskDragHandleView?

    func begin(taskID: UUID, state: DailyNotesState, source: TaskDragHandleView) -> Payload? {
        state.refreshIfDayChanged()
        guard nativeToken == nil, state.taskWindowPresentation.canMoveTask(state: state),
              let note = state.notes.first(where: { $0.id == taskID }),
              note.dayKey == state.todayKey else { return nil }
        let payload = Payload(token: UUID(), taskID: note.id, dayKey: note.dayKey,
                              sourceGroup: TaskGroupID(categoryID: note.categoryID))
        isDragging = true
        nativeToken = payload.token
        nativeSource = source
        active = payload
        scrollView = source.enclosingScrollView
        dragState = state
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            let hasOwner = MainActor.assumeIsolated {
                guard let self else { return false }
                self.scrollAtPointer()
                return true
            }
            if !hasOwner { timer.invalidate() }
        }
        scrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        return payload
    }

    /// Task 6 must use this at hover/drop time, then consume before dispatching
    /// the shared saved-move command. A copied token alone is not a local drag.
    func validatedPayload(for info: any NSDraggingInfo, state: DailyNotesState) -> Payload? {
        guard let payload = active, nativeToken == payload.token,
              let source = info.draggingSource as? TaskDragHandleView,
              source === nativeSource,
              state.taskWindowPresentation.canMoveTask(state: state),
              state.todayKey == payload.dayKey,
              let note = state.notes.first(where: { $0.id == payload.taskID }),
              note.dayKey == payload.dayKey,
              TaskGroupID(categoryID: note.categoryID) == payload.sourceGroup,
              let items = info.draggingPasteboard.pasteboardItems, items.count == 1,
              items[0].types == [Self.pasteboardType],
              items[0].string(forType: Self.pasteboardType) == payload.token.uuidString else { return nil }
        return payload
    }

    func consume(_ payload: Payload) -> Bool {
        guard active == payload, nativeToken == payload.token else { return false }
        stopScrolling()
        active = nil
        hoveredRequest = nil
        return true
    }

    /// Invalidation removes feedback/authorization immediately, but does not
    /// allow another drag until the old native session actually ends.
    func cancel() {
        stopScrolling()
        active = nil
        hoveredRequest = nil
    }

    func ended(token: UUID) {
        guard nativeToken == token else { return }
        stopScrolling()
        active = nil
        hoveredRequest = nil
        nativeToken = nil
        nativeSource = nil
        isDragging = false
    }

    private func stopScrolling() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        scrollView = nil
        dragState = nil
    }

    /// Uses the existing SwiftUI scroll view's clip viewport; no extra scroll owner.
    func scrollAtPointer(screenPoint: NSPoint = NSEvent.mouseLocation) {
        guard let payload = active, let state = dragState,
              state.taskWindowPresentation.canMoveTask(state: state),
              state.todayKey == payload.dayKey,
              state.notes.contains(where: {
                  $0.id == payload.taskID && TaskGroupID(categoryID: $0.categoryID) == payload.sourceGroup
              }) else { cancel(); return }
        guard let scrollView, let window = scrollView.window, window.isVisible,
              let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let point = clip.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        let viewport = clip.bounds
        let topDownPoint = NSPoint(x: point.x - viewport.minX,
                                   y: clip.isFlipped ? point.y - viewport.minY : viewport.maxY - point.y)
        let step = Self.edgeStep(point: topDownPoint,
                                 viewport: NSRect(origin: .zero, size: viewport.size))
        guard step != 0 else { return }
        // Account for AppKit document orientation, and constrain both ends.
        var next = viewport
        next.origin.y += document.isFlipped ? step : -step
        next = clip.constrainBoundsRect(next)
        guard next.origin != viewport.origin else { return }
        hoveredRequest = nil // Old row halves no longer describe the pointer.
        clip.scroll(to: next.origin)
        scrollView.reflectScrolledClipView(clip)
    }

    /// At most 12 points per 30 Hz tick; outside the viewport never scrolls.
    static func edgeStep(point: NSPoint, viewport: NSRect) -> CGFloat {
        guard viewport.contains(point), viewport.height > 0 else { return 0 }
        let edge = min(40, viewport.height / 2)
        if point.y < viewport.minY + edge {
            return -12 * (1 - (point.y - viewport.minY) / edge)
        }
        if point.y > viewport.maxY - edge {
            return 12 * (1 - (viewport.maxY - point.y) / edge)
        }
        return 0
    }

}

struct TaskDragHandle: NSViewRepresentable {
    let taskID: UUID
    let text: String
    let state: DailyNotesState
    let session: TaskDragSession
    let enabled: Bool

    func makeNSView(context: Context) -> TaskDragHandleView {
        let view = TaskDragHandleView(frame: .zero)
        // macOS 14+ permits visibleRect beyond bounds unless clipping is enabled.
        // Cursor tracking must remain confined to this small handle.
        view.clipsToBounds = true
        return view
    }

    func updateNSView(_ view: TaskDragHandleView, context: Context) {
        view.taskID = taskID
        view.state = state
        view.session = session
        if view.isEnabled != enabled {
            view.isEnabled = enabled
            view.window?.invalidateCursorRects(for: view)
        }
        view.toolTip = "Drag to move task"
        view.setAccessibilityLabel("Move task: \(text)")
        view.setAccessibilityIdentifier("taskDragHandle-\(taskID)")
        view.needsDisplay = true
    }

    static func dismantleNSView(_ view: TaskDragHandleView, coordinator: ()) {
        view.clearMouseTracking()
    }
}

/// Only this small handle receives mouse tracking; the surrounding text and
/// controls retain their existing native selection/click behavior.
@MainActor
final class TaskDragHandleView: NSView, NSDraggingSource {
    var taskID: UUID?
    weak var state: DailyNotesState?
    var session: TaskDragSession?
    var isEnabled = false
    private var mouseDownPoint: NSPoint?
    private var sourceToken: UUID?
    // Retain the session owner independently of SwiftUI row updates/removal.
    private var sourceSession: TaskDragSession?
    private var cursorTrackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let color = isEnabled ? NSColor.secondaryLabelColor : NSColor.disabledControlTextColor
        color.setFill()
        for x in [bounds.midX - 3, bounds.midX + 3] {
            for y in [bounds.midY - 5, bounds.midY, bounds.midY + 5] {
                NSBezierPath(ovalIn: NSRect(x: x - 1, y: y - 1, width: 2, height: 2)).fill()
            }
        }
    }

    override func resetCursorRects() {
        if isEnabled { addCursorRect(bounds, cursor: .openHand) }
    }

    override func updateTrackingAreas() {
        if let cursorTrackingArea { removeTrackingArea(cursorTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        cursorTrackingArea = area
        super.updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) {
        (isEnabled ? NSCursor.openHand : NSCursor.arrow).set()
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = isEnabled ? convert(event.locationInWindow, from: nil) : nil
    }

    override func mouseUp(with event: NSEvent) { mouseDownPoint = nil }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = mouseDownPoint, isEnabled, sourceToken == nil,
              let taskID, let state, let session, window != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - origin.x, point.y - origin.y) >= 4 else { return }
        mouseDownPoint = nil
        guard let payload = session.begin(taskID: taskID, state: state, source: self),
              let note = state.notes.first(where: { $0.id == taskID }) else { return }
        sourceToken = payload.token
        sourceSession = session
        let writer = NSPasteboardItem()
        writer.setString(payload.token.uuidString, forType: TaskDragSession.pasteboardType)
        let item = NSDraggingItem(pasteboardWriter: writer)
        let image = preview(for: note)
        item.setDraggingFrame(NSRect(x: point.x - 16, y: point.y - image.size.height / 2,
                                    width: image.size.width, height: image.size.height), contents: image)
        let native = beginDraggingSession(with: [item], event: event, source: self)
        native.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Task 6's destination also advertises .move. There is no external export.
        context == .withinApplication && sourceSession?.active?.token == sourceToken ? .move : []
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        if let token = sourceToken { sourceSession?.ended(token: token) }
        sourceToken = nil
        sourceSession = nil
        mouseDownPoint = nil
    }

    func clearMouseTracking() { mouseDownPoint = nil }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { clearMouseTracking() }
        super.viewWillMove(toWindow: newWindow)
    }

    private func preview(for note: Note) -> NSImage {
        let size = NSSize(width: 300, height: 56)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1),
                     xRadius: 8, yRadius: 8).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1),
                     xRadius: 8, yRadius: 8).stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: note.isCompleted ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let marker = note.isCompleted ? "checkmark.square" : "square"
        NSImage(systemSymbolName: marker, accessibilityDescription: nil)?
            .draw(in: NSRect(x: 12, y: 20, width: 16, height: 16))
        (note.text as NSString).draw(in: NSRect(x: 40, y: 12, width: 248, height: 32),
                                    withAttributes: attributes)
        return image
    }
}
