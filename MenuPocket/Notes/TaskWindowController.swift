import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class TaskWindowPresentation {
    struct NewTaskRequest: Equatable {
        let id: UUID
        let destination: TaskListDestination
    }

    enum FocusTarget: Equatable {
        case draft(TaskListDestination)
        case row(TaskActionTarget)
        case group(TaskListDestination, TaskGroupID)
        case add(TaskListDestination)
        case retry(TaskListDestination)
    }

    /// A category awaiting confirmed removal, with the all-days task count the
    /// confirmation states.
    struct CategoryRemovalTarget: Equatable {
        let id: UUID
        let name: String
        let usageCount: Int
        /// The count changed after the user last saw it, so the confirmation
        /// shows the new count and must be confirmed again.
        let countChanged: Bool
    }

    enum CategoryRemovalOutcome: Equatable {
        case removed
        case countChanged
        /// Nothing was removed: no target, a missing category, unavailable data,
        /// or a failed count or write. The state reports any command error.
        case notRemoved
    }

    private(set) var selectedDestination: TaskListDestination = .today
    private(set) var deletionTarget: TaskActionTarget?
    private(set) var newTaskRequest: NewTaskRequest?
    var newTaskRequestID: UUID? { newTaskRequest?.id }
    private(set) var isTodayComposerVisible = false
    private(set) var isLaterComposerVisible = false
    private(set) var isManagingCategories = false
    private(set) var categoryRemovalTarget: CategoryRemovalTarget?

    private func hasGuardedInteraction(state: DailyNotesState) -> Bool {
        state.editingNoteID != nil || state.editingLaterTaskID != nil ||
            deletionTarget != nil || isManagingCategories
    }

    @discardableResult
    func selectDestination(_ destination: TaskListDestination, state: DailyNotesState) -> Bool {
        if destination == selectedDestination { return true }
        guard !hasGuardedInteraction(state: state) else { return false }
        selectedDestination = destination
        newTaskRequest = nil
        return true
    }

    /// Matches `selectDestination`: the current list is always selectable;
    /// switching waits for any edit, deletion, or category manager to finish.
    func canSelectDestination(_ destination: TaskListDestination, state: DailyNotesState) -> Bool {
        destination == selectedDestination || !hasGuardedInteraction(state: state)
    }

    func isComposerVisible(in destination: TaskListDestination) -> Bool {
        switch destination {
        case .today: isTodayComposerVisible
        case .later: isLaterComposerVisible
        }
    }

    func hasNewTaskComposer(in destination: TaskListDestination, state: DailyNotesState) -> Bool {
        isComposerVisible(in: destination) || !(destination == .today ? state.draft : state.laterDraft).isEmpty
    }

    private func isAvailable(_ destination: TaskListDestination, state: DailyNotesState) -> Bool {
        switch destination {
        case .today: state.availableProgress != nil
        case .later: state.availableLaterTasks != nil
        }
    }

    /// Also false while the category manager is open, so no task command acts behind it.
    func canAddTask(state: DailyNotesState) -> Bool {
        isAvailable(selectedDestination, state: state) && !hasGuardedInteraction(state: state)
    }

    @discardableResult
    func showComposer(in destination: TaskListDestination, state: DailyNotesState) -> Bool {
        guard destination == selectedDestination, canAddTask(state: state) else { return false }
        // Only a genuinely new draft takes the remembered category. An empty but
        // already-open composer still has its own pending category choice.
        if !hasNewTaskComposer(in: destination, state: state) {
            switch destination {
            case .today: state.startNewDraft()
            case .later: state.startNewLaterDraft()
            }
        }
        switch destination {
        case .today: isTodayComposerVisible = true
        case .later: isLaterComposerVisible = true
        }
        return true
    }

    func hideComposer(in destination: TaskListDestination) {
        switch destination {
        case .today: isTodayComposerVisible = false
        case .later: isLaterComposerVisible = false
        }
        consumeNewTaskRequest(in: destination)
    }

    @discardableResult
    func requestNewTask(state: DailyNotesState) -> Bool {
        guard showComposer(in: selectedDestination, state: state) else { return false }
        newTaskRequest = NewTaskRequest(id: UUID(), destination: selectedDestination)
        return true
    }

    func consumeNewTaskRequest(in destination: TaskListDestination) {
        if newTaskRequest?.destination == destination { newTaskRequest = nil }
    }

    @discardableResult
    func requestDeletion(id: UUID, state: DailyNotesState) -> Bool {
        guard !hasGuardedInteraction(state: state) else { return false }
        state.refreshIfDayChanged()
        switch selectedDestination {
        case .today:
            guard let note = state.notes.first(where: { $0.id == id }) else { return false }
            return requestDeletion(.daily(id: id, dayKey: note.dayKey), state: state)
        case .later:
            return requestDeletion(.later(id: id), state: state)
        }
    }

    @discardableResult
    func requestDeletion(_ target: TaskActionTarget, state: DailyNotesState) -> Bool {
        guard !hasGuardedInteraction(state: state) else { return false }
        state.refreshIfDayChanged()
        guard target.destination == selectedDestination, isValid(target, state: state) else { return false }
        deletionTarget = target
        return true
    }

    private func isValid(_ target: TaskActionTarget, state: DailyNotesState) -> Bool {
        switch target {
        case .daily(let id, let dayKey):
            state.availableProgress != nil && state.todayKey == dayKey &&
                state.notes.contains { $0.id == id && $0.dayKey == dayKey }
        case .later(let id):
            state.availableLaterTasks?.contains { $0.id == id } == true
        }
    }

    func cancelDeletion() { deletionTarget = nil }

    func validateDeletion(state: DailyNotesState) {
        guard let target = deletionTarget else { return }
        if !isValid(target, state: state) {
            cancelDeletion()
        }
    }

    @discardableResult
    func confirmDeletion(state: DailyNotesState) -> Bool {
        guard let target = deletionTarget else { return false }
        // Consume confirmation before a write changes the observable rows.
        cancelDeletion()
        state.refreshIfDayChanged()
        guard isValid(target, state: state) else { return false }
        switch target {
        case .daily(let id, _): return state.delete(id: id)
        case .later(let id): return state.deleteLater(id: id)
        }
    }

    func focusAfterSelection(state: DailyNotesState) -> FocusTarget {
        let destination = selectedDestination
        guard isAvailable(destination, state: state) else { return .retry(destination) }
        return hasNewTaskComposer(in: destination, state: state) ? .draft(destination) : .add(destination)
    }

    /// The row, its surviving/collapsed group, Add, or Retry. Never resolve an
    /// action against the other list, even if both lists contain the same UUID.
    func focusAfterLeavingRow(_ target: TaskActionTarget, fallbackGroup: TaskGroupID?,
                              state: DailyNotesState) -> FocusTarget {
        let destination = target.destination
        guard isAvailable(destination, state: state) else { return .retry(destination) }
        let groupID: TaskGroupID?
        let groupIDs: [TaskGroupID]
        switch target {
        case .daily(let id, let dayKey):
            groupID = state.groups.first { $0.notes.contains { $0.id == id && $0.dayKey == dayKey } }?.id
            groupIDs = state.groups.map(\.id)
        case .later(let id):
            groupID = state.laterGroups.first { $0.tasks.contains { $0.id == id } }?.id
            groupIDs = state.laterGroups.map(\.id)
        }
        if let groupID {
            return state.categoryPreferences.isCollapsed(groupID, in: destination) ?
                .group(destination, groupID) : .row(target)
        }
        if let fallbackGroup, groupIDs.contains(fallbackGroup) { return .group(destination, fallbackGroup) }
        return .add(destination)
    }

    func windowWillClose() {
        cancelDeletion()
        dismissCategoryManager()
        newTaskRequest = nil
    }

    /// The manager can open over a pending new-task draft, which it leaves
    /// alone, but not over an edit or a deletion confirmation.
    func canManageCategories(state: DailyNotesState) -> Bool {
        state.availableCategories != nil && state.editingNoteID == nil &&
            state.editingLaterTaskID == nil && deletionTarget == nil
    }

    @discardableResult
    func showCategoryManager(state: DailyNotesState) -> Bool {
        guard !isManagingCategories else { return true }
        guard canManageCategories(state: state) else { return false }
        // A reopened manager starts without the last session's messages.
        state.clearCategoryIssues()
        isManagingCategories = true
        return true
    }

    func dismissCategoryManager() {
        cancelCategoryRemoval()
        isManagingCategories = false
    }

    /// Reads the all-days count the confirmation must state. A failed count
    /// leaves no confirmation and reports its own command error.
    @discardableResult
    func requestCategoryRemoval(id: UUID, state: DailyNotesState) -> Bool {
        guard isManagingCategories,
              let category = state.availableCategories?.first(where: { $0.id == id }),
              let count = state.categoryUsageCount(id: id) else { return false }
        categoryRemovalTarget = CategoryRemovalTarget(id: id, name: category.name,
                                                      usageCount: count, countChanged: false)
        return true
    }

    func cancelCategoryRemoval() { categoryRemovalTarget = nil }

    /// Cancels a confirmation whose category left the catalog or whose data
    /// became unavailable.
    func validateCategoryRemoval(state: DailyNotesState) {
        guard let target = categoryRemovalTarget else { return }
        if state.availableCategories?.contains(where: { $0.id == target.id }) != true {
            cancelCategoryRemoval()
        }
    }

    /// Consumes the confirmation before writing, then rechecks the target and
    /// its count. A changed count asks again with the new count; a failed
    /// removal needs a fresh confirmation.
    @discardableResult
    func confirmCategoryRemoval(state: DailyNotesState) -> CategoryRemovalOutcome {
        guard let target = categoryRemovalTarget else { return .notRemoved }
        cancelCategoryRemoval()
        guard isManagingCategories,
              let category = state.availableCategories?.first(where: { $0.id == target.id }),
              let count = state.categoryUsageCount(id: target.id) else { return .notRemoved }
        guard count == target.usageCount else {
            categoryRemovalTarget = CategoryRemovalTarget(id: target.id, name: category.name,
                                                          usageCount: count, countChanged: true)
            return .countChanged
        }
        return state.removeCategory(id: target.id) ? .removed : .notRemoved
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
        hostingController.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "MenuPocket Tasks"
        window.toolbarStyle = .unified
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
        presentation.validateDeletion(state: state)
        presentation.validateCategoryRemoval(state: state)
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.contentMinSize = Self.minimumContentSize
    }

    /// Bring the retained window forward even when active work prevents Today
    /// selection. Native routes use this in TASK-009, rather than forcing a tab.
    @discardableResult
    func showToday() -> Bool {
        guard window != nil else { return false }
        showTasks()
        return presentation.selectDestination(.today, state: state)
    }

    func windowWillClose(_ notification: Notification) {
        presentation.windowWillClose()
    }
}
