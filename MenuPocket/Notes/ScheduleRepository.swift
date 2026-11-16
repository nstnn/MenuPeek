import Foundation

enum ScheduleRepositoryError: Error, Equatable {
    /// No saved block has this ID. Nothing was written.
    case notFound(UUID)
    /// A saved block already uses this ID. The saved block is unchanged.
    case duplicateID(UUID)
    /// A saved row failed `ScheduleBlockContent` validation. Reads throw
    /// rather than skip or repair it, so a calendar is never shown partly.
    case invalidRow
}

/// Calendar block storage, separate from `NoteRepository` so task fakes and
/// task behaviour are unaffected. Values arrive already validated as
/// `ScheduleBlock` / `ScheduleBlockContent`.
///
/// Every mutation persists fully or throws, and a throw leaves saved blocks
/// unchanged. Callers publish a change only after the call returns.
protocol ScheduleRepository {
    /// Blocks whose day lies in [range.start, range.end), sorted by
    /// `ScheduleBlock.isOrderedBefore`. A failed or malformed read throws
    /// (`ScheduleRepositoryError.invalidRow` for a bad row); only a successful
    /// read may be empty.
    func scheduleBlocks(in range: HistoryDayRange) throws -> [ScheduleBlock]
    /// Saves a new block. Throws `.duplicateID` without replacing a saved block.
    func addScheduleBlock(_ block: ScheduleBlock) throws
    /// Replaces title, day, start and end together, keeping the ID and
    /// creation instant, and returns the saved block. Throws `.notFound`.
    func updateScheduleBlock(id: UUID, to content: ScheduleBlockContent) throws -> ScheduleBlock
    /// Removes the block. Throws `.notFound` for a missing ID.
    func deleteScheduleBlock(id: UUID) throws
}
