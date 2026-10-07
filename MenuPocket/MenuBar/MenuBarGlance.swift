import Foundation

/// The read-only menu bar glance, derived from the shared state's published
/// Today values on each right-click. It describes content only: it holds no
/// state reference, opens no storage, and never lists Later tasks.
struct MenuBarGlance: Equatable {
    /// Unfinished Today tasks listed before the overflow row.
    static let rowLimit = 5
    /// Characters kept in a row title, including the trailing ellipsis.
    static let titleLimit = 60
    /// Characters kept in a row's category name; names have no saved limit.
    static let categoryLimit = 24

    struct Header: Equatable {
        /// `EEE d MMM` in English, or the raw key when it cannot be parsed.
        let dateLabel: String
        /// nil when Today is unavailable; the header then shows `—` and no bar.
        let progress: NoteProgress?
        /// The date VoiceOver speaks, for example `Wednesday 7 October`.
        let spokenDate: String

        /// The progress VoiceOver speaks after the date.
        var accessibilityValue: String {
            progress.map { "\($0.completed) of \($0.total) tasks done" } ?? "tasks are unavailable"
        }

        /// The whole header as one phrase: the spoken date, then the value.
        var accessibilityLabel: String { "\(spokenDate), \(accessibilityValue)" }

        var countLabel: String {
            progress.map { "\($0.completed) of \($0.total) done" } ?? "—"
        }

        /// completed / max(total, 1), so an empty day draws an empty bar.
        var fraction: Double? {
            progress.map { Double($0.completed) / Double(max($0.total, 1)) }
        }
    }

    struct Row: Equatable, Identifiable {
        let id: UUID
        /// Whitespace runs collapsed to one space, truncated with an ellipsis.
        let title: String
        let fullText: String
        /// Set only when today's tasks span more than one group.
        let categoryName: String?
        /// The untruncated category name, set whenever `categoryName` is.
        let fullCategoryName: String?

        /// The full text, plus the full category name on a second line when it
        /// is cut; nil when the row already shows everything.
        var toolTip: String? {
            let categoryCut = categoryName != fullCategoryName
            guard title != fullText || categoryCut else { return nil }
            return categoryCut ? "\(fullText)\n\(fullCategoryName ?? "")" : fullText
        }
    }

    enum Body: Equatable {
        /// Not loaded yet, or the latest Today read failed.
        case unavailable
        /// A successful read with no tasks.
        case empty
        case allDone
        /// `overflowCount` is nil when every unfinished task is listed.
        case tasks(rows: [Row], overflowCount: Int?)
    }

    let header: Header
    let body: Body
    /// Unfinished Later tasks; nil when unavailable or zero, which hides the line.
    let laterRemainingCount: Int?
    /// Add Task… targets Today, so it is never available while Today is unavailable.
    let canAddTask: Bool

    /// - Parameters:
    ///   - dayKey: The saved `todayKey`, or today's key from `NoteDay` when none
    ///     is saved, like the task window.
    ///   - progress: `DailyNotesState.availableProgress`.
    ///   - groups: `DailyNotesState.groups`, in the Today window's order.
    ///     Ignored when `progress` is nil, because a failed read can leave
    ///     stale rows behind.
    ///   - laterRemainingCount: `DailyNotesState.availableLaterRemainingCount`.
    ///   - canAddTask: Whether the window could add a task to Today now.
    init(dayKey: String, progress: NoteProgress?, groups: [TaskGroup],
         laterRemainingCount: Int?, canAddTask: Bool) {
        let day = try? GregorianDay(key: dayKey)
        let dateLabel = day?.label("EEE d MMM") ?? dayKey
        header = Header(dateLabel: dateLabel, progress: progress,
                        spokenDate: day?.label("EEEE d MMMM") ?? dayKey)

        if let progress {
            body = Self.body(progress: progress, groups: groups)
        } else {
            body = .unavailable
        }
        self.laterRemainingCount = laterRemainingCount.flatMap { $0 > 0 ? $0 : nil }
        self.canAddTask = canAddTask && progress != nil
    }

    private static func body(progress: NoteProgress, groups: [TaskGroup]) -> Body {
        // Collapsed groups are included: the header count covers their tasks.
        let showsCategory = groups.count > 1
        let unfinished = groups.flatMap { group in
            group.notes.filter { !$0.isCompleted }.map { (note: $0, group: group) }
        }
        guard !unfinished.isEmpty else { return progress.total == 0 ? .empty : .allDone }
        let rows = unfinished.prefix(rowLimit).map { entry in
            Row(id: entry.note.id, title: title(for: entry.note.text), fullText: entry.note.text,
                categoryName: showsCategory ? title(for: entry.group.name, limit: categoryLimit) : nil,
                fullCategoryName: showsCategory ? entry.group.name : nil)
        }
        let overflow = unfinished.count - rowLimit
        return .tasks(rows: rows, overflowCount: overflow > 0 ? overflow : nil)
    }

    /// One line of at most `limit` characters. Saved text can contain
    /// line breaks, which a menu item would otherwise show as extra lines.
    static func title(for text: String, limit: Int = titleLimit) -> String {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard line.count > limit else { return line }
        var kept = line.prefix(limit - 1)
        while kept.last?.isWhitespace == true { kept = kept.dropLast() }
        return String(kept) + "…"
    }
}
