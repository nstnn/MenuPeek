import SwiftUI

/// History's month controls, month calendar, and the selected day's read-only
/// detail. Wide windows place detail beside the calendar; narrow windows place
/// it below.
struct TaskHistoryView: View {
    let history: TaskHistoryState
    let isWide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            monthControls
            if isWide {
                HStack(alignment: .top, spacing: 24) {
                    TaskHistoryCalendarView(history: history).frame(width: 380)
                    Divider()
                    HistoryDayDetailView(history: history)
                }
            } else {
                TaskHistoryCalendarView(history: history)
                Divider()
                HistoryDayDetailView(history: history)
            }
        }
    }

    private var monthControls: some View {
        HStack(spacing: 8) {
            Button { try? history.showPreviousMonth() } label: {
                Image(systemName: "chevron.left")
            }
            .historyKeyAction { try? history.showPreviousMonth() }
            .help("Previous month")
            .accessibilityLabel("Previous month")
            .accessibilityIdentifier("historyPreviousMonth")
            Text(history.month.start.label("MMMM yyyy"))
                .font(.headline)
                .frame(minWidth: 140)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("historyMonth")
            Button { try? history.showNextMonth() } label: {
                Image(systemName: "chevron.right")
            }
            .historyKeyAction { try? history.showNextMonth() }
            .help("Next month")
            .accessibilityLabel("Next month")
            .accessibilityIdentifier("historyNextMonth")
            Spacer(minLength: 8)
            Button("This month") { try? history.thisMonth() }
                .historyKeyAction { try? history.thisMonth() }
                .accessibilityIdentifier("historyThisMonth")
        }
        .buttonStyle(.bordered)
    }
}
