import AppKit
import SwiftUI

@MainActor
final class TaskWindowController: NSWindowController {
    static let initialContentSize = NSSize(width: 800, height: 560)
    static let minimumContentSize = NSSize(width: 600, height: 400)
    let state: DailyNotesState

    init(state: DailyNotesState, onSettings: @escaping () -> Void) {
        self.state = state
        let hostingController = NSHostingController(
            rootView: TaskWindowShell(state: state, onSettings: onSettings)
        )
        hostingController.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "MenuPocket Tasks"
        window.contentViewController = hostingController
        // Installing the hosting view can replace the frame with its fitting size.
        // Restore the intended size before centering and presenting the window.
        window.setContentSize(Self.initialContentSize)
        window.contentMinSize = Self.minimumContentSize
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func showTasks() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.contentMinSize = Self.minimumContentSize
    }
}

// TASK-003 replaces this lifecycle shell with the Today layout.
struct TaskWindowShell: View {
    let state: DailyNotesState
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Today").font(.largeTitle)
            Text("Your task window is ready.")
                .foregroundStyle(.secondary)
            Button("Settings…", action: onSettings)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
