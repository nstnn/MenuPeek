import AppKit
import SwiftUI

/// Desktop checklist backed by the app-owned saved snapshot and draft.
struct TaskWindowView: View {
    private struct Row: Identifiable {
        let id: UUID
        let text: String
        let isCompleted: Bool
        let categoryID: UUID?
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
        return state.notes.map { Row(id: $0.id, text: $0.text, isCompleted: $0.isCompleted, categoryID: $0.categoryID) }
    }
    private var groups: [Group] {
        if isLater {
            return state.laterGroups.map { group in
                Group(id: group.id, name: group.name, notes: group.tasks.map {
                    Row(id: $0.id, text: $0.text, isCompleted: $0.isCompleted, categoryID: $0.categoryID)
                })
            }
        }
        return state.groups.map { group in
            Group(id: group.id, name: group.name, notes: group.notes.map {
                Row(id: $0.id, text: $0.text, isCompleted: $0.isCompleted, categoryID: $0.categoryID)
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
        case add, manageCategories, settings, retry, save, draft, category, cancelDelete, confirmDelete
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
    @State private var moveNoticeID = UUID()
    @State private var isMoveNoticeVisible = false
    @FocusState private var focusedControl: FocusControl?
    @State private var keyboardFocus = KeyboardFocusVisibility.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = geometry.size.width < 700 ? 24 : 32
            VStack(alignment: .leading, spacing: 0) {
                header
                    .frame(maxWidth: Self.contentWidth, alignment: .leading)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, horizontalPadding)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                    .background { focusClearingBackground }
                if hasTopInteractionContent {
                    VStack(alignment: .leading, spacing: 12) {
                        if hasComposer { composer }
                        if hasMoveNotice {
                            Text("Moved task to Today.")
                                .font(.callout)
                                .accessibilityIdentifier("laterMoveNotice")
                        }
                        if let message = topWriteError { taskWriteError(message) }
                    }
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: Self.contentWidth, alignment: .leading)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            recoveryNotice
                            if isAvailable {
                                if rows.isEmpty {
                                    emptyState
                                } else {
                                    LazyVStack(alignment: .leading, spacing: 24) {
                                        ForEach(groups) { group in
                                            groupSurface(group)
                                                .id(group.id)
                                        }
                                    }
                                }
                                if !isLater, state.yesterdayIncompleteCount > 0 {
                                    Text("\(state.yesterdayIncompleteCount) unfinished \(state.yesterdayIncompleteCount == 1 ? "task" : "tasks") from yesterday")
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.red)
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
                    .accessibilityIdentifier(identifier("todayTaskList", "laterTaskList"))
                    .id(destination)
                    .disabled(presentation.deletionTarget != nil || presentation.isManagingCategories)
                    .contentShape(Rectangle())
                    .gesture(TapGesture().onEnded { clearFocus() }, including: .gesture)
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
                                guard focusRequestID == requestID else { return }
                                if let group = groups.first(where: { $0.notes.contains { $0.id == id } }) {
                                    // Entry/exit changes the space above the list.
                                    // Mount the group before targeting its row.
                                    scroll.scrollTo(group.id, anchor: .top)
                                    await Task.yield()
                                }
                                guard focusRequestID == requestID else { return }
                                scroll.scrollTo(id, anchor: .center)
                                if new != nil { focusDraft(requestID: requestID) }
                                else { restoreRowFocus(id, requestID: requestID) }
                            }
                        }
                    }
                }
                if hasFooterContent {
                    Divider()
                    footer
                        .frame(maxWidth: Self.contentWidth, alignment: .leading)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .background { focusClearingBackground }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { canvasBackground }
        // Attached to this window, so it blocks the rows and actions behind it.
        .sheet(isPresented: Binding(
            get: { presentation.isManagingCategories },
            set: { if !$0 { presentation.dismissCategoryManager() } }
        )) {
            TaskCategoryManagerView(state: state, presentation: presentation)
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
            switch presentation.focusAfterSelection(state: state) {
            case .draft: focusDraft()
            case .retry: focusedControl = .retry
            default: focusedControl = .add
            }
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

    private var writeError: String? {
        switch issue {
        case .add: "Could not save task. Try again."
        case .complete: "Could not update task. Try again."
        case .edit: "Could not save edit. Try again."
        case .delete: "Could not delete task. Try again."
        case .move: "Could not move task to Today. Try again."
        default: nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            destinationControl
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    listHeading
                    Spacer(minLength: 16)
                    topActions
                }
                VStack(alignment: .leading, spacing: 16) {
                    listHeading
                    topActions
                }
            }
            if !isLater {
                HStack(spacing: 12) {
                    if let progress = state.availableProgress {
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(Color.accentColor)
                                .frame(width: 160 * Double(progress.completed) / Double(max(progress.total, 1)))
                        }
                        .frame(width: 160, height: 4)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Today's task progress")
                        .accessibilityValue("\(progress.completed) of \(progress.total) complete")
                        Text("\(progress.completed)/\(progress.total) complete")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("todayProgress")
                    } else {
                        Text("—")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Task progress unavailable")
                            .accessibilityIdentifier("todayProgress")
                    }
                }
            }
        }
    }

