import Foundation

/// Why a Calendar block's title or times were refused. Validation runs before
/// any read or write, so a refused value never reaches storage.
enum ScheduleBlockError: Error, Equatable {
    /// The title is empty after trimming surrounding whitespace and newlines.
    case blankTitle
    /// The trimmed title still contains a line break.
    case multilineTitle
    /// The start is outside 0...1425 (00:00–23:45).
    case startOutOfRange(Int)
    /// The end is outside 15...1440 (00:15–24:00).
    case endOutOfRange(Int)
    /// The minute is not a multiple of `ScheduleBlockContent.slotMinutes`.
    case offGrid(Int)
    /// The end is not at least one slot after the start (zero-length or reversed).
    case endNotAfterStart(start: Int, end: Int)
}

/// The user-editable part of a Calendar block: a title and a wall-clock span
/// on one civil day. Times are minutes from that day's midnight, so a
/// time-zone change never moves a block, and a block never crosses midnight.
/// Only validated values can be constructed.
struct ScheduleBlockContent: Equatable, Sendable {
    static let slotMinutes = 15
    static let minutesPerDay = 24 * 60
    static let latestStartMinute = minutesPerDay - slotMinutes

    let title: String
    let day: GregorianDay
    let startMinute: Int
    let endMinute: Int

    /// Trims the title and checks every time rule; see `ScheduleBlockError`.
    init(title: String, day: GregorianDay, startMinute: Int, endMinute: Int) throws {
        self.title = try Self.validateTitle(title)
        try Self.validateTimes(startMinute: startMinute, endMinute: endMinute)
        self.day = day
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    var dayKey: String { day.key }
    var durationMinutes: Int { endMinute - startMinute }

    /// Same rule as task text (surrounding whitespace and newlines trimmed,
    /// blank refused) plus the category-name rule that a title is one line.
    /// Returns the trimmed spelling that is saved and shown.
    static func validateTitle(_ input: String) throws -> String {
        let title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ScheduleBlockError.blankTitle }
        guard title.rangeOfCharacter(from: .newlines) == nil else {
            throw ScheduleBlockError.multilineTitle
        }
        return title
    }

    /// Range is checked first, then the grid, then the order of the two times.
    static func validateTimes(startMinute: Int, endMinute: Int) throws {
        guard (0...latestStartMinute).contains(startMinute) else {
            throw ScheduleBlockError.startOutOfRange(startMinute)
        }
        guard (slotMinutes...minutesPerDay).contains(endMinute) else {
            throw ScheduleBlockError.endOutOfRange(endMinute)
        }
        guard startMinute.isMultiple(of: slotMinutes) else {
            throw ScheduleBlockError.offGrid(startMinute)
        }
        guard endMinute.isMultiple(of: slotMinutes) else {
            throw ScheduleBlockError.offGrid(endMinute)
        }
        guard endMinute - startMinute >= slotMinutes else {
            throw ScheduleBlockError.endNotAfterStart(start: startMinute, end: endMinute)
        }
    }

    /// Formats a minute from midnight as 24-hour `HH:mm`, independent of the
    /// user's locale. 1440 is the end of the day and reads `24:00`.
    static func clockText(minute: Int) -> String {
        precondition((0...minutesPerDay).contains(minute), "minute outside one day")
        return String(format: "%02d:%02d", locale: Locale(identifier: "en_US_POSIX"),
                      minute / 60, minute % 60)
    }
}

/// A manually created Calendar entry. It stands alone: it has no task link,
/// category, colour or repetition. `createdAt` is internal bookkeeping (and the
/// last display tie-break), never a user-editable time.
struct ScheduleBlock: Identifiable, Equatable, Sendable {
    let id: UUID
    let content: ScheduleBlockContent
    let createdAt: Date

    init(id: UUID, content: ScheduleBlockContent, createdAt: Date) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
    }

    /// Validates like `ScheduleBlockContent.init`.
    init(id: UUID, title: String, day: GregorianDay, startMinute: Int, endMinute: Int,
         createdAt: Date) throws {
        try self.init(id: id,
                      content: ScheduleBlockContent(title: title, day: day,
                                                    startMinute: startMinute,
                                                    endMinute: endMinute),
                      createdAt: createdAt)
    }

    var title: String { content.title }
    var day: GregorianDay { content.day }
    var dayKey: String { content.dayKey }
    var startMinute: Int { content.startMinute }
    var endMinute: Int { content.endMinute }
    var durationMinutes: Int { content.durationMinutes }

    /// The same block with new user-editable content; identity and creation stay.
    func replacingContent(_ content: ScheduleBlockContent) -> Self {
        Self(id: id, content: content, createdAt: createdAt)
    }

    /// Display and read order: day, start, end, creation instant, then ID text,
    /// so two reads of the same blocks always list them identically.
    static func isOrderedBefore(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.day != rhs.day { return lhs.day < rhs.day }
        if lhs.startMinute != rhs.startMinute { return lhs.startMinute < rhs.startMinute }
        if lhs.endMinute != rhs.endMinute { return lhs.endMinute < rhs.endMinute }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
