import SwiftUI

/// The Day and Week time grid: a fixed weekday/date row above a vertically
/// scrolling 24-hour grid with an hour gutter. Week has seven columns, Day one.
///
/// Every position comes from `ScheduleTimeGridModel` and `ScheduleGridMetrics`,
/// computed once per state change; the views only place what they are given.
/// Bodies are split into small views so older Swift type checkers stay fast.
struct ScheduleTimeGridView: View {
    let schedule: ScheduleState
    let blocks: [ScheduleBlock]
    let editor: ScheduleEditorContext
    var focus: FocusState<ScheduleFocusTarget?>.Binding
    @Environment(\.colorScheme) private var colorScheme
    /// Width of the scroll content. It is narrower than the pane by a legacy
    /// (always shown) scroller, which the header row leaves room for.
    @State private var scrollContentWidth: CGFloat = 0

    var body: some View {
        // The GeometryReader takes the width it is offered, never its content's,
        // so columns shrink with the window and with zoom instead of holding
        // the width they were last laid out at.
        GeometryReader { geometry in
            grid(width: geometry.size.width)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scheduleTimeGrid")
    }

    private func grid(width: CGFloat) -> some View {
        let model = ScheduleTimeGridModel(days: schedule.days, blocks: blocks, today: schedule.today)
        let scrollerInset = ScheduleTimeGridSize.scrollerInset(paneWidth: width, scrollContentWidth: scrollContentWidth)
        let columnWidth = ScheduleTimeGridSize.columnWidth(contentWidth: width - scrollerInset,
                                                           columnCount: model.days.count)
        return VStack(spacing: 0) {
            ScheduleDayHeaderRow(days: model.days, columnWidth: columnWidth)
            Rectangle().fill(DaybookPalette.rule(colorScheme)).frame(height: 1).accessibilityHidden(true)
            ScheduleGridScrollView(schedule: schedule, model: model, columnWidth: columnWidth,
                                   editor: editor, focus: focus, contentWidth: $scrollContentWidth)
        }
        .frame(width: width, alignment: .topLeading)
    }
}

// MARK: - Day header row

private struct ScheduleDayHeaderRow: View {
    let days: [ScheduleGridDay]
    let columnWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: ScheduleTimeGridSize.gutterWidth).accessibilityHidden(true)
            ForEach(days) { day in
                ScheduleDayHeader(day: day, showsFullName: days.count == 1)
                    .frame(width: columnWidth)
            }
            Spacer(minLength: 0)
        }
        .frame(height: ScheduleTimeGridSize.dayHeaderHeight)
    }
}

/// Weekday above the date number; today's number sits on an accent disc.
private struct ScheduleDayHeader: View {
    let day: ScheduleGridDay
    let showsFullName: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let accent = DaybookPalette.accent(colorScheme)
        VStack(spacing: 2) {
            Text(showsFullName ? day.weekdayName : day.weekdaySymbol)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(day.isToday ? accent : Color.secondary)
            Text(day.dayNumber)
                .font(.system(size: 14, weight: day.isToday ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(day.isToday ? DaybookPalette.canvas(colorScheme) : Color.primary)
                .frame(minWidth: 24, minHeight: 22)
                .background { Capsule().fill(day.isToday ? accent : Color.clear) }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.headerLabel)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier(day.headerIdentifier)
    }
}

// MARK: - Scrolling grid

private struct ScheduleGridScrollView: View {
    let schedule: ScheduleState
    let model: ScheduleTimeGridModel
    let columnWidth: CGFloat
    let editor: ScheduleEditorContext
    var focus: FocusState<ScheduleFocusTarget?>.Binding
    @Binding var contentWidth: CGFloat

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    ScheduleHourAnchors()
                    HStack(alignment: .top, spacing: 0) {
                        ScheduleHourGutter()
                        ScheduleGridBody(schedule: schedule, model: model, columnWidth: columnWidth,
                                         editor: editor, focus: focus)
                    }
                    .padding(.vertical, ScheduleTimeGridSize.verticalInset)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            }
            .onAppear {
                // Once per appearance: later period changes and reloads keep the
                // user's scroll position instead of jumping.
                let hour = model.initialScrollHour(current: schedule.currentTime())
                DispatchQueue.main.async { proxy.scrollTo(hour, anchor: .top) }
            }
        }
    }
}

