import AppKit
import SwiftUI

/// Desktop checklist backed by the app-owned saved snapshot and draft.
struct TaskWindowView: View {
    private struct Row: Identifiable {
        let id: UUID
        let text: String
        let isCompleted: Bool
        let categoryID: UUID?
        var continuedOn: String? = nil
    }

    private struct Group: Identifiable {
        let id: TaskGroupID
        let name: String
        let notes: [Row]
        var progress: NoteProgress {
            NoteProgress(completed: notes.count { $0.isCompleted }, total: notes.count)
        }
    }

    private var destination: TaskListDestination { presentation.selectedDestination }
    private var isLater: Bool { destination == .later }
    private var isAvailable: Bool { isLater ? state.availableLaterTasks != nil : state.availableProgress != nil }
    private var editingID: UUID? { isLater ? state.editingLaterTaskID : state.editingNoteID }
    private var issue: DailyNotesIssue? { isLater ? state.laterIssue : state.issue }
    private var rows: [Row] {
        if isLater {
            return state.laterTasks.map { Row(id: $0.id, text: $0.text, isCompleted: $0.isCompleted, categoryID: $0.categoryID) }
        }
        return state.notes.map { Row(id: $0.id, text: $0.text, isCompleted: $0.isCompleted, categoryID: $0.categoryID, continuedOn: $0.continuedOn) }
    }
    private var groups: [Group] {
        if isLater {
            return state.laterGroups.map { group in
                Group(id: group.id, name: group.name, notes: group.tasks.map {
                    Row(id: $0.id, text: $0.text, isCompleted: $0.isCompleted, categoryID: $0.categoryID)
                })
            }
        }
        return movementGroups.map { group in
            Group(id: group.id, name: group.name, notes: group.notes.map {
                Row(id: $0.id, text: $0.text, isCompleted: $0.isCompleted, categoryID: $0.categoryID, continuedOn: $0.continuedOn)
            })
        }
    }
    private var draftBinding: Binding<String> {
        if isLater { return editingID == nil ? $state.laterDraft : $state.laterEditDraft }
        return editingID == nil ? $state.draft : $state.editDraft
    }
    private func categoryBinding(editing: Bool) -> Binding<UUID?> {
        if isLater { return editing ? $state.laterEditCategoryID : $state.laterDraftCategoryID }
        return editing ? $state.editCategoryID : $state.draftCategoryID
    }
    private func identifier(_ today: String, _ later: String) -> String { isLater ? later : today }
    private func actionTarget(_ id: UUID) -> TaskActionTarget {
        isLater ? .later(id: id) : .daily(id: id, dayKey: state.todayKey ?? "")
    }

    private enum FocusControl: Hashable {
        case add, manageCategories, retry, save, draft, category, cancelDelete, confirmDelete, history, yesterday
        case edit(UUID)
        case group(TaskGroupID)
        case completion(UUID)
        case actions(UUID)
    }

    /// Row controls and checkboxes align with the group name after its chevron.
    private static let groupRowIndent: CGFloat = 22
    private static let contentWidth: CGFloat = 660

    @Bindable var state: DailyNotesState
    let presentation: TaskWindowPresentation
    let onSettings: () -> Void
    @State private var rowActionOrigin: (id: UUID, groupID: TaskGroupID)?
    @State private var focusRequestID = UUID()
    @State private var editFocusRequestID: UUID?
    /// A menu-moved row whose actions regain focus once its reveal finishes.
    @State private var menuMoveFocusID: UUID?
    @State private var moveNoticeID = UUID()
    @State private var isMoveNoticeVisible = false
    @FocusState private var focusedControl: FocusControl?
    @State private var keyboardFocus = KeyboardFocusVisibility.shared
    @Environment(\.colorScheme) private var colorScheme

    /// Add and inline Edit mount different native fields. Separate focus values
    /// ensure replacing one field also requests focus for the other.
    private var textFocusControl: FocusControl {
        editingID.map(FocusControl.edit) ?? .draft
    }

    // Split so older Swift type checkers can check each piece in reasonable time.
    var body: some View {
        observingMovement(taskWindow)
    }

