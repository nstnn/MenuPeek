import SwiftUI

/// Keeps composer visibility alongside the app-owned notes state while the
/// menu bar panel is open.
struct DailyNotesPanel: View {
    @Bindable var state: DailyNotesState
    @State private var isComposerVisible = false
    let onOpenSettings: () -> Void

    var body: some View {
        DailyNotesView(
            dateLabel: Self.dateLabel(for: state.todayKey),
            notes: state.notes,
            progress: state.progress,
            yesterdayIncompleteCount: state.yesterdayIncompleteCount,
            errorMessage: state.errorMessage,
            draft: $state.draft,
            isComposerVisible: $isComposerVisible,
            editingNoteID: state.editingNoteID,
            editDraft: $state.editDraft,
            onOpenSettings: onOpenSettings,
            onSave: { state.addDraft() },
            onBeginEditing: { state.beginEditing(id: $0) },
            onSaveEdit: { state.saveEdit() },
            onCancelEdit: { state.cancelEditing() },
            onDelete: { state.delete(id: $0) },
            onToggleCompletion: { id, completed in
                state.setCompleted(id: id, completed: completed)
            }
        )
        .onAppear { state.panelDidOpen() }
    }

    private static func dateLabel(for dayKey: String?) -> String {
        let key = dayKey ?? NoteDay().keys().today
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: key) else { return key }
        parser.dateFormat = "d MMM"
        return parser.string(from: date)
    }
}

/// The Notes panel's presentation boundary. Callers supply saved values and
/// actions; the view does not open storage or assume that a save succeeded.
struct DailyNotesView: View {
    private enum FocusControl: Hashable {
        case settings
        case add
        case save
        case rowActions(UUID)
    }

    let dateLabel: String
    let notes: [Note]
    let progress: NoteProgress
    let yesterdayIncompleteCount: Int
    let errorMessage: String?
    @Binding var draft: String
    @Binding var isComposerVisible: Bool
    let editingNoteID: UUID?
    @Binding var editDraft: String
    let onOpenSettings: () -> Void
    let onSave: () -> Bool
    let onBeginEditing: (UUID) -> Void
    let onSaveEdit: () -> Bool
    let onCancelEdit: () -> Void
    let onDelete: (UUID) -> Void
    let onToggleCompletion: (UUID, Bool) -> Void

    @FocusState private var isDraftFocused: Bool
    @FocusState private var focusedControl: FocusControl?
    @State private var noteToDelete: Note?

    private let rowHeight: CGFloat = 43
    private let maximumListHeight: CGFloat = 258

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            dateAndProgress
            noteList
            addArea

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("dailyNotesError")
            }

            if yesterdayIncompleteCount > 0 {
                Text("\(yesterdayIncompleteCount) unfinished \(yesterdayIncompleteCount == 1 ? "item" : "items") from yesterday")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: 360)
        .frame(maxHeight: 480)
        .fixedSize(horizontal: false, vertical: true)
        .alert("Delete note?", isPresented: Binding(
            get: { noteToDelete != nil },
            set: { if !$0 { noteToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let noteToDelete { onDelete(noteToDelete.id) }
                noteToDelete = nil
            }
            Button("Cancel", role: .cancel) { noteToDelete = nil }
        } message: {
            if let noteToDelete { Text(noteToDelete.text) }
        }
    }

    private var header: some View {
        HStack {
            Text("MenuPocket")
                .font(.headline)
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Settings")
            .focusable()
            .focused($focusedControl, equals: .settings)
            .overlay { focusOutline(focusedControl == .settings) }
        }
    }

    private var dateAndProgress: some View {
        HStack {
            Text(dateLabel)
                .fontWeight(.medium)
            Spacer()
            Text("\(progress.completed)/\(progress.total) complete")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private var noteList: some View {
        ScrollView {
            if notes.isEmpty {
                Text("No notes yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(notes) { note in
                        HStack(spacing: 8) {
                            Toggle(isOn: Binding(
                                get: { note.isCompleted },
                                set: { onToggleCompletion(note.id, $0) }
                            )) {
                                Text(note.text)
                                    .lineLimit(2)
                                    .foregroundStyle(note.isCompleted ? .secondary : .primary)
                            }
                            .toggleStyle(.checkbox)
                            .tint(.primary)
                            .accessibilityLabel("\(note.text), \(note.isCompleted ? "completed" : "incomplete")")
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Menu {
                                Button("Edit") {
                                    onBeginEditing(note.id)
                                    isComposerVisible = false
                                }
                                Button("Delete", role: .destructive) { noteToDelete = note }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .frame(width: 24, height: 24)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .accessibilityLabel("Actions for \(note.text)")
                            .focusable()
                            .focused($focusedControl, equals: .rowActions(note.id))
                            .overlay { focusOutline(focusedControl == .rowActions(note.id)) }
                        }
                        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)

                        if note.id != notes.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(
            notes.isEmpty ? rowHeight : CGFloat(notes.count) * rowHeight + CGFloat(max(notes.count - 1, 0)),
            maximumListHeight
        ))
        .accessibilityIdentifier("dailyNotesScrollView")
    }

    private var addArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isComposerVisible || editingNoteID != nil {
                composer
            } else {
                Button {
                    isComposerVisible = true
                } label: {
                    Label("Add note", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.medium))
                .frame(height: 32)
                .focusable()
                .focused($focusedControl, equals: .add)
                .overlay { focusOutline(focusedControl == .add) }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(editingNoteID == nil ? "Write a note" : "Edit note",
                      text: editingNoteID == nil ? $draft : $editDraft)
                .accessibilityLabel(editingNoteID == nil ? "New note" : "Edit note")
                .textFieldStyle(.plain)
                .focused($isDraftFocused)
                .onSubmit(saveDraft)
                .onExitCommand { cancelDraft() }
                .task { isDraftFocused = true }
                .onChange(of: editingNoteID) { _, _ in isDraftFocused = true }

            Button("Save", action: saveDraft)
                .buttonStyle(.plain)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Color.primary, in: RoundedRectangle(cornerRadius: 6))
                .focusable()
                .focused($focusedControl, equals: .save)
                .overlay { focusOutline(focusedControl == .save) }
        }
        .padding(.horizontal, 8)
        .frame(height: 42)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(isDraftFocused ? 0.65 : 0.18), lineWidth: 1)
        }
    }

    private func saveDraft() {
        if editingNoteID != nil {
            _ = onSaveEdit()
        } else if onSave() { isComposerVisible = false }
    }

    private func cancelDraft() {
        if editingNoteID != nil { onCancelEdit() }
        else {
            draft = ""
            isComposerVisible = false
        }
    }

    private func focusOutline(_ focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.accentColor, lineWidth: focused ? 2 : 0)
            .padding(-2)
            .allowsHitTesting(false)
    }
}

