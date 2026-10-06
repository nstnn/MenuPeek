import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class TaskWindowPresentation {
    enum Route { case today, history, unfinished }
    enum HistoryEntry { case calendar, yesterday }

    private(set) var route: Route = .today
    private(set) var historyEntry: HistoryEntry = .calendar
    private(set) var historyState: TaskHistoryState?
    private(set) var unfinishedState: UnfinishedTasksState?
    private(set) var browserIssue: String?
    /// The top visible group is a fallback if retained scroll content disappears.
    var todayScrollAnchor: TaskGroupID?
    private(set) var todayScrollRestoreID: UUID?
    @ObservationIgnored private var isWindowVisible = false
    @ObservationIgnored private var isTerminating = false

    func canBrowse(state: DailyNotesState) -> Bool {
        !isTerminating && state.editingNoteID == nil && deletionTarget == nil && !isManagingCategories
    }

    @discardableResult
    func showHistory(state: DailyNotesState, entry: HistoryEntry = .calendar) -> Bool {
        guard canBrowse(state: state) else { return false }
        historyEntry = entry
        route = .history
        refreshBrowser(state: state)
        if entry == .yesterday, let historyState {
            do { try historyState.select(state.yesterdayForHistory(), filter: .unfinished) }
            catch { browserIssue = "Could not open yesterday. Try again." }
        }
        return true
    }

    @discardableResult
    func showUnfinished(state: DailyNotesState) -> Bool {
        guard route == .history, canBrowse(state: state) else { return false }
        route = .unfinished
        refreshBrowser(state: state)
        return true
    }

    func backToHistory(state: DailyNotesState) {
        guard route == .unfinished, !isTerminating else { return }
        route = .history
        refreshBrowser(state: state)
    }

    @discardableResult
    func showToday(state: DailyNotesState) -> Bool {
        guard !isTerminating else { return false }
        if route != .today {
            guard canBrowse(state: state) else { return false }
            // Keep the exact native offset when content survives. If the saved
            // anchor vanished, explicitly restore the first surviving group.
            if let anchor = todayScrollAnchor, !state.groups.contains(where: { $0.id == anchor }) {
                todayScrollAnchor = state.groups.first?.id
                todayScrollRestoreID = UUID()
            }
            route = .today
        }
        updateBrowserVisibility()
        return true
    }

    func setWindowVisible(_ visible: Bool, state: DailyNotesState) {
        guard !isTerminating else { return }
        isWindowVisible = visible
        refreshBrowser(state: state)
    }

    func refreshBrowser(state: DailyNotesState) {
        guard !isTerminating else { return }
        // Hide before invalidation so only the pane being presented reads.
        historyState?.setVisible(month: false, day: false)
        unfinishedState?.setVisible(false)
        do {
            if route != .today && historyState == nil { historyState = try state.makeHistoryState() }
            if route == .unfinished && unfinishedState == nil { unfinishedState = try state.makeUnfinishedState() }
            try historyState?.refresh(revision: state.historyRevision)
            try unfinishedState?.refresh(revision: state.historyRevision)
            browserIssue = nil
        } catch { browserIssue = "Could not open task history. Try again." }
        updateBrowserVisibility()
    }

    private func updateBrowserVisibility() {
        historyState?.setVisible(month: isWindowVisible && route == .history,
                                 day: isWindowVisible && route == .history)
        unfinishedState?.setVisible(isWindowVisible && route == .unfinished)
    }

    func stopForTermination() {
        isTerminating = true
        isWindowVisible = false
        updateBrowserVisibility()
    }

    struct DeletionTarget {
        let id: UUID
        let dayKey: String
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

    private(set) var deletionTarget: DeletionTarget?
    private(set) var newTaskRequestID: UUID?
    private(set) var isManagingCategories = false
    private(set) var categoryRemovalTarget: CategoryRemovalTarget?

    /// Also false while the category manager is open, so no task command acts behind it.
    func canAddTask(state: DailyNotesState) -> Bool {
        !isTerminating && state.availableProgress != nil && state.editingNoteID == nil && deletionTarget == nil &&
            !isManagingCategories
    }

    @discardableResult
    func requestNewTask(state: DailyNotesState) -> Bool {
        guard canAddTask(state: state), showToday(state: state) else { return false }
        newTaskRequestID = UUID()
        return true
    }

    func consumeNewTaskRequest() { newTaskRequestID = nil }

    func requestDeletion(id: UUID, state: DailyNotesState) {
        guard route == .today, !isManagingCategories, !isTerminating else { return }
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

    /// The manager can open over a pending new-task draft, which it leaves
    /// alone, but not over an edit or a deletion confirmation.
    func canManageCategories(state: DailyNotesState) -> Bool {
        !isTerminating && route == .today && state.availableCategories != nil && state.editingNoteID == nil && deletionTarget == nil
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
    private var isTerminating = false

    init(state: DailyNotesState, onSettings: @escaping () -> Void) {
        self.state = state
        let presentation = TaskWindowPresentation()
        self.presentation = presentation
        let hostingController = NSHostingController(
            rootView: TaskBrowserView(state: state, presentation: presentation, onSettings: onSettings)
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
        refreshBrowserAndObserve()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func showTasks() {
        guard !isTerminating, let window else { return }
        state.windowWillOpen()
        guard presentation.showToday(state: state) else { return }
        presentation.setWindowVisible(true, state: state)
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.contentMinSize = Self.minimumContentSize
    }

    private func refreshBrowserAndObserve() {
        guard !isTerminating else { return }
        _ = withObservationTracking {
            state.historyRevision
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.refreshBrowserAndObserve() }
        }
        presentation.refreshBrowser(state: state)
    }

    func stopForTermination() {
        isTerminating = true
        presentation.stopForTermination()
    }

    func windowWillClose(_ notification: Notification) {
        presentation.setWindowVisible(false, state: state)
        presentation.cancelDeletion()
        presentation.dismissCategoryManager()
    }
}
