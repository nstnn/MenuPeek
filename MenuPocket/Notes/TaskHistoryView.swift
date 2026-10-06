import SwiftUI

/// History's month controls, days with saved tasks, and the selected day's
/// read-only detail. Wide windows place detail beside the list; narrow windows
/// place it below.
struct TaskHistoryView: View {
    let history: TaskHistoryState
    let isWide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            monthControls
            if isWide {
                HStack(alignment: .top, spacing: 24) {
                    dateList.frame(width: 220)
                    Divider()
                    HistoryDayDetailView(history: history)
                }
            } else {
                dateList
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

    @ViewBuilder
    private var dateList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Days with tasks")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            if let summaries = history.monthSummaries {
                // Newest first, so recent days lead the list.
                let days = summaries.filter { $0.progress.total > 0 }.reversed()
                if days.isEmpty {
                    Text("No saved tasks this month.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("historyMonthEmpty")
                } else {
                    ForEach(Array(days), id: \.day) { summary in
                        dayRow(summary)
                    }
                }
            } else if let issue = history.monthIssue {
                Text(issue.message)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("historyMonthIssue")
                Button("Retry") { history.retryMonth() }
                    .historyKeyAction { history.retryMonth() }
                    .accessibilityLabel("Retry loading this month")
                    .accessibilityIdentifier("retryHistoryMonth")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("historyDateList")
    }

    /// Selection keeps the current filter; only explicit routes choose one.
    private func dayRow(_ summary: DayTaskSummary) -> some View {
        let selected = history.selectedDay == summary.day
        let select = { try? history.select(summary.day, filter: history.filter) }
        return Button { select() } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .opacity(selected ? 1 : 0)
                Text(summary.day.label("EEE, MMM d"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(summary.progress.completed)/\(summary.progress.total)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(selected ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .historyKeyAction { select() }
        .accessibilityLabel("\(summary.day.label("MMMM d, yyyy")), \(summary.progress.completed) of \(summary.progress.total) complete")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("historyDay-\(summary.day.key)")
    }
}
