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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TaskWindowView(state: state, presentation: presentation, onSettings: onSettings,
                       detailContent: detailContent)
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
            } else if previous == .unfinished, route == .history, presentation.browserIssue == nil {
                unfinishedEntryFocused = true
            } else {
                backFocused = route != .today
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
        return presentation.route == .today ? nil : AnyView(browserContent)
    }

    private func goBack() {
        switch presentation.route {
        case .unfinishedDay: presentation.backToUnfinished(state: state)
        case .unfinished: presentation.backToHistory(state: state)
        case .history, .today: presentation.showToday(state: state)
        }
    }

    private var backTitle: String {
        switch presentation.route {
        case .unfinishedDay: "Back to Unfinished"
        case .unfinished: "Back to History"
        case .history, .today: "Back to Today"
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
            Label("Unfinished from previous days", systemImage: "chevron.right")
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
    }

    @ViewBuilder
    private func browserHeader(isWide: Bool) -> some View {
        if presentation.route == .history {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    backButton.buttonStyle(.plain)
                    Divider().frame(height: 20).accessibilityHidden(true)
                    Text("History")
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("taskBrowserHeading")
                    Spacer(minLength: 12)
                    if isWide, presentation.browserIssue == nil {
                        unfinishedEntry.buttonStyle(.plain)
                    }
                }
                .frame(minHeight: 30)
                if !isWide, presentation.browserIssue == nil {
                    unfinishedEntry.buttonStyle(.plain)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    backButton
                    Spacer()
                    // Unfinished is nested; Today stays one action away.
                    Button("Go to Today") { presentation.showToday(state: state) }
                        .historyKeyAction { presentation.showToday(state: state) }
                        .accessibilityIdentifier("taskBrowserToday")
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
            let isWide = presentation.route == .history && geometry.size.width >= 760
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
                                            calendarWidth: min(380, contentWidth * 0.43), state: state)
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
        // The same tinted canvas as Today keeps group cards distinct in Light.
        .background {
            Color(nsColor: .windowBackgroundColor)
                .overlay { Color.primary.opacity(colorScheme == .light ? 0.04 : 0) }
        }
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
