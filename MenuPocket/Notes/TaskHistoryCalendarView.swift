import SwiftUI

/// History's seven-column month selector. It renders HistoryMonthGrid from the
/// one month read already held by TaskHistoryState; cells never read storage.
/// Selecting a day reuses the shared read-only detail and keeps the current filter.
struct TaskHistoryCalendarView: View {
    let history: TaskHistoryState
    @FocusState private var focusedDay: GregorianDay?
    @Environment(\.historyScrollProxy) private var proxy

    /// A grid that cannot be built (mismatched summaries) shows Unavailable
    /// rather than invented counts.
    private var grid: HistoryMonthGrid? {
        (try? HistoryMonthGrid(month: history.month, today: history.today, selectedDay: history.selectedDay,
                               summaries: history.monthSummaries))
            ?? (try? HistoryMonthGrid(month: history.month, today: history.today, selectedDay: history.selectedDay,
                                      summaries: nil))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let issue = history.monthIssue {
                HStack(spacing: 12) {
                    Text(issue.message)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("historyMonthIssue")
                    Button("Retry") { history.retryMonth() }
                        .historyKeyAction { history.retryMonth() }
                        .accessibilityLabel("Retry loading this month")
                        .accessibilityIdentifier("retryHistoryMonth")
                }
            }
            if let grid {
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    GridRow {
                        ForEach(grid.weekdaySymbols, id: \.self) { symbol in
                            Text(symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    // Every cell already names its weekday.
                    .accessibilityHidden(true)
                    ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                        GridRow {
                            ForEach(week) { cell in
                                switch cell {
                                case .padding:
                                    // Blank filler: no focus, action, or accessibility element.
                                    // Every row and column also holds a day, which sizes the grid.
                                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]).accessibilityHidden(true)
                                case let .day(day):
                                    dayCell(day, in: grid)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(history.month.start.label("MMMM yyyy"))
        .accessibilityIdentifier("historyCalendar")
    }

    private func dayCell(_ cell: HistoryCalendarDay, in grid: HistoryMonthGrid) -> some View {
        let select = {
            guard cell.isSelectable else { return }
            try? history.select(cell.day, filter: history.filter)
        }
        return Button(action: select) {
            VStack(spacing: 2) {
                Text("\(cell.day.day)")
                    .font(.system(size: 13, weight: cell.isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(cell.isToday ? Color.white : cell.isFuture ? Color.secondary : Color.primary)
                    .frame(minWidth: 22, minHeight: 22)
                    .background {
                        // Today is a filled circle; selection is the cell outline.
                        if cell.isToday { Circle().fill(Color.accentColor) }
                    }
                Text(cell.countText)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .background(cell.isSelected ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                if cell.isSelected {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .focusable()
        .keyboardFocusAppearance()
        .focused($focusedDay, equals: cell.day)
        .id(cell.day.key)
        .onChange(of: focusedDay) { _, focused in
            if focused == cell.day { withAnimation(.easeOut(duration: 0.15)) { proxy?.scrollTo(cell.day.key) } }
        }
        .onKeyPress(keys: [.space, .return]) { _ in
            select()
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            let step = switch press.key {
            case .leftArrow: -1
            case .rightArrow: 1
            case .upArrow: -7
            default: 7
            }
            moveFocus(from: cell.day, by: step, in: grid)
            return .handled
        }
        .help(cell.statusText)
        .accessibilityLabel(accessibilityLabel(cell))
        .accessibilityRemoveTraits(cell.isSelectable ? [] : .isButton)
        .accessibilityAddTraits(cell.isSelected ? .isSelected : [])
        .accessibilityIdentifier("historyCalendarDay-\(cell.day.key)")
    }

    private func accessibilityLabel(_ cell: HistoryCalendarDay) -> String {
        var parts = [cell.day.label("EEEE, MMMM d, yyyy"), cell.statusText]
        if cell.isToday { parts.insert("Today", at: 0) }
        return parts.joined(separator: ", ")
    }

    /// Arrow keys move focus by day or week; leaving the month changes it with
    /// the usual selection clamping, then focuses the matching day there.
    private func moveFocus(from day: GregorianDay, by step: Int, in grid: HistoryMonthGrid) {
        let target = day.day + step
        do {
            if target < 1 {
                try history.showPreviousMonth()
                focus(try history.month.day(clampedTo: history.month.dayCount + target))
            } else if target > grid.month.dayCount {
                try history.showNextMonth()
                focus(try history.month.day(clampedTo: target - grid.month.dayCount))
            } else {
                focusedDay = try grid.month.day(clampedTo: target)
            }
        } catch {
            // The first or last representable month: keep focus where it is.
        }
    }

    /// The new month's cells appear in the next update, so focus them after it.
    private func focus(_ day: GregorianDay) {
        DispatchQueue.main.async { focusedDay = day }
    }
}