/// One invisible row per hour, starting `verticalInset` above that hour's
/// line, so scrolling to an hour also shows its label.
private struct ScheduleHourAnchors: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Color.clear.frame(height: ScheduleTimeGridSize.hourHeight).id(hour)
            }
        }
        .frame(width: 1)
        .accessibilityHidden(true)
    }
}

/// "00:00" ... "23:00", each centred on its hour line.
private struct ScheduleHourGutter: View {
    var body: some View {
        let metrics = ScheduleTimeGridSize.metrics
        ZStack(alignment: .topTrailing) {
            ForEach(0..<24, id: \.self) { hour in
                Text(ScheduleBlockContent.clockText(minute: hour * 60))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(height: 12)
                    .offset(y: metrics.offset(forMinute: hour * 60) - 6)
            }
        }
        .padding(.trailing, 8)
        .frame(width: ScheduleTimeGridSize.gutterWidth, height: metrics.dayHeight, alignment: .topTrailing)
        .accessibilityHidden(true)
    }
}

/// Lines, today's tint, the empty-slot click target, the day columns and the
/// current-time line. The block editor's popover for grid openings is anchored
/// here, on the clicked slot or the edited block.
private struct ScheduleGridBody: View {
    let schedule: ScheduleState
    let model: ScheduleTimeGridModel
    let columnWidth: CGFloat
    let editor: ScheduleEditorContext
    var focus: FocusState<ScheduleFocusTarget?>.Binding
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let height = ScheduleTimeGridSize.metrics.dayHeight
        ZStack(alignment: .topLeading) {
            if let today = model.todayIndex {
                Rectangle()
                    .fill(DaybookPalette.accent(colorScheme).opacity(colorScheme == .dark ? 0.07 : 0.05))
                    .frame(width: columnWidth, height: height)
                    .offset(x: CGFloat(today) * columnWidth)
                    .accessibilityHidden(true)
            }
            ScheduleGridLines(columnCount: model.days.count, columnWidth: columnWidth)
            ScheduleSlotClickTarget(days: model.days.map(\.day), columnWidth: columnWidth) { day, minute in
                editor.openFromClick(.slot(day: day, startMinute: minute))
            }
            if let draft = editor.previewDraft, let rect = previewRect(for: draft) {
                ScheduleSlotPreview(rect: rect)
            }
            ForEach(Array(model.days.enumerated()), id: \.element.id) { index, day in
                ScheduleDayColumn(day: day, columnWidth: columnWidth, focus: focus,
                                  onOpen: { editor.open(.edit($0)) },
                                  onClick: { editor.openFromClick(.edit($0)) })
                .offset(x: CGFloat(index) * columnWidth)
            }
            ScheduleCurrentTimeLine(schedule: schedule, model: model, columnWidth: columnWidth)
        }
        .frame(width: columnWidth * CGFloat(model.days.count), height: height, alignment: .topLeading)
        .popover(item: editor.binding(where: \.isOnGrid),
                 attachmentAnchor: .rect(.rect(editor.request.map(anchorRect(for:)) ?? .zero)),
                 arrowEdge: .trailing) { request in
            ScheduleBlockEditor(schedule: schedule, request: request,
                                onDraftChange: { editor.updateDraft(request.id, $0) },
                                onClose: { editor.finish(request, $0) })
                .id(request.id)
        }
    }

    /// The draft's span in its day's column, or nil when that day is not shown.
    private func previewRect(for draft: ScheduleBlockDraft) -> CGRect? {
        guard let index = model.columnIndex(of: draft.day) else { return nil }
        let metrics = ScheduleTimeGridSize.metrics
        let top = metrics.offset(forMinute: draft.startMinute)
        return CGRect(x: CGFloat(index) * columnWidth, y: top, width: columnWidth,
                      height: metrics.offset(forMinute: draft.endMinute) - top)
    }

    /// The edited block's rectangle, or the new block's one-hour span in the
    /// clicked day's column, in this view's coordinates.
    private func anchorRect(for request: ScheduleEditorRequest) -> CGRect {
        let metrics = ScheduleTimeGridSize.metrics
        switch request.origin {
        case let .block(id):
            for (index, day) in model.days.enumerated() {
                guard let placement = day.placements.first(where: { $0.id == id }) else { continue }
                return metrics.rect(for: placement, columnWidth: columnWidth)
                    .offsetBy(dx: CGFloat(index) * columnWidth, dy: 0)
            }
        case let .slot(day, _):
            if let index = model.columnIndex(of: day) {
                let top = metrics.offset(forMinute: request.draft.startMinute)
                return CGRect(x: CGFloat(index) * columnWidth, y: top, width: columnWidth,
                              height: metrics.offset(forMinute: request.draft.endMinute) - top)
            }
        case .newBlockButton:
            break
        }
        return CGRect(x: 0, y: 0, width: 1, height: 1)
    }
}

