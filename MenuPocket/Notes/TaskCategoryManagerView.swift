import SwiftUI

/// Detail pane in the task window for creating, renaming, and removing
/// custom categories. Saved categories come only from shared state. Name drafts
/// stay in this pane, apart from task drafts, and are discarded when it closes.
struct TaskCategoryManagerView: View {
    private enum Field: Hashable {
        case newName, create, done, retry
        case rename(UUID), actions(UUID)
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
    @State private var categoryListHeight: CGFloat = 1
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
        .padding(28)
        .frame(maxWidth: 660, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .font(.system(size: 14, design: .monospaced))
        .background { DaybookPalette.canvas(colorScheme) }
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
        .onDisappear {
            presentation.cancelCategoryMovement()
            presentation.setManagerRenaming(nil)
        }
    }

    private var manager: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Categories")
                        .font(.system(size: 28, weight: .medium, design: .monospaced))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 12)
                    Button("Done", action: dismiss)
                        .modifier(keyboard(.done, dismiss))
                        // While renaming, Escape belongs to the rename's Cancel.
                        .keyboardShortcut(renamingID == nil ? KeyboardShortcut.cancelAction : nil)
                        .accessibilityIdentifier("doneManagingCategories")
                }
                Text("Shared by Today, Later & saved days.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 8)
            if let categories = state.availableCategories {
                categoryList(categories)
                newCategoryRow
                    .padding(.top, 4)
                Text("General can’t be renamed or removed.\nDrag the handle to reorder your categories.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                unavailableState
            }
            if let message = state.categoryIssue?.message {
                Text(message)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("categoryCommandError")
            }
            if let message = state.categoryReorderIssue?.message {
                Text(message)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("categoryReorderError")
            }
            Spacer(minLength: 0)
        }
    }

    private func categoryList(_ categories: [TaskCategory]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(TaskCategoryOption.ordered(categories: categories)) { option in
                        switch option {
                        case .general:
                            generalRow
                                .overlay { categoryTarget(.general, categories: categories) }
                        case let .custom(category):
                            DaybookPalette.rule(colorScheme)
                                .frame(height: 1)
                                .accessibilityHidden(true)
                            categoryRow(category)
                                .overlay { categoryTarget(.category(category.id), categories: categories) }
                                .id(category.id)
                        }
                    }
                    if categories.isEmpty {
                        Text("No custom categories yet.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: CategoryListHeight.self, value: geometry.size.height)
                    }
                }
            }
            // Hug short catalogs; the list alone gives up height and scrolls
            // when the window cannot fit every row and the creation controls.
            .frame(maxHeight: max(1, categoryListHeight))
            .background { DaybookPalette.rail(colorScheme).opacity(0.5) }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(DaybookPalette.rule(colorScheme), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .onPreferenceChange(CategoryListHeight.self) { categoryListHeight = $0 }
            .accessibilityIdentifier("categoryList")
            .onChange(of: createdID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
            .onChange(of: presentation.categoryMovementReveal) { _, request in
                guard let request, request.context == .manager else { return }
                Task { @MainActor in
                    defer { presentation.consumeCategoryMovementReveal(request) }
                    await Task.yield()
                    guard presentation.isCategoryMovementRevealValid(request, state: state) else { return }
                    proxy.scrollTo(request.categoryID)
                }
            }
            .onChange(of: focus) { _, field in
                // Confirmation replaces the list. Bring its restored row focus
                // back into view when the list returns, including after a failure.
                switch field {
                case let .rename(id), let .actions(id): proxy.scrollTo(id)
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
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 14) {
                    HStack(spacing: 2) {
                        ForEach(0..<2) { _ in
                            VStack(spacing: 2) {
                                ForEach(0..<3) { _ in
                                    Circle().frame(width: 2, height: 2)
                                }
                            }
                        }
                    }
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text(category.name)
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay {
                        CategoryDragSource(name: category.name, categoryID: category.id, context: .manager,
                                           state: state, session: presentation.categoryDragSession,
                                           enabled: presentation.canReorderCategories(in: .manager, state: state),
                                           count: { state.categoryUsageCount(id: category.id) })
                            .accessibilityHidden(true)
                    }
                Button("Rename") { beginRename(category) }
                    .modifier(keyboard(.rename(category.id)) { beginRename(category) })
                    .fixedSize()
                    .accessibilityLabel("Rename \(category.name)")
                    .accessibilityIdentifier("renameCategory-\(category.id)")
                CategoryActionsMenu(category: category, onRemove: { requestRemoval(category) }, onDismiss: {
                    focus = .actions(category.id)
                })
                    .focused($focus, equals: .actions(category.id))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            // One rename at a time, so an unsaved name is never silently replaced.
            .disabled(renamingID != nil)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("categoryRow-\(category.id)")
        }
    }

    private func categoryTarget(_ group: TaskGroupID, categories: [TaskCategory]) -> some View {
        CategoryDropTarget(state: state, session: presentation.categoryDragSession,
                           context: .manager, group: group,
                           firstCustomID: categories.first?.id)
            .accessibilityHidden(true)
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
                    .buttonStyle(.daybookProminent)
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
        .padding(16)
    }

    /// General has no saved row, so it has no actions.
    private var generalRow: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(TaskCategoryName.general)
                    .fontWeight(.medium)
                Text("For tasks without a category.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Text("Built-in")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(DaybookPalette.rule(colorScheme), lineWidth: 1)
                }
                .fixedSize()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("generalCategory")
    }

    private var newCategoryRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New category")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Category name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .newName)
                    .onSubmit(create)
                    .onExitCommand(perform: handleEscape)
                    .accessibilityLabel("New category name")
                    .accessibilityIdentifier("newCategoryName")
                Button("Create", action: create)
                    .buttonStyle(.daybookProminent)
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
                .font(.headline.monospaced())
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
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("categoryNameError")
        }
    }

    private func removalConfirmation(_ target: TaskWindowPresentation.CategoryRemovalTarget) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remove category?")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .accessibilityAddTraits(.isHeader)
            // Names have no length limit. Scroll the full name independently
            // so the all-days notice and actions stay visible in this sheet.
            ScrollView {
                Text(target.name)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: .infinity)
            .background { insetSurface }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("categoryRemovalName")
            Text(Self.removalMessage(usageCount: target.usageCount))
                .font(.system(size: 13, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
            if target.countChanged {
                Text("The number of tasks changed. Review it and confirm again.")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
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
                    .buttonStyle(.daybookProminent)
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
        presentation.setManagerRenaming(category.id)
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
        presentation.setManagerRenaming(nil)
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

    /// The row's actions button while the category exists, otherwise the name field.
    private func restoreFocusAfterRemoval(_ id: UUID) {
        Task { @MainActor in
            await Task.yield()
            guard let categories = state.availableCategories else {
                focus = .retry
                return
            }
            focus = categories.contains(where: { $0.id == id }) ? .actions(id) : .newName
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

private struct CategoryListHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Use the existing Daybook popover so pointer and keyboard activation share
/// the same dismissal and focus behavior as the task row actions.
private struct CategoryActionsMenu: View {
    let category: TaskCategory
    let onRemove: () -> Void
    let onDismiss: () -> Void
    @State private var anchor = TaskMenuAnchor.Reference()
    @State private var isHovered = false
    @State private var isOpen = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let accent = DaybookPalette.accent(colorScheme)
        let active = isEnabled && (isHovered || isOpen)
        Button { showMenu(fromKeyboard: false) } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 28, height: 28)
                .foregroundStyle(active ? accent : Color.secondary)
                .background {
                    Circle().fill(accent.opacity(isOpen ? 0.18 : active ? 0.10 : 0))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("More actions for \(category.name)")
        .accessibilityLabel("Actions for category: \(category.name)")
        .accessibilityIdentifier("categoryActions-\(category.id)")
        .onHover { isHovered = $0 }
        .focusable()
        .keyboardFocusAppearance()
        .onKeyPress(keys: [.space, .return], phases: [.down, .repeat, .up]) { press in
            if anchor.presenter.isOpen { return .ignored }
            if press.phase == .down {
                anchor.opensOnKeyUp = true
            } else if press.phase == .up {
                guard anchor.opensOnKeyUp else { return .ignored }
                anchor.opensOnKeyUp = false
                showMenu(fromKeyboard: true)
            }
            return .handled
        }
        .background {
            TaskMenuAnchor(reference: anchor)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onDisappear { anchor.presenter.close(with: nil) }
    }

    private func showMenu(fromKeyboard: Bool) {
        guard isEnabled, !anchor.presenter.isOpen, let view = anchor.view, view.window != nil else { return }
        isOpen = true
        let remove = TaskActionRow.item(.init(
            id: "removeCategory-\(category.id)", title: "Remove…",
            accessibilityLabel: "Remove \(category.name)", symbol: "trash",
            isDestructive: true, selection: .delete))
        anchor.presenter.present(
            rows: [remove], from: view, highlight: fromKeyboard ? .first : .none,
            labels: .init(popover: "Category actions", identifier: "categoryActionsPopover", itemPrefix: ""),
            onKeyboardDismiss: {
                // An outside click/scroll owns its destination focus. Only a
                // keyboard dismissal should explicitly restore this trigger.
                DispatchQueue.main.async { onDismiss() }
            }) { selection in
                isOpen = false
                // Let the task window regain key status before the confirmation
                // mounts and focuses its Cancel button.
                if case .delete = selection { DispatchQueue.main.async { onRemove() } }
            }
    }
}
