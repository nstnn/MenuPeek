import Foundation

/// All mutations either persist fully or throw, including writes for a missing
/// ID. Callers should publish changed notes only after successful persistence.
protocol NoteRepository {
    /// Returns tasks in saved insertion order, independent of completion or timestamps.
    func notes(for dayKey: String) throws -> [Note]
    func incompleteCount(for dayKey: String) throws -> Int
    /// Appends a task after the day's existing tasks.
    func add(_ note: Note) throws
    func setCompleted(id: UUID, completedAt: Date?) throws
    func updateText(id: UUID, text: String) throws
    func delete(id: UUID) throws
}
