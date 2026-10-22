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
    @State private var selection: Set<UUID> = []
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading
            if let state {
                if !eligibleNotes.isEmpty {
                    Button(selection.isEmpty ? "Continue today" : "Continue today (\(selection.count))") {
                        continueSelection(state)
                    }
                    .historyKeyAction { continueSelection(state) }
                    .disabled(selection.isEmpty || !state.hasLoadedToday)
                    .accessibilityIdentifier("continueHistoryTasks")
                }
                if let message = state.continuationMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(state.continuationFailed ? Color.red : Color.secondary)
                        .accessibilityIdentifier("historyContinuationMessage")
                }
            }
            if history.daySnapshot != nil {
                Picker("Show", selection: Binding(get: { history.filter }, set: { history.setFilter($0) })) {
                    Text("All").tag(HistoryTaskFilter.all)
                    Text("Unfinished").tag(HistoryTaskFilter.unfinished)
                    Text("Completed").tag(HistoryTaskFilter.completed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
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
                // Without a selection (e.g. a future month), say what to do next.
                Text(history.selectedDay == nil && history.dayIssue == nil ? "Choose a day from the calendar." : message)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("historyDetailMessage")
                if history.dayIssue != nil {
                    Button("Retry") { history.retryDay() }
                        .historyKeyAction { history.retryDay() }
                        .accessibilityLabel("Retry loading this day")
                        .accessibilityIdentifier("retryHistoryDay")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("historyDayDetail")
        .onChange(of: history.selectedDay) { _, _ in
            selection = []
            state?.clearContinuationMessage()
        }
        .onChange(of: history.filter) { _, _ in selection = [] }
        .onChange(of: history.today) { _, _ in selection = [] }
        .onChange(of: history.daySnapshot) { _, _ in
            selection.formIntersection(eligibleNotes.map(\.id))
        }
    }

    private var eligibleNotes: [Note] {
        guard state != nil else { return [] }
        return history.daySnapshot?.notes.filter { $0.isUnfinished && $0.dayKey < history.today.key } ?? []
    }

    private func continueSelection(_ state: DailyNotesState) {
        let sources = eligibleNotes.filter { selection.contains($0.id) }
        if state.continueHistoryTasks(sources, expectedToday: history.today) { selection = [] }
    }

    @ViewBuilder
    private var heading: some View {
        if let day = history.selectedDay {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(day.label("EEEE, MMMM d"))
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityLabel(day.label("EEEE, MMMM d, yyyy"))
                            .accessibilityIdentifier("historyDayTitle")
                        Text(day.label("yyyy"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let progress = history.progress {
                    HStack(spacing: 10) {
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(Color.accentColor)
                                .frame(width: 100 * Double(progress.completed) / Double(max(progress.total, 1)))
                        }
                        .frame(width: 100, height: 4)
                        .accessibilityHidden(true)
                        Text("\(progress.completed) of \(progress.total) complete")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("\(progress.completed) of \(progress.total) tasks complete")
                            .accessibilityIdentifier("historyDayProgress")
                    }
                }
            }
        } else if history.dayIssue == nil && history.monthSummaries != nil {
            Text("Select a day")
                .font(.title3.weight(.semibold))
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text(group.name)
                        .font(.system(size: 13, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(group.progress.completed)/\(group.progress.total)")
                        .font(.system(size: 12).monospacedDigit())
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
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 1)
                }
        }
    }

    /// Checkboxes select work to continue; they never change old completion.
    private func row(_ note: Note) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if state != nil, note.isUnfinished, note.dayKey < history.today.key {
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
                .accessibilityIdentifier("continueSelection-\(note.id)")
            } else if note.isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            } else {
                Circle().fill(Color.secondary)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
            }
            Text(note.text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(status(note))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 14))
        .foregroundStyle(note.isCompleted ? .secondary : .primary)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(status(note)): \(note.text)")
        .accessibilityIdentifier("historyTaskRow-\(note.id)")
    }

    private func status(_ note: Note) -> String {
        if let key = note.continuedOn, let day = try? GregorianDay(key: key) {
            return "Continued on \(day.label("MMM d, yyyy"))"
        }
        return note.isCompleted ? "Completed" : "Unfinished"
    }
}
