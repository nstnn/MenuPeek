import Foundation
import Observation

struct HistoryDetailGroup: Identifiable, Equatable {
    let group: TaskGroup
    let visibleNotes: [Note]
    var id: TaskGroupID { group.id }
}

enum HistoryPaneIssue: Equatable {
    case month, day

    var message: String {
        switch self {
        case .month: "Could not load this month. Try again."
        case .day: "Could not load this day. Try again."
        }
    }
}

/// Process-local read projection. The shell forwards visibility and the shared
/// historyRevision; this object owns no repository, defaults, or lifecycle observers.
/// Reads are synchronous on the main actor, so selection cannot change across an await.
@MainActor
@Observable
final class TaskHistoryState {
    private(set) var today: GregorianDay
    private(set) var month: HistoryDayRange
    /// Disclosure is per viewed day: choosing another day starts expanded.
    private(set) var selectedDay: GregorianDay? {
        didSet { if oldValue != selectedDay { collapsedGroups = [] } }
    }
    private(set) var filter: HistoryTaskFilter = .all
    private(set) var monthSummaries: [DayTaskSummary]?
    private(set) var daySnapshot: HistoryDaySnapshot?
    private(set) var monthIssue: HistoryPaneIssue?
    private(set) var dayIssue: HistoryPaneIssue?
    private(set) var monthDirty = true
    private(set) var dayDirty = true
    private(set) var collapsedGroups: Set<TaskGroupID> = []

    @ObservationIgnored private let noteDay: NoteDay
    @ObservationIgnored private let readMonth: (HistoryDayRange) throws -> [DayTaskSummary]
    @ObservationIgnored private let readDay: (String) throws -> HistoryDaySnapshot
    @ObservationIgnored private var monthVisible = false
    @ObservationIgnored private var dayVisible = false
    @ObservationIgnored private var revision: UInt64?
    @ObservationIgnored private var preferredDay: Int
    @ObservationIgnored private var pendingFutureDay: GregorianDay?

    init(noteDay: NoteDay = NoteDay(),
         readMonth: @escaping (HistoryDayRange) throws -> [DayTaskSummary],
         readDay: @escaping (String) throws -> HistoryDaySnapshot) throws {
        let keys = try noteDay.historyKeys()
        today = keys.today
        selectedDay = keys.yesterday
        month = try .month(containing: keys.yesterday)
        preferredDay = keys.yesterday.day
        self.noteDay = noteDay
        self.readMonth = readMonth
        self.readDay = readDay
    }

    convenience init(dailyState: DailyNotesState, noteDay: NoteDay = NoteDay()) throws {
        try self.init(noteDay: noteDay,
                      readMonth: { try dailyState.daySummaries(in: $0) },
                      readDay: { try dailyState.historyDaySnapshot(for: $0) })
    }

    var progress: NoteProgress? { daySnapshot?.progress }
    var detailGroups: [HistoryDetailGroup] {
        daySnapshot?.groups.compactMap { group in
            let rows = group.notes.filter(filter.includes)
            return rows.isEmpty ? nil : HistoryDetailGroup(group: group, visibleNotes: rows)
        } ?? []
    }

    var detailMessage: String? {
        guard let snapshot = daySnapshot else {
            if dayIssue != nil { return dayIssue?.message }
            return selectedDay == nil && monthSummaries != nil ? "Not yet" : nil
        }
        if snapshot.notes.isEmpty { return "No saved tasks for this day." }
        guard snapshot.filteredNotes(filter).isEmpty else { return nil }
        return filter == .completed ? "No completed tasks for this day." : "No unfinished tasks for this day."
    }

    func setFilter(_ filter: HistoryTaskFilter) { self.filter = filter }

    func toggleDisclosure(_ id: TaskGroupID) {
        if !collapsedGroups.insert(id).inserted { collapsedGroups.remove(id) }
    }

    func setVisible(month: Bool, day: Bool) {
        monthVisible = month
        dayVisible = day
        reloadVisible()
    }

