import Foundation
import Observation

/// What the Calendar pane may show for the visible period. `unavailable` is
/// never shown as an empty calendar; only a successful read is `loaded`.
enum ScheduleContent: Equatable {
    /// Not read yet for this period (for example while the pane is hidden).
    case notLoaded
    /// The saved blocks of the visible period, in repository order.
    case loaded([ScheduleBlock])
    /// The read failed; the pane shows `ScheduleState.loadMessage` and Retry.
    case unavailable
}

/// Why a block command failed. Published blocks are unchanged in every case.
enum ScheduleCommandFailure: Error, Equatable {
    case add
    case update
    case delete
    /// The block is no longer saved (update or delete of a missing ID).
    case missing

    var message: String {
        switch self {
        case .add: "Could not save block. Try again."
        case .update: "Could not save block changes. Try again."
        case .delete: "Could not delete block. Try again."
        case .missing: "This block no longer exists."
        }
    }
}

enum ScheduleStateError: Error, Equatable {
    /// The shared store does not provide Calendar blocks.
    case repositoryUnavailable
    /// A read returned a block outside the period that was asked for.
    case blockOutsidePeriod
}

/// The Calendar pane's state: the visible period and its saved blocks.
///
/// Reads are synchronous on the main actor, so the period cannot change while a
/// read or write is in flight. Each successful write reloads the current period,
/// so published order always equals repository order and a write never adds a
/// block the repository did not return. A hidden Calendar does not read: a
/// period change or write while hidden only marks the period dirty.
@MainActor
@Observable
final class ScheduleState {
    private(set) var period: SchedulePeriod
    private(set) var content: ScheduleContent = .notLoaded
    /// The Today marker. Changes only through `refreshToday()`; never reloads blocks.
    private(set) var today: GregorianDay
    /// The day the user last chose, or the day Day view shows; kept across mode
    /// switches when visible.
    private(set) var selectedDay: GregorianDay?

    @ObservationIgnored private let noteDay: NoteDay
    @ObservationIgnored private let openRepository: () throws -> any ScheduleRepository
    @ObservationIgnored private let makeID: () -> UUID
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var dirty = true

    init(noteDay: NoteDay = NoteDay(),
         makeID: @escaping () -> UUID = UUID.init,
         repository: @escaping () throws -> any ScheduleRepository) throws {
        let today = try noteDay.historyKeys().today
        self.today = today
        period = try SchedulePeriod(mode: .initial, anchor: today)
        self.noteDay = noteDay
        self.makeID = makeID
        openRepository = repository
    }

    var mode: ScheduleViewMode { period.mode }
    var header: ScheduleHeader { period.header }
    var days: [GregorianDay] { period.days }

    /// nil unless the visible period loaded successfully.
    var blocks: [ScheduleBlock]? {
        if case let .loaded(blocks) = content { blocks } else { nil }
    }

    var isUnavailable: Bool { content == .unavailable }

    /// "Could not load this week. Try again." while unavailable, else nil.
    var loadMessage: String? {
        guard isUnavailable else { return nil }
        let unit = switch period.mode {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        }
        return "Could not load this \(unit). Try again."
    }

    func isToday(_ day: GregorianDay) -> Bool { day == today }

    /// The civil day and minute now, on the same clock and time zone as Today.
    /// Read by the current-time line on each tick; never changes the period.
    func currentTime() -> ScheduleCurrentTime? {
        ScheduleCurrentTime(instant: noteDay.now(), calendar: noteDay.calendar)
    }

    /// The loaded blocks on one day, in repository order.
    func blocks(on day: GregorianDay) -> [ScheduleBlock] {
        blocks?.filter { $0.day == day } ?? []
    }

    // MARK: Visibility and refresh

    func setVisible(_ visible: Bool) {
        self.visible = visible
        guard visible else { return }
        refreshToday()
        if dirty { load() }
    }

    /// Moves the Today marker when the civil day changed (midnight, clock or
    /// time-zone change). Blocks and the visible period are left alone.
    func refreshToday() {
        guard let current = try? noteDay.historyKeys().today, current != today else { return }
        today = current
    }

    func retry() {
        dirty = true
        load()
    }

    // MARK: Navigation

    /// Each returns false and changes nothing at the ends of the storable years.
    @discardableResult
    func showPrevious() -> Bool { show { try period.previous() } }

    @discardableResult
    func showNext() -> Bool { show { try period.next() } }

    @discardableResult
    func showToday() -> Bool {
        refreshToday()
        return show { try period.showingToday(today) }
    }

    @discardableResult
    func setMode(_ mode: ScheduleViewMode) -> Bool {
        guard mode != period.mode else { return true }
        refreshToday()
        return show { try period.switching(to: mode, selectedDay: selectedDay, today: today) }
    }

    /// Opens one day in Day view, for example from a Month cell.
    @discardableResult
    func showDay(_ day: GregorianDay) -> Bool {
        guard show({ try SchedulePeriod(mode: .day, anchor: day) }) else { return false }
        selectedDay = day
        return true
    }

    /// Remembers a chosen day without changing the period.
    func select(_ day: GregorianDay?) { selectedDay = day }

    private func show(_ makePeriod: () throws -> SchedulePeriod) -> Bool {
        guard let next = try? makePeriod() else { return false }
        // Day view shows exactly one day, so that day is the selection. Stepping
        // with Previous/Next/Today then carries it into Week and Month.
        if next.mode == .day { selectedDay = next.anchor }
        guard next != period else { return true }
        period = next
        content = .notLoaded
        dirty = true
        if visible { load() }
        return true
    }

    // MARK: Commands

    /// Saves a new block. On success the period is reloaded and the saved block returned.
    @discardableResult
    func add(_ content: ScheduleBlockContent) -> Result<ScheduleBlock, ScheduleCommandFailure> {
        let block = ScheduleBlock(id: makeID(), content: content, createdAt: noteDay.now())
        do {
            try openRepository().addScheduleBlock(block)
        } catch {
            return .failure(.add)
        }
        didWrite()
        return .success(block)
    }

    @discardableResult
    func update(id: UUID, to content: ScheduleBlockContent) -> Result<ScheduleBlock, ScheduleCommandFailure> {
        let saved: ScheduleBlock
        do {
            saved = try openRepository().updateScheduleBlock(id: id, to: content)
        } catch ScheduleRepositoryError.notFound {
            return .failure(.missing)
        } catch {
            return .failure(.update)
        }
        didWrite()
        return .success(saved)
    }

    @discardableResult
    func delete(id: UUID) -> Result<Void, ScheduleCommandFailure> {
        do {
            try openRepository().deleteScheduleBlock(id: id)
        } catch ScheduleRepositoryError.notFound {
            return .failure(.missing)
        } catch {
            return .failure(.delete)
        }
        didWrite()
        return .success(())
    }

    // MARK: Loading

    private func didWrite() {
        dirty = true
        if visible { load() }
    }

    private func load() {
        let range = period.range
        do {
            let read = try openRepository().scheduleBlocks(in: range)
            guard read.allSatisfy({ range.contains($0.day) }) else {
                throw ScheduleStateError.blockOutsidePeriod
            }
            content = .loaded(read)
        } catch {
            content = .unavailable
        }
        dirty = false
    }
}

extension ScheduleState {
    /// Reads and writes through the task window's shared store and civil clock.
    convenience init(dailyState: DailyNotesState, noteDay: NoteDay = NoteDay(),
                     makeID: @escaping () -> UUID = UUID.init) throws {
        try self.init(noteDay: noteDay, makeID: makeID,
                      repository: { try dailyState.scheduleRepository() })
    }
}