    private var taskWindow: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 740 || geometry.size.height < 480
            HStack(spacing: 0) {
                daybookSidebar(compact: compact)
                    .frame(width: compact ? 164 : 218)
                Rectangle().fill(daybookRule).frame(width: 1).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .frame(maxWidth: Self.contentWidth, alignment: .leading)
                        .padding(.horizontal, 28)
                        .padding(.top, compact ? 20 : 30)
                        .padding(.bottom, compact ? 16 : 24)
                        .frame(maxWidth: .infinity)
                        .background { focusClearingBackground }
                    if hasTopInteractionContent {
                        VStack(alignment: .leading, spacing: 10) {
                            if hasComposer { composer }
                            if hasMoveNotice {
                                Text("Moved task to Today.")
                                    .font(.callout)
                                    .accessibilityIdentifier("laterMoveNotice")
                            }
                            if let message = topWriteError { taskWriteError(message) }
                            if let message = state.categoryReorderIssue?.message {
                                Text(message)
                                    .foregroundStyle(.red)
                                    .accessibilityIdentifier("categoryReorderError")
                            }
                        }
                        .frame(maxWidth: Self.contentWidth, alignment: .leading)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity)
                    }
                    taskList(geometry: geometry, horizontalPadding: 28)
                    if hasFooterContent {
                        Divider()
                        footer
                            .frame(maxWidth: Self.contentWidth, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background { focusClearingBackground }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { canvasBackground }
        .tint(daybookAccent)
        // Attached to this window, so it blocks the rows and actions behind it.
        .sheet(isPresented: Binding(
            get: { presentation.isManagingCategories },
            set: { if !$0 { presentation.dismissCategoryManager() } }
        )) {
            TaskCategoryManagerView(state: state, presentation: presentation)
        }
        .onChange(of: presentation.route) { old, new in
            focusRequestID = UUID()
            if new != .today { focusedControl = nil }
            else if old != .today {
                let requestID = focusRequestID
                Task { @MainActor in
                    await Task.yield()
                    guard presentation.route == .today, focusRequestID == requestID else { return }
                    if isLater { focusSelectedList(); return }
                    focusedControl = state.availableProgress == nil ? .retry
                        : (presentation.historyEntry == .yesterday && state.yesterdayIncompleteCount > 0 ? .yesterday : .history)
                }
            }
        }
        .onChange(of: presentation.isManagingCategories) { wasManaging, isManaging in
            if wasManaging, !isManaging { focusManageCategories() }
        }
        .onChange(of: presentation.newTaskRequestID, initial: true) { _, request in
            if request != nil, presentation.newTaskRequest?.destination == destination {
                showComposer()
                presentation.consumeNewTaskRequest(in: destination)
            }
        }
        .onChange(of: destination) { _, _ in
            // Supersede every delayed focus/scroll request from the previous list.
            focusRequestID = UUID()
            editFocusRequestID = nil
            rowActionOrigin = nil
            focusedControl = nil
            // Leaving History for another list focuses after the route settles.
            if presentation.route == .today { focusSelectedList() }
        }
        .task(id: moveNoticeID) {
            guard isMoveNoticeVisible else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            isMoveNoticeVisible = false
        }
        .onChange(of: state.todayKey) { _, _ in presentation.validateDeletion(state: state) }
        .onChange(of: state.notes) { old, new in
            presentation.validateDeletion(state: state)
            if !isLater, let id = focusedNoteID, !new.contains(where: { $0.id == id }),
               let note = old.first(where: { $0.id == id }) {
                restoreRowFocus(id, fallbackGroup: TaskGroupID(categoryID: note.categoryID))
            }
        }
        .onChange(of: state.hasLoadedToday) { _, _ in presentation.validateDeletion(state: state) }
        .onChange(of: state.laterTasks) { old, new in
            presentation.validateDeletion(state: state)
            if isLater, let id = focusedNoteID, !new.contains(where: { $0.id == id }),
               let task = old.first(where: { $0.id == id }) {
                restoreRowFocus(id, fallbackGroup: TaskGroupID(categoryID: task.categoryID))
            }
        }
        .onChange(of: state.hasLoadedLater) { _, _ in presentation.validateDeletion(state: state) }
        .onChange(of: presentation.deletionTarget) { old, new in
            if let old, new == nil, old.destination == destination { restoreRowFocus(old.id) }
        }
    }

    private func taskList(geometry: GeometryProxy, horizontalPadding: CGFloat) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    recoveryNotice
                    if isAvailable {
                        if rows.isEmpty {
                            emptyState
                        } else {
                            // Tall groups must keep stable geometry while scrolling/revealing.
                            // Lazy group layout can spin SwiftUI's update graph on macOS.
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(groups) { group in
                                    groupSurface(group)
                                        .padding(.bottom, 24)
                                        .overlay {
                                            CategoryDropTarget(state: state, session: presentation.categoryDragSession,
                                                               context: .list(destination), group: group.id,
                                                               firstCustomID: groups.compactMap { group -> UUID? in
                                                                   if case let .category(id) = group.id { return id }
                                                                   return nil
                                                               }.first,
                                                               bottomInset: 24)
                                                .accessibilityHidden(true)
                                        }
                                        .id(group.id)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        if !isLater, state.yesterdayIncompleteCount > 0 {
                            Button {
                                openHistory(.yesterday)
                            } label: {
                                Text("\(state.yesterdayIncompleteCount) unfinished \(state.yesterdayIncompleteCount == 1 ? "task" : "tasks") from yesterday")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.red)
                            }
                            .focusable()
                            .keyboardFocusAppearance()
                            .focused($focusedControl, equals: .yesterday)
                            .onKeyPress(keys: [.space, .return]) { _ in
                                openHistory(.yesterday)
                                return .handled
                            }
                            .disabled(!presentation.canBrowse(state: state))
                            .help("View yesterday's unfinished tasks")
                            .accessibilityIdentifier("yesterdayHistoryEntry")
                        }
                    } else {
                        unavailableState
                    }
                }
                .frame(maxWidth: Self.contentWidth, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, horizontalPadding)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollPosition(id: Binding(
                // The retained anchor belongs to Today's groups only.
                get: { isLater ? nil : presentation.todayScrollAnchor },
                set: { if presentation.route == .today, !isLater { presentation.todayScrollAnchor = $0 } }
            ))
            .accessibilityIdentifier(identifier("todayTaskList", "laterTaskList"))
            .id(destination)
            .disabled(presentation.deletionTarget != nil || presentation.isManagingCategories)
            .contentShape(Rectangle())
            .gesture(TapGesture().onEnded { clearFocus() }, including: .gesture)
            .onChange(of: presentation.categoryMovementReveal) { _, request in
                guard let request, request.context == .list(destination) else { return }
                Task { @MainActor in
                    defer { presentation.consumeCategoryMovementReveal(request) }
                    await Task.yield()
                    guard presentation.isCategoryMovementRevealValid(request, state: state) else { return }
                    // The header has its own small target, even for very tall groups.
                    scroll.scrollTo("categoryHeader-\(request.categoryID)")
                }
            }
            .onChange(of: presentation.movementReveal) { _, request in
                guard let request else { return }
                let ownership = focusRequestID
                Task { @MainActor in
                    defer {
                        presentation.consumeMovementReveal(request)
                        if menuMoveFocusID == request.taskID {
                            menuMoveFocusID = nil
                            if focusRequestID == ownership {
                                focusedControl = focusAfterLeavingRow(request.taskID,
                                                                      fallbackGroup: request.group)
                            }
                        }
                    }
                    await Task.yield()
                    guard canReveal(request, ownership: ownership) else { return }
                    // Minimal scrolling: a .top/.center target past the end
                    // of a re-created last group can leave the lazy list
                    // blank until the user scrolls.
                    scroll.scrollTo(request.group)
                    await Task.yield()
                    guard canReveal(request, ownership: ownership) else { return }
                    scroll.scrollTo(request.taskID)
                    // Pointer movement does not create a keyboard ring. A
                    // preexisting focused control keeps its row identity.
                }
            }
            .onChange(of: presentation.todayScrollRestoreID) { _, _ in
                if !isLater, let anchor = presentation.todayScrollAnchor { scroll.scrollTo(anchor, anchor: .top) }
            }
            .onChange(of: geometry.size) { _, _ in
                guard let id = editingID else { return }
                let requestID = focusRequestID
                let owner = destination
                Task { @MainActor in
                    await Task.yield()
                    guard focusRequestID == requestID, destination == owner, editingID == id else { return }
                    scroll.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: editingID, initial: true) { old, new in
                // Keep the editor or its saved destination visible when
                // the Add composer changes the list's available height.
                if let id = new ?? old {
                    if new != nil {
                        focusRequestID = UUID()
                        editFocusRequestID = focusRequestID
                    }
                    let requestID = editFocusRequestID ?? focusRequestID
                    Task { @MainActor in
                        await Task.yield()
                        guard presentation.route == .today, focusRequestID == requestID else { return }
                        if let group = groups.first(where: { $0.notes.contains { $0.id == id } }) {
                            // Entry/exit changes the space above the list.
                            // Mount the group before targeting its row.
                            scroll.scrollTo(group.id, anchor: .top)
                            await Task.yield()
                        }
                        guard presentation.route == .today, focusRequestID == requestID else { return }
                        scroll.scrollTo(id, anchor: .center)
                        if new != nil { focusDraft(requestID: requestID) }
                        else { restoreRowFocus(id, requestID: requestID) }
                    }
                }
            }
        }
    }

