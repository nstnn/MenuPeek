import SwiftUI

/// The Calendar pane in the task window's right column: the visible period's
/// title, the Day/Week/Month switch, Previous/Today/Next, and the body below.
///
/// Day and Week show the loaded blocks on a time grid (`ScheduleTimeGridView`);
/// Month shows a day grid (`ScheduleMonthView`) whose cells open Day view.
/// A failed read never shows an empty calendar: it shows the period's load
/// message with Retry.
///
/// The block editor opens from the New block button, a click on an empty grid
/// slot, a drag on empty grid space (with the drawn times), or a click or
/// Return on a block. Dragging a block's lower edge saves its new end directly. The open request lives in the window
/// presentation, which treats Calendar as busy while it is open; focus returns
/// to the opener when it closes.
struct ScheduleView: View {
    /// nil when the Calendar state could not be created; `issue` explains why.
    let schedule: ScheduleState?
    let issue: String?
    let onRetry: () -> Void
    /// The open editor, if any.
    var editor: ScheduleEditorRequest?
    /// Asks the presentation to open the editor; refused while it is busy.
    var onOpenEditor: (ScheduleEditorRequest) -> Void = { _ in }
    /// Closes the editor with this ID; false when it was no longer open.
    var onCloseEditor: (UUID) -> Bool = { _ in false }
    /// Whether a grid drag may start: false while a task edit or a
    /// confirmation is open, like opening the editor.
    var canStartDrag: () -> Bool = { true }
    @FocusState private var focus: ScheduleFocusTarget?
    /// The open editor's current draft, so the grid preview follows its fields.
    @State private var liveDraft: (id: UUID, draft: ScheduleBlockDraft)?
    /// When the popover last closed itself, on a click outside it (system uptime).
    @State private var dismissedAt: TimeInterval = -.infinity
    @Environment(\.colorScheme) private var colorScheme

    private var editorContext: ScheduleEditorContext {
        let draft = editor.map { request in liveDraft?.id == request.id ? liveDraft?.draft ?? request.draft : request.draft }
        return ScheduleEditorContext(request: editor, draft: draft, open: onOpenEditor,
                                     openFromClick: openEditorFromClick, finish: finishEditor,
                                     dismissed: dismissEditor,
                                     updateDraft: { id, draft in liveDraft = (id, draft) },
                                     canDrag: canStartDrag)
    }

