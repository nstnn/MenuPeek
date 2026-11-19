import AppKit
import Observation
import SwiftUI

/// Runs one time-grid drag at a time for the Day/Week grid: holds the
/// `ScheduleDragSession` the preview is drawn from, cancels it on Escape, and
/// scrolls the grid while the pointer is held near its top or bottom edge.
///
/// The gesture itself is SwiftUI's; this object only adds what SwiftUI lacks.
/// A cancelled or refused gesture is ignored until the mouse is released, so
/// it can never restart halfway through.
@MainActor
@Observable
final class ScheduleGridDragController {
    private(set) var session: ScheduleDragSession?
    @ObservationIgnored private var isIgnoringGesture = false
    @ObservationIgnored private var escapeMonitor: Any?
    @ObservationIgnored private var scrollTimer: Timer?
    @ObservationIgnored weak var probe: ScheduleGridProbeView?

    /// Called for each gesture change. `makeSession` runs once, on the first
    /// change; returning nil refuses the gesture until release.
    func track(to point: CGPoint, makeSession: () -> ScheduleDragSession?) {
        guard !isIgnoringGesture else { return }
        if session == nil {
            guard let started = makeSession() else {
                isIgnoringGesture = true
                return
            }
            session = started
            startMonitoring()
        }
        session?.update(to: point)
    }

    /// Ends the gesture and returns its session, or nil after Escape, a
    /// refusal, or a gesture that never started.
    func finish(at point: CGPoint) -> ScheduleDragSession? {
        defer { reset() }
        guard !isIgnoringGesture, var finished = session else { return nil }
        finished.update(to: point)
        return finished
    }

    /// Drops the drag with nothing saved. The gesture stays ignored until release.
    func cancel() {
        guard session != nil else { return }
        stopMonitoring()
        session = nil
        isIgnoringGesture = true
    }

    private func reset() {
        stopMonitoring()
        session = nil
        isIgnoringGesture = false
    }

    // MARK: Escape and auto-scroll

    private func startMonitoring() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.session != nil else { return false }
                self.cancel()
                return true
            }
            return handled ? nil : event
        }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            let hasOwner = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                self.scrollAtPointer()
                return true
            }
            if !hasOwner { timer.invalidate() }
        }
        scrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopMonitoring() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    /// One auto-scroll tick. The pointer is where the gesture last reported
    /// it (not the hardware cursor, which events posted by assistive tools do
    /// not move). After scrolling, that same window point sits over a later
    /// (or earlier) minute, so the session's point is re-read from it and the
    /// preview follows.
    private func scrollAtPointer() {
        guard let current = session, current.isDragging, let probe, let window = probe.window,
              window.isVisible, let scrollView = probe.enclosingScrollView,
              let document = scrollView.documentView,
              let windowPoint = probe.windowPoint(fromGrid: current.current) else { return }
        let clip = scrollView.contentView
        let pointer = clip.convert(windowPoint, from: nil)
        let viewport = clip.bounds
        let fromTop = clip.isFlipped ? pointer.y - viewport.minY : viewport.maxY - pointer.y
        let step = ScheduleDragAutoScroll.step(pointerY: fromTop, viewportHeight: viewport.height)
        guard step != 0 else { return }
        var next = viewport
        next.origin.y += document.isFlipped ? step : -step
        next = clip.constrainBoundsRect(next)
        guard next.origin != viewport.origin else { return }
        clip.scroll(to: next.origin)
        scrollView.reflectScrolledClipView(clip)
        if let point = probe.gridPoint(fromWindow: windowPoint) {
            session?.update(to: point)
        }
    }
}

/// An invisible view covering the grid body, so the drag controller can find
/// the grid's scroll view and turn the pointer into grid coordinates.
struct ScheduleGridDragProbe: NSViewRepresentable {
    let controller: ScheduleGridDragController
    /// The grid body's size in SwiftUI points.
    let gridSize: CGSize

    func makeNSView(context: Context) -> ScheduleGridProbeView { ScheduleGridProbeView(frame: .zero) }

    func updateNSView(_ view: ScheduleGridProbeView, context: Context) {
        view.gridSize = gridSize
        controller.probe = view
    }

    static func dismantleNSView(_ view: ScheduleGridProbeView, coordinator: ()) {
        view.removeFromSuperview()
    }
}

final class ScheduleGridProbeView: NSView {
    var gridSize: CGSize = .zero

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The grid point under a window location. Divides by the view's own size
    /// so a zoomed window still yields SwiftUI points.
    func gridPoint(fromWindow point: NSPoint) -> CGPoint? {
        guard bounds.width > 0, bounds.height > 0, gridSize.width > 0, gridSize.height > 0 else { return nil }
        let local = convert(point, from: nil)
        return CGPoint(x: local.x * gridSize.width / bounds.width,
                       y: local.y * gridSize.height / bounds.height)
    }

    /// The window location of a grid point; the inverse of `gridPoint(fromWindow:)`.
    func windowPoint(fromGrid point: CGPoint) -> NSPoint? {
        guard bounds.width > 0, bounds.height > 0, gridSize.width > 0, gridSize.height > 0 else { return nil }
        let local = NSPoint(x: point.x * bounds.width / gridSize.width,
                            y: point.y * bounds.height / gridSize.height)
        return convert(local, to: nil)
    }
}
