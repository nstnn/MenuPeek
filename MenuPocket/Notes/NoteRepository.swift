import Foundation

enum TaskCategoryRepositoryError: Error, Equatable {
    case duplicateName
    case notFound(UUID)
    case invalidRow
    case orderExhausted
}

enum LaterTaskRepositoryError: Error, Equatable {
    /// No saved Later task has this ID.
    case notFound(UUID)
    /// Only unfinished Later tasks can move to Today.
    case alreadyCompleted(UUID)
    /// A daily task already uses this ID, so a move would duplicate it.
    case idCollision(UUID)
    /// The repository does not implement this Later operation yet. Nothing was
    /// read or written; callers must treat it as a failure, never as empty data.
    case unsupported(String)
}

/// All mutations either persist fully or throw, including writes for a missing
/// ID. Callers should publish changed notes only after successful persistence.
protocol NoteRepository {
    /// Custom categories only, in saved creation order. General has no row.
    func categories() throws -> [TaskCategory]
    func createCategory(name: String) throws -> TaskCategory
    /// Keeps the category's identity and creation order.
    func renameCategory(id: UUID, name: String) throws -> TaskCategory
    /// Includes completed and incomplete tasks across every saved day.
    /// A missing category throws, rather than reporting an unused category.
    func categoryUsageCount(id: UUID) throws -> Int
    /// Preserves every task and clears its association, atomically across all days.
    func removeCategory(id: UUID) throws

    /// Returns tasks in saved insertion order, independent of completion or timestamps.
    func notes(for dayKey: String) throws -> [Note]
    /// Sparse whole-day counts, ordered oldest first, in [start, end).
    /// A failed or malformed read throws; only successful reads may be empty.
    func daySummaries(in range: HistoryDayRange) throws -> [DayTaskSummary]
    /// Current catalog and ordered tasks from one coherent, read-only snapshot.
    /// Required-read or validation failures throw, never publish a partial day.
    func historyDaySnapshot(for dayKey: String) throws -> HistoryDaySnapshot
    func incompleteCount(for dayKey: String) throws -> Int
    /// Appends a task after the day's existing tasks.
    func add(_ note: Note) throws
    func setCompleted(id: UUID, completedAt: Date?) throws
    /// Saves both fields together, preserving day, timestamps, completion, and order.
    func update(id: UUID, text: String, categoryID: UUID?) throws
    func delete(id: UUID) throws

    /// Later tasks in saved insertion order, including completed ones.
    func laterTasks() throws -> [LaterTask]
    /// Appends a task after the existing Later tasks.
    func addLater(_ task: LaterTask) throws
    /// Preserves identity, text, category, creation instant, and order.
    func setLaterCompleted(id: UUID, completedAt: Date?) throws
    /// Saves both fields together, preserving timestamps, completion, and order.
    func updateLater(id: UUID, text: String, categoryID: UUID?) throws
    func deleteLater(id: UUID) throws
    /// Atomically moves one unfinished Later task to the end of `dayKey`'s
    /// tasks, keeping its ID, text, category, and creation instant, and returns
    /// the saved daily task. The caller supplies `dayKey` from the action-time
    /// clock, never from the task's creation instant. Throws
    /// `LaterTaskRepositoryError.notFound`, `.alreadyCompleted`, or
    /// `.idCollision` without changing either list.
    func moveLaterToToday(id: UUID, dayKey: String) throws -> Note
}
