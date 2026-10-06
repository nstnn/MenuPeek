import AppKit
import SwiftUI

/// Desktop checklist backed by the app-owned saved snapshot and draft.
struct TaskWindowView: View {
    private enum FocusControl: Hashable {
        case add, manageCategories, settings, retry, save, draft, category, cancelDelete, confirmDelete, history, yesterday
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
    @State private var isComposerVisible = false
    @State private var rowActionOrigin: (id: UUID, groupID: TaskGroupID)?
    @State private var focusRequestID = UUID()
    @State private var editFocusRequestID: UUID?
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
                            if let progress = state.availableProgress {
                                if progress.total == 0 {
                                    emptyState
                                } else {
                                    LazyVStack(alignment: .leading, spacing: 24) {
                                        ForEach(state.groups) { group in
                                            groupSurface(group)
                                                .id(group.id)
                                        }
                                    }
                                    .scrollTargetLayout()
                                }
                                if state.yesterdayIncompleteCount > 0 {
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
                        get: { presentation.todayScrollAnchor },
                        set: { if presentation.route == .today { presentation.todayScrollAnchor = $0 } }
                    ))
                    .accessibilityIdentifier("todayTaskList")
                    .disabled(presentation.deletionTarget != nil || presentation.isManagingCategories)
                    .contentShape(Rectangle())
                    .gesture(TapGesture().onEnded { clearFocus() }, including: .gesture)
                    .onChange(of: presentation.todayScrollRestoreID) { _, _ in
                        if let anchor = presentation.todayScrollAnchor { scroll.scrollTo(anchor, anchor: .top) }
                    }
                    .onChange(of: state.editingNoteID, initial: true) { old, new in
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
                                if let group = state.groups.first(where: { $0.notes.contains { $0.id == id } }) {
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
        .onChange(of: presentation.route) { old, new in
            focusRequestID = UUID()
            if new != .today { focusedControl = nil }
            else if old != .today {
                let requestID = focusRequestID
                Task { @MainActor in
                    await Task.yield()
                    guard presentation.route == .today, focusRequestID == requestID else { return }
                    focusedControl = state.availableProgress == nil ? .retry
                        : (presentation.historyEntry == .yesterday && state.yesterdayIncompleteCount > 0 ? .yesterday : .history)
                }
            }
        }
        .onChange(of: presentation.isManagingCategories) { wasManaging, isManaging in
            if wasManaging, !isManaging { focusManageCategories() }
        }
        .onChange(of: presentation.newTaskRequestID, initial: true) { _, request in
            if request != nil {
                showComposer()
                presentation.consumeNewTaskRequest()
            }
        }
        .onChange(of: state.todayKey) { _, _ in presentation.validateDeletion(state: state) }
        .onChange(of: state.notes) { old, new in
            presentation.validateDeletion(state: state)
            if let id = focusedNoteID, !new.contains(where: { $0.id == id }),
               let note = old.first(where: { $0.id == id }) {
                restoreRowFocus(id, fallbackGroup: TaskGroupID(categoryID: note.categoryID))
            }
        }
        .onChange(of: state.hasLoadedToday) { _, _ in presentation.validateDeletion(state: state) }
        .onChange(of: presentation.deletionTarget?.id) { old, new in
            if let old, new == nil { restoreRowFocus(old) }
        }
    }

    private var writeError: String? {
        switch state.issue {
        case .add: "Could not save task. Try again."
        case .complete: "Could not update task. Try again."
        case .edit: "Could not save edit. Try again."
        case .delete: "Could not delete task. Try again."
        default: nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    dateHeading
                    Spacer(minLength: 16)
                    topActions
                }
                VStack(alignment: .leading, spacing: 16) {
                    dateHeading
                    topActions
                }
            }
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

    private var dateHeading: some View {
        let labels = dayLabels
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(labels.date)
                    .font(.system(size: 24, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Button { openHistory(.calendar) } label: {
                    Image(systemName: "calendar").frame(width: 28, height: 28)
                }
                .focusable()
                .keyboardFocusAppearance()
                .focused($focusedControl, equals: .history)
                .onKeyPress(keys: [.space, .return]) { _ in
                    openHistory(.calendar)
                    return .handled
                }
                .disabled(!presentation.canBrowse(state: state))
                .help("View task history")
                .accessibilityLabel("View task history")
                .accessibilityIdentifier("taskHistoryEntry")
            }
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
        presentation.deletionTarget == nil && state.editingNoteID == nil &&
            (isComposerVisible || !state.draft.isEmpty)
    }

    private var topWriteError: String? {
        state.editingNoteID != nil && state.issue == .edit ? nil : writeError
    }

    private var hasTopInteractionContent: Bool {
        presentation.deletionTarget == nil && (hasComposer || topWriteError != nil)
    }

    private var hasFooterContent: Bool {
        presentation.deletionTarget != nil
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let target = presentation.deletionTarget,
               let note = state.notes.first(where: { $0.id == target.id }) {
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
            .accessibilityIdentifier("taskWriteError")
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
            Text("Today's tasks will appear here.")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
        .accessibilityIdentifier("todayEmptyState")
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tasks are unavailable")
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("todayUnavailableState")
            Text("Could not load today's tasks. Try again.")
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
                .accessibilityIdentifier("retryTodayTasks")
        }
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private var recoveryNotice: some View {
        if let notice = state.refreshNotice {
            VStack(alignment: .leading, spacing: 8) {
                Text(notice)
                    .font(.callout)
                if let recovered = state.recoveredEdit {
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
            .accessibilityIdentifier("todayRecoveryNotice")
        }
    }

    /// The count covers every task in the group, including rows hidden by collapse.
    private func groupSurface(_ group: TaskGroup) -> some View {
        let collapsed = state.categoryPreferences.isCollapsed(group.id)
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

    private func groupHeader(_ group: TaskGroup, collapsed: Bool) -> some View {
        let progress = group.progress
        let containsEdit = group.notes.contains { $0.id == state.editingNoteID }
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
                Text("\(progress.completed)/\(progress.total)")
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
        .accessibilityLabel("\(group.name), \(progress.completed) of \(progress.total) complete")
        .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
        .accessibilityHint(collapsed ? "Shows this group's tasks" : "Hides this group's tasks")
        .accessibilityIdentifier("taskGroup-\(group.id.storageKey)")
    }

    private func toggleGroup(_ group: TaskGroup) {
        let collapse = !state.categoryPreferences.isCollapsed(group.id)
        state.categoryPreferences.setCollapsed(collapse, for: group.id)
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
    private func taskRow(_ note: Note) -> some View {
        if state.editingNoteID == note.id {
            VStack(alignment: .leading, spacing: 8) {
                composer
                if state.issue == .edit, let message = writeError {
                    taskWriteError(message)
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(.primary)
            .padding(.vertical, 10)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("taskRow-\(note.id)")
            .id(note.id)
        } else {
            savedTaskRow(note)
                .id(note.id)
        }
    }

    private func savedTaskRow(_ note: Note) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: Binding(
                get: { state.notes.first(where: { $0.id == note.id })?.isCompleted ?? note.isCompleted },
                set: { state.setCompleted(id: note.id, completed: $0) }
            )) { Text(note.text) }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .focusable()
                .keyboardFocusAppearance()
                .focused($focusedControl, equals: .completion(note.id))
                .onKeyPress(keys: [.space, .return]) { _ in
                    if let saved = state.notes.first(where: { $0.id == note.id }) {
                        state.setCompleted(id: note.id, completed: !saved.isCompleted)
                    }
                    return .handled
                }
                .overlay { focusOutline(focusedControl == .completion(note.id)) }
                .accessibilityLabel(note.text)
                .accessibilityIdentifier("taskCompletion-\(note.id)")
            Text(note.text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            TaskActionsMenu(onOpen: { focusedControl = .actions(note.id) },
                            onEdit: { beginEditing(note.id) }, onDelete: { requestDeletion(note.id) })
            .focused($focusedControl, equals: .actions(note.id))
            .overlay { focusOutline(focusedControl == .actions(note.id)) }
            .disabled(state.editingNoteID != nil)
            .help("Task actions")
            .accessibilityLabel("Actions for task: \(note.text)")
            .accessibilityHint("Opens Edit and Delete actions")
            .accessibilityIdentifier("taskActions-\(note.id)")
        }
        .font(.system(size: 14))
        .foregroundStyle(note.isCompleted ? .secondary : .primary)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("taskRow-\(note.id)")
    }

    /// The field takes its own row, so the category and actions stay usable at
    /// the minimum window width.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(state.editingNoteID == nil ? "Write a task" : "Edit task",
                      text: state.editingNoteID == nil ? $state.draft : $state.editDraft)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(state.editingNoteID == nil ? "New task" : "Edit task")
                .accessibilityIdentifier(state.editingNoteID == nil ? "newTaskDraft" : "editTaskDraft")
                .focused($focusedControl, equals: .draft)
                .onSubmit(saveDraft)
                .onExitCommand(perform: cancelDraft)
            HStack(spacing: 12) {
                categoryPicker(editing: state.editingNoteID != nil)
                Spacer(minLength: 0)
                Button("Save", action: saveDraft)
                    .focusable()
                    .keyboardFocusAppearance()
                    .focused($focusedControl, equals: .save)
                    .onKeyPress(keys: [.space, .return]) { _ in
                        saveDraft()
                        return .handled
                    }
                    .disabled((state.editingNoteID == nil ? state.draft : state.editDraft)
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.availableProgress == nil)
                    .accessibilityIdentifier("saveTask")
                Button("Cancel", action: cancelDraft)
                    .keyboardFocusAppearance()
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(state.editingNoteID == nil ? "cancelNewTask" : "cancelTaskEdit")
            }
        }
    }

    /// Binds the visible draft's selection in state; nil is General, listed
    /// last as in Today. With keyboard focus, Up and Down step the selection.
    /// Return does nothing here, so choosing a category never saves the draft.
    private func categoryPicker(editing: Bool) -> some View {
        Picker("Category", selection: editing ? $state.editCategoryID : $state.draftCategoryID) {
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
        .accessibilityIdentifier(editing ? "editTaskCategory" : "newTaskCategory")
    }

    private func stepCategory(by offset: Int, editing: Bool) {
        let options = state.categories.map { UUID?.some($0.id) } + [nil]
        let current = editing ? state.editCategoryID : state.draftCategoryID
        guard state.availableCategories != nil, let index = options.firstIndex(of: current) else { return }
        let next = options[min(max(index + offset, 0), options.count - 1)]
        if editing { state.editCategoryID = next } else { state.draftCategoryID = next }
    }

    private func deletionConfirmation(_ note: Note) -> some View {
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

    private func beginEditing(_ id: UUID) {
        guard canUseRowActions, let group = state.groups.first(where: { $0.notes.contains { $0.id == id } }) else { return }
        rowActionOrigin = (id, group.id)
        state.beginEditing(id: id)
    }

    private var canUseRowActions: Bool {
        state.availableProgress != nil && state.editingNoteID == nil &&
            presentation.deletionTarget == nil && !presentation.isManagingCategories
    }

    private func requestDeletion(_ id: UUID) {
        guard canUseRowActions, let group = state.groups.first(where: { $0.notes.contains { $0.id == id } }) else { return }
        rowActionOrigin = (id, group.id)
        presentation.requestDeletion(id: id, state: state)
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
        guard state.availableProgress != nil else { return .retry }
        guard let group = state.groups.first(where: { $0.notes.contains { $0.id == id } }) else {
            if let fallbackGroup, state.groups.contains(where: { $0.id == fallbackGroup }) {
                return .group(fallbackGroup)
            }
            return .add
        }
        return state.categoryPreferences.isCollapsed(group.id) ? .group(group.id) : .actions(id)
    }

    private func focusDraft(requestID: UUID? = nil) {
        // Explicit Add requests supersede an edit's delayed scroll/focus work,
        // including an edit-exit observer that has not run yet.
        let requestID = requestID ?? UUID()
        focusRequestID = requestID
        Task { @MainActor in
            await Task.yield()
            guard presentation.route == .today, focusRequestID == requestID else { return }
            focusedControl = .draft
        }
    }

    private func openHistory(_ entry: TaskWindowPresentation.HistoryEntry) {
        guard presentation.showHistory(state: state, entry: entry) else { return }
        focusRequestID = UUID()
        focusedControl = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func showComposer() {
        guard presentation.canAddTask(state: state) else { return }
        // Only a genuinely new draft takes the last-used category. A pending one,
        // from repeated Command-N or a reopened window, keeps its selection.
        if !isComposerVisible && state.draft.isEmpty { state.startNewDraft() }
        isComposerVisible = true
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
        if state.editingNoteID != nil {
            _ = state.saveEdit()
        } else if state.addDraft() {
            isComposerVisible = false
            focusedControl = .add
        }
    }

    private func cancelDraft() {
        if state.editingNoteID != nil {
            state.cancelEditing()
            return
        }
        state.cancelDraft()
        isComposerVisible = false
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
        case .edit: DispatchQueue.main.async { onEdit() }
        case .delete: DispatchQueue.main.async { onDelete() }
        case nil: break
        }
    }

    @MainActor private final class Actions: NSObject {
        enum Selection { case edit, delete }
        var selection: Selection?
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
