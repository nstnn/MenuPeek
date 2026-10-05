import Foundation

/// An unscheduled task in the Later list. It has no calendar day, deadline, or
/// planned date: `createdAt` and `completedAt` are internal bookkeeping
/// instants, never user-editable date inputs. Changing completion keeps the
/// task's identity, text, category, creation instant, and saved position.
struct LaterTask: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date
    let completedAt: Date?
    /// nil means the built-in General group, which has no saved category UUID.
    let categoryID: UUID?

    init(id: UUID, text: String, createdAt: Date, completedAt: Date?, categoryID: UUID? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.categoryID = categoryID
    }

    var isCompleted: Bool { completedAt != nil }
}

/// The two task lists shown in the task window.
enum TaskListDestination: Equatable, Sendable {
    case today
    case later
}

/// Identifies the saved task an edit or deletion acts on, including its list,
/// so an action can never reach a row with the same UUID in the other list.
/// A daily target also carries its assigned day, so a stale day cancels it;
/// a Later target has no day and is unaffected by day changes.
enum TaskActionTarget: Equatable, Sendable {
    case daily(id: UUID, dayKey: String)
    case later(id: UUID)

    var id: UUID {
        switch self {
        case .daily(let id, _), .later(let id): id
        }
    }

    var destination: TaskListDestination {
        switch self {
        case .daily: .today
        case .later: .later
        }
    }
}