    /// Clears drag sessions and pending reveals when their context changes.
    private func observingMovement(_ content: some View) -> some View {
        content
            .onChange(of: presentation.dragSession.active) { _, payload in
                if payload != nil {
                    focusRequestID = UUID()
                    if let request = presentation.movementReveal { presentation.consumeMovementReveal(request) }
                }
            }
            .onDisappear { interruptMovement() }
            .onChange(of: presentation.canMoveTask(state: state)) { _, eligible in
                if !eligible {
                    // Category ownership disables task movement without cancelling itself.
                    presentation.dragSession.cancel()
                    if let request = presentation.movementReveal { presentation.consumeMovementReveal(request) }
                    presentation.validateCategoryMovement(state: state)
                }
            }
            .onChange(of: state.todayKey) { _, _ in interruptMovement() }
            .onChange(of: state.notes) { _, notes in
                if let payload = presentation.dragSession.active,
                   !notes.contains(where: {
                       $0.id == payload.taskID && $0.dayKey == payload.dayKey &&
                       TaskGroupID(categoryID: $0.categoryID) == payload.sourceGroup
                   }) {
                    presentation.cancelMovement()
                }
            }
            .onChange(of: groups.map(\.id)) { _, ids in
                if !isLater, case let .group(id) = focusedControl, !ids.contains(id) {
                    focusedControl = state.availableProgress == nil ? .retry : .add
                }
            }
            .onChange(of: state.categories) { _, _ in
                if presentation.dragSession.active != nil { interruptMovement() }
                if let request = presentation.movementReveal,
                   !state.groups.contains(where: { $0.id == request.group }) {
                    interruptMovement()
                }
            }
            .onChange(of: focusedControl) { old, new in
                // Hierarchy removal can clear focus or invoke the fallback above;
                // neither is a newer user navigation action.
                guard new != nil else { return }
                if case let .group(id) = old, !groups.contains(where: { $0.id == id }) { return }
                if let request = presentation.movementReveal { presentation.consumeMovementReveal(request) }
            }
    }

    private func canReveal(_ request: TaskWindowPresentation.MovementReveal, ownership: UUID) -> Bool {
        presentation.movementReveal == request && focusRequestID == ownership &&
            presentation.canMoveTask(state: state) && state.todayKey == request.dayKey &&
            !state.categoryPreferences.isCollapsed(request.group) &&
            state.notes.contains { $0.id == request.taskID && TaskGroupID(categoryID: $0.categoryID) == request.group }
    }

    private func interruptMovement() {
        let hadMovement = presentation.dragSession.active != nil || presentation.movementReveal != nil
        presentation.cancelMovement()
        // Supersede only delayed movement work; switching to Later or History
        // keeps that route's own focus request.
        if hadMovement { focusRequestID = UUID() }
        if !isLater, state.availableProgress == nil, focusedControl != nil { focusedControl = .retry }
    }

    private var writeError: String? {
        switch issue {
        case .add: "Could not save task. Try again."
        case .complete: "Could not update task. Try again."
        case .edit: "Could not save edit. Try again."
        case .delete: "Could not delete task. Try again."
        case .move: "Could not move task. Try again."
        case .moveToToday: "Could not move task to Today. Try again."
        default: nil
        }
    }

