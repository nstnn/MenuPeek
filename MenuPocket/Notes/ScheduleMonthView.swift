import SwiftUI

/// The Calendar's Month view: seven Monday-first columns under a weekday row.
/// Each in-month day lists its first blocks as "10:00 Title" lines, then
/// "+N more"; choosing a day (click, Return, Space or AXPress) opens it in Day
/// view. Padding cells are blank, inert and hidden from Accessibility.
///
/// Blocks come from the state's one read of the month and are grouped by day
/// once per state change in `ScheduleMonthModel`; resizing only changes the
/// cell size and the line count (`ScheduleMonthSize.lineCount`). Bodies are
/// split into small views so older Swift type checkers stay fast.
struct ScheduleMonthView: View {
    let schedule: ScheduleState
    let blocks: [ScheduleBlock]
    @FocusState private var focusedDay: GregorianDay?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let model = (try? schedule.period.monthGrid()).map {
            ScheduleMonthModel(grid: $0, blocks: blocks, today: schedule.today, selectedDay: schedule.selectedDay)
        }
        GeometryReader { geometry in
            if let model {
                ScheduleMonthLayoutView(model: model, size: geometry.size, focusedDay: $focusedDay,
                                        onOpen: open, onMove: moveFocus)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(schedule.header.title)
        .accessibilityIdentifier("scheduleMonthGrid")
    }

    private func open(_ day: GregorianDay) {
        guard isEnabled else { return }
        schedule.showDay(day)
    }

    /// Arrow keys move focus by a day or a week. Leaving the month steps to the
    /// previous or next month first, then focuses the same target day there.
    private func moveFocus(from day: GregorianDay, by step: Int) {
        guard isEnabled, let target = try? day.adding(days: step) else { return }
        if schedule.period.contains(target) {
            focusedDay = target
            return
        }
        let moved = step < 0 ? schedule.showPrevious() : schedule.showNext()
        guard moved, schedule.period.contains(target) else { return }
        // The new month's cells appear in the next update, so focus them after it.
        DispatchQueue.main.async { focusedDay = target }
    }
}

/// Sizes the cells to the space offered. A grid that cannot fit its minimum
/// row height (only below the minimum window size) scrolls instead of clipping.
private struct ScheduleMonthLayoutView: View {
    let model: ScheduleMonthModel
    let size: CGSize
    var focusedDay: FocusState<GregorianDay?>.Binding
    let onOpen: (GregorianDay) -> Void
    let onMove: (GregorianDay, Int) -> Void

    var body: some View {
        let weekCount = model.weeks.count
        let rowHeight = ScheduleMonthSize.rowHeight(availableHeight: size.height, weekCount: weekCount)
        let fits = ScheduleMonthSize.gridHeight(rowHeight: rowHeight, weekCount: weekCount) <= size.height + 0.5
        if fits {
            grid(width: size.width, rowHeight: rowHeight)
        } else {
            ScrollView(.vertical) {
                grid(width: max(size.width - ScheduleTimeGridSize.maximumScrollerWidth, 0), rowHeight: rowHeight)
            }
        }
    }

    private func grid(width: CGFloat, rowHeight: CGFloat) -> some View {
        let columnWidth = max(width / 7, 0)
        let lineCount = ScheduleMonthSize.lineCount(cellHeight: rowHeight)
        return VStack(spacing: 0) {
            ScheduleMonthWeekdayRow(symbols: model.weekdaySymbols, columnWidth: columnWidth)
            ForEach(Array(model.weeks.enumerated()), id: \.offset) { _, week in
                ScheduleMonthWeekRow(week: week, columnWidth: columnWidth, rowHeight: rowHeight,
                                     lineCount: lineCount, focusedDay: focusedDay,
                                     onOpen: onOpen, onMove: onMove)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .background(alignment: .topLeading) {
            ScheduleMonthGridLines(weekCount: model.weeks.count, columnWidth: columnWidth, rowHeight: rowHeight)
        }
    }
}

/// "Mon" ... "Sun". Every cell already names its weekday, so this row is
/// hidden from Accessibility.
private struct ScheduleMonthWeekdayRow: View {
    let symbols: [String]
    let columnWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, ScheduleMonthSize.cellHorizontalPadding)
                    .frame(width: columnWidth, alignment: .leading)
            }
        }
        .frame(height: ScheduleMonthSize.weekdayHeaderHeight, alignment: .center)
        .accessibilityHidden(true)
    }
}

