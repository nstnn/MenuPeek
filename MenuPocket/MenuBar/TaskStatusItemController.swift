import AppKit
import Observation

@MainActor
final class TaskStatusItemController: NSObject {
    private(set) var statusItem: NSStatusItem?
    private let state: DailyNotesState
    private let showTasks: () -> Void

    init(state: DailyNotesState, showTasks: @escaping () -> Void) {
        self.state = state
        self.showTasks = showTasks
        super.init()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "MenuPocket")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(openTasks)
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
        if let progress {
            button.title = "\(progress.completed)/\(progress.total)"
            let description = "MenuPocket, today, \(progress.completed) of \(progress.total) tasks completed"
            button.setAccessibilityLabel(description)
            button.toolTip = "\(description). Click to show tasks."
        } else {
            button.title = "—"
            let description = "MenuPocket, today's tasks are unavailable. Open the task window to load or retry."
            button.setAccessibilityLabel(description)
            button.toolTip = description
        }
    }

    @objc private func openTasks() { showTasks() }

    func remove() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }
}
