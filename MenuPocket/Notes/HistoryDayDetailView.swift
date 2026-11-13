import SwiftUI

extension GregorianDay {
    /// English labels for the civil date itself. Formatting in UTC never shifts
    /// a saved day into the device's time zone.
    func label(_ format: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return key }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

extension EnvironmentValues {
    /// The browser's scroll proxy, so keyboard focus can bring a control into view.
    @Entry var historyScrollProxy: ScrollViewProxy?
    /// Lets sibling calendar/header controls cancel the detail's selection.
    @Entry var historySelectionCancelRequest: UUID?
}

/// Scrolls the browser just enough to reveal this control when it gains focus.
private struct HistoryFocusScroll: ViewModifier {
    @Environment(\.historyScrollProxy) private var proxy
    @FocusState private var focused: Bool
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .id(id)
            .onChange(of: focused) { _, isFocused in
                if isFocused { withAnimation(.easeOut(duration: 0.15)) { proxy?.scrollTo(id) } }
            }
    }
}

extension View {
    /// Space and Return activate a focusable button, as in Today.
    func historyKeyAction(_ action: @escaping () -> Void) -> some View {
        focusable()
            .keyboardFocusAppearance()
            .onKeyPress(keys: [.space, .return]) { _ in
                action()
                return .handled
            }
            .historyFocusScroll()
    }

    func historyFocusScroll() -> some View { modifier(HistoryFocusScroll()) }
}