#if DEBUG
private struct DailyNotesPreview: View {
    enum Scenario { case empty, five, long }

    @State private var notes: [Note]
    @State private var draft = ""
    @State private var editingNoteID: UUID?
    @State private var editDraft = ""
    @State private var isComposerVisible: Bool

    init(_ scenario: Scenario, composerOpen: Bool = false) {
        let samples = [
            "Send design draft to the team",
            "Book a dentist appointment",
            "Reply to Maya's email",
            "Review September expenses",
            "Pick up a package"
        ]
        let count = switch scenario {
        case .empty: 0
        case .five: 5
        case .long: 20
        }
        _notes = State(initialValue: (0..<count).map { index in
            Note(
                id: UUID(),
                text: samples[index % samples.count],
                dayKey: "2026-09-26",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_790_000_000 - index)),
                completedAt: nil
            )
        })
        _isComposerVisible = State(initialValue: composerOpen)
    }

    var body: some View {
        DailyNotesView(
            dateLabel: "26 Sep",
            notes: NoteOrder.sorted(notes),
            progress: NoteProgress(notes: notes, for: "2026-09-26"),
            yesterdayIncompleteCount: notes.isEmpty ? 0 : 3,
            errorMessage: nil,
            draft: $draft,
            isComposerVisible: $isComposerVisible,
            editingNoteID: editingNoteID,
            editDraft: $editDraft,
            onOpenSettings: {},
            onSave: {
                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return false }
                notes.append(Note(id: UUID(), text: text, dayKey: "2026-09-26",
                                  createdAt: Date(), completedAt: nil))
                draft = ""
                return true
            },
            onBeginEditing: { id in
                editingNoteID = id
                editDraft = notes.first(where: { $0.id == id })?.text ?? ""
            },
            onSaveEdit: {
                guard let id = editingNoteID,
                      let index = notes.firstIndex(where: { $0.id == id }) else { return false }
                let text = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return false }
                let note = notes[index]
                notes[index] = Note(id: note.id, text: text, dayKey: note.dayKey,
                                    createdAt: note.createdAt, completedAt: note.completedAt)
                editingNoteID = nil
                editDraft = ""
                return true
            },
            onCancelEdit: {
                editingNoteID = nil
                editDraft = ""
            },
            onDelete: { id in notes.removeAll { $0.id == id } },
            onToggleCompletion: { id, isCompleted in
                guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
                let note = notes[index]
                notes[index] = Note(id: note.id, text: note.text, dayKey: note.dayKey,
                                    createdAt: note.createdAt,
                                    completedAt: isCompleted ? Date() : nil)
            }
        )
    }
}

#Preview("Empty · Light") { DailyNotesPreview(.empty).preferredColorScheme(.light) }
#Preview("Five notes · Light") { DailyNotesPreview(.five).preferredColorScheme(.light) }
#Preview("Narrow · Light") { DailyNotesPreview(.five).frame(width: 320).preferredColorScheme(.light) }
#Preview("Composer · Light") { DailyNotesPreview(.five, composerOpen: true).preferredColorScheme(.light) }
#Preview("Long list · Light") { DailyNotesPreview(.long).preferredColorScheme(.light) }
#Preview("Empty · Dark") { DailyNotesPreview(.empty).preferredColorScheme(.dark) }
#Preview("Five notes · Dark") { DailyNotesPreview(.five).preferredColorScheme(.dark) }
#Preview("Composer · Dark") { DailyNotesPreview(.five, composerOpen: true).preferredColorScheme(.dark) }
#Preview("Long list · Dark") { DailyNotesPreview(.long).preferredColorScheme(.dark) }
#endif
