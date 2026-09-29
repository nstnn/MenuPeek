import SwiftUI

/// Desktop checklist backed by the app-owned saved snapshot and draft.
struct TaskWindowView: View {
    private enum FocusControl: Hashable {
        case add, settings, retry, save, draft
        case completion(UUID)
    }

    @Bindable var state: DailyNotesState
    let onSettings: () -> Void
    @State private var isComposerVisible = false
    @FocusState private var focusedControl: FocusControl?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    recoveryNotice
                    if let progress = state.availableProgress {
                        if progress.total == 0 {
                            emptyState
                        } else {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(state.notes) { note in
                                    taskRow(note)
                                    if note.id != state.notes.last?.id { Divider() }
                                }
                            }
                        }
                        if state.yesterdayIncompleteCount > 0 {
                            Text("\(state.yesterdayIncompleteCount) unfinished \(state.yesterdayIncompleteCount == 1 ? "task" : "tasks") from yesterday")
                                .font(.callout)
                                .foregroundStyle(.secondary)
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
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                if isComposerVisible || !state.draft.isEmpty {
                    composer
                }
                if let issue = state.issue, issue == .add || issue == .complete {
                    Text(issue == .add ? "Could not save task. Try again." : "Could not update task. Try again.")
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
                    .disabled(state.availableProgress == nil)
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
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
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
        }
        .foregroundStyle(note.isCompleted ? .secondary : .primary)
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("taskRow-\(note.id)")
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField("Write a task", text: $state.draft)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("New task")
                .accessibilityIdentifier("newTaskDraft")
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
                .disabled(state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.availableProgress == nil)
                .accessibilityIdentifier("saveTask")
            Button("Cancel", action: cancelDraft)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("cancelNewTask")
        }
    }

    private func showComposer() {
        isComposerVisible = true
        Task { @MainActor in
            await Task.yield()
            focusedControl = .draft
        }
    }

    private func saveDraft() {
        if state.addDraft() {
            isComposerVisible = false
            focusedControl = .add
        }
    }

    private func cancelDraft() {
        state.cancelDraft()
        isComposerVisible = false
        focusedControl = .add
    }

    private func focusOutline(_ focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.accentColor, lineWidth: focused ? 2 : 0)
            .padding(-3)
            .allowsHitTesting(false)
    }
}