    /// Forward after the existing lifecycle refresh settles. Civil selection is
    /// retained when the injected time zone or Today cutoff changes.
    func refresh(revision newRevision: UInt64) throws {
        let currentToday = try noteDay.historyKeys().today
        guard revision != newRevision || currentToday != today else { return }
        revision = newRevision
        today = currentToday
        monthDirty = true
        dayDirty = true
        invalidateMonth()
        invalidateDay()
        if let candidate = pendingFutureDay { selectedDay = candidate <= today ? candidate : nil }
        reloadVisible()
    }

    /// Explicit routes (including yesterday/Unfinished) choose both date and filter.
    func select(_ day: GregorianDay, filter: HistoryTaskFilter = .all) throws {
        let range = try HistoryDayRange.month(containing: day)
        if range != month {
            month = range
            invalidateMonth()
        }
        self.filter = filter
        preferredDay = day.day
        pendingFutureDay = nil
        selectedDay = day
        invalidateDay()
        reloadVisible()
    }

    func changeMonth(containing day: GregorianDay) throws {
        let range = try HistoryDayRange.month(containing: day)
        // Gregorian UTC arithmetic operates on civil components, never 86400 seconds.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: range.start.year, month: range.start.month, day: 1))!
        let count = calendar.range(of: .day, in: .month, for: start)!.count
        let candidate = try GregorianDay(key: String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"),
                                                     range.start.year, range.start.month, min(preferredDay, count)))
        preferredDay = candidate.day
        month = range
        invalidateMonth()
        invalidateDay()
        selectedDay = candidate <= today ? candidate : nil
        pendingFutureDay = candidate > today ? candidate : nil
        reloadVisible()
    }

    func showPreviousMonth() throws {
        let start = month.start
        let year = start.month == 1 ? start.year - 1 : start.year
        let previous = start.month == 1 ? 12 : start.month - 1
        try changeMonth(containing: GregorianDay(key: String(format: "%04d-%02d-01", locale: Locale(identifier: "en_US_POSIX"),
                                                             year, previous)))
    }

    /// The exclusive end is the first day of the next month.
    func showNextMonth() throws { try changeMonth(containing: month.end) }

    func thisMonth() throws {
        today = try noteDay.historyKeys().today
        invalidateMonth()
        try select(today, filter: .all)
    }

    func retryMonth() {
        invalidateMonth()
        loadMonth()
        if dayVisible && dayDirty { loadDay() }
    }

    func retryDay() {
        invalidateDay()
        loadDay()
    }

    private func invalidateMonth() {
        monthSummaries = nil
        monthIssue = nil
        monthDirty = true
    }

    private func invalidateDay() {
        daySnapshot = nil
        dayIssue = nil
        dayDirty = true
    }

    private func reloadVisible() {
        if (monthVisible || (dayVisible && pendingFutureDay != nil)) && monthDirty { loadMonth() }
        if dayVisible && dayDirty { loadDay() }
    }

    private func loadMonth() {
        do {
            let summaries = try readMonth(month)
            guard summaries.allSatisfy({ month.contains($0.day) }),
                  Set(summaries.map(\.day)).count == summaries.count else {
                throw TaskHistoryDomainError.mismatchedDay
            }
            monthSummaries = summaries
            monthIssue = nil
            if let candidate = pendingFutureDay {
                let previousSelection = selectedDay
                selectedDay = candidate <= today || summaries.contains(where: { $0.day == candidate && $0.progress.total > 0 })
                    ? candidate : nil
                if previousSelection != selectedDay { invalidateDay() }
            }
        } catch {
            monthSummaries = nil
            monthIssue = .month
        }
        monthDirty = false
    }

    private func loadDay() {
        guard let selectedDay else { return }
        do {
            let snapshot = try readDay(selectedDay.key)
            guard snapshot.summary.day == selectedDay else { throw TaskHistoryDomainError.mismatchedDay }
            daySnapshot = snapshot
            dayIssue = nil
        } catch {
            daySnapshot = nil
            dayIssue = .day
        }
        dayDirty = false
    }
}
