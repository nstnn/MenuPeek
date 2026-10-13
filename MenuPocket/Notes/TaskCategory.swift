import Foundation

/// A custom category's identity and saved order are independent of its name.
/// General is represented by a nil Note.categoryID, never a TaskCategory row.
struct TaskCategory: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let nameKey: String
    /// Mutable saved rank, not creation chronology. The legacy property and
    /// SQLite `creation_order` column retain their names; gaps/negative ranks
    /// in compatible stores are valid until an explicit changed reorder.
    let creationOrder: Int64

    init(id: UUID = UUID(), name: String, creationOrder: Int64) throws {
        self.id = id
        self.name = try TaskCategoryName.validate(name)
        self.nameKey = TaskCategoryName.key(for: self.name)
        self.creationOrder = creationOrder
    }

    /// Copy validated category fields exactly, replacing only the saved rank.
    init(_ category: TaskCategory, creationOrder: Int64) {
        id = category.id
        name = category.name
        nameKey = category.nameKey
        self.creationOrder = creationOrder
    }
}

enum TaskCategoryNameError: Error, Equatable {
    case blank
    case multiline
    case reserved
}

/// Shared by future category commands and storage uniqueness checks.
enum TaskCategoryName {
    static let general = "General"

    static func validate(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TaskCategoryNameError.blank }
        guard input.rangeOfCharacter(from: .newlines) == nil else {
            throw TaskCategoryNameError.multiline
        }
        guard key(for: name) != key(for: general) else {
            throw TaskCategoryNameError.reserved
        }
        return name
    }

    /// Canonical normalization and case folding with a fixed locale. Diacritics
    /// remain significant; the trimmed display spelling is stored separately.
    static func key(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }
}
