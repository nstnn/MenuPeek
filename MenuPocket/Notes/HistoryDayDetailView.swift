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

/// Read-only detail of one saved day. Progress always covers the whole day;
/// filters change visible rows only. Shared by History and Unfinished.
struct HistoryDayDetailView: View {
    let history: TaskHistoryState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading
            if history.daySnapshot != nil {
                Picker("Show", selection: Binding(get: { history.filter }, set: { history.setFilter($0) })) {
                    Text("All").tag(HistoryTaskFilter.all)
                    Text("Unfinished").tag(HistoryTaskFilter.unfinished)
                    Text("Completed").tag(HistoryTaskFilter.completed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
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
    }

    @ViewBuilder
    private var heading: some View {
        if let day = history.selectedDay {
            VStack(alignment: .leading, spacing: 8) {
                Text(day.label("EEEE, MMMM d, yyyy"))
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("historyDayTitle")
                if let progress = history.progress {
                    HStack(spacing: 12) {
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(Color.accentColor)
                                .frame(width: 120 * Double(progress.completed) / Double(max(progress.total, 1)))
                        }
                        .frame(width: 120, height: 4)
                        .accessibilityHidden(true)
                        Text("\(progress.completed)/\(progress.total) complete")
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
                .padding(.vertical, 8)
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
                    row(note)
                }
                .padding(.leading, 22)
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

    /// A status image, not a checkbox: historical tasks have no actions.
    private func row(_ note: Note) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: note.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(note.isCompleted ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            Text(note.text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 14))
        .foregroundStyle(note.isCompleted ? .secondary : .primary)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(note.isCompleted ? "Completed" : "Not completed"): \(note.text)")
        .accessibilityIdentifier("historyTaskRow-\(note.id)")
    }
}
