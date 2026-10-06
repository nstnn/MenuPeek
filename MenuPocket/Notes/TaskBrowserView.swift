import SwiftUI

/// Retains Today at the same size while child screens replace its visible
/// content. Hidden Today cannot receive input or expose accessibility controls.
struct TaskBrowserView: View {
    let state: DailyNotesState
    let presentation: TaskWindowPresentation
    let onSettings: () -> Void
    @FocusState private var backFocused: Bool

    var body: some View {
        ZStack {
            TaskWindowView(state: state, presentation: presentation, onSettings: onSettings)
                .opacity(presentation.route == .today ? 1 : 0)
                .allowsHitTesting(presentation.route == .today)
                .disabled(presentation.route != .today)
                .accessibilityHidden(presentation.route != .today)
            if presentation.route != .today { browserPlaceholder }
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

    private var browserPlaceholder: some View {
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
                } else {
                    Text(presentation.route == .unfinished
                         ? "The unfinished-day list will appear here."
                         : "Day browsing will appear here.")
                        .foregroundStyle(.secondary)
                    if presentation.route == .history {
                        Button("Unfinished from previous days") { presentation.showUnfinished(state: state) }
                            .focusable()
                            .keyboardFocusAppearance()
                            .onKeyPress(keys: [.space, .return]) { _ in
                                presentation.showUnfinished(state: state)
                                return .handled
                            }
                            .accessibilityIdentifier("unfinishedHistoryEntry")
                    } else {
                        Button("Back to Today") { presentation.showToday(state: state) }
                            .keyboardFocusAppearance()
                    }
                }
            }
            .frame(maxWidth: 660, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("taskBrowserChild")
    }
}
