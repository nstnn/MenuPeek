import Foundation

/// The Calendar pane's views. Week is shown first.
enum ScheduleViewMode: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month

    static let initial: Self = .week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }
}

/// Fixed Calendar vocabulary. Names are English and never read from the device
/// locale, so header text is the same on every Mac and in every test.
enum ScheduleCalendar {
    /// Every Calendar week starts on Monday (Calendar.Component.weekday
    /// convention, 1 = Sunday). The History month grid keeps its Sunday start.
    static let firstWeekday = 2

    static let monthNames = ["January", "February", "March", "April", "May", "June", "July",
                             "August", "September", "October", "November", "December"]

    /// Indexed by `GregorianDay.weekday - 1` (Sunday first).
    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// Short column headers starting at `firstWeekday`: Mon ... Sun.
    static let weekdaySymbols = (0..<7).map { String(weekdayNames[(firstWeekday - 1 + $0) % 7].prefix(3)) }

    static func monthYear(_ day: GregorianDay) -> String { "\(monthNames[day.month - 1]) \(day.year)" }

    /// "Tuesday, June 9, 2026".
    static func fullDate(_ day: GregorianDay) -> String {
        "\(weekdayNames[day.weekday - 1]), \(monthNames[day.month - 1]) \(day.day), \(day.year)"
    }
}

extension GregorianDay {
    /// ISO 8601 weekday: 1 = Monday ... 7 = Sunday.
    var isoWeekday: Int { weekdayOffset(from: 2) + 1 }

    /// ISO 8601 week-numbering year and week (1...53). A week belongs to the
    /// year of its Thursday, so 2026-12-28...2027-01-03 is week 53 of 2026 and
    /// 2024-12-30...2025-01-05 is week 1 of 2025. Throws only when that Thursday
    /// is outside the storable years.
    func isoWeek() throws -> (year: Int, week: Int) {
        let thursday = try adding(days: 4 - isoWeekday)
        let januaryFirst = Self.civilDayNumber(year: thursday.year, month: 1, day: 1)
        return (thursday.year, (thursday.civilDayNumber - januaryFirst) / 7 + 1)
    }
}

/// The text above the Calendar grid. `title` is always month and year; `detail`
/// adds the ISO week in Week view and the full date in Day view.
///
/// - Month: "June 2026"
/// - Week:  "June 2026 · Week 24", "June – July 2026 · Week 27",
///          "December 2026 – January 2027 · Week 53"
/// - Day:   "June 2026 · Tuesday, June 9, 2026"
struct ScheduleHeader: Equatable, Sendable {
    let title: String
    let detail: String?

    var text: String { detail.map { "\(title) · \($0)" } ?? title }
}

/// The visible Calendar period: a mode plus an anchor day inside it. Pure civil
/// arithmetic on GregorianDay, so no time zone, DST or device calendar enters.
///
/// Anchor rules:
/// - Previous/Next move the anchor by one day, seven days, or one month. A month
///   step keeps the day of month, clamped to the target month's length
///   (January 31 → February 28 or 29).
/// - Today makes today the anchor in the current mode.
/// - Switching mode keeps, in order: the selected day if it is in the visible
///   period, else today if it is in the visible period, else the current anchor.
struct SchedulePeriod: Equatable, Sendable {
    let mode: ScheduleViewMode
    let anchor: GregorianDay
    /// Start inclusive, end exclusive: one day, Monday...Sunday, or a whole month.
    let range: HistoryDayRange
    let header: ScheduleHeader

    /// Throws only at the ends of the storable years (0001...9999), where a
    /// period's exclusive end or ISO week cannot be represented.
    init(mode: ScheduleViewMode, anchor: GregorianDay) throws {
        let range: HistoryDayRange
        let header: ScheduleHeader
        switch mode {
        case .day:
            range = try HistoryDayRange(start: anchor, end: anchor.adding(days: 1))
            header = ScheduleHeader(title: ScheduleCalendar.monthYear(anchor),
                                    detail: ScheduleCalendar.fullDate(anchor))
        case .week:
            let start = try anchor.adding(days: -anchor.weekdayOffset(from: ScheduleCalendar.firstWeekday))
            range = try HistoryDayRange(start: start, end: start.adding(days: 7))
            header = try ScheduleHeader(title: Self.spanTitle(range), detail: "Week \(anchor.isoWeek().week)")
        case .month:
            range = try .month(containing: anchor)
            header = ScheduleHeader(title: ScheduleCalendar.monthYear(anchor), detail: nil)
        }
        self.mode = mode
        self.anchor = anchor
        self.range = range
        self.header = header
    }

