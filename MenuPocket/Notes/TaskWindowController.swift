import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class TaskWindowPresentation {
    enum Route { case today, history, unfinished, unfinishedDay }
    enum HistoryEntry { case calendar, yesterday }

    private(set) var isShowingSettings = false
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

    /// History is a child of the Today list; Later never browses history.
    func canBrowse(state: DailyNotesState) -> Bool {
        !isTerminating && selectedDestination == .today && canNavigate(state: state)
    }

    /// Task-list commands act only on the visible Today/Later list.
    private var isShowingList: Bool { !isTerminating && route == .today && !isShowingSettings }

    @discardableResult
    func showHistory(state: DailyNotesState, entry: HistoryEntry = .calendar) -> Bool {
        guard canBrowse(state: state) else { return false }
        leaveAuxiliaryPane()
        cancelMovement()
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

    /// Opens the shared read-only detail at an indexed day with the Unfinished
    /// filter. The index keeps its loaded pages for Back to Unfinished.
    @discardableResult
    func showUnfinishedDay(_ day: GregorianDay, state: DailyNotesState) -> Bool {
        guard route == .unfinished, !isTerminating, let historyState,
              unfinishedState?.select(day) != nil else { return false }
        do { try historyState.select(day, filter: .unfinished) }
        catch { return false }
        route = .unfinishedDay
        refreshBrowser(state: state)
        return true
    }

    func backToUnfinished(state: DailyNotesState) {
        guard route == .unfinishedDay, !isTerminating else { return }
        route = .unfinished
        refreshBrowser(state: state)
    }

    @discardableResult
    func showToday(state: DailyNotesState) -> Bool {
        guard !isTerminating else { return false }
        if route != .today || isShowingSettings || isManagingCategories {
            guard canNavigate(state: state) else { return false }
            leaveAuxiliaryPane()
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
        if !visible { cancelCategoryMovement() }
        refreshBrowser(state: state)
    }

    func refreshBrowser(state: DailyNotesState) {
        guard !isTerminating else { return }
        // Hide before invalidation so only the pane being presented reads.
        historyState?.setVisible(month: false, day: false)
        unfinishedState?.setVisible(false)
        do {
            if route != .today && historyState == nil { historyState = try state.makeHistoryState() }
            if (route == .unfinished || route == .unfinishedDay) && unfinishedState == nil { unfinishedState = try state.makeUnfinishedState() }
            try historyState?.refresh(revision: state.historyRevision)
            try unfinishedState?.refresh(revision: state.historyRevision)
            browserIssue = nil
        } catch { browserIssue = "Could not open task history. Try again." }
        updateBrowserVisibility()
    }

    private func updateBrowserVisibility() {
        historyState?.setVisible(month: isWindowVisible && route == .history,
                                 day: isWindowVisible && (route == .history || route == .unfinishedDay))
        unfinishedState?.setVisible(isWindowVisible && route == .unfinished)
        reconcileUnfinishedSelection()
    }

    /// The selected day's full snapshot tells the index whether that day still
    /// holds unfinished work. Uses the current generation after any refresh.
    private func reconcileUnfinishedSelection() {
        guard route == .unfinishedDay, let unfinishedState, let day = unfinishedState.selectedDay,
              let snapshot = historyState?.daySnapshot, snapshot.summary.day == day else { return }
        unfinishedState.reconcileSelection(UnfinishedDaySelection(day: day, generation: unfinishedState.generation),
                                           snapshot: snapshot)
    }

    func stopForTermination() {
        isTerminating = true
        isWindowVisible = false
        cancelMovement()
        updateBrowserVisibility()
    }

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

    struct MovementReveal: Equatable {
        let id = UUID()
        let taskID: UUID
        let dayKey: String
        let group: TaskGroupID
    }

    let dragSession = TaskDragSession()
    private(set) var movementReveal: MovementReveal?
    let categoryDragSession = CategoryDragSession()
    private(set) var managerRenamingID: UUID?

    struct CategoryMovementReveal: Equatable {
        let id = UUID()
        let categoryID: UUID
        let context: CategoryReorderContext
        let catalog: [TaskCategory]
    }

    private(set) var categoryMovementReveal: CategoryMovementReveal?

    /// Both start and save use this path. The manager owns its idle sheet;
    /// list sources never act through that sheet or a hidden browser pane.
    func canReorderCategories(in context: CategoryReorderContext, state: DailyNotesState) -> Bool {
        guard !isTerminating, isWindowVisible, isShowingList,
              state.canReorderCategories(in: context), deletionTarget == nil,
              categoryRemovalTarget == nil, !dragSession.isDragging else { return false }
        switch context {
        case let .list(destination):
            return !isManagingCategories && selectedDestination == destination
        case .manager:
            return isManagingCategories && managerRenamingID == nil
        }
    }

    func setManagerRenaming(_ id: UUID?) {
        guard managerRenamingID != id else { return }
        managerRenamingID = id
        cancelCategoryMovement()
    }

    func requestCategoryMovementReveal(categoryID: UUID, context: CategoryReorderContext, catalog: [TaskCategory]) {
        categoryMovementReveal = CategoryMovementReveal(categoryID: categoryID, context: context, catalog: catalog)
    }

    func isCategoryMovementRevealValid(_ request: CategoryMovementReveal, state: DailyNotesState) -> Bool {
        categoryMovementReveal == request && state.categories == request.catalog &&
            request.catalog.contains { $0.id == request.categoryID } &&
            canReorderCategories(in: request.context, state: state)
    }

    func consumeCategoryMovementReveal(_ request: CategoryMovementReveal) {
        if categoryMovementReveal == request { categoryMovementReveal = nil }
    }

    func cancelCategoryMovement() {
        categoryDragSession.cancel()
        categoryMovementReveal = nil
    }

    func validateCategoryMovement(state: DailyNotesState) {
        categoryDragSession.validate(state: state)
        if let request = categoryMovementReveal, !isCategoryMovementRevealValid(request, state: state) {
            categoryMovementReveal = nil
        }
    }

    func requestMovementReveal(_ request: TaskMoveRequest) {
        movementReveal = MovementReveal(taskID: request.taskID, dayKey: request.expectedDayKey,
                                       group: request.destinationGroup)
    }

    func consumeMovementReveal(_ request: MovementReveal) {
        if movementReveal == request { movementReveal = nil }
    }

    func cancelMovement() {
        dragSession.cancel()
        movementReveal = nil
        cancelCategoryMovement()
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

    /// Sidebar destinations remain available from an idle category pane.
    /// Rename and removal confirmation must finish before leaving it.
    func canNavigate(state: DailyNotesState) -> Bool {
        !isTerminating && state.editingNoteID == nil && state.editingLaterTaskID == nil &&
            deletionTarget == nil && managerRenamingID == nil && categoryRemovalTarget == nil
    }

    private func leaveAuxiliaryPane() {
        if isManagingCategories { dismissCategoryManager() }
        isShowingSettings = false
    }

    @discardableResult
    func showSettings(state: DailyNotesState) -> Bool {
        guard canNavigate(state: state) else { return false }
        leaveAuxiliaryPane()
        cancelMovement()
        route = .today
        isShowingSettings = true
        updateBrowserVisibility()
        return true
    }

    @discardableResult
    func selectDestination(_ destination: TaskListDestination, state: DailyNotesState) -> Bool {
        if destination == selectedDestination && route == .today && !isShowingSettings && !isManagingCategories { return true }
        guard canNavigate(state: state) else { return false }
        // Selecting either list leaves History, which only lives under Today.
        guard showToday(state: state) else { return false }
        if destination != selectedDestination {
            cancelMovement()
            selectedDestination = destination
            newTaskRequest = nil
        }
        return true
    }

    /// Matches `selectDestination`: the current list is always selectable;
    /// switching waits for any edit, deletion, or category manager to finish.
    func canSelectDestination(_ destination: TaskListDestination, state: DailyNotesState) -> Bool {
        canNavigate(state: state)
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
        canAddTask(to: selectedDestination, state: state)
    }

    /// Whether selecting `destination` and then adding would succeed. The menu
    /// bar glance uses it for Today, whichever list is selected.
    func canAddTask(to destination: TaskListDestination, state: DailyNotesState) -> Bool {
        !isTerminating && isAvailable(destination, state: state) && !hasGuardedInteraction(state: state)
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

    /// Shared eligibility for drag start, drop, and row-menu movement. Only the
    /// visible Today list moves tasks; Later and History never do.
    func canMoveTask(state: DailyNotesState) -> Bool {
        isShowingList && selectedDestination == .today && state.canMoveTasks &&
            !hasGuardedInteraction(state: state) && !categoryDragSession.isDragging
    }

    /// Row-menu alternatives to dragging. They form the same identity-based
    /// requests as drops; nil requests are shown disabled.
    struct MenuMoves: Equatable {
        struct Destination: Equatable {
            let title: String
            let group: TaskGroupID
            let isCurrent: Bool
            let request: TaskMoveRequest?
        }

        let destinations: [Destination]
        let moveUp: TaskMoveRequest?
        let moveDown: TaskMoveRequest?
    }

    /// Move to appends to a group; Move Up/Down stay within the current group.
    func menuMoves(for id: UUID, state: DailyNotesState) -> MenuMoves? {
        guard let dayKey = state.todayKey,
              let note = state.notes.first(where: { $0.id == id && $0.dayKey == dayKey }) else { return nil }
        let source = TaskGroupID(categoryID: note.categoryID)
        let enabled = canMoveTask(state: state)
        func request(_ group: TaskGroupID, _ placement: TaskMovePlacement) -> TaskMoveRequest? {
            guard enabled else { return nil }
            return TaskMoveRequest(taskID: id, expectedDayKey: dayKey, expectedSourceGroup: source,
                                   destinationGroup: group, placement: placement)
        }
        let groups = TaskCategoryOption.ordered(categories: state.categories)
        let siblings = state.notes.filter { TaskGroupID(categoryID: $0.categoryID) == source }
        guard let index = siblings.firstIndex(where: { $0.id == id }) else { return nil }
        return MenuMoves(
            destinations: groups.map { group in
                let isCurrent = group.id == source
                return MenuMoves.Destination(title: group.name, group: group.id, isCurrent: isCurrent,
                                             request: isCurrent ? nil : request(group.id, .endOfGroup))
            },
            moveUp: index > 0 ? request(source, .before(siblings[index - 1].id)) : nil,
            moveDown: index + 1 < siblings.count ? request(source, .after(siblings[index + 1].id)) : nil)
    }

    @discardableResult
    func requestNewTask(state: DailyNotesState) -> Bool {
        guard canAddTask(state: state), showToday(state: state),
              showComposer(in: selectedDestination, state: state) else { return false }
        cancelMovement()
        newTaskRequest = NewTaskRequest(id: UUID(), destination: selectedDestination)
        return true
    }

    /// Selects `destination`, then opens its composer like `requestNewTask`.
    /// Does nothing while a guarded interaction would block the switch.
    @discardableResult
    func requestNewTask(in destination: TaskListDestination, state: DailyNotesState) -> Bool {
        guard canAddTask(to: destination, state: state),
              selectDestination(destination, state: state) else { return false }
        return requestNewTask(state: state)
    }

    func consumeNewTaskRequest(in destination: TaskListDestination) {
        if newTaskRequest?.destination == destination { newTaskRequest = nil }
    }

    @discardableResult
    func requestDeletion(id: UUID, state: DailyNotesState) -> Bool {
        guard isShowingList, !hasGuardedInteraction(state: state) else { return false }
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
        guard isShowingList, !hasGuardedInteraction(state: state) else { return false }
        state.refreshIfDayChanged()
        guard target.destination == selectedDestination, isValid(target, state: state) else { return false }
        cancelMovement()
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
        cancelMovement()
        cancelDeletion()
        dismissCategoryManager()
        newTaskRequest = nil
    }

    /// The manager can open over a pending new-task draft, which it leaves
    /// alone, but not over an edit or a deletion confirmation.
    func canManageCategories(state: DailyNotesState) -> Bool {
        canNavigate(state: state) && state.availableCategories != nil
    }

    @discardableResult
    func showCategoryManager(state: DailyNotesState) -> Bool {
        guard !isManagingCategories else { return true }
        guard canManageCategories(state: state) else { return false }
        // A reopened manager starts without the last session's messages.
        state.clearCategoryIssues()
        isShowingSettings = false
        route = .today
        updateBrowserVisibility()
        cancelMovement()
        isManagingCategories = true
        return true
    }

    func dismissCategoryManager() {
        cancelCategoryMovement()
        managerRenamingID = nil
        cancelCategoryRemoval()
        isManagingCategories = false
    }

    /// Reads the all-days count the confirmation must state. A failed count
    /// leaves no confirmation and reports its own command error.
    @discardableResult
    func requestCategoryRemoval(id: UUID, state: DailyNotesState) -> Bool {
        guard isManagingCategories,
              managerRenamingID == nil,
              let category = state.availableCategories?.first(where: { $0.id == id }),
              let count = state.categoryUsageCount(id: id) else { return false }
        cancelCategoryMovement()
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
    static let initialContentSize = NSSize(width: 1000, height: 700)
    static let minimumContentSize = NSSize(width: 800, height: 560)
    let state: DailyNotesState
    let presentation: TaskWindowPresentation
    let zoom: TaskWindowZoom
    private var isTerminating = false

    /// The content size before a zoom grew the window, and the size it grew to.
    /// Zooming back out returns to `original`; a manual resize drops it.
    private struct ZoomRestore {
        var original: NSSize
        var grown: NSSize
    }
    private var zoomRestore: ZoomRestore?

    init(state: DailyNotesState, model: AppModel? = nil, zoom: TaskWindowZoom = TaskWindowZoom(),
         onSettings: @escaping () -> Void) {
        self.state = state
        let presentation = state.taskWindowPresentation
        self.presentation = presentation
        self.zoom = zoom
        let hostingController = NSHostingController(
            rootView: TaskWindowZoomContainer(zoom: zoom) {
                TaskBrowserView(state: state, presentation: presentation, onSettings: onSettings, model: model)
            }
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
        // A saved zoom raises the content floor, so the window may start larger.
        let minimum = Self.scaled(Self.minimumContentSize, by: zoom.scale)
        window.setContentSize(NSSize(width: max(Self.initialContentSize.width, minimum.width),
                                     height: max(Self.initialContentSize.height, minimum.height)))
        window.contentMinSize = minimum
        let startSize = window.contentRect(forFrameRect: window.frame).size
        if !Self.sameSize(startSize, Self.initialContentSize) {
            zoomRestore = ZoomRestore(original: Self.initialContentSize, grown: startSize)
        }
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
        // Native routes leave History for the retained Today/Later list, and
        // still bring the window forward if an active interaction blocks that.
        presentation.showToday(state: state)
        presentation.setWindowVisible(true, state: state)
        presentation.validateDeletion(state: state)
        presentation.validateCategoryRemoval(state: state)
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.contentMinSize = minimumContentSize
    }

    // MARK: Zoom

    /// The content floor at the current zoom: the layout keeps at least the
    /// Actual Size minimum in logical points.
    var minimumContentSize: NSSize { Self.scaled(Self.minimumContentSize, by: zoom.scale) }

    var canZoomIn: Bool { zoom.nextLarger.map(fitsOnScreen) ?? false }
    var canZoomOut: Bool { zoom.nextSmaller != nil }
    var canResetZoom: Bool { !zoom.isActualSize && fitsOnScreen(TaskWindowZoom.actualSize) }

    func zoomIn() {
        guard !isTerminating, zoom.zoomIn(fits: fitsOnScreen) else { return }
        applyZoomToWindow()
    }

    func zoomOut() {
        guard !isTerminating, zoom.zoomOut() else { return }
        applyZoomToWindow()
    }

    func resetZoom() {
        guard !isTerminating, canResetZoom, zoom.resetToActualSize() else { return }
        applyZoomToWindow()
    }

    static func scaled(_ size: NSSize, by scale: Double) -> NSSize {
        // Whole points, ignoring floating-point noise: 800 × 1.1 is 880, not 881.
        NSSize(width: (size.width * scale - 0.001).rounded(.up),
               height: (size.height * scale - 0.001).rounded(.up))
    }

    /// A level fits when the window's frame at that level's minimum content
    /// size fits the visible area of the window's screen.
    private func fitsOnScreen(_ scale: Double) -> Bool {
        guard let window, let screen = window.screen ?? NSScreen.main else { return true }
        let frame = window.frameRect(forContentRect: NSRect(
            origin: .zero, size: Self.scaled(Self.minimumContentSize, by: scale)
        ))
        return frame.width <= screen.visibleFrame.width && frame.height <= screen.visibleFrame.height
    }

    /// Raises the window's minimum to the new zoom and grows the window,
    /// keeping its top-left corner, when it is now smaller than that. Zooming
    /// back out returns the window to the size it had before it grew, unless
    /// the window was resized by hand in between.
    private func applyZoomToWindow() {
        guard let window else { return }
        let minimum = minimumContentSize
        window.contentMinSize = minimum
        let current = window.contentRect(forFrameRect: window.frame).size
        if let restore = zoomRestore, !Self.sameSize(current, restore.grown) {
            zoomRestore = nil
        }
        let original = zoomRestore?.original ?? current
        let target = NSSize(width: max(original.width, minimum.width),
                            height: max(original.height, minimum.height))
        if !Self.sameSize(current, target) {
            setContentSizeKeepingTopLeft(target, of: window)
        }
        let reached = window.contentRect(forFrameRect: window.frame).size
        zoomRestore = Self.sameSize(reached, original) ? nil : ZoomRestore(original: original, grown: reached)
    }

    private func setContentSizeKeepingTopLeft(_ size: NSSize, of window: NSWindow) {
        let content = window.contentRect(forFrameRect: window.frame)
        var frame = window.frameRect(forContentRect: NSRect(origin: content.origin, size: size))
        frame.origin.y = window.frame.maxY - frame.height
        if let screen = window.screen {
            let visible = screen.visibleFrame
            frame.origin.x = min(frame.origin.x, visible.maxX - frame.width)
            frame.origin.x = max(frame.origin.x, visible.minX)
            frame.origin.y = max(frame.origin.y, visible.minY)
        }
        window.setFrame(frame, display: true, animate: false)
    }

    private static func sameSize(_ a: NSSize, _ b: NSSize) -> Bool {
        abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    /// Bring the retained window forward even when active work prevents Today
    /// selection. Native routes use this in TASK-009, rather than forcing a tab.
    @discardableResult
    func showToday() -> Bool {
        guard !isTerminating, window != nil else { return false }
        showTasks()
        return presentation.selectDestination(.today, state: state)
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

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // Hosting layout can revise contentMinSize after presentation. Enforce
        // the usable content floor for native corner/edge resizing as well.
        let minimumFrame = sender.frameRect(forContentRect: NSRect(
            origin: .zero, size: minimumContentSize
        )).size
        return NSSize(width: max(frameSize.width, minimumFrame.width),
                      height: max(frameSize.height, minimumFrame.height))
    }

    func windowWillClose(_ notification: Notification) {
        presentation.setWindowVisible(false, state: state)
        presentation.windowWillClose()
    }
}