/// The one place a plain click on empty grid space is turned into a day and
/// 15-minute slot (`ScheduleSlotHitTest`). Blocks sit above it and take their
/// own clicks. TASK-011's drag-to-create replaces this view.
private struct ScheduleSlotClickTarget: View {
    let days: [GregorianDay]
    let columnWidth: CGFloat
    let onSlot: (GregorianDay, Int) -> Void

    var body: some View {
        Color.clear
            .frame(width: columnWidth * CGFloat(days.count), height: ScheduleTimeGridSize.metrics.dayHeight)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                guard let slot = ScheduleSlotHitTest.slot(at: location, columnWidth: columnWidth, days: days,
                                                          metrics: ScheduleTimeGridSize.metrics) else { return }
                onSlot(slot.day, slot.startMinute)
            }
            .accessibilityHidden(true)
    }
}

/// A dashed outline of where the open editor's block will be saved: a new
/// block, or an edited block whose day or times changed.
private struct ScheduleSlotPreview: View {
    let rect: CGRect
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(DaybookPalette.accent(colorScheme), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DaybookPalette.accent(colorScheme).opacity(0.08))
            }
            .frame(width: max(rect.width - 3, 1), height: max(rect.height - 2, 1))
            .offset(x: rect.minX + 1, y: rect.minY + 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Hour and half-hour lines and column separators, drawn in one Canvas.
private struct ScheduleGridLines: View {
    let columnCount: Int
    let columnWidth: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let rule = DaybookPalette.rule(colorScheme)
        Canvas { context, size in
            let metrics = ScheduleTimeGridSize.metrics
            var hours = Path()
            var halves = Path()
            for hour in 0...24 {
                let y = metrics.offset(forMinute: hour * 60)
                hours.move(to: CGPoint(x: 0, y: y))
                hours.addLine(to: CGPoint(x: size.width, y: y))
                guard hour < 24 else { continue }
                let half = metrics.offset(forMinute: hour * 60 + 30)
                halves.move(to: CGPoint(x: 0, y: half))
                halves.addLine(to: CGPoint(x: size.width, y: half))
            }
            for column in 0...columnCount {
                let x = min(CGFloat(column) * columnWidth, size.width - 0.5)
                hours.move(to: CGPoint(x: max(x, 0.5), y: 0))
                hours.addLine(to: CGPoint(x: max(x, 0.5), y: size.height))
            }
            context.stroke(halves, with: .color(rule.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            context.stroke(hours, with: .color(rule), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One day's blocks, each at the rectangle its placement gives.
private struct ScheduleDayColumn: View {
    let day: ScheduleGridDay
    let columnWidth: CGFloat
    var focus: FocusState<ScheduleFocusTarget?>.Binding
    let onOpen: (ScheduleBlock) -> Void
    let onClick: (ScheduleBlock) -> Void

    var body: some View {
        let metrics = ScheduleTimeGridSize.metrics
        ZStack(alignment: .topLeading) {
            ForEach(day.placements) { placement in
                let rect = metrics.rect(for: placement, columnWidth: columnWidth)
                ScheduleBlockView(block: placement.block,
                                  size: CGSize(width: max(rect.width - 3, 1), height: max(rect.height - 2, 1)),
                                  focus: focus, onOpen: { onOpen(placement.block) },
                                  onClick: { onClick(placement.block) })
                    .offset(x: rect.minX + 1, y: rect.minY + 1)
            }
        }
        .frame(width: columnWidth, height: metrics.dayHeight, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(day.headerLabel)
        .accessibilityIdentifier(day.columnIdentifier)
    }
}

// MARK: - Block

/// A saved block: title first, then the time range when there is room. Text
/// truncates inside the block's frame; the full text is in the tooltip and
/// the spoken label. A click, Return or Space (or AXPress) opens it in the editor.
private struct ScheduleBlockView: View {
    let block: ScheduleBlock
    let size: CGSize
    var focus: FocusState<ScheduleFocusTarget?>.Binding
    /// Return, Space and AXPress.
    let onOpen: () -> Void
    let onClick: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    /// Below this height only one line (the title) is drawn.
    private static let twoLineHeight: CGFloat = 28
    private static let titleSize: CGFloat = 11
    /// Leading accent stripe and text inset, plus the trailing inset.
    private static let horizontalInsets: CGFloat = 9

    var body: some View {
        let accent = DaybookPalette.accent(colorScheme)
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        content
            .padding(.leading, 6)
            .padding(.trailing, Self.horizontalInsets - 6)
            .padding(.vertical, size.height < Self.twoLineHeight ? 0 : 3)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background { shape.fill(accent.opacity(colorScheme == .dark ? 0.24 : 0.16)) }
            .overlay(alignment: .leading) { Rectangle().fill(accent).frame(width: 2) }
            .clipShape(shape)
            .contentShape(shape)
            .help(ScheduleBlockText.tooltip(block))
            .onTapGesture(perform: onClick)
            .focusable()
            .keyboardFocusAppearance()
            .focused(focus, equals: .block(block.id))
            .onKeyPress(keys: [.return, .space]) { _ in
                onOpen()
                return .handled
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ScheduleBlockText.accessibilityLabel(block))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen() }
            .accessibilityIdentifier(ScheduleBlockText.identifier(block))
    }

    @ViewBuilder
    private var content: some View {
        if size.height < Self.twoLineHeight {
            title(size: 10, lines: 1)
                .frame(maxHeight: .infinity, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                title(size: Self.titleSize, lines: titleLines)
                ScheduleBlockTime(block: block)
            }
        }
    }

    /// Lines left for the title above the time line, wrapping only whole words.
    private var titleLines: Int {
        ScheduleBlockText.titleLineLimit(block.title, textWidth: size.width - Self.horizontalInsets,
                                         availableLines: max(1, Int((size.height - 6 - 13) / 13)),
                                         characterWidth: Self.titleSize * 0.62)
    }

    private func title(size: CGFloat, lines: Int) -> some View {
        Text(block.title)
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.primary)
            .lineLimit(lines)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "10:00–11:00", or "10:00" when the range would not fit, or nothing.
private struct ScheduleBlockTime: View {
    let block: ScheduleBlock

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(ScheduleBlockText.timeRange(block))
            Text(ScheduleBlockText.start(block))
            Color.clear.frame(width: 0, height: 0)
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

// MARK: - Current time

/// A line across today's column at the current minute, refreshed each minute.
/// Drawn only when the current day is one of the visible columns.
private struct ScheduleCurrentTimeLine: View {
    let schedule: ScheduleState
    let model: ScheduleTimeGridModel
    let columnWidth: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { _ in
            if let now = schedule.currentTime(), let index = model.columnIndex(of: now.day) {
                ScheduleCurrentTimeMarker(clockText: now.clockText, width: columnWidth)
                    .offset(x: CGFloat(index) * columnWidth - 4,
                            y: ScheduleTimeGridSize.metrics.offset(forMinute: now.minute) - 4)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ScheduleCurrentTimeMarker: View {
    let clockText: String
    let width: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let color = DaybookPalette.danger(colorScheme)
        HStack(spacing: 0) {
            Circle().fill(color).frame(width: 8, height: 8)
            Rectangle().fill(color).frame(width: max(width - 4, 0), height: 1.5)
        }
        .frame(height: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current time, \(clockText)")
        .accessibilityIdentifier("scheduleCurrentTime")
    }
}