    // Split so older Swift type checkers can check each piece in reasonable time.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let schedule {
                    ScheduleHeaderView(schedule: schedule, editor: editorContext, focus: $focus)
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
            if let schedule, let blocks = schedule.blocks {
                loaded(schedule: schedule, blocks: blocks)
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
    private func loaded(schedule: ScheduleState, blocks: [ScheduleBlock]) -> some View {
        if schedule.mode == .month {
            ScheduleMonthView(schedule: schedule, blocks: blocks)
                .disabled(editor != nil)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
        } else {
            ScheduleTimeGridView(schedule: schedule, blocks: blocks, editor: editorContext, focus: $focus)
                .padding(.leading, 12)
                .padding(.trailing, 20)
        }
    }

    /// Everything except a loaded period: nothing yet, or Unavailable with Retry.
    @ViewBuilder
    private var content: some View {
        if let schedule {
            switch schedule.content {
            case .notLoaded, .loaded:
                // A loaded period is drawn by `loaded(schedule:blocks:)`.
                Color.clear.frame(height: 0)
            case .unavailable:
                unavailable(message: schedule.loadMessage ?? "Could not load the calendar. Try again.")
            }
        } else {
            unavailable(message: issue ?? "Could not open the calendar. Try again.")
        }
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

    /// Closes the editor once, then puts focus back on what opened it: the
    /// New block button, the edited block, or the block a slot click created.
    /// After a delete, or a save to a day outside the visible period, focus
    /// goes to New block.
    /// A click outside a transient popover closes it and then reaches the grid.
    /// That click only closes the editor, as with the task actions popover:
    /// opening another popover while this one is still closing would leave it
    /// unshown (and Calendar busy) until the app is reactivated. Keyboard and
    /// accessibility opens are never held back.
    private func openEditorFromClick(_ request: ScheduleEditorRequest) {
        guard ProcessInfo.processInfo.systemUptime - dismissedAt > Self.dismissalClickWindow else { return }
        onOpenEditor(request)
    }

    /// The popover closed itself (a click outside it): Cancel, and remember when.
    private func dismissEditor(_ request: ScheduleEditorRequest) {
        dismissedAt = ProcessInfo.processInfo.systemUptime
        finishEditor(request, .cancelled)
    }

    static let dismissalClickWindow: TimeInterval = 0.5

    private func finishEditor(_ request: ScheduleEditorRequest, _ outcome: ScheduleEditorOutcome) {
        // The popover may report its own dismissal after Save already closed it.
        guard onCloseEditor(request.id) else { return }
        liveDraft = nil
        // A save has already reloaded the visible period, so `blocks` is what the grid draws.
        let shown = Set(schedule?.blocks?.map(\.id) ?? [])
        guard let target = ScheduleFocusTarget.afterEditor(request.origin, outcome,
                                                            isShown: shown.contains) else { return }
        Task { @MainActor in
            // Let the popover close and the task window become key first.
            try? await Task.sleep(for: .milliseconds(60))
            focus = target
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
    let editor: ScheduleEditorContext
    var focus: FocusState<ScheduleFocusTarget?>.Binding

    private var canChangePeriod: Bool { editor.request == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                title
                Spacer(minLength: 8)
                newBlockButton
            }
            controls
                .disabled(!canChangePeriod)
        }
    }

    /// Prefills today (or the selected or first visible day) at the next whole
    /// hour on today, else 09:00, one hour long.
    private func openNewBlock() {
        guard schedule.blocks != nil,
              let draft = ScheduleBlockDraft.newBlock(days: schedule.days, today: schedule.today,
                                                      selectedDay: schedule.selectedDay,
                                                      now: schedule.currentTime()) else { return }
        editor.open(ScheduleEditorRequest(origin: .newBlockButton, draft: draft))
    }

    private var newBlockButton: some View {
        Button(action: openNewBlock) {
            Label("New block", systemImage: "plus")
        }
        .buttonStyle(.daybookProminent)
        .scheduleKeyAction(openNewBlock)
        .focused(focus, equals: .newBlock)
        .disabled(schedule.blocks == nil)
        .fixedSize()
        .help("New block")
        .accessibilityLabel("New block")
        .accessibilityIdentifier("scheduleNewBlock")
        .popover(item: editor.binding { $0 == .newBlockButton }, arrowEdge: .bottom) { request in
            ScheduleBlockEditor(schedule: schedule, request: request,
                                onDraftChange: { editor.updateDraft(request.id, $0) },
                                onClose: { editor.finish(request, $0) })
                .id(request.id)
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
                    .scheduleKeyAction(enabled: canChangePeriod) { schedule.showPrevious() }
                    .help("Previous \(unit)")
                    .accessibilityLabel("Previous \(unit)")
                    .accessibilityIdentifier("schedulePrevious")
                Button("Today") { schedule.showToday() }
                    .scheduleKeyAction(enabled: canChangePeriod) { schedule.showToday() }
                    .help("Show today")
                    .accessibilityLabel("Show today")
                    .accessibilityIdentifier("scheduleToday")
                Button { schedule.showNext() } label: { Image(systemName: "chevron.right") }
                    .scheduleKeyAction(enabled: canChangePeriod) { schedule.showNext() }
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
            guard canChangePeriod else { return .ignored }
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
    func scheduleKeyAction(enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        focusable()
            .keyboardFocusAppearance()
            .onKeyPress(keys: [.space, .return]) { _ in
                guard enabled else { return .ignored }
                action()
                return .handled
            }
    }
}

// MARK: - Editor plumbing

/// Where keyboard focus can return when the block editor closes.
enum ScheduleFocusTarget: Hashable {
    case newBlock
    case block(UUID)

    /// The opener, or the saved block for a slot click; New block after a
    /// delete; nothing after cancelling a slot click (it had no focus).
    /// A block that `isShown` says is not on the grid, such as one saved to a
    /// day outside the visible period, has no view to focus: New block instead.
    static func afterEditor(_ origin: ScheduleEditorOrigin, _ outcome: ScheduleEditorOutcome,
                            isShown: (UUID) -> Bool) -> Self? {
        let target: Self? = switch (origin, outcome) {
        case (.newBlockButton, _), (_, .deleted): .newBlock
        case let (_, .saved(id)): .block(id)
        case let (.block(id), .cancelled): .block(id)
        case (.slot, .cancelled): nil
        }
        guard case let .block(id)? = target, !isShown(id) else { return target }
        return .newBlock
    }
}

/// What the header and the grid need to open, show and close the editor.
/// A main-actor class, so popover bindings can capture it.
@MainActor
final class ScheduleEditorContext {
    let request: ScheduleEditorRequest?
    /// The open editor's fields as the user changes them (initially the request's draft).
    let draft: ScheduleBlockDraft?
    /// Keyboard, button and accessibility opens.
    let open: (ScheduleEditorRequest) -> Void
    /// Pointer clicks on the grid; ignored just after the popover closed itself.
    let openFromClick: (ScheduleEditorRequest) -> Void
    let finish: (ScheduleEditorRequest, ScheduleEditorOutcome) -> Void
    /// The popover closed itself (Escape it handled, or a click outside).
    let dismissed: (ScheduleEditorRequest) -> Void
    let updateDraft: (UUID, ScheduleBlockDraft) -> Void
    /// Whether a grid drag may start now.
    let canDrag: () -> Bool

    init(request: ScheduleEditorRequest?, draft: ScheduleBlockDraft?,
         open: @escaping (ScheduleEditorRequest) -> Void,
         openFromClick: @escaping (ScheduleEditorRequest) -> Void,
         finish: @escaping (ScheduleEditorRequest, ScheduleEditorOutcome) -> Void,
         dismissed: @escaping (ScheduleEditorRequest) -> Void,
         updateDraft: @escaping (UUID, ScheduleBlockDraft) -> Void,
         canDrag: @escaping () -> Bool = { true }) {
        self.request = request
        self.draft = draft
        self.open = open
        self.openFromClick = openFromClick
        self.finish = finish
        self.dismissed = dismissed
        self.updateDraft = updateDraft
        self.canDrag = canDrag
    }

    /// Where the grid draws the dashed preview: the new block (from a slot or
    /// the New block button), or an edited block whose fields have changed.
    var previewDraft: ScheduleBlockDraft? {
        guard let request, let draft else { return nil }
        if case .block = request.origin, draft == request.draft { return nil }
        return draft
    }

    /// The open request when its origin matches, for one popover site. The
    /// popover clearing it (Escape, a click outside) counts as Cancel.
    func binding(where matches: @escaping @Sendable (ScheduleEditorOrigin) -> Bool) -> Binding<ScheduleEditorRequest?> {
        Binding(
            get: { self.request.flatMap { matches($0.origin) ? $0 : nil } },
            set: { newValue in
                if newValue == nil, let request = self.request, matches(request.origin) {
                    self.dismissed(request)
                }
            })
    }
}
