import AppKit
import SwiftUI

/// How the block editor closed, so the Calendar can put focus back.
enum ScheduleEditorOutcome: Equatable {
    case cancelled
    /// The saved block's ID (new or edited).
    case saved(UUID)
    case deleted
}

/// The Calendar block editor, shown in a popover anchored to the New block
/// button, the clicked grid slot or the block being edited.
///
/// Fields: title, day, start and end. The time controls only offer 15-minute
/// values and keep the end after the start, so they cannot build an invalid
/// block. Save, Delete and Cancel go through `ScheduleState`; the editor closes
/// only after a write succeeds, and a failed write keeps the input and shows
/// the state's message. Return saves and Escape cancels.
struct ScheduleBlockEditor: View {
    let schedule: ScheduleState
    let request: ScheduleEditorRequest
    /// Reports each field change, for the grid preview.
    let onDraftChange: (ScheduleBlockDraft) -> Void
    let onClose: (ScheduleEditorOutcome) -> Void

    @State private var draft: ScheduleBlockDraft
    @State private var message: String?
    @State private var isConfirmingDelete = false
    @FocusState private var focus: Field?
    @Environment(\.colorScheme) private var colorScheme

    private enum Field: Hashable { case title, day, start, end, save, cancel, delete, cancelDelete, confirmDelete }

    static let width: CGFloat = 320

    init(schedule: ScheduleState, request: ScheduleEditorRequest,
         onDraftChange: @escaping (ScheduleBlockDraft) -> Void = { _ in },
         onClose: @escaping (ScheduleEditorOutcome) -> Void) {
        self.schedule = schedule
        self.request = request
        self.onDraftChange = onDraftChange
        self.onClose = onClose
        _draft = State(initialValue: request.draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.isNew ? "New block" : "Edit block")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .accessibilityAddTraits(.isHeader)
            titleField
            ScheduleEditorDayField(draft: $draft, focus: $focus, field: .day)
            timeFields
            if let message {
                Text(message)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DaybookPalette.danger(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scheduleEditorMessage")
            }
            if isConfirmingDelete { deleteConfirmation } else { actions }
        }
        .padding(16)
        .frame(width: Self.width, alignment: .leading)
        .background { DaybookPalette.canvas(colorScheme) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(draft.isNew ? "New block" : "Edit block")
        .accessibilityIdentifier("scheduleEditor")
        .onChange(of: draft) { _, new in onDraftChange(new) }
        .task {
            await Task.yield()
            focus = .title
        }
    }

    // MARK: Fields

    private var titleField: some View {
        TextField("Title", text: $draft.title)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13, design: .monospaced))
            .focused($focus, equals: .title)
            .onSubmit(save)
            .onChange(of: draft.title) { _, _ in
                if message == ScheduleBlockDraftIssue.blankTitle.message { message = nil }
            }
            .accessibilityLabel("Block title")
            .accessibilityIdentifier("scheduleEditorTitle")
    }

    /// Start and end on one line, the duration under them, aligned with the controls.
    private var timeFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            timeControls
            Text(draft.durationText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, ScheduleEditorFieldLabel.width + 10)
                .accessibilityLabel("Duration \(draft.durationText)")
                .accessibilityIdentifier("scheduleEditorDuration")
        }
    }

    private var timeControls: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ScheduleEditorFieldLabel(text: "From")
            ScheduleTimePopUp(label: "Start time", options: ScheduleBlockDraft.startOptions,
                              selection: Binding(get: { draft.startMinute }, set: { draft.setStart($0) }),
                              identifier: "scheduleEditorStart")
                .focused($focus, equals: .start)
            Text("to")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            ScheduleTimePopUp(label: "End time", options: ScheduleBlockDraft.endOptions,
                              selection: Binding(get: { draft.endMinute }, set: { draft.setEnd($0) }),
                              identifier: "scheduleEditorEnd")
                .focused($focus, equals: .end)
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            if !draft.isNew {
                Button("Delete…", role: .destructive) { beginDelete() }
                    .buttonStyle(.daybook)
                    .editorKeyAction { beginDelete() }
                    .focused($focus, equals: .delete)
                    .accessibilityLabel("Delete block")
                    .accessibilityIdentifier("scheduleEditorDelete")
            }
            Spacer(minLength: 0)
            Button("Cancel") { onClose(.cancelled) }
                .buttonStyle(.daybook)
                .keyboardShortcut(.cancelAction)
                .editorKeyAction { onClose(.cancelled) }
                .focused($focus, equals: .cancel)
                .accessibilityIdentifier("scheduleEditorCancel")
            Button("Save", action: save)
                .buttonStyle(.daybookProminent)
                .keyboardShortcut(.defaultAction)
                .editorKeyAction(save)
                .focused($focus, equals: .save)
                .accessibilityIdentifier("scheduleEditorSave")
        }
    }

    /// Inline, like task deletion: Cancel has focus, Escape backs out.
    private var deleteConfirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Delete block?")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
            Text(draft.title.isEmpty ? "Untitled" : draft.title)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel") { cancelDelete() }
                    .buttonStyle(.daybook)
                    .keyboardShortcut(.cancelAction)
                    .editorKeyAction { cancelDelete() }
                    .focused($focus, equals: .cancelDelete)
                    .accessibilityLabel("Keep block")
                    .accessibilityIdentifier("scheduleEditorCancelDelete")
                Button("Delete", role: .destructive) { confirmDelete() }
                    .buttonStyle(.daybookProminent)
                    .editorKeyAction { confirmDelete() }
                    .focused($focus, equals: .confirmDelete)
                    .accessibilityLabel("Delete block")
                    .accessibilityIdentifier("scheduleEditorConfirmDelete")
            }
        }
        .padding(10)
        .background(DaybookPalette.danger(colorScheme).opacity(colorScheme == .dark ? 0.10 : 0.06),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scheduleEditorDeleteConfirmation")
    }

    private func save() {
        guard !isConfirmingDelete else { return }
        let content: ScheduleBlockContent
        switch draft.validated() {
        case let .failure(issue):
            message = issue.message
            if issue != .invalidRange { focus = .title }
            return
        case let .success(valid):
            content = valid
        }
        let result: Result<ScheduleBlock, ScheduleCommandFailure>
        if let id = draft.blockID {
            result = schedule.update(id: id, to: content)
        } else {
            result = schedule.add(content)
        }
        switch result {
        case let .success(block): onClose(.saved(block.id))
        case let .failure(failure): message = failure.message
        }
    }

    private func beginDelete() {
        message = nil
        isConfirmingDelete = true
        Task { @MainActor in
            await Task.yield()
            focus = .cancelDelete
        }
    }

    private func cancelDelete() {
        isConfirmingDelete = false
        Task { @MainActor in
            await Task.yield()
            focus = .delete
        }
    }

    private func confirmDelete() {
        guard let id = draft.blockID else { return }
        switch schedule.delete(id: id) {
        case .success:
            onClose(.deleted)
        case let .failure(failure):
            isConfirmingDelete = false
            message = failure.message
        }
    }
}

