import AppKit

// TASK-006 adds saved-progress presentation to this app-lifetime action route.
@MainActor
final class TaskStatusItemController: NSObject {
    private(set) var statusItem: NSStatusItem?
    private let showTasks: () -> Void

    init(showTasks: @escaping () -> Void) {
        self.showTasks = showTasks
        super.init()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "MenuPocket")
            button.toolTip = "MenuPocket — Show Tasks"
            button.setAccessibilityLabel("MenuPocket, Show Tasks")
            button.target = self
            button.action = #selector(openTasks)
        }
    }

    @objc private func openTasks() { showTasks() }

    func remove() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }
}
