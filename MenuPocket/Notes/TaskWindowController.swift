import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class TaskWindowPresentation {
    struct DeletionTarget {
        let id: UUID
        let dayKey: String
    }

    private(set) var deletionTarget: DeletionTarget?
    private(set) var newTaskRequestID: UUID?

    func canAddTask(state: DailyNotesState) -> Bool {
        state.availableProgress != nil && state.editingNoteID == nil && deletionTarget == nil
    }

    @discardableResult
    func requestNewTask(state: DailyNotesState) -> Bool {
        guard canAddTask(state: state) else { return false }
        newTaskRequestID = UUID()
        return true
    }

    func consumeNewTaskRequest() { newTaskRequestID = nil }

    func requestDeletion(id: UUID, state: DailyNotesState) {
        state.refreshIfDayChanged()
        guard state.availableProgress != nil,
              let note = state.notes.first(where: { $0.id == id }),
              note.dayKey == state.todayKey else { return }
        deletionTarget = DeletionTarget(id: id, dayKey: note.dayKey)
    }

    func cancelDeletion() { deletionTarget = nil }

    func validateDeletion(state: DailyNotesState) {
        guard let target = deletionTarget else { return }
        if state.availableProgress == nil || state.todayKey != target.dayKey ||
            !state.notes.contains(where: { $0.id == target.id && $0.dayKey == target.dayKey }) {
            cancelDeletion()
        }
    }

    @discardableResult
    func confirmDeletion(state: DailyNotesState) -> Bool {
        guard let target = deletionTarget else { return false }
        // Consume confirmation before a write changes the observable rows.
        cancelDeletion()
        state.refreshIfDayChanged()
        guard state.availableProgress != nil, state.todayKey == target.dayKey,
              state.notes.contains(where: { $0.id == target.id && $0.dayKey == target.dayKey }) else {
            return false
        }
        return state.delete(id: target.id)
    }
}

@MainActor
final class TaskWindowController: NSWindowController, NSWindowDelegate {
    static let initialContentSize = NSSize(width: 800, height: 560)
    static let minimumContentSize = NSSize(width: 600, height: 400)
    let state: DailyNotesState
    let presentation: TaskWindowPresentation

    init(state: DailyNotesState, onSettings: @escaping () -> Void) {
        self.state = state
        let presentation = TaskWindowPresentation()
        self.presentation = presentation
        let hostingController = NSHostingController(
            rootView: TaskWindowView(state: state, presentation: presentation, onSettings: onSettings)
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
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func showTasks() {
        guard let window else { return }
        state.windowWillOpen()
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.contentMinSize = Self.minimumContentSize
    }

    func windowWillClose(_ notification: Notification) {
        presentation.cancelDeletion()
    }
}
