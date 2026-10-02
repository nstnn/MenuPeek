import AppKit
import SwiftUI

/// Desktop checklist backed by the app-owned saved snapshot and draft.
struct TaskWindowView: View {
    private enum FocusControl: Hashable {
        case add, settings, retry, save, draft, cancelDelete, confirmDelete
        case group(TaskGroupID)
        case completion(UUID)
        case edit(UUID), delete(UUID)
    }

    /// Row controls and checkboxes align with the group name after its chevron.
    private static let groupRowIndent: CGFloat = 22

    @Bindable var state: DailyNotesState
    let presentation: TaskWindowPresentation
    let onSettings: () -> Void
    @State private var isComposerVisible = false
    @FocusState private var focusedControl: FocusControl?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(24)
                .background { focusClearingBackground }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    recoveryNotice
                    if let progress = state.availableProgress {
                        if progress.total == 0 {
                            emptyState
                        } else {
                            let groups = state.groups
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(groups) { group in
                                    let collapsed = state.categoryPreferences.isCollapsed(group.id)
                                    groupHeader(group, collapsed: collapsed)
                                        .padding(.top, group.id == groups.first?.id ? 0 : 12)
                                    // A collapsed group renders no rows, so their
                                    // controls leave keyboard and accessibility traversal.
                                    if !collapsed {
                                        ForEach(group.notes) { note in
                                            Divider()
                                            taskRow(note)
                                        }
                                        .padding(.leading, Self.groupRowIndent)
                                    }
                                }
                            }
                        }
                        if state.yesterdayIncompleteCount > 0 {
                            Text("\(state.yesterdayIncompleteCount) unfinished \(state.yesterdayIncompleteCount == 1 ? "task" : "tasks") from yesterday")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                    } else {
                        unavailableState
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("todayTaskList")
            .disabled(presentation.deletionTarget != nil)
            .contentShape(Rectangle())
            .gesture(TapGesture().onEnded { clearFocus() }, including: .gesture)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                if let target = presentation.deletionTarget,
                   let note = state.notes.first(where: { $0.id == target.id }) {
                    deletionConfirmation(note)
                } else if state.editingNoteID != nil || isComposerVisible || !state.draft.isEmpty {
                    composer
                }
                if let message = writeError {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("taskWriteError")
                }
                HStack {
                    Button(action: showComposer) {
                        Label("Add task", systemImage: "plus")
                    }
                    .focusable()
                    .focused($focusedControl, equals: .add)
                    .onKeyPress(keys: [.space, .return]) { _ in
                        showComposer()
                        return .handled
                    }
                    .overlay { focusOutline(focusedControl == .add) }
                    .disabled(!presentation.canAddTask(state: state))
                    .accessibilityIdentifier("addTask")
                    Spacer()
                    Button("Settings…", action: onSettings)
                        .focusable()
                        .focused($focusedControl, equals: .settings)
                        .onKeyPress(keys: [.space, .return]) { _ in
                            onSettings()
                            return .handled
                        }
                        .overlay { focusOutline(focusedControl == .settings) }
                        .accessibilityLabel("Open Settings")
                        .disabled(presentation.deletionTarget != nil)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background { focusClearingBackground }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: presentation.newTaskRequestID, initial: true) { _, request in
            if request != nil {
                showComposer()
                presentation.consumeNewTaskRequest()
            }
        }
        .onChange(of: state.todayKey) { _, _ in presentation.validateDeletion(state: state) }
        .onChange(of: state.notes) { _, _ in presentation.validateDeletion(state: state) }
        .onChange(of: state.hasLoadedToday) { _, _ in presentation.validateDeletion(state: state) }
        .onChange(of: presentation.deletionTarget?.id) { old, new in
            if let old, new == nil { restoreRowFocus(old) }
        }
        .onChange(of: state.editingNoteID) { old, new in
            if new != nil { focusDraft() }
            else if let old { restoreRowFocus(old) }
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
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(dateLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let progress = state.availableProgress {
                    Text("\(progress.completed)/\(progress.total) complete")
                        .font(.headline.monospacedDigit())
                        .accessibilityIdentifier("todayProgress")
                    ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                        .frame(width: 140)
                        .accessibilityLabel("Today's task progress")
                } else {
                    Text("—")
                        .font(.headline)
                        .accessibilityLabel("Task progress unavailable")
                        .accessibilityIdentifier("todayProgress")
                }
            }
        }
    }

    private var dateLabel: String {
        let key = state.todayKey ?? NoteDay().keys().today
        // A saved day key is a calendar date, not an instant to shift into the
        // current time zone. Format its components without changing that date.
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: key) else { return key }
        formatter.locale = Locale(identifier: "en")
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
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
                if let text = state.recoveredEditDraft {
                    Text("Unsaved edit")
                        .font(.callout.weight(.semibold))
                    Text(text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("todayRecoveryNotice")
        }
    }

