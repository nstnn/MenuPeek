import Foundation

// What the Month grid shows, computed once per state change (a load, the Today
// marker or the selection) so resizing only lays the cells out again. No
// SwiftUI: tests check grouping, order, overflow, line counts and spoken text.

/// Fixed sizes of the Month grid, in unzoomed points. Window zoom scales the
/// whole pane, so these never change with zoom.
///
/// Line-count rule: a cell's height is the space below the weekday row shared
/// equally by the month's weeks (never less than `minimumRowHeight`). After
/// the cell chrome (padding and the date row), every `lineHeight` holds one
/// line, and at least `minimumLines` always fit, so a six-week month at the
/// 800×560 minimum window still shows one block line plus "+N more".
enum ScheduleMonthSize {
    /// The Mon ... Sun row above the cells.
    static let weekdayHeaderHeight: CGFloat = 22
    static let cellTopPadding: CGFloat = 4
    static let cellBottomPadding: CGFloat = 4
    static let cellHorizontalPadding: CGFloat = 5
    /// The date number (on an accent disc for today).
    static let dateRowHeight: CGFloat = 20
    /// Gap between the date row and the first block line.
    static let dateSpacing: CGFloat = 2
    /// One "10:00 Title" or "+N more" line.
    static let lineHeight: CGFloat = 14
    static let minimumLines = 2
    /// Bounds the line count so an absurd height cannot ask for absurd work.
    static let maximumLines = 40

    /// Everything in a cell except its lines.
    static var cellChrome: CGFloat { cellTopPadding + dateRowHeight + dateSpacing + cellBottomPadding }

    /// The smallest cell that still fits `minimumLines`.
    static var minimumRowHeight: CGFloat { cellChrome + CGFloat(minimumLines) * lineHeight }

    /// The weeks share the height below the weekday row, in whole points.
    static func rowHeight(availableHeight: CGFloat, weekCount: Int) -> CGFloat {
        guard weekCount > 0, availableHeight.isFinite else { return minimumRowHeight }
        let shared = ((availableHeight - weekdayHeaderHeight) / CGFloat(weekCount)).rounded(.down)
        return max(shared, minimumRowHeight)
    }

    /// How many lines (block lines plus "+N more") a cell this tall shows.
    static func lineCount(cellHeight: CGFloat) -> Int {
        guard cellHeight.isFinite else { return minimumLines }
        let fitting = ((cellHeight - cellChrome) / lineHeight).rounded(.down)
        return Int(min(max(fitting, CGFloat(minimumLines)), CGFloat(maximumLines)))
    }

    /// The height the whole grid needs at `rowHeight`.
    static func gridHeight(rowHeight: CGFloat, weekCount: Int) -> CGFloat {
        weekdayHeaderHeight + rowHeight * CGFloat(max(weekCount, 0))
    }
}

/// The lines one cell draws: the first blocks, then the count left out.
struct ScheduleMonthLines: Equatable {
    let blocks: [ScheduleBlock]
    /// Blocks not drawn; zero when every block fits.
    let overflow: Int

    /// "+3 more", or nil when nothing is left out.
    var overflowText: String? { overflow > 0 ? "+\(overflow) more" : nil }
}

/// One in-month day: its date, Today and selection marks, and its blocks.
struct ScheduleMonthDay: Identifiable, Equatable {
    let day: GregorianDay
    let isToday: Bool
    let isSelected: Bool
    /// This day's blocks in time order (`ScheduleBlock.isOrderedBefore`).
    let blocks: [ScheduleBlock]

    var id: String { day.key }
    /// "18".
    var dayNumber: String { String(day.day) }
    /// "scheduleMonthDay-2026-11-18".
    var identifier: String { "scheduleMonthDay-\(day.key)" }

    /// "Wednesday 18 November, today, 4 blocks" or "Thursday 19 November, no blocks".
    var accessibilityLabel: String {
        var parts = [ScheduleCalendar.dayAndMonth(day)]
        if isToday { parts.append("today") }
        parts.append(Self.countText(blocks.count))
        return parts.joined(separator: ", ")
    }

    /// Every block, not only the drawn ones: "10:00 Design review, 10:30 Pairing".
    var accessibilityValue: String { blocks.map(Self.lineText).joined(separator: ", ") }

    /// The full date and every block with its time range, for cells that truncate.
    var tooltip: String {
        ([ScheduleCalendar.fullDate(day)]
            + blocks.map { "\(ScheduleBlockText.timeRange($0)) \($0.title)" }).joined(separator: "\n")
    }

    /// When all blocks fit in `lineCount` lines, all of them; otherwise the
    /// first `lineCount - 1` and "+N more" for the rest, so the overflow line
    /// always has room.
    func lines(count lineCount: Int) -> ScheduleMonthLines {
        let available = max(lineCount, 1)
        guard blocks.count > available else { return ScheduleMonthLines(blocks: blocks, overflow: 0) }
        let shown = available - 1
        return ScheduleMonthLines(blocks: Array(blocks.prefix(shown)), overflow: blocks.count - shown)
    }

    /// "10:00 Design review".
    static func lineText(_ block: ScheduleBlock) -> String { "\(ScheduleBlockText.start(block)) \(block.title)" }

    static func countText(_ count: Int) -> String {
        switch count {
        case 0: "no blocks"
        case 1: "1 block"
        default: "\(count) blocks"
        }
    }
}

enum ScheduleMonthEntry: Identifiable, Equatable {
    /// Blank, inert filler before or after the month; the payload is its position.
    case padding(Int)
    case day(ScheduleMonthDay)

    var id: String {
        switch self {
        case let .padding(index): "padding-\(index)"
        case let .day(day): day.id
        }
    }
}

/// The Month grid for one month's loaded blocks.
struct ScheduleMonthModel: Equatable {
    let month: HistoryDayRange
    let weekdaySymbols: [String]
    /// Complete Monday-first weeks of seven entries.
    let weeks: [[ScheduleMonthEntry]]

    /// Groups the blocks by day once. Blocks outside the month are left out;
    /// the state never loads any.
    init(grid: ScheduleMonthGrid, blocks: [ScheduleBlock], today: GregorianDay, selectedDay: GregorianDay?) {
        let byDay = Dictionary(grouping: blocks, by: \.day).mapValues { $0.sorted(by: ScheduleBlock.isOrderedBefore) }
        let entries = grid.cells.map { cell -> ScheduleMonthEntry in
            switch cell {
            case let .padding(index):
                .padding(index)
            case let .day(day):
                .day(ScheduleMonthDay(day: day, isToday: day == today, isSelected: day == selectedDay,
                                      blocks: byDay[day] ?? []))
            }
        }
        month = grid.month
        weekdaySymbols = grid.weekdaySymbols
        weeks = stride(from: 0, to: entries.count, by: 7).map { Array(entries[$0..<min($0 + 7, entries.count)]) }
    }

    /// Every in-month day, in order.
    var days: [ScheduleMonthDay] {
        weeks.joined().compactMap { entry in
            if case let .day(day) = entry { day } else { nil }
        }
    }

    func day(_ day: GregorianDay) -> ScheduleMonthDay? { days.first { $0.day == day } }
}