    private var destinationControl: some View {
        Picker("Task list", selection: Binding(
            get: { destination },
            set: { _ = presentation.selectDestination($0, state: state) }
        )) {
            Text("Today").tag(TaskListDestination.today)
                .accessibilityIdentifier("todayTab")
            Text("Later").tag(TaskListDestination.later)
                .accessibilityIdentifier("laterTab")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 200)
        .disabled(state.editingNoteID != nil || state.editingLaterTaskID != nil ||
                  presentation.deletionTarget != nil || presentation.isManagingCategories)
        .accessibilityLabel("Task list")
        .accessibilityValue(isLater ? "Later" : "Today")
        .accessibilityIdentifier("taskDestination")
    }

    @ViewBuilder
    private var listHeading: some View {
        if isLater {
            VStack(alignment: .leading, spacing: 8) {
                Text("Later")
                    .font(.system(size: 24, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(state.availableLaterRemainingCount.map { "\($0) \($0 == 1 ? "task" : "tasks") remaining" } ?? "Tasks unavailable")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("laterRemainingCount")
            }
        } else { dateHeading }
    }

    private var dateHeading: some View {
        let labels = dayLabels
        return VStack(alignment: .leading, spacing: 8) {
            Text(labels.date)
                .font(.system(size: 24, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(labels.weekday)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var topActions: some View {
        HStack(spacing: 8) {
            Button(action: showComposer) {
                HStack(spacing: 12) {
                    Label("Add task", systemImage: "plus")
                    Text("⌘N")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
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
            Button(action: showCategoryManager) {
                Image(systemName: "folder.badge.gearshape")
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
            Button(action: onSettings) {
                Image(systemName: "gearshape")
            }
            .focusable()
            .keyboardFocusAppearance()
            .focused($focusedControl, equals: .settings)
            .onKeyPress(keys: [.space, .return]) { _ in
                onSettings()
                return .handled
            }
            .overlay { focusOutline(focusedControl == .settings) }
            .help("Open Settings (⌘,)")
            .accessibilityLabel("Open Settings")
            .disabled(presentation.deletionTarget != nil)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .fixedSize()
    }

    private var hasComposer: Bool {
        presentation.deletionTarget == nil && editingID == nil &&
            presentation.hasNewTaskComposer(in: destination, state: state)
    }

    private var topWriteError: String? {
        editingID != nil && issue == .edit ? nil : writeError
    }

    private var hasMoveNotice: Bool { isLater && isMoveNoticeVisible && issue != .move }

    private var hasTopInteractionContent: Bool {
        presentation.deletionTarget == nil && (hasComposer || hasMoveNotice || topWriteError != nil)
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

    /// The count covers every task in the group, including rows hidden by collapse.
    private func groupSurface(_ group: Group) -> some View {
        let collapsed = state.categoryPreferences.isCollapsed(group.id, in: destination)
        return VStack(alignment: .leading, spacing: 0) {
            groupHeader(group, collapsed: collapsed)
            // Remove collapsed rows from keyboard and accessibility traversal.
            if !collapsed {
                ForEach(group.notes) { note in
                    taskRow(note)
                }
                .padding(.leading, Self.groupRowIndent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0))
                }
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
                    .font(.system(size: 13, weight: .medium))
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
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            TaskActionsMenu(onOpen: { focusedControl = .actions(note.id) },
                            onEdit: { beginEditing(note.id) }, onDelete: { requestDeletion(note.id) },
                            onMove: isLater && !note.isCompleted ? { moveToToday(note.id) } : nil)
            .focused($focusedControl, equals: .actions(note.id))
            .overlay { focusOutline(focusedControl == .actions(note.id)) }
            .disabled(editingID != nil)
            .help("Task actions")
            .accessibilityLabel("Actions for task: \(note.text)")
            .accessibilityHint(isLater && !note.isCompleted ? "Opens Move to Today, Edit and Delete actions" : "Opens Edit and Delete actions")
            .accessibilityIdentifier("\(isLater ? "laterTaskActions" : "taskActions")-\(note.id)")
        }
        .font(.system(size: 14))
        .foregroundStyle(note.isCompleted ? .secondary : .primary)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
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
                .focused($focusedControl, equals: .draft)
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
    /// last as in Today. With keyboard focus, Up and Down step the selection.
    /// Return does nothing here, so choosing a category never saves the draft.
    private func categoryPicker(editing: Bool) -> some View {
        Picker("Category", selection: categoryBinding(editing: editing)) {
            ForEach(state.categories) { category in
                Text(category.name).tag(UUID?.some(category.id))
            }
            Text(TaskCategoryName.general).tag(UUID?.none)
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
        let options = state.categories.map { UUID?.some($0.id) } + [nil]
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

    private func confirmDeletion() {
        _ = presentation.confirmDeletion(state: state)
    }

    private func restoreRowFocus(_ id: UUID, fallbackGroup: TaskGroupID? = nil,
                                 requestID: UUID? = nil) {
        let originGroup = fallbackGroup ?? (rowActionOrigin?.id == id ? rowActionOrigin?.groupID : nil)
        let requestID = requestID ?? focusRequestID
        Task { @MainActor in
            await Task.yield()
            guard focusRequestID == requestID else { return }
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
        Task { @MainActor in
            await Task.yield()
            guard focusRequestID == requestID else { return }
            focusedControl = .draft
        }
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

    /// Native background colors can coincide; a semantic tint keeps inset
    /// groups distinct without introducing a fixed Light/Dark palette.
    private var canvasBackground: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay {
                Color.primary.opacity(colorScheme == .light ? 0.04 : 0)
            }
    }

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
    var onMove: (() -> Void)? = nil
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
        if onMove != nil {
            let move = menu.addItem(withTitle: "Move to Today", action: #selector(Actions.move), keyEquivalent: "")
            move.target = actions
            menu.addItem(.separator())
        }
        let edit = menu.addItem(withTitle: "Edit", action: #selector(Actions.edit), keyEquivalent: "")
        edit.target = actions
        let delete = menu.addItem(withTitle: "Delete…", action: #selector(Actions.delete), keyEquivalent: "")
        delete.target = actions
        withExtendedLifetime(actions) {
            _ = menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.maxY), in: view)
        }
        // Finish native menu tracking before changing the SwiftUI hierarchy.
        // Otherwise AppKit can restore the old responder after draft/Cancel focus.
        switch actions.selection {
        case .move: DispatchQueue.main.async { onMove?() }
        case .edit: DispatchQueue.main.async { onEdit() }
        case .delete: DispatchQueue.main.async { onDelete() }
        case nil: break
        }
    }

    @MainActor private final class Actions: NSObject {
        enum Selection { case edit, delete, move }
        var selection: Selection?
        @objc func move() { selection = .move }
        @objc func edit() { selection = .edit }
        @objc func delete() { selection = .delete }
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
