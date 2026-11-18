import Foundation

extension GregorianDay {
    /// Days since 1970-01-01 in the proleptic Gregorian calendar (H. Hinnant's
    /// days_from_civil). Pure civil arithmetic: no time zone, DST, or Julian
    /// cutover, so it agrees with GregorianDay's own leap rule for 0001...9999.
    var civilDayNumber: Int { Self.civilDayNumber(year: year, month: month, day: day) }

    static func civilDayNumber(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// 1 = Sunday ... 7 = Saturday, matching Calendar.Component.weekday.
    var weekday: Int { ((civilDayNumber % 7 + 11) % 7) + 1 }

    /// Days since the most recent `firstWeekday` (1 = Sunday), in 0...6. This is
    /// both a week's start offset and a month grid's leading padding.
    func weekdayOffset(from firstWeekday: Int) -> Int { (weekday - firstWeekday + 7) % 7 }

    private static let firstCivilDayNumber = civilDayNumber(year: 1, month: 1, day: 1)
    private static let lastCivilDayNumber = civilDayNumber(year: 9999, month: 12, day: 31)

    /// A canonical key from numeric parts; invalid parts throw like `init(key:)`.
    init(year: Int, month: Int, day: Int) throws {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            throw TaskHistoryDomainError.invalidDayKey("\(year)-\(month)-\(day)")
        }
        try self.init(key: String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"),
                                  year, month, day))
    }

    /// Inverse of `civilDayNumber` (H. Hinnant's civil_from_days). A day outside
    /// 0001-01-01...9999-12-31 throws instead of wrapping or overflowing.
    init(civilDayNumber number: Int) throws {
        guard (Self.firstCivilDayNumber...Self.lastCivilDayNumber).contains(number) else {
            throw TaskHistoryDomainError.invalidRange
        }
        let z = number + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        try self.init(year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month: month, day: day)
    }

    /// The civil day `days` away; throws outside the storable years.
    func adding(days: Int) throws -> GregorianDay {
        let (number, overflow) = civilDayNumber.addingReportingOverflow(days)
        guard !overflow else { throw TaskHistoryDomainError.invalidRange }
        return try GregorianDay(civilDayNumber: number)
    }
}

extension HistoryDayRange {
    /// Derived from the exclusive next-month boundary, never a month-length table.
    var dayCount: Int { end.civilDayNumber - start.civilDayNumber }

    /// The day of this month nearest to `preferred`, clamped to 1...dayCount
    /// (for example, the 31st becomes February 28 or 29).
    func day(clampedTo preferred: Int) throws -> GregorianDay {
        try GregorianDay(year: start.year, month: start.month, day: min(max(preferred, 1), dayCount))
    }

    /// Blank cells before the first day in a seven-column grid whose first
    /// column is `firstWeekday` (1 = Sunday).
    func leadingPadding(firstWeekday: Int) -> Int { start.weekdayOffset(from: firstWeekday) }

    /// Blank cells after the last day so the final row is complete.
    func trailingPadding(firstWeekday: Int) -> Int {
        (7 - (leadingPadding(firstWeekday: firstWeekday) + dayCount) % 7) % 7
    }
}

/// One in-month cell. Identity is the saved civil key, so a time-zone change
/// moves only the Today marker, never the cell a dayKey belongs to.
struct HistoryCalendarDay: Equatable, Identifiable {
    let day: GregorianDay
    let availability: HistoryDayAvailability
    let isToday: Bool
    let isSelected: Bool
    let isFuture: Bool

    var id: String { day.key }

    /// Past/today days open the read-only detail even when the month read failed,
    /// because detail has its own read. A future day is selectable only when the
    /// loaded month shows saved rows; it never offers a composer.
    var isSelectable: Bool { !isFuture || (availability.progress?.total ?? 0) > 0 }

    var countText: String {
        switch availability {
        case let .available(summary): "\(summary.progress.completed)/\(summary.progress.total)"
        case .notYet: "—"
        case .unavailable: "Unavailable"
        }
    }

    /// Spoken status; counts never rely on color.
    var statusText: String {
        switch availability {
        case let .available(summary) where summary.progress.total == 0: "No tasks"
        case let .available(summary): "\(summary.progress.completed) of \(summary.progress.total) complete"
        case .notYet: "Not yet"
        case .unavailable: "Unavailable"
        }
    }
}

enum HistoryCalendarCell: Equatable, Identifiable {
    /// Blank, non-actionable filler before or after the month.
    case padding(Int)
    case day(HistoryCalendarDay)

    var id: String {
        switch self {
        case let .padding(index): "padding-\(index)"
        case let .day(day): day.id
        }
    }
}

/// Seven-column month geometry for the History calendar. Pure value: Today comes
/// from the injected NoteDay through TaskHistoryState, and summaries are the
/// sparse month read (nil while unloaded or failed, so no counts are invented).
struct HistoryMonthGrid: Equatable {
    static let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    let month: HistoryDayRange
    let firstWeekday: Int
    let cells: [HistoryCalendarCell]

    /// Column headers starting at firstWeekday.
    var weekdaySymbols: [String] {
        (0..<7).map { Self.weekdaySymbols[(firstWeekday - 1 + $0) % 7] }
    }

    var weeks: [[HistoryCalendarCell]] {
        stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// firstWeekday uses Calendar's convention (1 = Sunday); presentation may
    /// change it without affecting storage or read APIs.
    init(month: HistoryDayRange, today: GregorianDay, selectedDay: GregorianDay?,
         summaries: [DayTaskSummary]?, firstWeekday: Int = 1) throws {
        guard (1...7).contains(firstWeekday) else { throw TaskHistoryDomainError.invalidRange }
        var byDay: [GregorianDay: DayTaskSummary]?
        if let summaries {
            byDay = [:]
            for summary in summaries {
                guard month.contains(summary.day), byDay?.updateValue(summary, forKey: summary.day) == nil else {
                    throw TaskHistoryDomainError.mismatchedDay
                }
            }
        }
        var cells = (0..<month.leadingPadding(firstWeekday: firstWeekday)).map(HistoryCalendarCell.padding)
        for number in 1...month.dayCount {
            let day = try month.day(clampedTo: number)
            let availability: HistoryDayAvailability = if let byDay {
                try .loaded(day: day, summary: byDay[day], today: today)
            } else {
                .unavailable
            }
            cells.append(.day(HistoryCalendarDay(day: day, availability: availability, isToday: day == today,
                                                 isSelected: day == selectedDay, isFuture: day > today)))
        }
        let trailingStart = cells.count
        cells += (trailingStart..<trailingStart + month.trailingPadding(firstWeekday: firstWeekday))
            .map(HistoryCalendarCell.padding)
        self.month = month
        self.firstWeekday = firstWeekday
        self.cells = cells
    }
}
