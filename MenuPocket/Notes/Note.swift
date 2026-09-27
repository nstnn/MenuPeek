import Foundation

/// A note belongs to the local calendar day assigned when it was created.
/// `createdAt` and `completedAt` are absolute instants; changing completion
/// never changes `dayKey`.
struct Note: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let dayKey: String
    let createdAt: Date
    let completedAt: Date?

    var isCompleted: Bool { completedAt != nil }
}

struct NoteProgress: Equatable {
    let completed: Int
    let total: Int

    init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }

    init(notes: [Note], for dayKey: String) {
        let dailyNotes = notes.filter { $0.dayKey == dayKey }
        self.init(completed: dailyNotes.count(where: \.isCompleted), total: dailyNotes.count)
    }
}

enum NoteOrder {
    /// Incomplete notes first; newest creation first within each group.
    /// The ID makes ordering deterministic when creation instants match.
    static func sorted(_ notes: [Note]) -> [Note] {
        notes.sorted { left, right in
            if left.isCompleted != right.isCompleted {
                return !left.isCompleted
            }
            if left.createdAt != right.createdAt {
                return left.createdAt > right.createdAt
            }
            return left.id.uuidString < right.id.uuidString
        }
    }
}
