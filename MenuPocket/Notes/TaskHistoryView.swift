import SwiftUI

/// History's month controls, month calendar, and the selected day's read-only
/// detail. Wide windows place detail beside the calendar; narrow windows place
/// it below.
struct TaskHistoryView: View {
    let history: TaskHistoryState
    let isWide: Bool
    var calendarWidth: CGFloat = 380
    var state: DailyNotesState? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if isWide {
                HStack(alignment: .top, spacing: 28) {
                    calendarPane.frame(width: calendarWidth)
                    Divider()
                    HistoryDayDetailView(history: history, state: state)
                }
            } else {
                calendarPane
                Divider()
                HistoryDayDetailView(history: history, state: state)
            }
        }
    }

    private var calendarPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            monthControls
            TaskHistoryCalendarView(history: history)
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.15))
                        .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(Color.accentColor, lineWidth: 1) }
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text("Selected")
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text("Today")
                }
                Text("Completed / total")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
    }

    private var monthControls: some View {
        HStack(spacing: 8) {
            Text(history.month.start.label("MMMM yyyy"))
                .font(.headline)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("historyMonth")
            Spacer(minLength: 4)
            Button { try? history.showPreviousMonth() } label: {
                Image(systemName: "chevron.left")
            }
            .historyKeyAction { try? history.showPreviousMonth() }
            .help("Previous month")
            .accessibilityLabel("Previous month")
            .accessibilityIdentifier("historyPreviousMonth")
            Button { try? history.showNextMonth() } label: {
                Image(systemName: "chevron.right")
            }
            .historyKeyAction { try? history.showNextMonth() }
            .help("Next month")
            .accessibilityLabel("Next month")
            .accessibilityIdentifier("historyNextMonth")
            Button("This month") { try? history.thisMonth() }
                .historyKeyAction { try? history.thisMonth() }
                .accessibilityIdentifier("historyThisMonth")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(minHeight: 30)
    }
}