// MARK: - Day field

/// "‹ Wednesday, November 18, 2026 ›". The arrows, Left/Right keys and the
/// VoiceOver adjust actions move one day.
private struct ScheduleEditorDayField<Field: Hashable>: View {
    @Binding var draft: ScheduleBlockDraft
    var focus: FocusState<Field?>.Binding
    let field: Field

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ScheduleEditorFieldLabel(text: "Day")
            HStack(spacing: 4) {
                stepButton(-1, symbol: "chevron.left", label: "Previous day", identifier: "scheduleEditorPreviousDay")
                Text(draft.dayText)
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .focusable()
                    .keyboardFocusAppearance()
                    .focused(focus, equals: field)
                    .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                        draft.moveDay(by: press.key == .rightArrow ? 1 : -1)
                        return .handled
                    }
                    .accessibilityLabel("Day")
                    .accessibilityValue(draft.dayText)
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: draft.moveDay(by: 1)
                        case .decrement: draft.moveDay(by: -1)
                        @unknown default: break
                        }
                    }
                    .accessibilityIdentifier("scheduleEditorDay")
                stepButton(1, symbol: "chevron.right", label: "Next day", identifier: "scheduleEditorNextDay")
            }
        }
    }

    private func stepButton(_ offset: Int, symbol: String, label: String, identifier: String) -> some View {
        Button { draft.moveDay(by: offset) } label: {
            Image(systemName: symbol).frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .focusable(false)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

private struct ScheduleEditorFieldLabel: View {
    static let width: CGFloat = 36
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: Self.width, alignment: .leading)
            .accessibilityHidden(true)
    }
}

// MARK: - Time pop-up

/// A native pop-up of 15-minute times in the system monospaced font, so it
/// cannot produce an off-grid value. Up/Down step one slot while focused,
/// and Space opens the menu.
private struct ScheduleTimePopUp: View {
    let label: String
    let options: [Int]
    @Binding var selection: Int
    let identifier: String
    @State private var reference = ScheduleTimePopUpButton.Reference()

    var body: some View {
        ScheduleTimePopUpButton(label: label, identifier: identifier, options: options,
                                selection: $selection, reference: reference)
            .fixedSize()
            .focusable()
            .keyboardFocusAppearance()
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                step(press.key == .downArrow ? 1 : -1)
                return .handled
            }
            .onKeyPress(.space) {
                reference.button?.performClick(nil)
                return .handled
            }
            .accessibilityIdentifier(identifier)
    }

    private func step(_ offset: Int) {
        guard let index = options.firstIndex(of: selection) else { return }
        selection = options[min(max(index + offset, 0), options.count - 1)]
    }
}

private struct ScheduleTimePopUpButton: NSViewRepresentable {
    @MainActor final class Reference {
        weak var button: NSPopUpButton?
    }

    let label: String
    let identifier: String
    let options: [Int]
    @Binding var selection: Int
    let reference: Reference

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.font = font
        button.menu?.font = font
        button.addItems(withTitles: options.map { ScheduleBlockContent.clockText(minute: $0) })
        button.target = context.coordinator
        button.action = #selector(Coordinator.select(_:))
        button.setAccessibilityLabel(label)
        button.setAccessibilityIdentifier(identifier)
        button.refusesFirstResponder = true
        reference.button = button
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.popUp = self
        reference.button = button
        if let index = options.firstIndex(of: selection), button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var popUp: ScheduleTimePopUpButton

        init(_ popUp: ScheduleTimePopUpButton) { self.popUp = popUp }

        @objc func select(_ sender: NSPopUpButton) {
            guard popUp.options.indices.contains(sender.indexOfSelectedItem) else { return }
            popUp.selection = popUp.options[sender.indexOfSelectedItem]
        }
    }
}

private extension View {
    /// Space and Return act like a click, matching the other Daybook controls.
    func editorKeyAction(_ action: @escaping () -> Void) -> some View {
        focusable()
            .keyboardFocusAppearance()
            .onKeyPress(keys: [.space, .return]) { _ in
                action()
                return .handled
            }
    }
}
