import Foundation

enum TaskCategoryRepositoryError: Error, Equatable {
    case duplicateName
    case notFound(UUID)
    case invalidRow
    case orderExhausted
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
    func incompleteCount(for dayKey: String) throws -> Int
    /// Appends a task after the day's existing tasks.
    func add(_ note: Note) throws
    func setCompleted(id: UUID, completedAt: Date?) throws
    /// Saves both fields together, preserving day, timestamps, completion, and order.
    func update(id: UUID, text: String, categoryID: UUID?) throws
    func delete(id: UUID) throws
}