    // Presentation only: every control still uses the existing guarded command.
    private func daybookSidebar(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 18 : 28) {
            Label("MENUPOCKET", systemImage: "book.closed")
                .font(.system(size: 11, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(dayLabels.weekday.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Text(daybookDate.day)
                    .font(.custom("Georgia", size: compact ? 52 : 76, relativeTo: .largeTitle))
                    .tracking(-3)
                Text(daybookDate.month)
                    .font(.custom("Georgia", size: compact ? 16 : 20, relativeTo: .title3))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(dayLabels.weekday), \(dayLabels.date)")
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("daybookDate")
            destinationControl
            daybookProgress
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                historyButton
                categoryManagerButton
                Button(action: onSettings) {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .disabled(presentation.deletionTarget != nil)
                .help("Open Settings (⌘,)")
                .accessibilityLabel("Open Settings")
            }
            .font(.system(size: 12))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, compact ? 16 : 24)
        .padding(.top, compact ? 20 : 30)
        .padding(.bottom, 24)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(daybookRail)
    }

    private var destinationControl: some View {
        Picker("Task list", selection: Binding(
            get: { destination },
            set: { _ = presentation.selectDestination($0, state: state) }
        )) {
            Text("Today").tag(TaskListDestination.today).accessibilityIdentifier("todayTab")
            Text("Later").tag(TaskListDestination.later).accessibilityIdentifier("laterTab")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(state.editingNoteID != nil || state.editingLaterTaskID != nil ||
                  presentation.deletionTarget != nil || presentation.isManagingCategories)
        .accessibilityLabel("Task list")
        .accessibilityValue(isLater ? "Later" : "Today")
        .accessibilityIdentifier("taskDestination")
    }

    private var daybookProgress: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(daybookRule).frame(height: 1).accessibilityHidden(true)
            if let progress = state.availableProgress {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(daybookRule, lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: CGFloat(progress.completed) / CGFloat(max(progress.total, 1)))
                            .stroke(daybookAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                    Text("Today: \(progress.completed)/\(progress.total) complete")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Today's task progress")
                        .accessibilityValue("\(progress.completed) of \(progress.total) complete")
                        .accessibilityIdentifier("todayProgress")
                }
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Task progress unavailable")
                    .accessibilityIdentifier("todayProgress")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(isLater ? "FOR ANOTHER DAY" : "YOUR DAILY PAGE")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Text(isLater ? "Later" : "Make room for today.")
                    .font(.custom("Georgia", size: 32, relativeTo: .largeTitle))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if isLater {
                    Text(state.availableLaterRemainingCount.map { "\($0) \($0 == 1 ? "task" : "tasks") remaining" } ?? "Tasks unavailable")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("laterRemainingCount")
                }
            }
            if !hasComposer {
                Button(action: showComposer) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Add task")
                        Spacer(minLength: 4)
                        Text("⌘N").font(.caption).accessibilityHidden(true)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable()
                .keyboardFocusAppearance()
                .focused($focusedControl, equals: .add)
                .onKeyPress(keys: [.space, .return]) { _ in
                    showComposer()
                    return .handled
                }
                .overlay { focusOutline(focusedControl == .add) }
                .disabled(!presentation.canAddTask(state: state))
                .help("Add task (⌘N)")
                .accessibilityIdentifier("addTask")
                Rectangle().fill(daybookRule).frame(height: 1).accessibilityHidden(true)
            }
        }
    }

    private var canOpenHistory: Bool {
        isLater ? presentation.canSelectDestination(.today, state: state) : presentation.canBrowse(state: state)
    }

    private var historyButton: some View {
        Button { openHistory(.calendar) } label: {
            Label("History", systemImage: "calendar")
        }
        .focusable()
        .keyboardFocusAppearance()
        .focused($focusedControl, equals: .history)
        .onKeyPress(keys: [.space, .return]) { _ in
            openHistory(.calendar)
            return .handled
        }
        .disabled(!canOpenHistory)
        .help("View task history")
        .accessibilityLabel("View task history")
        .accessibilityIdentifier("taskHistoryEntry")
    }

    private var categoryManagerButton: some View {
        Button(action: showCategoryManager) {
            Label("Categories", systemImage: "folder")
        }
        .focusable()
        .keyboardFocusAppearance()
        .focused($focusedControl, equals: .manageCategories)
        .onKeyPress(keys: [.space, .return]) { _ in
            showCategoryManager()
            return .handled
        }
        .overlay { focusOutline(focusedControl == .manageCategories) }
        .disabled(!presentation.canManageCategories(state: state))
        .help("Manage categories")
        .accessibilityLabel("Manage categories")
        .accessibilityIdentifier("manageCategories")
    }

    private var daybookDate: (day: String, month: String) {
        // These are components of the saved civil date, never a new time-zone conversion.
        let parts = (state.todayKey ?? NoteDay().keys().today).split(separator: "-")
        let month = dayLabels.date.split(separator: " ").first.map(String.init) ?? ""
        return (parts.last.map(String.init) ?? "", "\(month), \(parts.first.map(String.init) ?? "")")
    }

    private var hasComposer: Bool {
        presentation.deletionTarget == nil && editingID == nil &&
            presentation.hasNewTaskComposer(in: destination, state: state)
    }

    private var topWriteError: String? {
        editingID != nil && issue == .edit ? nil : writeError
    }

    private var hasMoveNotice: Bool { isLater && isMoveNoticeVisible && issue != .moveToToday }

    private var hasTopInteractionContent: Bool {
        presentation.deletionTarget == nil && (hasComposer || hasMoveNotice || topWriteError != nil || state.categoryReorderIssue != nil)
    }

    private var hasFooterContent: Bool {
        presentation.deletionTarget != nil
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let target = presentation.deletionTarget,
               target.destination == destination,
               let note = rows.first(where: { $0.id == target.id }) {
                deletionConfirmation(note)
            }
            if let message = writeError {
                taskWriteError(message)
            }
        }
    }