private struct ScheduleMonthWeekRow: View {
    let week: [ScheduleMonthEntry]
    let columnWidth: CGFloat
    let rowHeight: CGFloat
    let lineCount: Int
    var focusedDay: FocusState<GregorianDay?>.Binding
    let onOpen: (GregorianDay) -> Void
    let onMove: (GregorianDay, Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(week) { entry in
                switch entry {
                case .padding:
                    // Blank filler: no focus, action, or accessibility element.
                    Color.clear.accessibilityHidden(true)
                        .frame(width: columnWidth, height: rowHeight)
                case let .day(day):
                    ScheduleMonthDayCell(day: day, lines: day.lines(count: lineCount), focusedDay: focusedDay,
                                         onOpen: { onOpen(day.day) }, onMove: { onMove(day.day, $0) })
                        .frame(width: columnWidth, height: rowHeight)
                }
            }
        }
    }
}

/// One day: date number (today on an accent disc), its first blocks and
/// "+N more". The whole cell is one button that opens the day in Day view.
private struct ScheduleMonthDayCell: View {
    let day: ScheduleMonthDay
    let lines: ScheduleMonthLines
    var focusedDay: FocusState<GregorianDay?>.Binding
    let onOpen: () -> Void
    let onMove: (Int) -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onOpen) {
            content
                .padding(.horizontal, ScheduleMonthSize.cellHorizontalPadding)
                .padding(.top, ScheduleMonthSize.cellTopPadding)
                .padding(.bottom, ScheduleMonthSize.cellBottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background { background }
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .keyboardFocusAppearance()
        .focused(focusedDay, equals: day.day)
        .onHover { isHovered = $0 }
        .onKeyPress(keys: [.space, .return]) { _ in
            onOpen()
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            onMove(Self.step(for: press.key))
            return .handled
        }
        .help(day.tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
        .accessibilityValue(day.accessibilityValue)
        .accessibilityAddTraits(day.isSelected ? [.isButton, .isSelected] : .isButton)
        // Ignoring the children drops the button's own press, so AXPress
        // (VoiceOver's VO-Space) needs its own action.
        .accessibilityAction { onOpen() }
        .accessibilityIdentifier(day.identifier)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScheduleMonthDateNumber(day: day)
                .frame(height: ScheduleMonthSize.dateRowHeight, alignment: .leading)
                .padding(.bottom, ScheduleMonthSize.dateSpacing)
            ForEach(lines.blocks) { block in
                ScheduleMonthBlockLine(block: block)
            }
            if let overflow = lines.overflowText {
                Text(overflow)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: ScheduleMonthSize.lineHeight, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        let accent = DaybookPalette.accent(colorScheme)
        ZStack {
            if day.isToday {
                Rectangle().fill(accent.opacity(colorScheme == .dark ? 0.07 : 0.05))
            }
            if isHovered {
                Rectangle().fill(accent.opacity(colorScheme == .dark ? 0.08 : 0.06))
            }
            if day.isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(accent, lineWidth: 1)
                    .padding(2)
            }
        }
    }

    private static func step(for key: KeyEquivalent) -> Int {
        switch key {
        case .leftArrow: -1
        case .rightArrow: 1
        case .upArrow: -7
        default: 7
        }
    }
}

private struct ScheduleMonthDateNumber: View {
    let day: ScheduleMonthDay
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(day.dayNumber)
            .font(.system(size: 13, weight: day.isToday ? .semibold : .regular, design: .monospaced)
                .monospacedDigit())
            .foregroundStyle(day.isToday ? DaybookPalette.canvas(colorScheme) : Color.primary)
            .frame(minWidth: 22, minHeight: 20)
            .background { Capsule().fill(day.isToday ? DaybookPalette.accent(colorScheme) : Color.clear) }
            .lineLimit(1)
    }
}

/// "10:00 Design review": the start time, then the title truncated to the cell.
private struct ScheduleMonthBlockLine: View {
    let block: ScheduleBlock
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(DaybookPalette.accent(colorScheme))
                .frame(width: 2, height: 9)
            Text(ScheduleBlockText.start(block))
                .foregroundStyle(.secondary)
                .layoutPriority(1)
            Text(block.title)
                .foregroundStyle(Color.primary)
                .truncationMode(.tail)
        }
        .font(.system(size: 10, design: .monospaced))
        .lineLimit(1)
        .frame(height: ScheduleMonthSize.lineHeight, alignment: .leading)
    }
}

/// The lines under the weekday row and between columns, drawn in one Canvas.
private struct ScheduleMonthGridLines: View {
    let weekCount: Int
    let columnWidth: CGFloat
    let rowHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let height = ScheduleMonthSize.gridHeight(rowHeight: rowHeight, weekCount: weekCount)
        Canvas { context, size in
            var path = Path()
            let top = ScheduleMonthSize.weekdayHeaderHeight
            for row in 0...weekCount {
                let y = min(top + CGFloat(row) * rowHeight, size.height - 0.5)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            for column in 0...7 {
                let x = min(max(CGFloat(column) * columnWidth, 0.5), size.width - 0.5)
                path.move(to: CGPoint(x: x, y: top))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(path, with: .color(DaybookPalette.rule(colorScheme)), lineWidth: 1)
        }
        .frame(width: columnWidth * 7, height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
