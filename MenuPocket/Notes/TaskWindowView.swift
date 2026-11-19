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
        case add, manageCategories, retry, save, draft, category, cancelDelete, confirmDelete, calendar, history, yesterday
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
    var detailContent: AnyView? = nil
    @State private var rowActionOrigin: (id: UUID, groupID: TaskGroupID)?
    @State private var focusRequestID = UUID()
    @State private var editFocusRequestID: UUID?
    /// A menu-moved row whose actions regain focus once its reveal finishes.
    @State private var menuMoveFocusID: UUID?
    @State private var moveNoticeID = UUID()
    /// The list whose transfer notice is showing; nil hides it.
    @State private var moveNoticeDestination: TaskListDestination?
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
        observingMovement(observeWindow(taskWindow))
    }

    private var taskWindow: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 740 || geometry.size.height < 480
            HStack(spacing: 0) {
                daybookSidebar(compact: compact)
                    .frame(width: compact ? 164 : 218)
                Rectangle().fill(daybookRule).frame(width: 1).accessibilityHidden(true)
                ZStack {
                    listContent(geometry: geometry, compact: compact)
                        .opacity(detailContent == nil ? 1 : 0)
                        .allowsHitTesting(detailContent == nil)
                        .disabled(detailContent != nil)
                        .accessibilityHidden(detailContent != nil)
                    if let detailContent { detailContent }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { canvasBackground }
        .tint(daybookAccent)
        // Buttons without their own style (Save, Cancel, Retry, pane actions) use Daybook's.
        .buttonStyle(.daybook)
    }

    private func listContent(geometry: GeometryProxy, compact: Bool) -> some View {
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
                        Text(isLater ? "Moved task to Today." : "Moved task to Later.")
                            .font(.callout.monospaced())
                            .accessibilityIdentifier(identifier("todayMoveNotice", "laterMoveNotice"))
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
    }

    private func observeWindow(_ content: some View) -> some View {
        content
        .onChange(of: presentation.route) { old, new in
            focusRequestID = UUID()
            if new != .today { focusedControl = nil }
            else if old != .today {
                let requestID = focusRequestID
                Task { @MainActor in
                    await Task.yield()
                    guard presentation.route == .today, detailContent == nil, focusRequestID == requestID else { return }
                    if isLater { focusSelectedList(); return }
                    // Returning focuses the sidebar entry that opened the pane.
                    if old == .calendar { focusedControl = .calendar; return }
                    focusedControl = state.availableProgress == nil ? .retry
                        : (presentation.historyEntry == .yesterday && state.yesterdayIncompleteCount > 0 ? .yesterday : .history)
                }
            }
        }
        .onChange(of: presentation.isManagingCategories) { wasManaging, isManaging in
            if wasManaging, !isManaging, detailContent == nil { focusManageCategories() }
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
            guard moveNoticeDestination != nil else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            moveNoticeDestination = nil
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
                                    .font(.callout.weight(.semibold).monospaced())
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
        case .moveToLater: "Could not move task to Later. Try again."
        default: nil
        }
    }

    // Presentation only: every control still uses the existing guarded command.
    private func daybookSidebar(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 18 : 28) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dayLabels.weekday.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Text(daybookDate.day)
                    .font(.system(size: compact ? 52 : 76, design: .monospaced))
                    .tracking(-3)
                Text(daybookDate.month)
                    .font(.system(size: compact ? 16 : 20, design: .monospaced))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(dayLabels.weekday), \(dayLabels.date)")
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("daybookDate")
            destinationControl
            daybookProgress
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                calendarButton
                Rectangle().fill(daybookRule).frame(height: 1)
                    .padding(.vertical, 4)
                    .accessibilityHidden(true)
                historyButton
                categoryManagerButton
                Button(action: onSettings) {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .disabled(!presentation.canNavigate(state: state))
                .foregroundStyle(presentation.isShowingSettings ? daybookAccent : Color.secondary)
                .help("Open Settings (⌘,)")
                .accessibilityLabel("Open Settings")
            }
            .font(.system(size: 14, design: .monospaced))
            .labelStyle(DaybookNavLabelStyle())
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
        DaybookDestinationControl(selection: Binding(
            get: { destination },
            set: { _ = presentation.selectDestination($0, state: state) }
        ))
        .disabled(state.editingNoteID != nil || state.editingLaterTaskID != nil ||
                  !presentation.canNavigate(state: state))
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
                    Text("\(progress.completed)/\(progress.total) done today")
                        .font(.system(size: 11, design: .monospaced).monospacedDigit())
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
                Text(isLater ? "Later" : "Today")
                    .font(.system(size: 32, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if isLater {
                    Text(state.availableLaterRemainingCount.map { "\($0) \($0 == 1 ? "task" : "tasks") remaining" } ?? "Tasks unavailable")
                        .font(.system(size: 12, design: .monospaced))
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
                        Text("⌘N").font(.caption.monospaced()).accessibilityHidden(true)
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
            Label("History", systemImage: "clock.arrow.circlepath")
        }
        .focusable()
        .keyboardFocusAppearance()
        .focused($focusedControl, equals: .history)
        .onKeyPress(keys: [.space, .return]) { _ in
            openHistory(.calendar)
            return .handled
        }
        .disabled(!canOpenHistory)
        .foregroundStyle(presentation.isShowingHistory ? daybookAccent : Color.secondary)
        .help("View task history")
        .accessibilityLabel("View task history")
        .accessibilityIdentifier("taskHistoryEntry")
    }

    /// Calendar sits beside Today and Later rather than under Today, so it opens
    /// from either list and leaves the selected list as it was.
    private var calendarButton: some View {
        Button(action: openCalendar) {
            Label("Calendar", systemImage: "calendar")
        }
        .focusable()
        .keyboardFocusAppearance()
        .focused($focusedControl, equals: .calendar)
        .onKeyPress(keys: [.space, .return]) { _ in
            openCalendar()
            return .handled
        }
        .disabled(!presentation.canShowCalendar(state: state))
        .foregroundStyle(presentation.isShowingCalendar ? daybookAccent : Color.secondary)
        .help("Open Calendar")
        .accessibilityLabel("Open Calendar")
        .accessibilityIdentifier("calendarEntry")
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
        .foregroundStyle(presentation.isManagingCategories ? daybookAccent : Color.secondary)
        .help("Manage categories")
        .accessibilityLabel("Manage categories")
        .accessibilityIdentifier("manageCategories")
    }

    private var daybookDate: (day: String, month: String) {
        // These are components of the saved civil date, never a new time-zone conversion.
        let parts = (state.todayKey ?? NoteDay().keys().today).split(separator: "-")
        let month = dayLabels.date.split(separator: " ").first.map(String.init) ?? ""
        return (parts.last.map(String.init) ?? "", "\(month) \(parts.first.map(String.init) ?? "")")
    }

    private var hasComposer: Bool {
        presentation.deletionTarget == nil && editingID == nil &&
            presentation.hasNewTaskComposer(in: destination, state: state)
    }

    private var topWriteError: String? {
        editingID != nil && issue == .edit ? nil : writeError
    }

    private var hasMoveNotice: Bool {
        moveNoticeDestination == destination && issue != (isLater ? .moveToToday : .moveToLater)
    }

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
                .font(.title3.weight(.semibold).monospaced())
            Text(isLater ? "Tasks saved for later will appear here." : "Today's tasks will appear here.")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
        .accessibilityIdentifier(identifier("todayEmptyState", "laterEmptyState"))
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tasks are unavailable")
                .font(.title3.weight(.semibold).monospaced())
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
        let notice = isLater ? state.laterRefreshNotice : state.refreshNotice
        let recovered = isLater ? state.laterRecoveredEdit : state.recoveredEdit
        let visibleNotice = notice == "Moved task to Today." ? nil : notice
        if visibleNotice != nil || recovered != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let visibleNotice {
                    Text(visibleNotice)
                        .font(.callout.monospaced())
                }
                if let recovered {
                    Text("Unsaved edit")
                        .font(.callout.weight(.semibold).monospaced())
                    Text(recovered.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    // The name captured at cancellation, so a removed category still shows.
                    if let name = recovered.categoryID == nil ? TaskCategoryName.general : recovered.categoryName {
                        Text("Category: \(name)")
                            .font(.callout.monospaced())
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
                        .font(.caption.monospaced())
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
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: Self.groupRowIndent - 8)
                Text(group.name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(isLater ? "\(progress.total - progress.completed) remaining" : "\(progress.completed)/\(progress.total)")
                    .font(.system(size: 12, design: .monospaced).monospacedDigit())
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
            .font(.system(size: 14, design: .monospaced))
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
                            onMoveToLater: !isLater && !note.isCompleted && note.continuedOn == nil ? { moveToLater(note.id) } : nil,
                            moves: { isLater ? nil : presentation.menuMoves(for: note.id, state: state) },
                            onMove: moveFromMenu)
            .focused($focusedControl, equals: .actions(note.id))
            .overlay { focusOutline(focusedControl == .actions(note.id)) }
            .disabled(editingID != nil)
            .help("Task actions")
            .accessibilityLabel("Actions for task: \(note.text)")
            .accessibilityHint(isLater ? (note.isCompleted ? "Opens Edit and Delete actions"
                                                           : "Opens Move to Today, Edit and Delete actions")
                                       : (!note.isCompleted ? "Opens Move to Later, Edit, Move, and Delete actions"
                                                            : "Opens Edit, Move, and Delete actions"))
            .accessibilityIdentifier("\(isLater ? "laterTaskActions" : "taskActions")-\(note.id)")
        }
        .font(.system(size: 14, design: .monospaced))
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
                    .buttonStyle(.daybookProminent)
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
    /// first as in Today. The capsule opens the same Daybook popover as row
    /// actions. With keyboard focus, Up and Down step the selection and
    /// Space/Return open the popover; choosing a category never saves the draft.
    private func categoryPicker(editing: Bool) -> some View {
        HStack(spacing: 8) {
            Text("Category")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TaskCategoryPicker(options: TaskCategoryOption.ordered(categories: state.categories),
                               selection: categoryBinding(editing: editing),
                               onStep: { stepCategory(by: $0, editing: editing) })
                .focused($focusedControl, equals: .category)
                .overlay { focusOutline(focusedControl == .category) }
                .disabled(state.availableCategories == nil)
                .help(editing ? "Category for this task" : "Category for the new task")
                .accessibilityIdentifier(isLater ? (editing ? "editLaterTaskCategory" : "newLaterTaskCategory") : (editing ? "editTaskCategory" : "newTaskCategory"))
        }
        // A long name truncates in the control instead of crowding Save and Cancel.
        .frame(maxWidth: 280, alignment: .leading)
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
            Text("Delete task?").font(.headline.monospaced())
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
                .buttonStyle(.daybookProminent)
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
            moveNoticeDestination = .later
            moveNoticeID = UUID()
            restoreRowFocus(id, fallbackGroup: group.id)
        }
    }

    private func moveToLater(_ id: UUID) {
        guard !isLater, canUseRowActions,
              let group = groups.first(where: { $0.notes.contains { $0.id == id } }) else { return }
        rowActionOrigin = (id, group.id)
        if state.moveTodayToLater(id: id) {
            moveNoticeDestination = .today
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

    private func openCalendar() {
        guard presentation.showCalendar(state: state) else { return }
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

    /// After the category pane closes: its entry button, or Retry if data became unavailable.
    private func focusManageCategories() {
        Task { @MainActor in
            await Task.yield()
            guard detailContent == nil else { return }
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

    private var canvasBackground: some View { DaybookPalette.canvas(colorScheme) }

    private var daybookRail: Color { DaybookPalette.rail(colorScheme) }

    private var daybookAccent: Color { DaybookPalette.accent(colorScheme) }

    private var daybookRule: Color { DaybookPalette.rule(colorScheme) }

    private func focusOutline(_ focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.accentColor, lineWidth: focused && keyboardFocus.isVisible ? 2 : 0)
            .padding(-3)
            .allowsHitTesting(false)
    }
}

/// A focusable SwiftUI trigger for the row's Daybook actions popover, opened
/// the same way by mouse and keyboard. A separate focus wrapper around SwiftUI's
/// Menu does not reliably open it with Space/Return; use the same button key
/// handling as other row controls.
private struct TaskActionsMenu: View {
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    var onMoveToToday: (() -> Void)? = nil
    var onMoveToLater: (() -> Void)? = nil
    /// Read when the popover opens, so entries reflect the current saved order.
    /// Nil omits the Today movement items.
    var moves: () -> TaskWindowPresentation.MenuMoves? = { nil }
    var onMove: (TaskMoveRequest) -> Void = { _ in }
    @State private var anchor = TaskMenuAnchor.Reference()
    @State private var isHovered = false
    @State private var isOpen = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isActive = isEnabled && (isHovered || isOpen)
        let accent = DaybookPalette.accent(colorScheme)
        Button { showMenu(fromKeyboard: false) } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 28, height: 28)
                .foregroundStyle(isActive ? accent : Color.secondary)
                .background {
                    Circle().fill(accent.opacity(isOpen ? (colorScheme == .dark ? 0.22 : 0.16)
                                                        : isActive ? (colorScheme == .dark ? 0.14 : 0.10) : 0))
                }
                .contentShape(Circle())
                .animation(.easeOut(duration: 0.12), value: isActive)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .focusable()
        .keyboardFocusAppearance()
        .onKeyPress(keys: [.space, .return], phases: [.down, .repeat, .up]) { press in
            // Let the initiating key finish before the popover takes the keyboard;
            // subsequent Return/Space belong to the popover, not its trigger.
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
        guard !anchor.presenter.isOpen, let view = anchor.view, view.window != nil else { return }
        onOpen()
        isOpen = true
        anchor.presenter.present(rows: rows(), from: view, highlight: fromKeyboard ? .first : .none) { selection in
            isOpen = false
            // Finish closing the popover before changing the SwiftUI hierarchy, so
            // the task window's restored key status cannot override draft/Cancel focus.
            switch selection {
            case .moveToToday: DispatchQueue.main.async { onMoveToToday?() }
            case .moveToLater: DispatchQueue.main.async { onMoveToLater?() }
            case .edit: DispatchQueue.main.async { onEdit() }
            case .delete: DispatchQueue.main.async { onDelete() }
            case let .move(request): DispatchQueue.main.async { onMove(request) }
            case .category, nil: break
            }
        }
    }

    private func rows() -> [TaskActionRow] {
        var rows: [TaskActionRow] = []
        if onMoveToToday != nil {
            rows.append(.item(.init(id: "moveToToday", title: "Move to Today", accessibilityLabel: "Move to Today",
                                    symbol: "sun.max", selection: .moveToToday)))
            rows.append(.separator("today"))
        }
        if onMoveToLater != nil {
            rows.append(.item(.init(id: "moveToLater", title: "Move to Later", accessibilityLabel: "Move to Later",
                                    symbol: "tray", selection: .moveToLater)))
            rows.append(.separator("later"))
        }
        rows.append(.item(.init(id: "edit", title: "Edit", accessibilityLabel: "Edit",
                                symbol: "pencil", selection: .edit)))
        if let moves = moves() {
            rows.append(.separator("moves"))
            rows.append(.item(.init(id: "moveUp", title: "Move Up", accessibilityLabel: "Move Up",
                                    symbol: "arrow.up", isEnabled: moves.moveUp != nil,
                                    selection: moves.moveUp.map(TaskActionSelection.move))))
            rows.append(.item(.init(id: "moveDown", title: "Move Down", accessibilityLabel: "Move Down",
                                    symbol: "arrow.down", isEnabled: moves.moveDown != nil,
                                    selection: moves.moveDown.map(TaskActionSelection.move))))
            rows.append(.header("Move To"))
            for destination in moves.destinations {
                rows.append(.item(.init(id: "moveTo-\(destination.group.storageKey)", title: destination.title,
                                        accessibilityLabel: "Move to \(destination.title)", symbol: nil,
                                        isEnabled: destination.request != nil, isCurrent: destination.isCurrent,
                                        selection: destination.request.map(TaskActionSelection.move))))
            }
        }
        rows.append(.separator("delete"))
        rows.append(.item(.init(id: "delete", title: "Delete…", accessibilityLabel: "Delete…",
                                symbol: "trash", isDestructive: true, selection: .delete)))
        return rows
    }
}

/// The composer's category control: a Daybook capsule showing the selected
/// category that opens a popover listing General and every custom category,
/// with the current one checked.
private struct TaskCategoryPicker: View {
    let options: [TaskCategoryOption]
    @Binding var selection: UUID?
    let onStep: (Int) -> Void
    @State private var anchor = TaskMenuAnchor.Reference()
    @State private var isHovered = false
    @State private var isOpen = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    private var selectedName: String {
        options.first(where: { $0.categoryID == selection })?.name ?? "General"
    }

    var body: some View {
        let isActive = isEnabled && (isHovered || isOpen)
        let accent = DaybookPalette.accent(colorScheme)
        Button { open(fromKeyboard: false) } label: {
            HStack(spacing: 6) {
                Text(selectedName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isActive ? accent : Color.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isActive ? accent : Color.secondary)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .font(.system(size: 13, design: .monospaced))
            .padding(.horizontal, 12)
            .frame(minHeight: 26)
            .background {
                Capsule().fill(accent.opacity(isOpen ? (colorScheme == .dark ? 0.20 : 0.14)
                                                     : isActive ? (colorScheme == .dark ? 0.12 : 0.08) : 0))
            }
            .overlay {
                Capsule().strokeBorder(isActive ? accent.opacity(0.5) : DaybookPalette.rule(colorScheme),
                                       lineWidth: 1)
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.12), value: isActive)
            .animation(.easeOut(duration: 0.15), value: isOpen)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .focusable()
        .keyboardFocusAppearance()
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            if anchor.presenter.isOpen { return .ignored }
            onStep(press.key == .downArrow ? 1 : -1)
            return .handled
        }
        .onKeyPress(keys: [.space, .return], phases: [.down, .repeat, .up]) { press in
            // Open on key release so the opening key never reaches the popover.
            if anchor.presenter.isOpen { return .ignored }
            if press.phase == .down {
                anchor.opensOnKeyUp = true
            } else if press.phase == .up {
                guard anchor.opensOnKeyUp else { return .ignored }
                anchor.opensOnKeyUp = false
                open(fromKeyboard: true)
            }
            return .handled
        }
        .background {
            TaskMenuAnchor(reference: anchor)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onDisappear { anchor.presenter.close(with: nil) }
        .accessibilityLabel("Category")
        .accessibilityValue(selectedName)
        .accessibilityHint("Opens the category list")
    }

    private func optionID(_ option: TaskCategoryOption) -> String { option.id.storageKey }

    private func open(fromKeyboard: Bool) {
        guard isEnabled, !anchor.presenter.isOpen, let view = anchor.view, view.window != nil else { return }
        let rows: [TaskActionRow] = options.map { option in
            .item(.init(id: optionID(option), title: option.name, accessibilityLabel: option.name,
                        symbol: nil, isCurrent: option.categoryID == selection,
                        selection: .category(option.categoryID)))
        }
        let current = options.first(where: { $0.categoryID == selection }).map(optionID)
        isOpen = true
        anchor.presenter.present(
            rows: rows, from: view,
            highlight: fromKeyboard ? current.map { .item($0) } ?? .first : .none,
            alignment: .leading,
            labels: .init(popover: "Categories", identifier: "categoryPopover", itemPrefix: "categoryOption-",
                          currentValue: "Selected")
        ) { choice in
            isOpen = false
            if case let .category(id) = choice { selection = id }
        }
    }
}

/// Shared anchor for the task, composer and category actions popovers.
struct TaskMenuAnchor: NSViewRepresentable {
    // The anchor is layout plumbing, not observable UI state. Updating a binding
    // when it mounts can interrupt the parent window's sheet dismissal.
    @MainActor final class Reference {
        weak var view: NSView?
        let presenter = TaskActionsPresenter()
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

/// Today/Later switch on a quiet paper track: the selected segment is a raised
/// canvas-colored thumb with accent text, the other is secondary text. Assistive
/// technologies and the fixture driver still see the native segmented picker
/// (`taskDestination`, `todayTab`, `laterTab`) through its representation.
private struct DaybookDestinationControl: View {
    @Binding var selection: TaskListDestination
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Namespace private var thumb
    @State private var hovered: TaskListDestination?

    var body: some View {
        HStack(spacing: 0) {
            segment(.today, "Today")
            segment(.later, "Later")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.06))
        )
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.snappy(duration: 0.18), value: selection)
        .accessibilityRepresentation {
            Picker("Task list", selection: $selection) {
                Text("Today").tag(TaskListDestination.today).accessibilityIdentifier("todayTab")
                Text("Later").tag(TaskListDestination.later).accessibilityIdentifier("laterTab")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityValue(selection == .later ? "Later" : "Today")
            .accessibilityIdentifier("taskDestination")
        }
    }

    /// Light: the canvas paper raised off the rail. Dark: a lighter wash, so the
    /// thumb still reads as raised rather than recessed.
    private var thumbFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : DaybookPalette.canvas(colorScheme)
    }

    private func segment(_ option: TaskListDestination, _ title: String) -> some View {
        let isSelected = selection == option
        return Button { selection = option } label: {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular, design: .monospaced))
                .foregroundStyle(isSelected ? DaybookPalette.accent(colorScheme)
                                 : hovered == option && isEnabled ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(thumbFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(DaybookPalette.rule(colorScheme), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 1, y: 0.5)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = option } else if hovered == option { hovered = nil }
        }
    }
}

/// Sidebar footer rows: a fixed icon column so labels align, and a full-width hit area.
private struct DaybookNavLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon
                .font(.system(size: 16, design: .monospaced))
                .frame(width: 22, alignment: .center)
            configuration.title
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
