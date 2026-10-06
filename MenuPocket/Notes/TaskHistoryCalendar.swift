import Foundation

extension GregorianDay {
    /// Days since 1970-01-01 in the proleptic Gregorian calendar (H. Hinnant's
    /// days_from_civil). Pure civil arithmetic: no time zone, DST, or Julian
    /// cutover, so it agrees with GregorianDay's own leap rule for 0001...9999.
    var civilDayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// 1 = Sunday ... 7 = Saturday, matching Calendar.Component.weekday.
    var weekday: Int { ((civilDayNumber % 7 + 11) % 7) + 1 }
}

extension HistoryDayRange {
    /// Derived from the exclusive next-month boundary, never a month-length table.
    var dayCount: Int { end.civilDayNumber - start.civilDayNumber }

    /// The day of this month nearest to `preferred`, clamped to 1...dayCount
    /// (for example, the 31st becomes February 28 or 29).
    func day(clampedTo preferred: Int) throws -> GregorianDay {
        try GregorianDay(key: String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"),
                                     start.year, start.month, min(max(preferred, 1), dayCount)))
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
        let leading = (month.start.weekday - firstWeekday + 7) % 7
        var cells = (0..<leading).map(HistoryCalendarCell.padding)
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
        while !cells.count.isMultiple(of: 7) { cells.append(.padding(cells.count)) }
        self.month = month
        self.firstWeekday = firstWeekday
        self.cells = cells
    }
}
