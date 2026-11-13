import SwiftUI

/// History's month controls, month calendar, and the selected day's read-only
/// detail. Wide windows place detail beside the calendar; narrow windows place
/// it below.
struct TaskHistoryView: View {
    let history: TaskHistoryState
    let isWide: Bool
    var calendarWidth: CGFloat = 260
    var state: DailyNotesState? = nil

    var body: some View {
        // Changing layout must not replace day detail and discard a pending
        // continuation selection when the window crosses the width threshold.
        let layout = isWide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
        layout {
            calendarPane
                .frame(width: isWide ? calendarWidth : nil)
                .frame(maxWidth: isWide ? nil : 280, alignment: .leading)
            Rectangle()
                .fill(.quaternary)
                .frame(width: isWide ? 1 : nil, height: isWide ? nil : 1)
                .accessibilityHidden(true)
            HistoryDayDetailView(history: history, state: state, isWideLayout: isWide)
        }
    }

    private var calendarPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            monthControls
            TaskHistoryCalendarView(history: history)
            Text("• Has tasks · Today: \(history.today.label("MMM d"))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Button("This month") { try? history.thisMonth() }
                .historyKeyAction { try? history.thisMonth() }
                .accessibilityIdentifier("historyThisMonth")
        }
    }

    private var monthControls: some View {
        HStack(spacing: 8) {
            Text(history.month.start.label("MMMM yyyy"))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
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
        }
        .frame(minHeight: 30)
    }
}