    /// The count covers every task in the group, including rows hidden by collapse.
    private func groupHeader(_ group: TaskGroup, collapsed: Bool) -> some View {
        let progress = group.progress
        return Button {
            toggleGroup(group)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.groupRowIndent - 8)
                Text(group.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(progress.completed)/\(progress.total)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focusedControl, equals: .group(group.id))
        .onKeyPress(keys: [.space, .return]) { _ in
            toggleGroup(group)
            return .handled
        }
        .overlay { focusOutline(focusedControl == .group(group.id)) }
        .help(collapsed ? "Show tasks" : "Hide tasks")
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
        case let .completion(id), let .edit(id), let .delete(id): id
        default: nil
        }
    }

    private func taskRow(_ note: Note) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: Binding(
                get: { state.notes.first(where: { $0.id == note.id })?.isCompleted ?? note.isCompleted },
                set: { state.setCompleted(id: note.id, completed: $0) }
            )) { Text(note.text) }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .focusable()
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
            Button {
                state.beginEditing(id: note.id)
            } label: {
                Image(systemName: "pencil")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
            }
            .focusable()
            .focused($focusedControl, equals: .edit(note.id))
            .onKeyPress(keys: [.space, .return]) { _ in
                state.beginEditing(id: note.id)
                return .handled
            }
            .overlay { focusOutline(focusedControl == .edit(note.id)) }
            .disabled(state.editingNoteID != nil)
            .help("Edit task")
            .accessibilityLabel("Edit task: \(note.text)")
            .accessibilityIdentifier("editTask-\(note.id)")
            Button(role: .destructive) {
                requestDeletion(note.id)
            } label: {
                Image(systemName: "trash")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
            }
            .focusable()
            .focused($focusedControl, equals: .delete(note.id))
            .onKeyPress(keys: [.space, .return]) { _ in
                requestDeletion(note.id)
                return .handled
            }
            .overlay { focusOutline(focusedControl == .delete(note.id)) }
            .disabled(state.editingNoteID != nil)
            .help("Delete task")
            .accessibilityLabel("Delete task: \(note.text)")
            .accessibilityIdentifier("deleteTask-\(note.id)")
        }
        .foregroundStyle(note.isCompleted ? .secondary : .primary)
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("taskRow-\(note.id)")
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField(state.editingNoteID == nil ? "Write a task" : "Edit task",
                      text: state.editingNoteID == nil ? $state.draft : $state.editDraft)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(state.editingNoteID == nil ? "New task" : "Edit task")
                .accessibilityIdentifier(state.editingNoteID == nil ? "newTaskDraft" : "editTaskDraft")
                .focused($focusedControl, equals: .draft)
                .onSubmit(saveDraft)
                .onExitCommand(perform: cancelDraft)
                .task {
                    await Task.yield()
                    focusedControl = .draft
                }
            Button("Save", action: saveDraft)
                .focusable()
                .focused($focusedControl, equals: .save)
                .onKeyPress(keys: [.space, .return]) { _ in
                    saveDraft()
                    return .handled
                }
                .disabled((state.editingNoteID == nil ? state.draft : state.editDraft)
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.availableProgress == nil)
                .accessibilityIdentifier("saveTask")
            Button("Cancel", action: cancelDraft)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(state.editingNoteID == nil ? "cancelNewTask" : "cancelTaskEdit")
        }
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

    private func requestDeletion(_ id: UUID) {
        presentation.requestDeletion(id: id, state: state)
    }

    private func confirmDeletion() {
        _ = presentation.confirmDeletion(state: state)
    }

    private func restoreRowFocus(_ id: UUID) {
        Task { @MainActor in
            await Task.yield()
            focusedControl = focusAfterLeavingRow(id)
        }
    }

    /// The row's Edit button when it is visible; its group header when the
    /// group is collapsed; Add when the task is gone; Retry when data is unavailable.
    private func focusAfterLeavingRow(_ id: UUID) -> FocusControl {
        guard state.availableProgress != nil else { return .retry }
        guard let group = state.groups.first(where: { $0.notes.contains { $0.id == id } }) else {
            return .add
        }
        return state.categoryPreferences.isCollapsed(group.id) ? .group(group.id) : .edit(id)
    }

    private func focusDraft() {
        Task { @MainActor in
            await Task.yield()
            focusedControl = .draft
        }
    }

    private func showComposer() {
        guard presentation.canAddTask(state: state) else { return }
        isComposerVisible = true
        focusDraft()
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
        if let id = state.editingNoteID {
            state.cancelEditing()
            restoreRowFocus(id)
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
            Color(nsColor: .windowBackgroundColor)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityHidden(true)
    }

    private func focusOutline(_ focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.accentColor, lineWidth: focused ? 2 : 0)
            .padding(-3)
            .allowsHitTesting(false)
    }
}