    /// Every day shown, in order.
    var days: [GregorianDay] {
        (0..<range.dayCount).compactMap { try? range.start.adding(days: $0) }
    }

    func contains(_ day: GregorianDay) -> Bool { range.contains(day) }

    func previous() throws -> Self { try Self(mode: mode, anchor: stepAnchor(forward: false)) }

    func next() throws -> Self { try Self(mode: mode, anchor: stepAnchor(forward: true)) }

    func showingToday(_ today: GregorianDay) throws -> Self { try Self(mode: mode, anchor: today) }

    func switching(to newMode: ScheduleViewMode, selectedDay: GregorianDay?,
                   today: GregorianDay) throws -> Self {
        let anchor = if let selectedDay, contains(selectedDay) {
            selectedDay
        } else if contains(today) {
            today
        } else {
            self.anchor
        }
        return try Self(mode: newMode, anchor: anchor)
    }

    /// Month geometry for this period's month (any mode).
    func monthGrid() throws -> ScheduleMonthGrid { try ScheduleMonthGrid(containing: anchor) }

    private func stepAnchor(forward: Bool) throws -> GregorianDay {
        let sign = forward ? 1 : -1
        switch mode {
        case .day:
            return try anchor.adding(days: sign)
        case .week:
            return try anchor.adding(days: 7 * sign)
        case .month:
            let index = anchor.year * 12 + anchor.month - 1 + sign
            let first = try GregorianDay(year: index / 12, month: index % 12 + 1, day: 1)
            return try HistoryDayRange.month(containing: first).day(clampedTo: anchor.day)
        }
    }

    /// "June 2026", "June – July 2026" or "December 2026 – January 2027".
    private static func spanTitle(_ range: HistoryDayRange) throws -> String {
        let first = range.start
        let last = try range.end.adding(days: -1)
        if first.year != last.year {
            return "\(ScheduleCalendar.monthYear(first)) – \(ScheduleCalendar.monthYear(last))"
        }
        if first.month != last.month {
            return "\(ScheduleCalendar.monthNames[first.month - 1]) – \(ScheduleCalendar.monthYear(last))"
        }
        return ScheduleCalendar.monthYear(first)
    }
}

enum ScheduleMonthCell: Equatable, Identifiable, Sendable {
    /// Blank, inert filler before or after the month; the payload is its position.
    case padding(Int)
    case day(GregorianDay)

    var id: String {
        switch self {
        case let .padding(index): "padding-\(index)"
        case let .day(day): day.key
        }
    }

    var day: GregorianDay? {
        if case let .day(day) = self { day } else { nil }
    }
}

/// Seven-column, Monday-first month geometry for the Calendar's Month view.
/// Shares the padding arithmetic with HistoryMonthGrid but carries no History
/// data; block lists and Today marking belong to the state and view.
struct ScheduleMonthGrid: Equatable, Sendable {
    let month: HistoryDayRange
    let cells: [ScheduleMonthCell]

    var weekdaySymbols: [String] { ScheduleCalendar.weekdaySymbols }

    var weeks: [[ScheduleMonthCell]] {
        stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    init(containing day: GregorianDay) throws {
        let month = try HistoryDayRange.month(containing: day)
        let firstWeekday = ScheduleCalendar.firstWeekday
        var cells = (0..<month.leadingPadding(firstWeekday: firstWeekday)).map(ScheduleMonthCell.padding)
        for number in 1...month.dayCount {
            try cells.append(.day(month.day(clampedTo: number)))
        }
        let trailingStart = cells.count
        cells += (trailingStart..<trailingStart + month.trailingPadding(firstWeekday: firstWeekday))
            .map(ScheduleMonthCell.padding)
        self.month = month
        self.cells = cells
    }
}
