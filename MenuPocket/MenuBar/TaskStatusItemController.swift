import AppKit
import Observation

@MainActor
final class TaskStatusItemController: NSObject {
    private(set) var statusItem: NSStatusItem?
    private let state: DailyNotesState
    private let showTasks: () -> Void
    /// Builds a fresh glance menu for each right-click; nil disables the glance.
    let makeGlanceMenu: (@MainActor () -> NSMenu?)?
    /// Tracks the attached menu. The default clicks the button, which blocks
    /// until the menu closes.
    private let presentGlanceMenu: @MainActor (NSStatusBarButton) -> Void
    private var isPresentingGlance = false

    init(
        state: DailyNotesState,
        showTasks: @escaping () -> Void,
        makeGlanceMenu: (@MainActor () -> NSMenu?)? = nil,
        presentGlanceMenu: @escaping @MainActor (NSStatusBarButton) -> Void = { $0.performClick(nil) }
    ) {
        self.state = state
        self.showTasks = showTasks
        self.makeGlanceMenu = makeGlanceMenu
        self.presentGlanceMenu = presentGlanceMenu
        super.init()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(openTasks)
            if makeGlanceMenu != nil {
                // Keep the primary click's existing event and add right-mouse-up.
                let previous = button.sendAction(on: .rightMouseUp)
                button.sendAction(on: NSEvent.EventTypeMask(rawValue: UInt64(previous)).union(.rightMouseUp))
                button.setAccessibilityCustomActions([
                    NSAccessibilityCustomAction(name: "Show quick look", target: self,
                                                selector: #selector(showGlanceForAccessibility)),
                ])
            }
        }
        updateAndObserve()
    }

    private func updateAndObserve() {
        guard let button = statusItem?.button else { return }
        let progress = withObservationTracking {
            state.availableProgress
        } onChange: { [weak self] in
            // Observation fires before mutation. Read the settled snapshot and
            // renew tracking on the main actor, independently of any window.
            Task { @MainActor [weak self] in self?.updateAndObserve() }
        }
        let glanceHint = makeGlanceMenu == nil ? "" : " Right-click for a quick look."
        if let progress {
            button.title = "\(progress.completed)/\(progress.total)"
            let description = "MenuPocket, today, \(progress.completed) of \(progress.total) tasks completed"
            button.setAccessibilityLabel(description)
            button.toolTip = "\(description). Click to show tasks.\(glanceHint)"
        } else {
            button.title = "—"
            let description = "MenuPocket, today's tasks are unavailable. Open the task window to load or retry."
            button.setAccessibilityLabel(description)
            button.toolTip = description + glanceHint
        }
    }

    @objc private func openTasks() { handlePress(NSApplication.shared.currentEvent) }

    /// A right-click or Control-click shows the glance; anything else,
    /// including a press with no mouse event, is a primary click.
    func handlePress(_ event: NSEvent?) {
        if makeGlanceMenu != nil, Self.isGlanceRequest(event) {
            showGlance()
        } else if !isPresentingGlance {
            showTasks()
        }
    }

    static func isGlanceRequest(_ event: NSEvent?) -> Bool {
        switch event?.type {
        case .rightMouseDown, .rightMouseUp: true
        case .leftMouseDown, .leftMouseUp: event?.modifierFlags.contains(.control) == true
        default: false
        }
    }

    /// Attaches the menu only while it tracks, so a primary click never opens it.
    /// Returns whether the glance was presented.
    @discardableResult
    func showGlance() -> Bool {
        guard !isPresentingGlance, let statusItem, let button = statusItem.button,
              let menu = makeGlanceMenu?() else { return false }
        isPresentingGlance = true
        defer {
            self.statusItem?.menu = nil
            isPresentingGlance = false
        }
        statusItem.menu = menu
        presentGlanceMenu(button)
        return true
    }

    @objc private func showGlanceForAccessibility() -> Bool { showGlance() }

    func remove() {
        if let statusItem {
            statusItem.menu = nil
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }
}
