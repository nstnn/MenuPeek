import Foundation

enum TaskHistoryDomainError: Error, Equatable {
    case invalidDayKey(String)
    case invalidRange
    case invalidProgress(completed: Int, total: Int)
    case mismatchedDay
    case missingCategory(UUID)
    case invalidPage
}

/// A Gregorian civil date, independent of a time zone or an absolute instant.
/// Only canonical ASCII YYYY-MM-DD keys in years 0001...9999 are accepted;
/// malformed dates are rejected rather than normalized into another day.
struct GregorianDay: Hashable, Comparable, Sendable {
    let key: String
    let year: Int
    let month: Int
    let day: Int

    init(key: String) throws {
        let bytes = Array(key.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48...57).contains(byte)
              }),
              let year = Int(key.prefix(4)),
              let month = Int(key.dropFirst(5).prefix(2)),
              let day = Int(key.suffix(2)),
              (1...9999).contains(year), (1...12).contains(month) else {
            throw TaskHistoryDomainError.invalidDayKey(key)
        }
        let leapYear = year.isMultiple(of: 4)
            && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        let monthLengths = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...monthLengths[month - 1]).contains(day) else {
            throw TaskHistoryDomainError.invalidDayKey(key)
        }
        self.key = key
        self.year = year
        self.month = month
        self.day = day
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.key < rhs.key }
}

/// A nonempty civil-date interval: start is inclusive and end is exclusive.
/// Canonical keys compare chronologically, including at month/year boundaries.
struct HistoryDayRange: Equatable, Sendable {
    let start: GregorianDay
    let end: GregorianDay

    init(start: GregorianDay, end: GregorianDay) throws {
        guard start < end else { throw TaskHistoryDomainError.invalidRange }
        self.start = start
        self.end = end
    }

    func contains(_ day: GregorianDay) -> Bool { start <= day && day < end }

    /// Civil month boundaries do not depend on DST or the device's time zone.
    /// December 9999 throws because its exclusive end cannot be a stored key.
    static func month(containing day: GregorianDay) throws -> Self {
        let nextYear = day.month == 12 ? day.year + 1 : day.year
        let nextMonth = day.month == 12 ? 1 : day.month + 1
        let locale = Locale(identifier: "en_US_POSIX")
        let start = try GregorianDay(key: String(format: "%04d-%02d-01", locale: locale,
                                                 day.year, day.month))
        let end = try GregorianDay(key: String(format: "%04d-%02d-01", locale: locale,
                                               nextYear, nextMonth))
        return try Self(start: start, end: end)
    }
}

extension NoteDay {
    /// One injected clock reading; only the current-day cutoff follows the
    /// injected time zone. Previously selected GregorianDay values stay fixed.
    func historyKeys() throws -> (today: GregorianDay, yesterday: GregorianDay) {
        let keys = keys()
        return try (GregorianDay(key: keys.today), GregorianDay(key: keys.yesterday))
    }

    func historyMonthRange() throws -> HistoryDayRange {
        try .month(containing: historyKeys().today)
    }
}

/// Derived from all currently saved tasks assigned to this day, never from
/// the date of completedAt. This is not a persisted end-of-day snapshot.
struct DayTaskSummary: Equatable {
    let day: GregorianDay
    let progress: NoteProgress
    let continued: Int

    var dayKey: String { day.key }
    var incomplete: Int { progress.total - progress.completed - continued }

    init(dayKey: String, progress: NoteProgress, continued: Int = 0) throws {
        self.day = try GregorianDay(key: dayKey)
        guard progress.total >= 0, progress.completed >= 0,
              continued >= 0, continued <= progress.total - progress.completed else {
            throw TaskHistoryDomainError.invalidProgress(completed: progress.completed,
                                                        total: progress.total)
        }
        self.progress = progress
        self.continued = continued
    }
}

enum HistoryTaskFilter: CaseIterable, Equatable, Sendable {
    case all, unfinished, completed

    func includes(_ note: Note) -> Bool {
        switch self {
        case .all: true
        case .unfinished: note.isUnfinished
        case .completed: note.isCompleted
        }
    }
}

/// Construct only after categories and ordered notes have been read in one
/// coherent repository transaction. Categories use today's catalog labels;
/// notes retain saved insertion order. Filtering never changes the summary.
struct HistoryDaySnapshot: Equatable {
    let summary: DayTaskSummary
    let notes: [Note]
    let categories: [TaskCategory]

    var dayKey: String { summary.dayKey }
    var progress: NoteProgress { summary.progress }
    /// Full groups retain their whole-group counts; filter their rows for display.
    var groups: [TaskGroup] { TaskGroup.groups(categories: categories, notes: notes) }

    init(dayKey: String, notes: [Note], categories: [TaskCategory]) throws {
        guard notes.allSatisfy({ $0.dayKey == dayKey }) else {
            throw TaskHistoryDomainError.mismatchedDay
        }
        let categoryIDs = Set(categories.map(\.id))
        for note in notes {
            if let id = note.categoryID, !categoryIDs.contains(id) {
                throw TaskHistoryDomainError.missingCategory(id)
            }
        }
        self.summary = try DayTaskSummary(dayKey: dayKey,
                                         progress: NoteProgress(notes: notes, for: dayKey),
                                         continued: notes.count { $0.continuedOn != nil })
        self.notes = notes
        self.categories = categories.sorted { $0.creationOrder < $1.creationOrder }
    }

    func filteredNotes(_ filter: HistoryTaskFilter) -> [Note] {
        notes.filter(filter.includes)
    }
}

/// Sparse month summaries may fill missing days only after a successful read.
/// Unloaded/failed reads have no counts. A future empty day is Not yet; a future
/// day with saved rows is readable and uses the same assigned-day metric.
enum HistoryDayAvailability: Equatable {
    case unavailable
    case notYet
    case available(DayTaskSummary)

    static func loaded(day: GregorianDay, summary: DayTaskSummary?,
                       today: GregorianDay) throws -> Self {
        if let summary {
            guard summary.day == day else { throw TaskHistoryDomainError.mismatchedDay }
            if summary.progress.total > 0 { return .available(summary) }
        }
        if day > today { return .notYet }
        return try .available(DayTaskSummary(dayKey: day.key,
                                            progress: NoteProgress(completed: 0, total: 0)))
    }

    var progress: NoteProgress? {
        guard case let .available(summary) = self else { return nil }
        return summary.progress
    }
}

/// Newest-first days with unfinished tasks, strictly before the request cutoff.
/// The first cutoff is Today; subsequent cutoffs are the oldest published day.
/// Consumers fetch limit + 1 summaries, trim the extra row, then set hasMore.
/// Failures throw before constructing a page; an empty page is a successful read.
struct UnfinishedDayPage: Equatable {
    let before: GregorianDay
    let limit: Int
    let summaries: [DayTaskSummary]
    let nextBefore: GregorianDay?

    init(before: GregorianDay, limit: Int, summaries: [DayTaskSummary], hasMore: Bool) throws {
        guard limit > 0, limit < Int.max, summaries.count <= limit,
              !hasMore || summaries.count == limit else {
            throw TaskHistoryDomainError.invalidPage
        }
        var cutoff = before
        for summary in summaries {
            guard summary.day < cutoff, summary.incomplete > 0 else {
                throw TaskHistoryDomainError.invalidPage
            }
            cutoff = summary.day
        }
        self.before = before
        self.limit = limit
        self.summaries = summaries
        self.nextBefore = hasMore ? summaries.last?.day : nil
    }
}