/// Historical detail with explicit continuation of selected unfinished work.
/// Progress always covers the whole day;
/// filters change visible rows only. Shared by History and Unfinished.
struct HistoryDayDetailView: View {
    let history: TaskHistoryState
    var state: DailyNotesState? = nil
    var isWideLayout = true
    @State private var selection: Set<UUID> = []
    @State private var isSelecting = false
    @State private var selectionFocusRequest: UUID?
    private enum FocusControl: Hashable { case select, cancel, task(UUID) }
    @FocusState private var focusedControl: FocusControl?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.historyScrollProxy) private var scrollProxy
    @Environment(\.historySelectionCancelRequest) private var cancelRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading
            if let snapshot = history.daySnapshot, !snapshot.notes.isEmpty {
                SystemMonospaceSegmentedPicker(label: "Show",
                    selection: Binding(get: { history.filter }, set: { history.setFilter($0) }),
                    options: [(.all, "All"), (.unfinished, "Unfinished"), (.completed, "Completed")])
                .frame(maxWidth: 320, alignment: .leading)
                .focusable()
                .keyboardFocusAppearance()
                .historyFocusScroll()
                .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                    let filters = HistoryTaskFilter.allCases
                    let index = filters.firstIndex(of: history.filter) ?? 0
                    let next = min(max(index + (press.key == .rightArrow ? 1 : -1), 0), filters.count - 1)
                    history.setFilter(filters[next])
                    return .handled
                }
                .accessibilityLabel("Show tasks")
                .accessibilityIdentifier("historyFilter")
                ForEach(history.detailGroups) { group in
                    groupSurface(group)
                }
            }
            if let message = history.detailMessage {
                if history.daySnapshot?.notes.isEmpty == true {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No tasks saved")
                            .font(.headline.monospaced())
                            .accessibilityIdentifier("historyDetailMessage")
                        Text("Choose a marked day to see its tasks.")
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)
                } else {
                    // Keep read failures and empty filtered results distinct.
                    Text(history.selectedDay == nil && history.dayIssue == nil ? "Choose a day from the calendar." : message)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("historyDetailMessage")
                }
                if history.dayIssue != nil {
                    Button("Retry") { history.retryDay() }
                        .historyKeyAction { history.retryDay() }
                        .accessibilityLabel("Retry loading this day")
                        .accessibilityIdentifier("retryHistoryDay")
                }
            }
            if let state {
                if !visibleEligibleNotes.isEmpty {
                    continuationControls(state)
                }
                if let message = state.continuationMessage {
                    Text(message)
                        .font(.callout.monospaced())
                        .foregroundStyle(state.continuationFailed ? Color.red : Color.secondary)
                        .accessibilityIdentifier("historyContinuationMessage")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("historyDayDetail")
        .task(id: isWideLayout) {
            // A zoom/resize can move the focused checkbox below the calendar
            // without changing focus. Reveal it after the new layout settles.
            await Task.yield()
            guard !Task.isCancelled, isSelecting else { return }
            if case let .task(id) = focusedControl {
                scrollProxy?.scrollTo(id, anchor: .center)
            } else {
                scrollProxy?.scrollTo("historySelectionActions", anchor: .center)
            }
        }
        .task(id: selectionFocusRequest) {
            guard selectionFocusRequest != nil else { return }
            // The selector is reinserted after selection mode exits. Wait for
            // that update before asking AppKit to focus its new control.
            await Task.yield()
            guard !Task.isCancelled, !isSelecting, !visibleEligibleNotes.isEmpty else { return }
            focusedControl = .select
        }
        .onChange(of: history.selectedDay) { _, _ in
            resetSelection()
            state?.clearContinuationMessage()
        }
        .onChange(of: history.filter) { _, _ in resetSelection() }
        .onChange(of: history.today) { _, _ in resetSelection() }
        .onChange(of: cancelRequest) { _, _ in
            if isSelecting { cancelSelection() }
        }
        .onChange(of: history.daySnapshot) { _, _ in
            selection.formIntersection(eligibleNotes.map(\.id))
            if visibleEligibleNotes.isEmpty { resetSelection() }
        }
        .onKeyPress(.escape) {
            guard isSelecting else { return .ignored }
            cancelSelection()
            return .handled
        }
    }

    private var eligibleNotes: [Note] {
        guard state != nil else { return [] }
        return history.daySnapshot?.notes.filter { $0.isUnfinished && $0.dayKey < history.today.key } ?? []
    }

    private func continueSelection(_ state: DailyNotesState) {
        let sources = eligibleNotes.filter { selection.contains($0.id) }
        if state.continueHistoryTasks(sources, expectedToday: history.today) {
            resetSelection()
            selectionFocusRequest = UUID()
        }
    }

    private var visibleEligibleNotes: [Note] {
        let eligibleIDs = Set(eligibleNotes.map(\.id))
        return history.detailGroups.flatMap(\.visibleNotes).filter { eligibleIDs.contains($0.id) }
    }

    private func resetSelection() {
        selection = []
        isSelecting = false
        focusedControl = nil
        selectionFocusRequest = nil
    }

    private func beginSelection() {
        state?.clearContinuationMessage()
        isSelecting = true
        let eligibleIDs = Set(visibleEligibleNotes.map(\.id))
        let first = history.detailGroups
            .filter { !history.collapsedGroups.contains($0.group.id) }
            .flatMap(\.visibleNotes).first { eligibleIDs.contains($0.id) }
        focusedControl = first.map { .task($0.id) } ?? .cancel
    }

    private func cancelSelection() {
        resetSelection()
        selectionFocusRequest = UUID()
    }

    @ViewBuilder
    private func continuationControls(_ state: DailyNotesState) -> some View {
        if isSelecting {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { selectionActions(state) }
                VStack(alignment: .leading, spacing: 10) { selectionActions(state) }
            }
            .id("historySelectionActions")
            .padding(.top, 8)
        } else {
            Button("Select tasks to continue…", action: beginSelection)
                .buttonStyle(.daybook)
                .historyKeyAction(beginSelection)
                .focused($focusedControl, equals: .select)
                .accessibilityIdentifier("selectHistoryTasks")
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func selectionActions(_ state: DailyNotesState) -> some View {
        Text("\(selection.count) selected")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("historySelectionCount")
        Button("Cancel", action: cancelSelection)
            .historyKeyAction(cancelSelection)
            .focused($focusedControl, equals: .cancel)
            .accessibilityIdentifier("cancelHistorySelection")
        Button(selection.isEmpty ? "Continue today" : "Continue today (\(selection.count))") {
            continueSelection(state)
        }
        .buttonStyle(.daybookProminent)
        .historyKeyAction { continueSelection(state) }
        .disabled(selection.isEmpty || !state.hasLoadedToday)
        .accessibilityIdentifier("continueHistoryTasks")
    }

    @ViewBuilder
    private var heading: some View {
        if let day = history.selectedDay {
            VStack(alignment: .leading, spacing: 6) {
                Text(day.label("EEEE, MMM d"))
                    .font(.title3.weight(.medium).monospaced())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(day.label("EEEE, MMMM d, yyyy"))
                    .accessibilityIdentifier("historyDayTitle")
                if let progress = history.progress, progress.total > 0 {
                    Text("\(day.label("yyyy")) · \(progress.completed) of \(progress.total) completed")
                        .font(.system(size: 12, design: .monospaced).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(progress.completed) of \(progress.total) tasks complete")
                        .accessibilityIdentifier("historyDayProgress")
                } else {
                    Text(day.label("yyyy"))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        } else if history.dayIssue == nil && history.monthSummaries != nil {
            Text("Select a day")
                .font(.title3.weight(.semibold).monospaced())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("historyDayTitle")
        }
    }

    /// Group counts cover the whole group, including rows hidden by the filter.
    private func groupSurface(_ detail: HistoryDetailGroup) -> some View {
        let group = detail.group
        let collapsed = history.collapsedGroups.contains(group.id)
        let toggle = { history.toggleDisclosure(group.id) }
        return VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text(group.name)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(group.progress.completed)/\(group.progress.total)")
                        .font(.system(size: 12, design: .monospaced).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .historyKeyAction(toggle)
            .help(collapsed ? "Show tasks" : "Hide tasks")
            .accessibilityLabel("\(group.name), \(group.progress.completed) of \(group.progress.total) complete")
            .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
            .accessibilityIdentifier("historyGroup-\(group.id.storageKey)")
            if !collapsed {
                ForEach(detail.visibleNotes) { note in
                    Divider().accessibilityHidden(true)
                    row(note)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Checkboxes select work to continue; they never change old completion.
    private func row(_ note: Note) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if isSelecting, state != nil, note.isUnfinished, note.dayKey < history.today.key {
                Toggle("Select \(note.text) to continue today", isOn: Binding(
                    get: { selection.contains(note.id) },
                    set: { if $0 { selection.insert(note.id) } else { selection.remove(note.id) } }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .focusable()
                .keyboardFocusAppearance()
                .onKeyPress(keys: [.space, .return]) { _ in
                    if !selection.insert(note.id).inserted { selection.remove(note.id) }
                    return .handled
                }
                .historyFocusScroll()
                .focused($focusedControl, equals: .task(note.id))
                .accessibilityIdentifier("continueSelection-\(note.id)")
            } else if note.isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DaybookPalette.accent(colorScheme))
                    .accessibilityHidden(true)
            } else {
                Circle().fill(Color.secondary)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(note.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if note.continuedOn != nil {
                    Text(status(note))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 14, design: .monospaced))
        .foregroundStyle(note.isCompleted ? .secondary : .primary)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(status(note)): \(note.text)")
        .accessibilityIdentifier("historyTaskRow-\(note.id)")
        .id(note.id)
    }

    private func status(_ note: Note) -> String {
        if let key = note.continuedOn, let day = try? GregorianDay(key: key) {
            return "Continued on \(day.label("MMM d, yyyy"))"
        }
        return note.isCompleted ? "Completed" : "Unfinished"
    }
}
