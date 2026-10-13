import AppKit
import SwiftUI

/// Invisible pointer source confined to headers and empty padding; never task rows.
struct CategoryDragSource: NSViewRepresentable {
    let name: String
    let categoryID: UUID
    let context: CategoryReorderContext
    let state: DailyNotesState
    let session: CategoryDragSession
    let enabled: Bool
    let count: () -> Int?
    var click: (() -> Void)? = nil

    func makeNSView(context: Context) -> CategoryDragSourceView {
        let view = CategoryDragSourceView(frame: .zero)
        view.clipsToBounds = true
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: CategoryDragSourceView, context: Context) {
        view.name = name
        if view.categoryID != categoryID || view.context != self.context || view.catalog != state.categories {
            view.cancelCandidate()
        }
        view.categoryID = categoryID
        view.context = self.context
        view.catalog = state.categories
        view.state = state
        view.session = session
        view.count = count
        view.click = click
        if view.enabled && !enabled { view.cancelCandidate() }
        view.enabled = enabled
    }

    static func dismantleNSView(_ view: CategoryDragSourceView, coordinator: ()) {
        view.cancelCandidate()
    }
}

@MainActor
final class CategoryDragSourceView: NSView, NSDraggingSource {
    static let holdDuration: TimeInterval = 0.300
    static let movementDistance: CGFloat = 4
    enum Phase { case idle, pressed, armed, dragging, cancelled }
    var name = ""
    var categoryID: UUID?
    var context: CategoryReorderContext = .list(.today)
    var catalog: [TaskCategory] = []
    weak var state: DailyNotesState?
    var session: CategoryDragSession?
    var enabled = false
    var count: (() -> Int?)?
    var click: (() -> Void)?
    private(set) var phase = Phase.idle
    private var origin = NSPoint.zero
    private var timer: Timer?
    private var escapeMonitor: Any?
    private var windowObserver: NSObjectProtocol?
    private var nativeToken: UUID?
    private var sourceSession: CategoryDragSession?

    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard enabled else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEligible, nativeToken == nil else { return }
        cancelCandidate()
        origin = convert(event.locationInWindow, from: nil)
        phase = .pressed
        let timer = Timer(timeInterval: Self.holdDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.phase == .pressed, self.enabled,
                      let window = self.window, window.isKeyWindow else { return }
                self.armCandidate()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self,
                  self.phase == .pressed || self.phase == .armed else { return event }
            self.cancelCandidate()
            return nil
        }
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelCandidate() }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard phase == .pressed || phase == .armed else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - origin.x, point.y - origin.y) >= Self.movementDistance else { return }
        guard phase == .armed else { cancelCandidate(); return }
        guard isEligible, let total = count?(), isEligible, let categoryID, let state, let session,
              let payload = session.begin(categoryID: categoryID, context: context, state: state, source: self) else {
            cancelCandidate(); return
        }
        timer?.invalidate()
        timer = nil
        nativeToken = payload.token
        sourceSession = session
        phase = .dragging
        let writer = NSPasteboardItem()
        writer.setString(payload.token.uuidString, forType: CategoryDragSession.pasteboardType)
        let item = NSDraggingItem(pasteboardWriter: writer)
        let image = preview(total: total)
        item.setDraggingFrame(NSRect(x: point.x - 12, y: point.y - image.size.height / 2,
                                     width: image.size.width, height: image.size.height), contents: image)
        let native = beginDraggingSession(with: [item], event: event, source: self)
        native.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        guard phase != .dragging else { return }
        let shortClick = phase == .pressed && isEligible && bounds.contains(convert(event.locationInWindow, from: nil))
        removeTracking()
        phase = .idle
        needsDisplay = true
        if shortClick { click?() }
    }

    private var isEligible: Bool {
        guard enabled, let categoryID, let state, let session, state.categories == catalog else { return false }
        return session.canBegin(categoryID: categoryID, context: context, state: state)
    }

    func armCandidate() {
        guard phase == .pressed, isEligible else { cancelCandidate(); return }
        timer?.invalidate()
        timer = nil
        phase = .armed
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard phase == .armed else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
    }

    func cancelCandidate() {
        removeTracking()
        if phase == .dragging {
            sourceSession?.cancel()
        } else {
            phase = .cancelled
        }
        needsDisplay = true
    }

    private func removeTracking() {
        timer?.invalidate()
        timer = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { cancelCandidate() }
        super.viewWillMove(toWindow: newWindow)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication && sourceSession?.active?.token == nativeToken ? .move : []
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if let nativeToken { sourceSession?.ended(token: nativeToken) }
        nativeToken = nil
        sourceSession = nil
        phase = .idle
        needsDisplay = true
        removeTracking()
    }

    private func preview(total: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: 260, height: 54))
        image.lockFocus()
        defer { image.unlockFocus() }
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: image.size).insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (name as NSString).draw(in: NSRect(x: 12, y: 27, width: 236, height: 18), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph
        ])
        ("\(total) tasks" as NSString).draw(in: NSRect(x: 12, y: 9, width: 236, height: 16), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor
        ])
        return image
    }
}

