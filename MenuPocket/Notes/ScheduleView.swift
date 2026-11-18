import SwiftUI

/// The Calendar pane in the task window's right column: the visible period's
/// title, the Day/Week/Month switch, Previous/Today/Next, and the body below.
///
/// Day and Week show the loaded blocks on a time grid (`ScheduleTimeGridView`).
/// Month cells arrive in a later task; until then Month shows a short summary
/// of the loaded period. A failed read never shows an empty calendar: it shows
/// the period's load message with Retry.
struct ScheduleView: View {
    /// nil when the Calendar state could not be created; `issue` explains why.
    let schedule: ScheduleState?
    let issue: String?
    let onRetry: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    // Split so older Swift type checkers can check each piece in reasonable time.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let schedule {
                    ScheduleHeaderView(schedule: schedule)
                } else {
                    Text("Calendar")
                        .font(.system(size: 28, design: .monospaced))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("scheduleHeading")
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 30)
            .padding(.bottom, 20)
            Rectangle().fill(DaybookPalette.rule(colorScheme)).frame(height: 1).accessibilityHidden(true)
            if let schedule, schedule.mode != .month, let blocks = schedule.blocks {
                ScheduleTimeGridView(schedule: schedule, blocks: blocks)
                    .padding(.leading, 12)
                    .padding(.trailing, 20)
            } else {
                content
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { DaybookPalette.canvas(colorScheme) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedulePane")
    }

    @ViewBuilder
    private var content: some View {
        if let schedule {
            switch schedule.content {
            case .notLoaded:
                Color.clear.frame(height: 0)
            case let .loaded(blocks):
                placeholder(blocks: blocks, mode: schedule.mode)
            case .unavailable:
                unavailable(message: schedule.loadMessage ?? "Could not load the calendar. Try again.")
            }
        } else {
            unavailable(message: issue ?? "Could not open the calendar. Try again.")
        }
    }

    private func placeholder(blocks: [ScheduleBlock], mode: ScheduleViewMode) -> some View {
        let unit = Self.unit(for: mode)
        let summary = blocks.isEmpty ? "No blocks this \(unit)"
            : "\(blocks.count) \(blocks.count == 1 ? "block" : "blocks") this \(unit)"
        return Text(summary)
            .font(.system(size: 14, design: .monospaced))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("schedulePlaceholder")
    }

    private func unavailable(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendar is unavailable")
                .font(.title3.weight(.semibold).monospaced())
                .accessibilityIdentifier("scheduleUnavailableState")
            Text(message)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("scheduleLoadMessage")
            Button("Retry", action: onRetry)
                .scheduleKeyAction(onRetry)
                .accessibilityIdentifier("retrySchedule")
        }
    }

    static func unit(for mode: ScheduleViewMode) -> String {
        switch mode {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        }
    }
}

/// Period title, view switch and navigation. Every control acts through the
/// state's commands, which change the period and load exactly the new range.
private struct ScheduleHeaderView: View {
    let schedule: ScheduleState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            title
            controls
        }
    }

    private var title: some View {
        let header = schedule.header
        return VStack(alignment: .leading, spacing: 6) {
            Text(header.title)
                .font(.system(size: 28, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
            if let detail = header.detail {
                Text(detail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(header.text)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("scheduleHeading")
    }

    private var unit: String { ScheduleView.unit(for: schedule.mode) }

    private var controls: some View {
        HStack(spacing: 12) {
            modePicker
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button { schedule.showPrevious() } label: { Image(systemName: "chevron.left") }
                    .scheduleKeyAction { schedule.showPrevious() }
                    .help("Previous \(unit)")
                    .accessibilityLabel("Previous \(unit)")
                    .accessibilityIdentifier("schedulePrevious")
                Button("Today") { schedule.showToday() }
                    .scheduleKeyAction { schedule.showToday() }
                    .help("Show today")
                    .accessibilityLabel("Show today")
                    .accessibilityIdentifier("scheduleToday")
                Button { schedule.showNext() } label: { Image(systemName: "chevron.right") }
                    .scheduleKeyAction { schedule.showNext() }
                    .help("Next \(unit)")
                    .accessibilityLabel("Next \(unit)")
                    .accessibilityIdentifier("scheduleNext")
            }
            .fixedSize()
        }
    }

    private var modePicker: some View {
        SystemMonospaceSegmentedPicker(
            label: "Calendar view",
            selection: Binding(get: { schedule.mode }, set: { schedule.setMode($0) }),
            options: [(.day, ScheduleViewMode.day.title), (.week, ScheduleViewMode.week.title),
                      (.month, ScheduleViewMode.month.title)])
        .frame(maxWidth: 240, alignment: .leading)
        .focusable()
        .keyboardFocusAppearance()
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            let modes = ScheduleViewMode.allCases
            let index = modes.firstIndex(of: schedule.mode) ?? 0
            let next = min(max(index + (press.key == .rightArrow ? 1 : -1), 0), modes.count - 1)
            schedule.setMode(modes[next])
            return .handled
        }
        .accessibilityLabel("Calendar view")
        .accessibilityValue(schedule.mode.title)
        .accessibilityIdentifier("scheduleViewMode")
    }
}

private extension View {
    /// Space and Return act like a click, matching the other Daybook controls.
    func scheduleKeyAction(_ action: @escaping () -> Void) -> some View {
        focusable()
            .keyboardFocusAppearance()
            .onKeyPress(keys: [.space, .return]) { _ in
                action()
                return .handled
            }
    }
}
