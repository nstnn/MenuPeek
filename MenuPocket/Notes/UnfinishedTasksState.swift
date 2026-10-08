import Foundation
import Observation

struct UnfinishedDaySelection: Equatable {
    let day: GregorianDay
    let generation: UInt64
    let filter: HistoryTaskFilter = .unfinished
}

enum UnfinishedPaneIssue: Equatable {
    case initial, append

    var message: String {
        switch self {
        case .initial: "Could not load unfinished days. Try again."
        case .append: "Could not load more days. Try again."
        }
    }
}

enum UnfinishedSelectionIssue: Equatable {
    case noLongerPast, noUnfinishedTasks

    var message: String {
        switch self {
        case .noLongerPast: "This day is no longer before Today."
        case .noUnfinishedTasks: "This day no longer contains unfinished tasks."
        }
    }
}

/// Read-only date index. The shell forwards visibility/revisions and opens the
/// shared History detail using selectionIntent. No task arrays are cached here.
@MainActor
@Observable
final class UnfinishedTasksState {
    private(set) var today: GregorianDay
    /// nil means unavailable/unloaded; [] is a successful empty first page.
    private(set) var summaries: [DayTaskSummary]?
    private(set) var nextBefore: GregorianDay?
    private(set) var initialIssue: UnfinishedPaneIssue?
    private(set) var appendIssue: UnfinishedPaneIssue?
    private(set) var selectedDay: GregorianDay?
    private(set) var selectionIssue: UnfinishedSelectionIssue?
    private(set) var dirty = true
    private(set) var generation: UInt64 = 0
    let pageSize: Int

    @ObservationIgnored private let noteDay: NoteDay
    @ObservationIgnored private let readPage: (GregorianDay, Int) throws -> UnfinishedDayPage
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var revision: UInt64?
    @ObservationIgnored private var readingGeneration: UInt64?

    init(noteDay: NoteDay = NoteDay(), pageSize: Int = 31,
         readPage: @escaping (GregorianDay, Int) throws -> UnfinishedDayPage) throws {
        guard pageSize > 0, pageSize < Int.max else { throw TaskHistoryDomainError.invalidPage }
        today = try noteDay.historyKeys().today
        self.noteDay = noteDay
        self.pageSize = pageSize
        self.readPage = readPage
    }

    convenience init(dailyState: DailyNotesState, noteDay: NoteDay = NoteDay(), pageSize: Int = 31) throws {
        try self.init(noteDay: noteDay, pageSize: pageSize,
                      readPage: { try dailyState.unfinishedDayPage(before: $0, limit: $1) })
    }

    var hasMore: Bool { nextBefore != nil }
    var isEmpty: Bool { summaries?.isEmpty == true }
    var selectionIntent: UnfinishedDaySelection? {
        guard let selectedDay, selectionIssue == nil else { return nil }
        return UnfinishedDaySelection(day: selectedDay, generation: generation)
    }

    func setVisible(_ visible: Bool) {
        self.visible = visible
        if visible && dirty { loadFirstPage() }
    }

    func refresh(revision newRevision: UInt64) throws {
        let cutoff = try noteDay.historyKeys().today
        guard revision != newRevision || cutoff != today else { return }
        revision = newRevision
        today = cutoff
        reset()
        if visible { loadFirstPage() }
    }

    func retryInitial() {
        reset()
        loadFirstPage()
    }

    func loadMore() {
        guard !dirty, summaries != nil, let cutoff = nextBefore else { return }
        load(before: cutoff, appending: true)
    }

    @discardableResult
    func select(_ day: GregorianDay) -> UnfinishedDaySelection? {
        guard day < today, summaries?.contains(where: { $0.day == day }) == true else { return nil }
        selectedDay = day
        selectionIssue = nil
        return selectionIntent
    }

    /// Call with the shared History state's successful full-day read. Its whole-
    /// day counts remain in History; stale detail results cannot change this index.
    func reconcileSelection(_ intent: UnfinishedDaySelection, snapshot: HistoryDaySnapshot) {
        guard intent.generation == generation, intent.day == selectedDay,
              snapshot.summary.day == intent.day else { return }
        selectionIssue = intent.day >= today ? .noLongerPast
            : snapshot.summary.incomplete == 0 ? .noUnfinishedTasks : nil
    }

    private func reset() {
        generation &+= 1
        summaries = nil
        nextBefore = nil
        initialIssue = nil
        appendIssue = nil
        dirty = true
        selectionIssue = selectedDay.map { $0 >= today ? .noLongerPast : nil } ?? nil
    }

    private func loadFirstPage() { load(before: today, appending: false) }

    // Production reads are synchronous on the main actor. The generation guard
    // also protects against a read closure reentering refresh during a request.
    private func load(before cutoff: GregorianDay, appending: Bool) {
        let requestGeneration = generation
        guard readingGeneration != requestGeneration else { return }
        readingGeneration = requestGeneration
        defer {
            if readingGeneration == requestGeneration { readingGeneration = nil }
        }
        do {
            let page = try readPage(cutoff, pageSize)
            guard requestGeneration == generation else { return }
            guard page.before == cutoff, page.limit == pageSize else {
                throw TaskHistoryDomainError.invalidPage
            }
            summaries = (appending ? summaries ?? [] : []) + page.summaries
            nextBefore = page.nextBefore
            initialIssue = nil
            appendIssue = nil
            dirty = false
            if let selectedDay, selectedDay < today,
               summaries?.contains(where: { $0.day == selectedDay }) == false,
               nextBefore == nil || summaries?.last.map({ selectedDay >= $0.day }) == true {
                selectionIssue = .noUnfinishedTasks
            }
        } catch {
            guard requestGeneration == generation else { return }
            if appending { appendIssue = .append }
            else { initialIssue = .initial; dirty = false }
        }
    }
}
