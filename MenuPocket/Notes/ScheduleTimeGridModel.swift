import Foundation

// What the Day and Week time grid shows, computed once per state change so the
// views only position what comes back. No SwiftUI: tests check columns, text,
// identifiers and the current-time and scroll rules directly.

/// Fixed sizes of the time grid, in unzoomed points. Window zoom scales the
/// whole pane, so these never change with zoom.
enum ScheduleTimeGridSize {
    /// One hour of the grid: one point per minute, so a 15-minute block is
    /// 15 pt tall and the whole day is 1440 pt.
    static let hourHeight: CGFloat = 60
    /// The hour-label gutter to the left of the first day column.
    static let gutterWidth: CGFloat = 44
    /// The fixed weekday/date row above the scrolling grid.
    static let dayHeaderHeight: CGFloat = 46
    /// Space above 00:00 and below 24:00 so the first and last hour labels are not clipped.
    static let verticalInset: CGFloat = 8

    static let metrics = ScheduleGridMetrics(hourHeight: hourHeight)

    /// The width a legacy scroller takes from the scroll content: the pane
    /// width minus the measured content width, never negative or more than a
    /// scroller. Zero before the content is measured or with overlay scrollers.
    static func scrollerInset(paneWidth: CGFloat, scrollContentWidth: CGFloat) -> CGFloat {
        guard scrollContentWidth > 0, paneWidth.isFinite, scrollContentWidth.isFinite else { return 0 }
        return min(max(paneWidth - scrollContentWidth, 0), maximumScrollerWidth)
    }

    static let maximumScrollerWidth: CGFloat = 24

    /// Day columns share the width left of the gutter equally.
    static func columnWidth(contentWidth: CGFloat, columnCount: Int) -> CGFloat {
        guard columnCount > 0, contentWidth.isFinite else { return 0 }
        return max((contentWidth - gutterWidth) / CGFloat(columnCount), 0)
    }
}

/// One day column: its header text, Today marker and laid-out blocks.
struct ScheduleGridDay: Identifiable, Equatable {
    let day: GregorianDay
    let isToday: Bool
    /// Placements for this day only, in sweep order (start, creation, ID).
    let placements: [ScheduleBlockPlacement]

    var id: String { day.key }
    /// "Tue".
    var weekdaySymbol: String { String(weekdayName.prefix(3)) }
    /// "Tuesday".
    var weekdayName: String { ScheduleCalendar.weekdayNames[day.weekday - 1] }
    /// "9".
    var dayNumber: String { String(day.day) }
    /// "Tuesday 9 June", plus ", today" on today's column.
    var headerLabel: String {
        let label = ScheduleCalendar.dayAndMonth(day)
        return isToday ? "\(label), today" : label
    }

    var headerIdentifier: String { "scheduleDayHeader-\(day.key)" }
    var columnIdentifier: String { "scheduleDayColumn-\(day.key)" }
}

/// The columns of a Day (one) or Week (seven) grid for the loaded blocks.
struct ScheduleTimeGridModel: Equatable {
    let days: [ScheduleGridDay]

    /// Blocks on days outside `days` are left out; the state never loads any.
    init(days: [GregorianDay], blocks: [ScheduleBlock], today: GregorianDay) {
        let byDay = Dictionary(grouping: ScheduleOverlapLayout.placements(for: blocks)) { $0.block.day }
        self.days = days.map { ScheduleGridDay(day: $0, isToday: $0 == today, placements: byDay[$0] ?? []) }
    }

    func columnIndex(of day: GregorianDay) -> Int? { days.firstIndex { $0.day == day } }

    /// Today's column, or nil when today is not visible.
    var todayIndex: Int? { days.firstIndex(where: \.isToday) }

    /// The hour to show at the top when the grid first appears: two hours
    /// before the current time when that day is visible, so the line sits in
    /// the upper part of even the smallest window; else 07:00.
    func initialScrollHour(current: ScheduleCurrentTime?) -> Int {
        guard let current, columnIndex(of: current.day) != nil else { return Self.morningHour }
        return min(max(Int(current.minute) / 60 - 2, 0), 23)
    }

    static let morningHour = 7
}

/// The civil day and fractional minute from midnight at one clock reading.
struct ScheduleCurrentTime: Equatable, Sendable {
    let day: GregorianDay
    /// 0..<1440, with seconds as a fraction.
    let minute: Double

    init(day: GregorianDay, minute: Double) {
        self.day = day
        self.minute = minute
    }

    /// Reads `instant` in `calendar`'s time zone; nil only if the calendar
    /// cannot name the day.
    init?(instant: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond],
                                            from: instant)
        guard let year = parts.year, let month = parts.month, let dayOfMonth = parts.day,
              let hour = parts.hour, let minute = parts.minute,
              let day = try? GregorianDay(year: year, month: month, day: dayOfMonth) else { return nil }
        let seconds = Double(parts.second ?? 0) + Double(parts.nanosecond ?? 0) / 1_000_000_000
        self.day = day
        self.minute = Double(hour * 60 + minute) + seconds / 60
    }

    /// "16:05", for the current-time line's spoken label.
    var clockText: String { ScheduleBlockContent.clockText(minute: Int(minute)) }
}

/// Text and identifiers for one block on the grid.
enum ScheduleBlockText {
    /// "10:00–11:00".
    static func timeRange(_ block: ScheduleBlock) -> String {
        "\(start(block))–\(ScheduleBlockContent.clockText(minute: block.endMinute))"
    }

    /// "10:00".
    static func start(_ block: ScheduleBlock) -> String {
        ScheduleBlockContent.clockText(minute: block.startMinute)
    }

    /// "ats, Tuesday 9 June, 10:00 to 11:00": title, day and time range, so
    /// nothing depends on colour or position.
    static func accessibilityLabel(_ block: ScheduleBlock) -> String {
        "\(block.title), \(ScheduleCalendar.dayAndMonth(block.day)), "
            + "\(start(block)) to \(ScheduleBlockContent.clockText(minute: block.endMinute))"
    }

    /// The hover text: the full title and time range, for blocks too small to show them.
    static func tooltip(_ block: ScheduleBlock) -> String { "\(block.title)\n\(timeRange(block))" }

    /// How many lines a title may use in a text area `textWidth` points wide
    /// that has room for `availableLines`. It wraps only when its longest word
    /// fits on one line (monospaced, `characterWidth` per character), so a
    /// narrow block truncates on one line instead of breaking a word.
    static func titleLineLimit(_ title: String, textWidth: CGFloat, availableLines: Int,
                               characterWidth: CGFloat) -> Int {
        guard availableLines > 1 else { return 1 }
        let longestWord = title.split(whereSeparator: \.isWhitespace).map(\.count).max() ?? 0
        return CGFloat(longestWord) * characterWidth <= textWidth ? availableLines : 1
    }

    /// "scheduleBlock-<UUID>", stable for the life of the saved block.
    static func identifier(_ block: ScheduleBlock) -> String { "scheduleBlock-\(block.id.uuidString)" }
}

extension ScheduleCalendar {
    /// "Tuesday 9 June".
    static func dayAndMonth(_ day: GregorianDay) -> String {
        "\(weekdayNames[day.weekday - 1]) \(day.day) \(monthNames[day.month - 1])"
    }
}
