import AppKit
import SwiftUI

/// Retains Today at the same size while child screens replace its visible
/// content. Hidden Today cannot receive input or expose accessibility controls.
struct TaskBrowserView: View {
    let state: DailyNotesState
    let presentation: TaskWindowPresentation
    let onSettings: () -> Void
    var model: AppModel? = nil
    @FocusState private var backFocused: Bool
    @FocusState private var unfinishedEntryFocused: Bool
    @FocusState private var unfinishedDayFocus: GregorianDay?
    @State private var lastRoute: TaskWindowPresentation.Route = .today
    @State private var historySelectionCancelRequest: UUID?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TaskWindowView(state: state, presentation: presentation, onSettings: onSettings,
                       detailContent: detailContent)
        .environment(\.historySelectionCancelRequest, historySelectionCancelRequest)
        .onKeyPress(.escape) {
            guard !presentation.isManagingCategories, !presentation.isShowingSettings,
                  presentation.route == .history || presentation.route == .unfinishedDay else { return .ignored }
            historySelectionCancelRequest = UUID()
            return .handled
        }
        .font(.system(.body, design: .monospaced))
        .fontDesign(.monospaced)
        .task(id: presentation.route) {
            let previous = lastRoute
            let route = presentation.route
            lastRoute = route
            await Task.yield()
            // Returning focuses the control that opened the child screen.
            if previous == .unfinishedDay, route == .unfinished,
               let day = presentation.unfinishedState?.selectedDay,
               presentation.unfinishedState?.summaries?.contains(where: { $0.day == day }) == true {
                unfinishedDayFocus = day
            } else if route == .history, presentation.browserIssue == nil {
                unfinishedEntryFocused = true
            } else {
                backFocused = route == .unfinished || route == .unfinishedDay
            }
        }
    }

    private var detailContent: AnyView? {
        if presentation.isManagingCategories {
            return AnyView(TaskCategoryManagerView(state: state, presentation: presentation))
        }
        if presentation.isShowingSettings, let model {
            return AnyView(VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.system(size: 32, design: .monospaced))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 24)
                    .padding(.top, 30)
                SettingsView(model: model, onQuit: { NSApplication.shared.terminate(nil) })
            })
        }
        switch presentation.route {
        case .today: return nil
        case .calendar:
            return AnyView(ScheduleView(schedule: presentation.scheduleState, issue: presentation.calendarIssue,
                                        onRetry: { presentation.retryCalendar(state: state) }))
        case .history, .unfinished, .unfinishedDay: return AnyView(browserContent)
        }
    }

    private func goBack() {
        switch presentation.route {
        case .unfinishedDay: presentation.backToUnfinished(state: state)
        case .unfinished: presentation.backToHistory(state: state)
        case .history, .today, .calendar: presentation.showToday(state: state)
        }
    }

    private var backTitle: String {
        switch presentation.route {
        case .unfinishedDay: "Back to Unfinished"
        case .unfinished: "Back to History"
        case .history, .today, .calendar: "Back to Today"
        }
    }

    private var backButton: some View {
        Button(action: goBack) {
            Label(backTitle, systemImage: "chevron.left")
        }
        .focusable()
        .keyboardFocusAppearance()
        .focused($backFocused)
        .onKeyPress(keys: [.space, .return]) { _ in
            goBack()
            return .handled
        }
        .accessibilityIdentifier("taskBrowserBack")
    }

    private var unfinishedEntry: some View {
        Button {
            presentation.showUnfinished(state: state)
        } label: {
            Label("Review unfinished…", systemImage: "chevron.right")
                .labelStyle(TrailingIconLabelStyle())
        }
        .focusable()
        .keyboardFocusAppearance()
        .focused($unfinishedEntryFocused)
        .onKeyPress(keys: [.space, .return]) { _ in
            presentation.showUnfinished(state: state)
            return .handled
        }
        .accessibilityIdentifier("unfinishedHistoryEntry")
        .help("Review unfinished tasks from all previous days")
    }

    @ViewBuilder
    private func browserHeader(isWide: Bool) -> some View {
        if presentation.route == .history {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("History")
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("taskBrowserHeading")
                    Spacer(minLength: 12)
                    if isWide, presentation.browserIssue == nil {
                        unfinishedEntry.buttonStyle(.daybook)
                    }
                }
                .frame(minHeight: 30)
                if !isWide, presentation.browserIssue == nil {
                    unfinishedEntry.buttonStyle(.daybook)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    backButton
                    Spacer()
                }
                Text("Unfinished")
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("taskBrowserHeading")
            }
        }
    }

    private var browserContent: some View {
        GeometryReader { geometry in
            let isWide = presentation.route == .history && geometry.size.width >= 700
            let contentWidth = min(max(geometry.size.width - 48, 0), 920)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        browserHeader(isWide: isWide)
                        if let issue = presentation.browserIssue {
                            Text(issue).foregroundStyle(.secondary)
                            Button("Retry") { presentation.refreshBrowser(state: state) }
                                .keyboardFocusAppearance()
                        } else if presentation.route == .history, let history = presentation.historyState {
                            TaskHistoryView(history: history, isWide: isWide,
                                            calendarWidth: min(260, max(240, contentWidth * 0.30)), state: state)
                        } else if presentation.route == .unfinished, let unfinished = presentation.unfinishedState {
                            UnfinishedTasksView(unfinished: unfinished, focusedDay: $unfinishedDayFocus) { day in
                                presentation.showUnfinishedDay(day, state: state)
                            }
                        } else if presentation.route == .unfinishedDay, let history = presentation.historyState {
                            if let issue = presentation.unfinishedState?.selectionIssue {
                                Text(issue.message)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("unfinishedSelectionIssue")
                            }
                            HistoryDayDetailView(history: history, state: state)
                        }
                    }
                    .frame(maxWidth: isWide ? 920 : 660, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .environment(\.historyScrollProxy, proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { DaybookPalette.canvas(colorScheme) }
        .accessibilityIdentifier("taskBrowserChild")
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}
