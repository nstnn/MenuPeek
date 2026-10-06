import SwiftUI

/// Sheet attached to the task window for creating, renaming, and removing
/// custom categories. Saved categories come only from shared state. Name drafts
/// stay in this sheet, apart from task drafts, and are discarded when it closes.
struct TaskCategoryManagerView: View {
    private enum Field: Hashable {
        case newName, create, done, retry
        case rename(UUID), remove(UUID)
        case renameName, saveRename, cancelRename
        case cancelRemoval, confirmRemoval
    }

    /// The field the state's single `categoryNameIssue` belongs to.
    private enum NameField: Equatable {
        case new
        case rename(UUID)
    }

    let state: DailyNotesState
    let presentation: TaskWindowPresentation
    @State private var newName = ""
    @State private var renamingID: UUID?
    @State private var renameDraft = ""
    @State private var nameIssueField: NameField?
    @State private var createdID: UUID?
    @FocusState private var focus: Field?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let target = presentation.categoryRemovalTarget {
                removalConfirmation(target)
            } else {
                manager
            }
        }
        .padding(20)
        .frame(width: 480, height: 360, alignment: .topLeading)
        .font(.system(size: 14))
        .background {
            Color(nsColor: .windowBackgroundColor)
                .overlay { Color.primary.opacity(colorScheme == .light ? 0.04 : 0) }
        }
        .task {
            await Task.yield()
            focus = state.availableCategories == nil ? .retry : .newName
        }
        .onChange(of: state.categories) { _, categories in
            if let id = renamingID, !categories.contains(where: { $0.id == id }) { endRename() }
            presentation.validateCategoryRemoval(state: state)
        }
        .onChange(of: state.hasLoadedToday) { _, _ in presentation.validateCategoryRemoval(state: state) }
        .onChange(of: presentation.categoryRemovalTarget?.id) { old, new in
            if let old, new == nil { restoreFocusAfterRemoval(old) }
        }
    }

    private var manager: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Manage categories")
                    .font(.system(size: 18, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Categories are shared by Today, Later, and all saved days. Tasks without a category appear in General.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let categories = state.availableCategories {
                categoryList(categories)
                newCategoryRow
            } else {
                unavailableState
                Spacer(minLength: 0)
            }
            if let message = state.categoryIssue?.message {
                Text(message)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("categoryCommandError")
            }
            HStack {
                Spacer()
                Button("Done", action: dismiss)
                    .modifier(keyboard(.done, dismiss))
                    // While renaming, Escape belongs to the rename's Cancel.
                    .keyboardShortcut(renamingID == nil ? KeyboardShortcut.cancelAction : nil)
                    .accessibilityIdentifier("doneManagingCategories")
            }
        }
    }

    private func categoryList(_ categories: [TaskCategory]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if categories.isEmpty {
                        Text("No custom categories yet.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                    ForEach(categories) { category in
                        categoryRow(category)
                            .id(category.id)
                    }
                    generalRow
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)
            .background { insetSurface }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("categoryList")
            .onChange(of: createdID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
            .onChange(of: focus) { _, field in
                // Confirmation replaces the list. Bring its restored row focus
                // back into view when the list returns, including after a failure.
                switch field {
                case let .rename(id), let .remove(id): proxy.scrollTo(id)
                default: break
                }
            }
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: TaskCategory) -> some View {
        if renamingID == category.id {
            renameRow(category)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(category.name)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Rename") { beginRename(category) }
                    .modifier(keyboard(.rename(category.id)) { beginRename(category) })
                    .fixedSize()
                    .accessibilityLabel("Rename \(category.name)")
                    .accessibilityIdentifier("renameCategory-\(category.id)")
                Button("Remove…", role: .destructive) { requestRemoval(category) }
                    .modifier(keyboard(.remove(category.id)) { requestRemoval(category) })
                    .fixedSize()
                    .accessibilityLabel("Remove \(category.name)")
                    .accessibilityIdentifier("removeCategory-\(category.id)")
            }
            .padding(.vertical, 8)
            // One rename at a time, so an unsaved name is never silently replaced.
            .disabled(renamingID != nil)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("categoryRow-\(category.id)")
        }
    }

    private func renameRow(_ category: TaskCategory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Category name", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .renameName)
                    .onSubmit { saveRename(category.id) }
                    .onExitCommand(perform: handleEscape)
                    .accessibilityLabel("New name for \(category.name)")
                    .accessibilityIdentifier("renameCategoryName")
                Button("Save") { saveRename(category.id) }
                    .modifier(keyboard(.saveRename) { saveRename(category.id) })
                    .fixedSize()
                    .disabled(isBlank(renameDraft))
                    .accessibilityIdentifier("saveCategoryRename")
                Button("Cancel", action: cancelRename)
                    .modifier(keyboard(.cancelRename, cancelRename))
                    .fixedSize()
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cancelCategoryRename")
            }
            nameIssue(for: .rename(category.id))
        }
        .padding(.vertical, 8)
    }

    /// General has no saved row, so it has no actions.
    private var generalRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(TaskCategoryName.general)
            Text("Built in. Tasks without a category appear here. It can't be renamed or removed.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("generalCategory")
    }

    private var newCategoryRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("New category", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .newName)
                    .onSubmit(create)
                    .onExitCommand(perform: handleEscape)
                    .accessibilityLabel("New category name")
                    .accessibilityIdentifier("newCategoryName")
                Button("Create", action: create)
                    .modifier(keyboard(.create, create))
                    .fixedSize()
                    .disabled(isBlank(newName))
                    .accessibilityIdentifier("createCategory")
            }
            nameIssue(for: .new)
        }
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Categories are unavailable")
                .font(.headline)
            Text("Could not load saved categories. Try again.")
                .foregroundStyle(.secondary)
            Button("Retry") { state.refresh() }
                .modifier(keyboard(.retry) { state.refresh() })
                .accessibilityIdentifier("retryCategories")
        }
        .accessibilityIdentifier("categoriesUnavailable")
    }

    @ViewBuilder
    private func nameIssue(for field: NameField) -> some View {
        if nameIssueField == field, let message = state.categoryNameIssue?.message {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("categoryNameError")
        }
    }

    private func removalConfirmation(_ target: TaskWindowPresentation.CategoryRemovalTarget) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remove category?")
                .font(.system(size: 18, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            // Names have no length limit. Scroll the full name independently
            // so the all-days notice and actions stay visible in this sheet.
            ScrollView {
                Text(target.name)
                    .font(.system(size: 14, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: .infinity)
            .background { insetSurface }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("categoryRemovalName")
            Text(Self.removalMessage(usageCount: target.usageCount))
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            if target.countChanged {
                Text("The number of tasks changed. Review it and confirm again.")
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = state.categoryIssue?.message {
                Text(message)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("categoryCommandError")
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancelRemoval)
                    .modifier(keyboard(.cancelRemoval, cancelRemoval))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cancelCategoryRemoval")
                Button("Remove Category", role: .destructive, action: confirmRemoval)
                    .modifier(keyboard(.confirmRemoval, confirmRemoval))
                    .accessibilityIdentifier("confirmCategoryRemoval")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("categoryRemovalConfirmation")
        // Cancel starts focused, including after a changed count asks again.
        .task(id: target) {
            await Task.yield()
            focus = .cancelRemoval
        }
    }

    private var insetSurface: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0))
            }
    }

    /// Includes undated Later tasks and daily history in the removal scope.
    static func removalMessage(usageCount: Int) -> String {
        switch usageCount {
        case 0:
            "No task in Later or on any saved day uses this category. Removing it changes no tasks."
        case 1:
            "1 task, across all saved days and Later, uses this category. It will move to General and keep its text, completion, and any assigned day. No task is deleted."
        default:
            "\(usageCount) tasks, across all saved days and Later, use this category. They will move to General and keep their text, completion, and any assigned day. No task is deleted."
        }
    }

    private func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func create() {
        guard !isBlank(newName) else { return }
        nameIssueField = .new
        guard let saved = state.createCategory(name: newName) else { return }
        newName = ""
        nameIssueField = nil
        createdID = saved.id
        focus = .newName
    }

    private func beginRename(_ category: TaskCategory) {
        guard renamingID == nil, state.availableCategories != nil else { return }
        renamingID = category.id
        renameDraft = category.name
        nameIssueField = nil
        Task { @MainActor in
            await Task.yield()
            focus = .renameName
        }
    }

    private func saveRename(_ id: UUID) {
        guard !isBlank(renameDraft) else { return }
        nameIssueField = .rename(id)
        if state.renameCategory(id: id, name: renameDraft) != nil {
            endRename(focusing: id)
        } else if state.categoryIssue == .notFound {
            endRename()
        }
    }

    private func cancelRename() {
        guard let id = renamingID else { return }
        endRename(focusing: id)
    }

    private func endRename(focusing id: UUID? = nil) {
        renamingID = nil
        renameDraft = ""
        if case .rename = nameIssueField { nameIssueField = nil }
        guard let id else { return }
        Task { @MainActor in
            await Task.yield()
            focus = .rename(id)
        }
    }

    private func requestRemoval(_ category: TaskCategory) {
        guard renamingID == nil else { return }
        presentation.requestCategoryRemoval(id: category.id, state: state)
    }

    private func cancelRemoval() {
        presentation.cancelCategoryRemoval()
    }

    private func confirmRemoval() {
        presentation.confirmCategoryRemoval(state: state)
    }

    /// The row's Remove button while the category exists, otherwise the name field.
    private func restoreFocusAfterRemoval(_ id: UUID) {
        Task { @MainActor in
            await Task.yield()
            guard let categories = state.availableCategories else {
                focus = .retry
                return
            }
            focus = categories.contains(where: { $0.id == id }) ? .remove(id) : .newName
        }
    }

    /// Escape in a name field cancels the innermost action: a rename, then the
    /// sheet itself. Elsewhere, Escape reaches the visible cancel-action button.
    private func handleEscape() {
        if renamingID != nil {
            cancelRename()
        } else {
            dismiss()
        }
    }

    private func dismiss() {
        presentation.dismissCategoryManager()
    }

    private func keyboard(_ field: Field, _ action: @escaping () -> Void) -> KeyboardActivation {
        KeyboardActivation(field: field, focus: $focus, action: action)
    }

    /// The Today window's keyboard pattern: a button takes Tab focus, Space and
    /// Return activate it, and focus shows an accent outline.
    private struct KeyboardActivation: ViewModifier {
        @State private var keyboardFocus = KeyboardFocusVisibility.shared
        let field: Field
        let focus: FocusState<Field?>.Binding
        let action: () -> Void

        func body(content: Content) -> some View {
            content
                .focusable()
                .keyboardFocusAppearance()
                .focused(focus, equals: field)
                .onKeyPress(keys: [.space, .return]) { _ in
                    action()
                    return .handled
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: focus.wrappedValue == field && keyboardFocus.isVisible ? 2 : 0)
                        .padding(-3)
                        .allowsHitTesting(false)
                }
        }
    }
}