    private func taskWriteError(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.red)
            .accessibilityIdentifier(identifier("taskWriteError", "laterTaskWriteError"))
    }

    private var dayLabels: (date: String, weekday: String) {
        let key = state.todayKey ?? NoteDay().keys().today
        // A saved day key is a calendar date, not an instant to shift into the
        // current time zone. Format its components without changing that date.
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: key) else { return (key, "") }
        formatter.locale = Locale(identifier: "en")
        formatter.dateFormat = "MMMM d, yyyy"
        let dateLabel = formatter.string(from: date)
        formatter.dateFormat = "EEEE"
        return (dateLabel, formatter.string(from: date))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No tasks yet")
                .font(.title3.weight(.semibold))
            Text(isLater ? "Tasks saved for later will appear here." : "Today's tasks will appear here.")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
        .accessibilityIdentifier(identifier("todayEmptyState", "laterEmptyState"))
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tasks are unavailable")
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier(identifier("todayUnavailableState", "laterUnavailableState"))
            Text(isLater ? "Could not load Later tasks. Try again." : "Could not load today's tasks. Try again.")
                .foregroundStyle(.secondary)
            Button("Retry") { state.refresh() }
                .focusable()
                .keyboardFocusAppearance()
                .focused($focusedControl, equals: .retry)
                .onKeyPress(keys: [.space, .return]) { _ in
                    state.refresh()
                    return .handled
                }
                .overlay { focusOutline(focusedControl == .retry) }
                .accessibilityIdentifier(identifier("retryTodayTasks", "retryLaterTasks"))
        }
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private var recoveryNotice: some View {
        if let notice = isLater ? state.laterRefreshNotice : state.refreshNotice,
           notice != "Moved task to Today." {
            VStack(alignment: .leading, spacing: 8) {
                Text(notice)
                    .font(.callout)
                if let recovered = isLater ? state.laterRecoveredEdit : state.recoveredEdit {
                    Text("Unsaved edit")
                        .font(.callout.weight(.semibold))
                    Text(recovered.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    // The name captured at cancellation, so a removed category still shows.
                    if let name = recovered.categoryID == nil ? TaskCategoryName.general : recovered.categoryName {
                        Text("Category: \(name)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier(identifier("todayRecoveryNotice", "laterRecoveryNotice"))
        }
    }

    private var hasValidDrag: Bool {
        guard let payload = presentation.dragSession.active else { return false }
        return presentation.canMoveTask(state: state) && state.todayKey == payload.dayKey &&
            state.notes.contains { $0.id == payload.taskID && TaskGroupID(categoryID: $0.categoryID) == payload.sourceGroup }
    }

    private var movementGroups: [TaskGroup] {
        TaskGroup.groups(categories: state.categories, notes: state.notes, includeEmpty: hasValidDrag)
    }

    @ViewBuilder
    private func dropTarget(_ group: TaskGroupID, anchor: UUID? = nil) -> some View {
        if !isLater {
            TaskDropTarget(state: state, session: presentation.dragSession, group: group, anchor: anchor)
                .accessibilityHidden(true)
        }
    }

    /// The count covers every task in the group, including rows hidden by collapse.
    private func groupSurface(_ group: Group) -> some View {
        let collapsed = state.categoryPreferences.isCollapsed(group.id, in: destination)
        return VStack(alignment: .leading, spacing: 0) {
            groupHeader(group, collapsed: collapsed)
                .id("categoryHeader-\(group.id.storageKey)")
                .overlay { dropTarget(group.id) }
            // Remove collapsed rows from keyboard and accessibility traversal.
            if !collapsed {
                ForEach(group.notes) { note in
                    taskRow(note)
                        .overlay { dropTarget(group.id, anchor: note.id) }
                }
                .padding(.leading, Self.groupRowIndent)
                if hasValidDrag {
                    Text(group.notes.isEmpty ? "Drop task here" : "Move to end of group")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .padding(.leading, Self.groupRowIndent)
                        .overlay { dropTarget(group.id) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { categorySource(group).frame(height: 12) }
        .overlay(alignment: .bottom) { categorySource(group).frame(height: 12) }
        .overlay(alignment: .leading) { categorySource(group).frame(width: 16) }
        .overlay(alignment: .trailing) { categorySource(group).frame(width: 16) }
    }

    @ViewBuilder
    private func categorySource(_ group: Group, click: (() -> Void)? = nil) -> some View {
        if case let .category(id) = group.id {
            CategoryDragSource(name: group.name, categoryID: id, context: .list(destination),
                               state: state, session: presentation.categoryDragSession,
                               enabled: presentation.canReorderCategories(in: .list(destination), state: state),
                               count: { group.notes.count }, click: click)
                .accessibilityHidden(true)
        }
    }

    private func groupHeader(_ group: Group, collapsed: Bool) -> some View {
        let progress = group.progress
        let containsEdit = group.notes.contains { $0.id == editingID }
        return Button {
            toggleGroup(group)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.groupRowIndent - 8)
                Text(group.name)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(isLater ? "\(progress.total - progress.completed) remaining" : "\(progress.completed)/\(progress.total)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay { categorySource(group, click: { toggleGroup(group) }) }
        .focusable()
        .keyboardFocusAppearance()
        .focused($focusedControl, equals: .group(group.id))
        .onKeyPress(keys: [.space, .return]) { _ in
            toggleGroup(group)
            return .handled
        }
        .overlay { focusOutline(focusedControl == .group(group.id)) }
        .disabled(containsEdit)
        .help(containsEdit ? "Finish editing before hiding this group" : (collapsed ? "Show tasks" : "Hide tasks"))
        .accessibilityLabel(isLater ? "\(group.name), \(progress.total - progress.completed) remaining" : "\(group.name), \(progress.completed) of \(progress.total) complete")
        .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
        .accessibilityHint(collapsed ? "Shows this group's tasks" : "Hides this group's tasks")
        .accessibilityIdentifier("\(isLater ? "laterTaskGroup" : "taskGroup")-\(group.id.storageKey)")
    }

    private func toggleGroup(_ group: Group) {
        interruptMovement()
        let collapse = !state.categoryPreferences.isCollapsed(group.id, in: destination)
        state.categoryPreferences.setCollapsed(collapse, for: group.id, in: destination)
        // Its rows leave the view, so keep keyboard focus on the header.
        if collapse, let id = focusedNoteID, group.notes.contains(where: { $0.id == id }) {
            focusedControl = .group(group.id)
        }
    }

    private var focusedNoteID: UUID? {
        switch focusedControl {
        case let .completion(id), let .actions(id): id
        default: nil
        }
    }

    @ViewBuilder
    private func taskRow(_ note: Row) -> some View {
        if editingID == note.id {
            VStack(alignment: .leading, spacing: 8) {
                composer
                if issue == .edit, let message = writeError {
                    taskWriteError(message)
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(.primary)
            .padding(.vertical, 10)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("\(isLater ? "laterTaskRow" : "taskRow")-\(note.id)")
            .id(note.id)
        } else {
            savedTaskRow(note)
                .id(note.id)
        }
    }

    private func savedTaskRow(_ note: Row) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if !isLater {
                TaskDragHandle(taskID: note.id, text: note.text, state: state, session: presentation.dragSession,
                               enabled: presentation.canMoveTask(state: state) && !presentation.dragSession.isDragging)
                    .frame(width: 16, height: 20)
            }
            Toggle(isOn: Binding(
                get: { rows.first(where: { $0.id == note.id })?.isCompleted ?? note.isCompleted },
                set: { setCompleted(id: note.id, completed: $0) }
            )) { Text(note.text) }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .focusable()
                .keyboardFocusAppearance()
                .focused($focusedControl, equals: .completion(note.id))
                .onKeyPress(keys: [.space, .return]) { _ in
                    if let saved = rows.first(where: { $0.id == note.id }) {
                        setCompleted(id: note.id, completed: !saved.isCompleted)
                    }
                    return .handled
                }
                .overlay { focusOutline(focusedControl == .completion(note.id)) }
                .accessibilityLabel(note.text)
                .accessibilityIdentifier("\(isLater ? "laterTaskCompletion" : "taskCompletion")-\(note.id)")
            Text(note.text)
                .strikethrough(note.isCompleted, color: .secondary.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            TaskActionsMenu(onOpen: { focusedControl = .actions(note.id) },
                            onEdit: { beginEditing(note.id) }, onDelete: { requestDeletion(note.id) },
                            onMoveToToday: isLater && !note.isCompleted ? { moveToToday(note.id) } : nil,
                            moves: { isLater ? nil : presentation.menuMoves(for: note.id, state: state) },
                            onMove: moveFromMenu)
            .focused($focusedControl, equals: .actions(note.id))
            .overlay { focusOutline(focusedControl == .actions(note.id)) }
            .disabled(editingID != nil)
            .help("Task actions")
            .accessibilityLabel("Actions for task: \(note.text)")
            .accessibilityHint(isLater ? (note.isCompleted ? "Opens Edit and Delete actions"
                                                           : "Opens Move to Today, Edit and Delete actions")
                                       : "Opens Edit, Move, and Delete actions")
            .accessibilityIdentifier("\(isLater ? "laterTaskActions" : "taskActions")-\(note.id)")
        }
        .font(.system(size: 14))
        .disabled(note.continuedOn != nil)
        .help(note.continuedOn.map { "Continued on \($0)" } ?? "")
        .foregroundStyle(note.isCompleted ? .secondary : .primary)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { daybookRule.frame(height: 1).allowsHitTesting(false) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(isLater ? "laterTaskRow" : "taskRow")-\(note.id)")
    }

    /// The field takes its own row, so the category and actions stay usable at
    /// the minimum window width.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(editingID == nil ? "Write a task" : "Edit task",
                      text: draftBinding)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(editingID == nil ? "New task" : "Edit task")
                .accessibilityIdentifier(isLater ? (editingID == nil ? "newLaterTaskDraft" : "editLaterTaskDraft") : (editingID == nil ? "newTaskDraft" : "editTaskDraft"))
                .focused($focusedControl, equals: textFocusControl)
                .onSubmit(saveDraft)
                .onExitCommand(perform: cancelDraft)
            HStack(spacing: 12) {
                categoryPicker(editing: editingID != nil)
                Spacer(minLength: 0)
                Button("Save", action: saveDraft)
                    .focusable()
                    .keyboardFocusAppearance()
                    .focused($focusedControl, equals: .save)
                    .onKeyPress(keys: [.space, .return]) { _ in
                        saveDraft()
                        return .handled
                    }
                    .disabled(draftBinding.wrappedValue
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isAvailable)
                    .accessibilityIdentifier(identifier("saveTask", "saveLaterTask"))
                Button("Cancel", action: cancelDraft)
                    .keyboardFocusAppearance()
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(editingID == nil ? "cancelNewTask" : "cancelTaskEdit")
            }
        }
    }

    /// Binds the visible draft's selection in state; nil is General, listed
    /// first as in Today. With keyboard focus, Up and Down step the selection.
    /// Return does nothing here, so choosing a category never saves the draft.
    private func categoryPicker(editing: Bool) -> some View {
        Picker("Category", selection: categoryBinding(editing: editing)) {
            ForEach(TaskCategoryOption.ordered(categories: state.categories)) { option in
                Text(option.name).tag(option.categoryID)
            }
        }
        .focusable()
        .keyboardFocusAppearance()
        .focused($focusedControl, equals: .category)
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            stepCategory(by: press.key == .downArrow ? 1 : -1, editing: editing)
            return .handled
        }
        .overlay { focusOutline(focusedControl == .category) }
        // A long name truncates in the control instead of crowding Save and Cancel.
        .frame(maxWidth: 280, alignment: .leading)
        .disabled(state.availableCategories == nil)
        .help(editing ? "Category for this task" : "Category for the new task")
        .accessibilityIdentifier(isLater ? (editing ? "editLaterTaskCategory" : "newLaterTaskCategory") : (editing ? "editTaskCategory" : "newTaskCategory"))
    }

    private func stepCategory(by offset: Int, editing: Bool) {
        let options = TaskCategoryOption.ordered(categories: state.categories).map(\.categoryID)
        let current = categoryBinding(editing: editing).wrappedValue
        guard state.availableCategories != nil, let index = options.firstIndex(of: current) else { return }
        let next = options[min(max(index + offset, 0), options.count - 1)]
        categoryBinding(editing: editing).wrappedValue = next
    }

    private func deletionConfirmation(_ note: Row) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Delete task?").font(.headline)
            Text(note.text)
                .lineLimit(2)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") {
                    presentation.cancelDeletion()
                }
                .keyboardShortcut(.cancelAction)
                .focusable()
                .keyboardFocusAppearance()
                .focused($focusedControl, equals: .cancelDelete)
                .onKeyPress(keys: [.space, .return]) { _ in
                    presentation.cancelDeletion()
                    return .handled
                }
                .overlay { focusOutline(focusedControl == .cancelDelete) }
                .accessibilityIdentifier("cancelTaskDeletion")
                Button("Delete", role: .destructive) {
                    confirmDeletion()
                }
                .focusable()
                .keyboardFocusAppearance()
                .focused($focusedControl, equals: .confirmDelete)
                .onKeyPress(keys: [.space, .return]) { _ in
                    confirmDeletion()
                    return .handled
                }
                .overlay { focusOutline(focusedControl == .confirmDelete) }
                .accessibilityIdentifier("confirmTaskDeletion")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("taskDeletionConfirmation")
        .task {
            await Task.yield()
            focusedControl = .cancelDelete
        }
    }

    private func setCompleted(id: UUID, completed: Bool) {
        if isLater { _ = state.setLaterCompleted(id: id, completed: completed) }
        else { state.setCompleted(id: id, completed: completed) }
    }

    private func moveToToday(_ id: UUID) {
        guard isLater, canUseRowActions,
              let group = groups.first(where: { $0.notes.contains { $0.id == id } }) else { return }
        rowActionOrigin = (id, group.id)
        if state.moveLaterToToday(id: id) {
            isMoveNoticeVisible = true
            moveNoticeID = UUID()
            restoreRowFocus(id, fallbackGroup: group.id)
        }
    }

    private func beginEditing(_ id: UUID) {
        guard canUseRowActions, let group = groups.first(where: { $0.notes.contains { $0.id == id } }) else { return }
        rowActionOrigin = (id, group.id)
        if isLater { state.beginEditingLater(id: id) } else { state.beginEditing(id: id) }
    }

    private var canUseRowActions: Bool {
        isAvailable && editingID == nil &&
            presentation.deletionTarget == nil && !presentation.isManagingCategories
    }

    private func requestDeletion(_ id: UUID) {
        guard canUseRowActions, let group = groups.first(where: { $0.notes.contains { $0.id == id } }) else { return }
        rowActionOrigin = (id, group.id)
        presentation.requestDeletion(actionTarget(id), state: state)
    }

    /// Runs after native menu tracking ends. Uses the same saved command as drops;
    /// only a committed move reveals the row before its actions regain focus.
    private func moveFromMenu(_ request: TaskMoveRequest) {
        guard canUseRowActions else { return }
        rowActionOrigin = (request.taskID, request.expectedSourceGroup)
        focusRequestID = UUID()
        menuMoveFocusID = request.taskID
        guard case .changed = state.moveTask(request) else {
            menuMoveFocusID = nil
            restoreRowFocus(request.taskID)
            return
        }
    }

    private func confirmDeletion() {
        _ = presentation.confirmDeletion(state: state)
    }

    private func restoreRowFocus(_ id: UUID, fallbackGroup: TaskGroupID? = nil,
                                 requestID: UUID? = nil) {
        let originGroup = fallbackGroup ?? (rowActionOrigin?.id == id ? rowActionOrigin?.groupID : nil)
        let requestID = requestID ?? focusRequestID
        Task { @MainActor in
            await Task.yield()
            guard presentation.route == .today, focusRequestID == requestID else { return }
            focusedControl = focusAfterLeavingRow(id, fallbackGroup: originGroup)
        }
    }

    /// Return to the row menu or collapsed group; if the task disappeared,
    /// prefer its surviving group, then Add. Unavailable data always uses Retry.
    private func focusAfterLeavingRow(_ id: UUID, fallbackGroup: TaskGroupID?) -> FocusControl {
        let target = actionTarget(id)
        switch presentation.focusAfterLeavingRow(target, fallbackGroup: fallbackGroup, state: state) {
        case .row: return .actions(id)
        case .group(_, let groupID): return .group(groupID)
        case .retry: return .retry
        default: return .add
        }
    }

    private func focusDraft(requestID: UUID? = nil) {
        // Explicit Add requests supersede an edit's delayed scroll/focus work,
        // including an edit-exit observer that has not run yet.
        let requestID = requestID ?? UUID()
        focusRequestID = requestID
        presentation.cancelMovement()
        Task { @MainActor in
            await Task.yield()
            guard presentation.route == .today, focusRequestID == requestID else { return }
            focusedControl = textFocusControl
        }
    }

    private func focusSelectedList() {
        switch presentation.focusAfterSelection(state: state) {
        case .draft: focusDraft()
        case .retry: focusedControl = .retry
        default: focusedControl = .add
        }
    }

    private func openHistory(_ entry: TaskWindowPresentation.HistoryEntry) {
        // History always belongs to Today; the shared rail offers it from either list.
        guard presentation.selectDestination(.today, state: state),
              presentation.showHistory(state: state, entry: entry) else { return }
        focusRequestID = UUID()
        focusedControl = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func showComposer() {
        guard presentation.showComposer(in: destination, state: state) else { return }
        focusDraft()
    }

    /// A pending new-task draft stays in state and its composer stays visible.
    private func showCategoryManager() {
        presentation.showCategoryManager(state: state)
    }

    /// After the sheet closes: its entry button, or Retry if data became unavailable.
    private func focusManageCategories() {
        Task { @MainActor in
            await Task.yield()
            focusedControl = state.availableCategories == nil ? .retry : .manageCategories
        }
    }

    private func saveDraft() {
        if editingID != nil {
            if isLater { _ = state.saveLaterEdit() } else { _ = state.saveEdit() }
        } else if isLater ? state.addLaterDraft() : state.addDraft() {
            presentation.hideComposer(in: destination)
            focusedControl = .add
        }
    }

    private func cancelDraft() {
        if editingID != nil {
            if isLater { state.cancelEditingLater() } else { state.cancelEditing() }
            return
        }
        if isLater { state.cancelLaterDraft() } else { state.cancelDraft() }
        presentation.hideComposer(in: destination)
        focusedControl = .add
    }

    private func clearFocus() {
        interruptMovement()
        focusedControl = nil
        // Clear AppKit's first responder as well as SwiftUI's focus state.
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private var focusClearingBackground: some View {
        Button(action: clearFocus) {
            canvasBackground
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityHidden(true)
    }

    private var canvasBackground: some View {
        colorScheme == .dark
            ? Color(red: 0.145, green: 0.137, blue: 0.122)
            : Color(red: 0.980, green: 0.969, blue: 0.941)
    }

    private var daybookRail: Color {
        colorScheme == .dark
            ? Color(red: 0.188, green: 0.173, blue: 0.145)
            : Color(red: 0.941, green: 0.922, blue: 0.878)
    }

    private var daybookAccent: Color {
        colorScheme == .dark
            ? Color(red: 0.894, green: 0.667, blue: 0.514)
            : Color(red: 0.608, green: 0.310, blue: 0.196)
    }

    private var daybookRule: Color { Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.12) }

    private func focusOutline(_ focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.accentColor, lineWidth: focused && keyboardFocus.isVisible ? 2 : 0)
            .padding(-3)
            .allowsHitTesting(false)
    }
}

/// A focusable SwiftUI trigger with one native menu for mouse and keyboard.
/// A separate focus wrapper around SwiftUI's Menu does not reliably open it
/// with Space/Return; use the same button key handling as other row controls.
private struct TaskActionsMenu: View {
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    var onMoveToToday: (() -> Void)? = nil
    /// Read when the menu opens, so entries reflect the current saved order.
    /// Nil omits the Today movement items.
    var moves: () -> TaskWindowPresentation.MenuMoves? = { nil }
    var onMove: (TaskMoveRequest) -> Void = { _ in }
    @State private var anchor = TaskMenuAnchor.Reference()
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: showMenu) {
            Image(systemName: "ellipsis")
                .frame(width: 28, height: 28)
                .foregroundStyle(isHovered && isEnabled ? Color.primary : Color.secondary)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isHovered && isEnabled ? 0.06 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .focusable()
        .keyboardFocusAppearance()
        .onKeyPress(keys: [.space, .return], phases: [.down, .repeat, .up]) { press in
            // Let the initiating key finish before native menu tracking starts;
            // subsequent Return/Space belong to the menu, not its trigger.
            if anchor.isTrackingMenu { return .ignored }
            if press.phase == .down {
                anchor.opensOnKeyUp = true
            } else if press.phase == .up {
                guard anchor.opensOnKeyUp else { return .ignored }
                anchor.opensOnKeyUp = false
                showMenu()
            }
            return .handled
        }
        .background {
            TaskMenuAnchor(reference: anchor)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func showMenu() {
        guard !anchor.isTrackingMenu, let view = anchor.view, view.window != nil else { return }
        onOpen()
        anchor.isTrackingMenu = true
        defer { anchor.isTrackingMenu = false }
        let actions = Actions()
        let menu = NSMenu()
        menu.autoenablesItems = false
        if onMoveToToday != nil {
            let move = menu.addItem(withTitle: "Move to Today", action: #selector(Actions.moveToToday), keyEquivalent: "")
            move.target = actions
            menu.addItem(.separator())
        }
        let edit = menu.addItem(withTitle: "Edit", action: #selector(Actions.edit), keyEquivalent: "")
        edit.target = actions
        if let moves = moves() {
            menu.addItem(.separator())
            menu.addItem(actions.item("Move Up", moves.moveUp))
            menu.addItem(actions.item("Move Down", moves.moveDown))
            let moveTo = NSMenuItem(title: "Move To", action: nil, keyEquivalent: "")
            let destinations = NSMenu(title: "Move To")
            destinations.autoenablesItems = false
            for destination in moves.destinations {
                let item = actions.item(destination.title, destination.request)
                item.state = destination.isCurrent ? .on : .off
                destinations.addItem(item)
            }
            moveTo.submenu = destinations
            menu.addItem(moveTo)
            menu.addItem(.separator())
        }
        let delete = menu.addItem(withTitle: "Delete…", action: #selector(Actions.delete), keyEquivalent: "")
        delete.target = actions
        withExtendedLifetime(actions) {
            _ = menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.maxY), in: view)
        }
        // Finish native menu tracking before changing the SwiftUI hierarchy.
        // Otherwise AppKit can restore the old responder after draft/Cancel focus.
        switch actions.selection {
        case .moveToToday: DispatchQueue.main.async { onMoveToToday?() }
        case .edit: DispatchQueue.main.async { onEdit() }
        case .delete: DispatchQueue.main.async { onDelete() }
        case let .move(request): DispatchQueue.main.async { onMove(request) }
        case nil: break
        }
    }

    @MainActor private final class Actions: NSObject {
        enum Selection { case edit, delete, moveToToday, move(TaskMoveRequest) }
        var selection: Selection?
        private var requests: [TaskMoveRequest] = []
        @objc func moveToToday() { selection = .moveToToday }
        @objc func edit() { selection = .edit }
        @objc func delete() { selection = .delete }
        @objc func move(_ sender: NSMenuItem) { selection = .move(requests[sender.tag]) }

        /// A nil request is an unavailable boundary or guarded state.
        func item(_ title: String, _ request: TaskMoveRequest?) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(move(_:)), keyEquivalent: "")
            item.target = self
            item.isEnabled = request != nil
            if let request {
                item.tag = requests.count
                requests.append(request)
            }
            return item
        }
    }
}

private struct TaskMenuAnchor: NSViewRepresentable {
    // The anchor is layout plumbing, not observable UI state. Updating a binding
    // when it mounts can interrupt the parent window's sheet dismissal.
    @MainActor final class Reference {
        weak var view: NSView?
        var isTrackingMenu = false
        var opensOnKeyUp = false
    }

    let reference: Reference

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        reference.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
