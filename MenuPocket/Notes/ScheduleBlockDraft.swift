import Foundation

// The Calendar block editor's draft: what the editor fields hold before Save,
// the prefill rules for a new block, and the messages for refused input.
// No SwiftUI: tests check prefill, end-follows-start and validation directly.

/// Why the editor refused to save. Each has the message shown under the fields.
enum ScheduleBlockDraftIssue: Error, Equatable {
    case blankTitle
    case multilineTitle
    case invalidRange

    var message: String {
        switch self {
        case .blankTitle: "Enter a title for the block."
        case .multilineTitle: "Use a title on one line."
        case .invalidRange: "End time must be after start time."
        }
    }
}

/// The editor's working copy of one block. The time setters only ever produce
/// on-grid minutes with the end at least one slot after the start, so the time
/// controls cannot build an invalid range; `validated()` still checks every
/// rule before a write.
struct ScheduleBlockDraft: Equatable, Sendable {
    static let slotMinutes = ScheduleBlockContent.slotMinutes
    static let minutesPerDay = ScheduleBlockContent.minutesPerDay
    /// A new block is one hour long, or shorter when it would pass 24:00.
    static let newBlockMinutes = 60
    /// A new block on a day other than today starts at 09:00.
    static let defaultStartMinute = 9 * 60

    /// nil for a new block.
    let blockID: UUID?
    var title: String
    private(set) var day: GregorianDay
    private(set) var startMinute: Int
    private(set) var endMinute: Int

    var isNew: Bool { blockID == nil }
    var durationMinutes: Int { endMinute - startMinute }

    /// Every start a block may have: 00:00, 00:15 ... 23:45.
    static let startOptions = Array(stride(from: 0, through: ScheduleBlockContent.latestStartMinute, by: 15))
    /// Every end a block may have: 00:15 ... 24:00.
    static let endOptions = Array(stride(from: 15, through: ScheduleBlockContent.minutesPerDay, by: 15))

    /// A new block on `day` starting in the 15-minute slot that holds
    /// `startMinute`, one hour long and ending no later than 24:00.
    init(newOn day: GregorianDay, startMinute: Int) {
        let start = Self.slotStart(startMinute)
        blockID = nil
        title = ""
        self.day = day
        self.startMinute = start
        endMinute = min(start + Self.newBlockMinutes, Self.minutesPerDay)
    }

    /// The saved block's values, for editing.
    init(block: ScheduleBlock) {
        blockID = block.id
        title = block.title
        day = block.day
        startMinute = block.startMinute
        endMinute = block.endMinute
    }

    // MARK: Prefill for New block

    /// The day and start the New block button uses: today when it is visible,
    /// else the selected day when visible, else the first visible day. On today
    /// the block starts at the next whole hour (23:00 at the latest); on any
    /// other day at 09:00.
    static func newBlock(days: [GregorianDay], today: GregorianDay, selectedDay: GregorianDay?,
                         now: ScheduleCurrentTime?) -> ScheduleBlockDraft? {
        let day: GregorianDay
        if days.contains(today) {
            day = today
        } else if let selectedDay, days.contains(selectedDay) {
            day = selectedDay
        } else if let first = days.first {
            day = first
        } else {
            return nil
        }
        var start = defaultStartMinute
        if let now, now.day == day {
            let nextHour = (Int(now.minute) / 60 + 1) * 60
            start = min(nextHour, minutesPerDay - newBlockMinutes)
        }
        return ScheduleBlockDraft(newOn: day, startMinute: start)
    }

    // MARK: Editing

    /// Moves the start to the slot holding `minute` and keeps the duration;
    /// near midnight the end stops at 24:00, so the block only gets shorter.
    mutating func setStart(_ minute: Int) {
        let duration = durationMinutes
        startMinute = Self.slotStart(minute)
        endMinute = min(startMinute + max(duration, Self.slotMinutes), Self.minutesPerDay)
    }

    /// Moves the end to the nearest slot line in 00:15...24:00. An end at or
    /// before the start moves the start earlier by the current duration (to
    /// 00:00 at the latest), so the range stays valid.
    mutating func setEnd(_ minute: Int) {
        let duration = durationMinutes
        let end = Self.slotEnd(minute)
        endMinute = end
        if end <= startMinute {
            startMinute = max(end - max(duration, Self.slotMinutes), 0)
        }
    }

    /// Moves the day by `offset` days, keeping the times. Returns false and
    /// changes nothing outside the storable years.
    @discardableResult
    mutating func moveDay(by offset: Int) -> Bool {
        guard let next = try? day.adding(days: offset) else { return false }
        day = next
        return true
    }

    /// The values to save, or the first problem: the title before the times.
    func validated() -> Result<ScheduleBlockContent, ScheduleBlockDraftIssue> {
        do {
            return .success(try ScheduleBlockContent(title: title, day: day,
                                                     startMinute: startMinute, endMinute: endMinute))
        } catch ScheduleBlockError.blankTitle {
            return .failure(.blankTitle)
        } catch ScheduleBlockError.multilineTitle {
            return .failure(.multilineTitle)
        } catch {
            return .failure(.invalidRange)
        }
    }

    // MARK: Text

    /// "Wednesday, November 18, 2026".
    var dayText: String { ScheduleCalendar.fullDate(day) }
    var startText: String { ScheduleBlockContent.clockText(minute: startMinute) }
    var endText: String { ScheduleBlockContent.clockText(minute: endMinute) }
    /// "1 h", "45 min", "1 h 30 min".
    var durationText: String { Self.durationText(minutes: durationMinutes) }

    static func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(rest) min"
        }
    }

    // MARK: Snapping

    /// Start of the slot holding `minute`, within 00:00...23:45.
    static func slotStart(_ minute: Int) -> Int {
        let clamped = min(max(minute, 0), ScheduleBlockContent.latestStartMinute)
        return clamped - clamped % slotMinutes
    }

    /// Nearest slot line within 00:15...24:00 (a half slot rounds later).
    static func slotEnd(_ minute: Int) -> Int {
        let clamped = min(max(minute, slotMinutes), minutesPerDay)
        return (clamped + slotMinutes / 2) / slotMinutes * slotMinutes
    }
}

// MARK: - Editor request

/// What opened the block editor. The popover is anchored there, and focus
/// returns there when it closes (to the saved block after a slot click).
enum ScheduleEditorOrigin: Equatable, Sendable {
    case newBlockButton
    case slot(day: GregorianDay, startMinute: Int)
    case block(UUID)

    /// True for the origins anchored on the time grid rather than the header.
    var isOnGrid: Bool {
        if case .newBlockButton = self { false } else { true }
    }
}

/// One opening of the block editor. A new request (new `id`) starts a fresh
/// draft, even for the same block.
struct ScheduleEditorRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let origin: ScheduleEditorOrigin
    let draft: ScheduleBlockDraft

    init(id: UUID = UUID(), origin: ScheduleEditorOrigin, draft: ScheduleBlockDraft) {
        self.id = id
        self.origin = origin
        self.draft = draft
    }

    static func edit(_ block: ScheduleBlock) -> Self {
        Self(origin: .block(block.id), draft: ScheduleBlockDraft(block: block))
    }

    /// A one-hour block starting at the clicked 15-minute slot.
    static func slot(day: GregorianDay, startMinute: Int) -> Self {
        let draft = ScheduleBlockDraft(newOn: day, startMinute: startMinute)
        return Self(origin: .slot(day: day, startMinute: draft.startMinute), draft: draft)
    }
}
