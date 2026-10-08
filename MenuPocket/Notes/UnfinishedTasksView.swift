import SwiftUI

/// Days before Today that still hold unfinished tasks, newest first. Rows show
/// whole-day progress; selecting one opens the shared read-only detail.
struct UnfinishedTasksView: View {
    let unfinished: UnfinishedTasksState
    var focusedDay: FocusState<GregorianDay?>.Binding
    let onSelect: (GregorianDay) -> Void
    @Environment(\.historyScrollProxy) private var proxy

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Days with unfinished tasks")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            if let summaries = unfinished.summaries {
                if summaries.isEmpty {
                    Text("No saved unfinished tasks before today.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("unfinishedEmpty")
                } else {
                    ForEach(summaries, id: \.day) { summary in
                        dayRow(summary)
                    }
                    footer
                }
            } else if let issue = unfinished.initialIssue {
                Text(issue.message)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("unfinishedIssue")
                Button("Retry") { unfinished.retryInitial() }
                    .historyKeyAction { unfinished.retryInitial() }
                    .accessibilityLabel("Retry loading unfinished days")
                    .accessibilityIdentifier("retryUnfinished")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unfinishedDayList")
        .onChange(of: focusedDay.wrappedValue) { _, day in
            if let day { withAnimation(.easeOut(duration: 0.15)) { proxy?.scrollTo(day) } }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let issue = unfinished.appendIssue {
            Text(issue.message)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .accessibilityIdentifier("unfinishedAppendIssue")
            Button("Retry") { unfinished.loadMore() }
                .historyKeyAction { unfinished.loadMore() }
                .accessibilityLabel("Retry loading more days")
                .accessibilityIdentifier("retryUnfinishedMore")
        } else if unfinished.hasMore {
            Button("Load more") { unfinished.loadMore() }
                .historyKeyAction { unfinished.loadMore() }
                .padding(.top, 8)
                .accessibilityLabel("Load older days")
                .accessibilityIdentifier("unfinishedLoadMore")
        }
    }

    private func dayRow(_ summary: DayTaskSummary) -> some View {
        let progress = summary.progress
        let select = { onSelect(summary.day) }
        return Button(action: select) {
            HStack(spacing: 8) {
                Text(summary.day.label("EEE, MMM d, yyyy"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(summary.incomplete) unfinished · \(progress.completed)/\(progress.total) complete")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Row focus is bound by day so Back to Unfinished can restore it.
        .focusable()
        .keyboardFocusAppearance()
        .onKeyPress(keys: [.space, .return]) { _ in
            select()
            return .handled
        }
        .focused(focusedDay, equals: summary.day)
        .id(summary.day)
        .accessibilityLabel("\(summary.day.label("MMMM d, yyyy")), \(summary.incomplete) unfinished, "
            + "\(progress.completed) of \(progress.total) complete")
        .accessibilityIdentifier("unfinishedDay-\(summary.day.key)")
    }
}
