import SwiftUI

/// Retains Today at the same size while child screens replace its visible
/// content. Hidden Today cannot receive input or expose accessibility controls.
struct TaskBrowserView: View {
    let state: DailyNotesState
    let presentation: TaskWindowPresentation
    let onSettings: () -> Void
    @FocusState private var backFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            TaskWindowView(state: state, presentation: presentation, onSettings: onSettings)
                .opacity(presentation.route == .today ? 1 : 0)
                .allowsHitTesting(presentation.route == .today)
                .disabled(presentation.route != .today)
                .accessibilityHidden(presentation.route != .today)
            if presentation.route != .today { browserContent }
        }
        .task(id: presentation.route) {
            await Task.yield()
            backFocused = presentation.route != .today
        }
    }

    private func goBack() {
        if presentation.route == .unfinished { presentation.backToHistory(state: state) }
        else { presentation.showToday(state: state) }
    }

    private var browserContent: some View {
        GeometryReader { geometry in
            let isWide = presentation.route == .history && geometry.size.width >= 760
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(spacing: 16) {
                            Button {
                                goBack()
                            } label: {
                                Label(presentation.route == .unfinished ? "Back to History" : "Back to Today",
                                      systemImage: "chevron.left")
                            }
                            .focusable()
                            .keyboardFocusAppearance()
                            .focused($backFocused)
                            .onKeyPress(keys: [.space, .return]) { _ in
                                goBack()
                                return .handled
                            }
                            .accessibilityIdentifier("taskBrowserBack")
                            Spacer()
                            Button(action: onSettings) { Image(systemName: "gearshape") }
                                .keyboardFocusAppearance()
                                .accessibilityLabel("Settings")
                                .help("Settings (⌘,)")
                        }
                        Text(presentation.route == .unfinished ? "Unfinished" : "History")
                            .font(.system(size: 24, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("taskBrowserHeading")
                        if let issue = presentation.browserIssue {
                            Text(issue).foregroundStyle(.secondary)
                            Button("Retry") { presentation.refreshBrowser(state: state) }
                                .keyboardFocusAppearance()
                        } else if presentation.route == .history, let history = presentation.historyState {
                            Button {
                                presentation.showUnfinished(state: state)
                            } label: {
                                Label("Unfinished from previous days", systemImage: "chevron.right")
                                    .labelStyle(TrailingIconLabelStyle())
                            }
                            .historyKeyAction { presentation.showUnfinished(state: state) }
                            .accessibilityIdentifier("unfinishedHistoryEntry")
                            TaskHistoryView(history: history, isWide: isWide)
                        } else {
                            Text("The unfinished-day list will appear here.")
                                .foregroundStyle(.secondary)
                            if presentation.route == .unfinished {
                                Button("Back to Today") { presentation.showToday(state: state) }
                                    .keyboardFocusAppearance()
                            }
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
