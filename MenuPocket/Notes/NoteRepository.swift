import Foundation

/// All mutations either persist fully or throw, including writes for a missing
/// ID. Callers should publish changed notes only after successful persistence.
protocol NoteRepository {
    func notes(for dayKey: String) throws -> [Note]
    func incompleteCount(for dayKey: String) throws -> Int
    func add(_ note: Note) throws
    func setCompleted(id: UUID, completedAt: Date?) throws
    func updateText(id: UUID, text: String) throws
    func delete(id: UUID) throws
}
