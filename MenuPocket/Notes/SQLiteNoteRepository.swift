import Foundation
import SQLite3

/// Opening, schema, and query failures stay distinct so daily state can show
/// a recoverable storage error without publishing an unsaved change.
enum SQLiteNoteStoreError: Error {
    case openFailed(String)
    case unsupportedSchemaVersion(Int)
    case incompatibleSchema(String)
    case databaseError(operation: String, code: Int32, message: String)
    case invalidNoteRow
    case noteNotFound(UUID)
}

/// One connection to the app's local notes database. SQLite stores dates as
/// seconds since the Unix epoch and keeps the assigned local day separately.
final class SQLiteNoteRepository: NoteRepository {
    static let schemaVersion = 6

    private let database: OpaquePointer

    convenience init() throws {
        try self.init(databaseURL: Self.defaultDatabaseURL())
    }

    init(databaseURL: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw SQLiteNoteStoreError.openFailed(error.localizedDescription)
        }

        var connection: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &connection,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) }
                ?? "SQLite could not create a connection"
            if let connection { sqlite3_close(connection) }
            throw SQLiteNoteStoreError.openFailed(message)
        }

        do {
            try Self.bootstrap(connection)
        } catch {
            sqlite3_close(connection)
            throw error
        }
        database = connection
    }

    deinit {
        sqlite3_close(database)
    }

    static func defaultDatabaseURL(fileManager: FileManager = .default) throws -> URL {
        do {
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return support.appendingPathComponent("MenuPocket", isDirectory: true)
                .appendingPathComponent("notes.sqlite")
        } catch {
            throw SQLiteNoteStoreError.openFailed(error.localizedDescription)
        }
    }

    func categories() throws -> [TaskCategory] {
        let statement = try prepare(
            "SELECT id, name, name_key, creation_order FROM categories ORDER BY creation_order ASC"
        )
        defer { sqlite3_finalize(statement) }
        var result: [TaskCategory] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            try check(step, expected: SQLITE_ROW, operation: "read categories")
            result.append(try category(from: statement))
        }
    }

    func createCategory(name: String) throws -> TaskCategory {
        let name = try TaskCategoryName.validate(name)
        return try transaction {
            try checkCategoryNameAvailable(name)
            let orderStatement = try prepare("SELECT MAX(creation_order) FROM categories")
            defer { sqlite3_finalize(orderStatement) }
            try check(sqlite3_step(orderStatement), expected: SQLITE_ROW, operation: "read category order")
            let order: Int64
            if sqlite3_column_type(orderStatement, 0) == SQLITE_NULL {
                order = 0
            } else {
                guard sqlite3_column_type(orderStatement, 0) == SQLITE_INTEGER else {
                    throw TaskCategoryRepositoryError.invalidRow
                }
                let next = sqlite3_column_int64(orderStatement, 0).addingReportingOverflow(1)
                guard !next.overflow else { throw TaskCategoryRepositoryError.orderExhausted }
                order = next.partialValue
            }
            let saved = try TaskCategory(name: name, creationOrder: order)
            let statement = try prepare(
                "INSERT INTO categories (id, name, name_key, creation_order) VALUES (?, ?, ?, ?)"
            )
            defer { sqlite3_finalize(statement) }
            try bind(saved.id.uuidString, at: 1, to: statement)
            try bind(saved.name, at: 2, to: statement)
            try bind(saved.nameKey, at: 3, to: statement)
            try check(sqlite3_bind_int64(statement, 4, saved.creationOrder), operation: "bind category order")
            try check(sqlite3_step(statement), expected: SQLITE_DONE, operation: "create category")
            return saved
        }
    }

    func moveCategory(_ request: CategoryMoveRequest) throws -> CategoryMoveOutcome {
        try transaction {
            let snapshot = try categories()
            let outcome = CategoryMovePlanner.plan(request, categories: snapshot)
            guard case let .changed(ordered) = outcome else { return outcome }
            let stagingStart = try Self.categoryStagingStart(
                avoiding: snapshot.map(\.creationOrder), count: Int64(ordered.count)
            )
            let statement = try prepare("UPDATE categories SET creation_order = ? WHERE id = ?")
            defer { sqlite3_finalize(statement) }
            // The temporary range is disjoint from both saved and final ranks.
            // All arithmetic is checked before the first UPDATE.
            for temporary in [true, false] {
                for (index, category) in ordered.enumerated() {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    let rank = temporary ? stagingStart + Int64(index) : category.creationOrder
                    try check(sqlite3_bind_int64(statement, 1, rank), operation: "bind category order")
                    try bind(category.id.uuidString, at: 2, to: statement)
                    try executeWrite(statement, id: category.id, operation: "rewrite category order",
                                     notFound: TaskCategoryRepositoryError.notFound(category.id))
                }
            }
            // No post-commit read can misreport a successful write as a failure.
            // transaction publishes this coherent catalog only after COMMIT.
            return outcome
        }
    }

    /// Find a contiguous Int64 range outside the saved ranks and final 0..<count.
    /// Kept separate so exhaustion/overflow can be checked without a huge store.
    static func categoryStagingStart(avoiding ranks: [Int64], count: Int64) throws -> Int64 {
        guard count > 0 else { throw TaskCategoryRepositoryError.orderExhausted }
        let blocked = (ranks.map { (lower: $0, upper: $0) } + [(lower: Int64(0), upper: count - 1)])
            .sorted { $0.lower < $1.lower }
        var start = Int64.min
        for range in blocked {
            if range.upper < start { continue }
            let end = start.addingReportingOverflow(count - 1)
            guard !end.overflow else { throw TaskCategoryRepositoryError.orderExhausted }
            if end.partialValue < range.lower { return start }
            let next = range.upper.addingReportingOverflow(1)
            guard !next.overflow else { throw TaskCategoryRepositoryError.orderExhausted }
            start = next.partialValue
        }
        guard !start.addingReportingOverflow(count - 1).overflow else {
            throw TaskCategoryRepositoryError.orderExhausted
        }
        return start
    }

    func renameCategory(id: UUID, name: String) throws -> TaskCategory {
        let name = try TaskCategoryName.validate(name)
        return try transaction {
            let original = try requireCategory(id)
            try checkCategoryNameAvailable(name, excluding: id)
            let saved = try TaskCategory(id: id, name: name, creationOrder: original.creationOrder)
            let statement = try prepare("UPDATE categories SET name = ?, name_key = ? WHERE id = ?")
            defer { sqlite3_finalize(statement) }
            try bind(saved.name, at: 1, to: statement)
            try bind(saved.nameKey, at: 2, to: statement)
            try bind(id.uuidString, at: 3, to: statement)
            try check(sqlite3_step(statement), expected: SQLITE_DONE, operation: "rename category")
            guard sqlite3_changes(database) == 1 else { throw TaskCategoryRepositoryError.notFound(id) }
            return saved
        }
    }

    func categoryUsageCount(id: UUID) throws -> Int {
        // One statement distinguishes a missing category from an existing unused one,
        // and counts every saved day plus the Later list.
        let statement = try prepare(
            """
            SELECT (SELECT COUNT(*) FROM notes WHERE category_id = categories.id)
                 + (SELECT COUNT(*) FROM later_tasks WHERE category_id = categories.id)
            FROM categories WHERE id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, at: 1, to: statement)
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { throw TaskCategoryRepositoryError.notFound(id) }
        try check(step, expected: SQLITE_ROW, operation: "count category usage")
        return Int(sqlite3_column_int64(statement, 0))
    }

    func removeCategory(id: UUID) throws {
        try transaction {
            _ = try requireCategory(id)
            let statement = try prepare("DELETE FROM categories WHERE id = ?")
            defer { sqlite3_finalize(statement) }
            try bind(id.uuidString, at: 1, to: statement)
            // The connection's ON DELETE SET NULL relationships clear every day's and every
            // Later task's assignment within this statement, so all of it rolls back together.
            try check(sqlite3_step(statement), expected: SQLITE_DONE, operation: "remove category")
            guard sqlite3_changes(database) == 1 else { throw TaskCategoryRepositoryError.notFound(id) }
        }
    }

    func add(_ note: Note) throws {
        try transaction {
            if let id = note.categoryID { _ = try requireCategory(id) }
            let order = try nextDailyOrder(for: note.dayKey)
            let statement = try prepare(
                "INSERT INTO notes (id, text, day_key, created_at, completed_at, category_id, display_order) VALUES (?, ?, ?, ?, ?, ?, ?)"
            )
            defer { sqlite3_finalize(statement) }

            try bind(note.id.uuidString, at: 1, to: statement)
            try bind(note.text, at: 2, to: statement)
            try bind(note.dayKey, at: 3, to: statement)
            try check(sqlite3_bind_double(statement, 4, note.createdAt.timeIntervalSince1970),
                      operation: "bind created_at")
            let completedResult = note.completedAt.map {
                sqlite3_bind_double(statement, 5, $0.timeIntervalSince1970)
            } ?? sqlite3_bind_null(statement, 5)
            try check(completedResult, operation: "bind completed_at")
            try bindCategoryID(note.categoryID, at: 6, to: statement)
            try check(sqlite3_bind_int64(statement, 7, order), operation: "bind display_order")
            try check(sqlite3_step(statement), expected: SQLITE_DONE, operation: "insert note")
        }
    }

    func notes(for dayKey: String) throws -> [Note] {
        let statement = try prepare(
            """
            SELECT notes.id, text, day_key, created_at, completed_at, category_id,
                   categories.id, name, name_key, creation_order, notes.display_order, continued_on
            FROM notes LEFT JOIN categories ON categories.id = notes.category_id
            WHERE day_key = ? ORDER BY notes.display_order ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(dayKey, at: 1, to: statement)

        var result: [Note] = []
        var ranks = Set<Int64>()
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            try check(step, expected: SQLITE_ROW, operation: "read notes")
            let rank = sqlite3_column_int64(statement, 10)
            guard sqlite3_column_type(statement, 10) == SQLITE_INTEGER,
                  rank >= 0, ranks.insert(rank).inserted else {
                throw SQLiteNoteStoreError.invalidNoteRow
            }
            guard let id = UUID(uuidString: try text(at: 0, from: statement)),
                  sqlite3_column_type(statement, 3) == SQLITE_FLOAT ||
                  sqlite3_column_type(statement, 3) == SQLITE_INTEGER else {
                throw SQLiteNoteStoreError.invalidNoteRow
            }
            let createdAt = sqlite3_column_double(statement, 3)
            guard createdAt.isFinite else { throw SQLiteNoteStoreError.invalidNoteRow }
            let completedAt: Date?
            if sqlite3_column_type(statement, 4) == SQLITE_NULL {
                completedAt = nil
            } else {
                guard sqlite3_column_type(statement, 4) == SQLITE_FLOAT ||
                      sqlite3_column_type(statement, 4) == SQLITE_INTEGER else {
                    throw SQLiteNoteStoreError.invalidNoteRow
                }
                let value = sqlite3_column_double(statement, 4)
                guard value.isFinite else { throw SQLiteNoteStoreError.invalidNoteRow }
                completedAt = Date(timeIntervalSince1970: value)
            }
            let categoryID: UUID?
            if sqlite3_column_type(statement, 5) == SQLITE_NULL {
                categoryID = nil
            } else {
                guard let reference = UUID(uuidString: try text(at: 5, from: statement)),
                      sqlite3_column_type(statement, 6) != SQLITE_NULL else {
                    throw SQLiteNoteStoreError.invalidNoteRow
                }
                guard try category(from: statement, offset: 6).id == reference else {
                    throw SQLiteNoteStoreError.invalidNoteRow
                }
                categoryID = reference
            }
            let continuedOn: String?
            if sqlite3_column_type(statement, 11) == SQLITE_NULL {
                continuedOn = nil
            } else {
                let target = try GregorianDay(key: text(at: 11, from: statement))
                guard completedAt == nil, target.key > dayKey else { throw SQLiteNoteStoreError.invalidNoteRow }
                continuedOn = target.key
            }
            result.append(Note(id: id, text: try text(at: 1, from: statement),
                               dayKey: try text(at: 2, from: statement),
                               createdAt: Date(timeIntervalSince1970: createdAt),
                               completedAt: completedAt, categoryID: categoryID, continuedOn: continuedOn))
        }
    }

    func continueTasks(_ sources: [Note], to dayKey: String, at instant: Date) throws -> [Note] {
        _ = try GregorianDay(key: dayKey)
        guard !sources.isEmpty, Set(sources.map(\.id)).count == sources.count,
              instant.timeIntervalSince1970.isFinite,
              sources.allSatisfy({ $0.isUnfinished && $0.dayKey < dayKey }) else {
            throw TaskContinuationError.invalidSelection
        }
        return try transaction {
            // Compare saved content inside the same write transaction. A stale
            // selection fails as a whole; no task can be continued twice.
            for key in Set(sources.map(\.dayKey)) {
                let saved = try notes(for: key)
                for source in sources where source.dayKey == key {
                    guard saved.contains(source) else { throw TaskContinuationError.staleSource }
                }
            }
            var saved: [Note] = []
            for source in sources {
                let target = Note(id: UUID(), text: source.text, dayKey: dayKey,
                                  createdAt: instant, completedAt: nil, categoryID: source.categoryID)
                let insert = try prepare("INSERT INTO notes (id, text, day_key, created_at, completed_at, category_id, display_order) VALUES (?, ?, ?, ?, NULL, ?, ?)")
                defer { sqlite3_finalize(insert) }
                try bind(target.id.uuidString, at: 1, to: insert)
                try bind(target.text, at: 2, to: insert)
                try bind(dayKey, at: 3, to: insert)
                try bindInstant(instant, at: 4, to: insert)
                try bindCategoryID(target.categoryID, at: 5, to: insert)
                try check(sqlite3_bind_int64(insert, 6, nextDailyOrder(for: dayKey)), operation: "bind continuation order")
                try check(sqlite3_step(insert), expected: SQLITE_DONE, operation: "continue task")
                let mark = try prepare("UPDATE notes SET continued_on = ? WHERE id = ? AND completed_at IS NULL AND continued_on IS NULL")
                defer { sqlite3_finalize(mark) }
                try bind(dayKey, at: 1, to: mark)
                try bind(source.id.uuidString, at: 2, to: mark)
                try executeWrite(mark, id: source.id, operation: "mark continued task")
                saved.append(target)
            }
            return saved
        }
    }

    func moveTask(_ request: TaskMoveRequest) throws -> TaskMoveOutcome {
        try transaction {
            let snapshot = try notes(for: request.expectedDayKey)
            let outcome = TaskMovePlanner.plan(request, dayKey: request.expectedDayKey,
                                               notes: snapshot, categories: try categories())
            guard case let .changed(ordered) = outcome else { return outcome }
            try rewriteDailyOrder(ordered, dayKey: request.expectedDayKey)
            let statement = try prepare("UPDATE notes SET category_id = ? WHERE id = ? AND day_key = ?")
            defer { sqlite3_finalize(statement) }
            guard let moved = ordered.first(where: { $0.id == request.taskID }) else {
                throw SQLiteNoteStoreError.invalidNoteRow
            }
            try bindCategoryID(moved.categoryID, at: 1, to: statement)
            try bind(request.taskID.uuidString, at: 2, to: statement)
            try bind(request.expectedDayKey, at: 3, to: statement)
            try executeWrite(statement, id: request.taskID, operation: "move task category")
            // transaction returns this snapshot only after COMMIT succeeds.
            return outcome
        }
    }

    /// Called only inside a write transaction. Validate before allocating or compacting;
    /// malformed saved ranks are errors, never a reason to repair the store.
    private func nextDailyOrder(for dayKey: String) throws -> Int64 {
        let snapshot = try notes(for: dayKey)
        let maximum: Int64? = try {
            let statement = try prepare("SELECT MAX(display_order) FROM notes WHERE day_key = ?")
            defer { sqlite3_finalize(statement) }
            try bind(dayKey, at: 1, to: statement)
            try check(sqlite3_step(statement), expected: SQLITE_ROW, operation: "read daily order")
            return sqlite3_column_type(statement, 0) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 0)
        }()
        guard let maximum else { return 0 }
        let next = maximum.addingReportingOverflow(1)
        if !next.overflow { return next.partialValue }
        try rewriteDailyOrder(snapshot, dayKey: dayKey)
        return Int64(snapshot.count)
    }

    /// Two passes avoid collisions with the per-day unique index. Negative ranks
    /// remain private to the transaction and are never committed or published.
    private func rewriteDailyOrder(_ ordered: [Note], dayKey: String) throws {
        let statement = try prepare("UPDATE notes SET display_order = ? WHERE id = ? AND day_key = ?")
        defer { sqlite3_finalize(statement) }
        for temporary in [true, false] {
            for (index, note) in ordered.enumerated() {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                let rank = temporary ? -Int64(index) - 1 : Int64(index)
                try check(sqlite3_bind_int64(statement, 1, rank), operation: "bind display_order")
                try bind(note.id.uuidString, at: 2, to: statement)
                try bind(dayKey, at: 3, to: statement)
                try executeWrite(statement, id: note.id, operation: "rewrite daily order")
            }
        }
    }

    /// One statement gives a coherent snapshot and uses a day_key index search.
    func daySummaries(in range: HistoryDayRange) throws -> [DayTaskSummary] {
        let statement = try prepare(
            """
            SELECT day_key, COUNT(*), COUNT(completed_at),
                   SUM(CASE WHEN completed_at IS NULL OR
                       (typeof(completed_at) IN ('integer', 'real') AND
                        completed_at BETWEEN -1.7976931348623157e308 AND 1.7976931348623157e308)
                       THEN 0 ELSE 1 END), COUNT(continued_on)
            FROM notes WHERE day_key >= ? AND day_key < ?
            GROUP BY day_key ORDER BY day_key ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(range.start.key, at: 1, to: statement)
        try bind(range.end.key, at: 2, to: statement)

        var summaries: [DayTaskSummary] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return summaries }
            try check(step, expected: SQLITE_ROW, operation: "read day summaries")
            let summary = try daySummary(from: statement)
            guard range.contains(summary.day) else { throw SQLiteNoteStoreError.invalidNoteRow }
            summaries.append(summary)
        }
    }

    func unfinishedDayPage(before: GregorianDay, limit: Int) throws -> UnfinishedDayPage {
        guard limit > 0, limit < Int.max else { throw TaskHistoryDomainError.invalidPage }
        let statement = try prepare(
            """
            SELECT day_key, COUNT(*), COUNT(completed_at),
                   SUM(CASE WHEN completed_at IS NULL OR
                       (typeof(completed_at) IN ('integer', 'real') AND
                        completed_at BETWEEN -1.7976931348623157e308 AND 1.7976931348623157e308)
                       THEN 0 ELSE 1 END) AS invalid_completion, COUNT(continued_on)
            FROM notes WHERE day_key < ?
            GROUP BY day_key
            HAVING COUNT(*) > COUNT(completed_at) + COUNT(continued_on) OR invalid_completion > 0
            ORDER BY day_key DESC LIMIT ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(before.key, at: 1, to: statement)
        try check(sqlite3_bind_int64(statement, 2, Int64(limit + 1)), operation: "bind unfinished limit")

        var summaries: [DayTaskSummary] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            try check(step, expected: SQLITE_ROW, operation: "read unfinished day page")
            // Validate the lookahead too: corrupt data must not imply a valid next page.
            summaries.append(try daySummary(from: statement))
        }
        return try UnfinishedDayPage(before: before, limit: limit,
                                     summaries: Array(summaries.prefix(limit)),
                                     hasMore: summaries.count > limit)
    }

    private func daySummary(from statement: OpaquePointer) throws -> DayTaskSummary {
        guard sqlite3_column_type(statement, 1) == SQLITE_INTEGER,
              sqlite3_column_type(statement, 2) == SQLITE_INTEGER,
              sqlite3_column_type(statement, 3) == SQLITE_INTEGER,
              sqlite3_column_int64(statement, 3) == 0,
              let total = Int(exactly: sqlite3_column_int64(statement, 1)),
              let completed = Int(exactly: sqlite3_column_int64(statement, 2)),
              total > 0 else {
            throw SQLiteNoteStoreError.invalidNoteRow
        }
        return try DayTaskSummary(dayKey: text(at: 0, from: statement),
                                  progress: NoteProgress(completed: completed, total: total),
                                  continued: Int(sqlite3_column_int64(statement, 4)))
    }

    func historyDaySnapshot(for dayKey: String) throws -> HistoryDaySnapshot {
        let day = try GregorianDay(key: dayKey)
        return try readTransaction {
            let catalog = try categories()
            let orderedNotes = try notes(for: day.key)
            return try HistoryDaySnapshot(dayKey: day.key, notes: orderedNotes, categories: catalog)
        }
    }

    func incompleteCount(for dayKey: String) throws -> Int {
        let statement = try prepare(
            "SELECT COUNT(*) FROM notes WHERE day_key = ? AND completed_at IS NULL AND continued_on IS NULL"
        )
        defer { sqlite3_finalize(statement) }
        try bind(dayKey, at: 1, to: statement)
        try check(sqlite3_step(statement), expected: SQLITE_ROW, operation: "count notes")
        return Int(sqlite3_column_int64(statement, 0))
    }

    func setCompleted(id: UUID, completedAt: Date?) throws {
        try transaction {
            let statement = try prepare("UPDATE notes SET completed_at = ? WHERE id = ? AND continued_on IS NULL")
            defer { sqlite3_finalize(statement) }
            let timestampResult = completedAt.map {
                sqlite3_bind_double(statement, 1, $0.timeIntervalSince1970)
            } ?? sqlite3_bind_null(statement, 1)
            try check(timestampResult, operation: "bind completed_at")
            try bind(id.uuidString, at: 2, to: statement)
            try executeWrite(statement, id: id, operation: "set completion")
        }
    }

    func update(id: UUID, text: String, categoryID: UUID?) throws {
        try transaction {
            if let categoryID { _ = try requireCategory(categoryID) }
            let statement = try prepare("UPDATE notes SET text = ?, category_id = ? WHERE id = ? AND continued_on IS NULL")
            defer { sqlite3_finalize(statement) }
            try bind(text, at: 1, to: statement)
            try bindCategoryID(categoryID, at: 2, to: statement)
            try bind(id.uuidString, at: 3, to: statement)
            try executeWrite(statement, id: id, operation: "update note text and category")
        }
    }

    func delete(id: UUID) throws {
        try transaction {
            let statement = try prepare("DELETE FROM notes WHERE id = ?")
            defer { sqlite3_finalize(statement) }
            try bind(id.uuidString, at: 1, to: statement)
            try executeWrite(statement, id: id, operation: "delete note")
        }
    }

    func laterTasks() throws -> [LaterTask] {
        // Like notes, the rowid preserves insertion order across completion and edits.
        let statement = try prepare(
            """
            SELECT later_tasks.id, text, created_at, completed_at, category_id,
                   categories.id, name, name_key, creation_order
            FROM later_tasks LEFT JOIN categories ON categories.id = later_tasks.category_id
            ORDER BY later_tasks.rowid ASC
            """
        )
        defer { sqlite3_finalize(statement) }

        var result: [LaterTask] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            try check(step, expected: SQLITE_ROW, operation: "read Later tasks")
            guard let id = UUID(uuidString: try text(at: 0, from: statement)) else {
                throw SQLiteNoteStoreError.invalidNoteRow
            }
            guard let createdAt = try instant(at: 2, from: statement) else {
                throw SQLiteNoteStoreError.invalidNoteRow
            }
            let categoryID: UUID?
            if sqlite3_column_type(statement, 4) == SQLITE_NULL {
                categoryID = nil
            } else {
                // A dangling or unreadable association is a read error, never General.
                guard let reference = UUID(uuidString: try text(at: 4, from: statement)),
                      sqlite3_column_type(statement, 5) != SQLITE_NULL,
                      try category(from: statement, offset: 5).id == reference else {
                    throw SQLiteNoteStoreError.invalidNoteRow
                }
                categoryID = reference
            }
            result.append(LaterTask(id: id, text: try text(at: 1, from: statement),
                                    createdAt: createdAt,
                                    completedAt: try instant(at: 3, from: statement),
                                    categoryID: categoryID))
        }
    }

    func addLater(_ task: LaterTask) throws {
        try transaction {
            if let id = task.categoryID { _ = try requireCategory(id) }
            let statement = try prepare(
                "INSERT INTO later_tasks (id, text, created_at, completed_at, category_id) VALUES (?, ?, ?, ?, ?)"
            )
            defer { sqlite3_finalize(statement) }
            try bind(task.id.uuidString, at: 1, to: statement)
            try bind(task.text, at: 2, to: statement)
            try check(sqlite3_bind_double(statement, 3, task.createdAt.timeIntervalSince1970),
                      operation: "bind created_at")
            try bindInstant(task.completedAt, at: 4, to: statement)
            try bindCategoryID(task.categoryID, at: 5, to: statement)
            // A duplicate ID fails the primary key; the saved row is never replaced.
            try check(sqlite3_step(statement), expected: SQLITE_DONE, operation: "insert Later task")
        }
    }

    func setLaterCompleted(id: UUID, completedAt: Date?) throws {
        try transaction {
            let statement = try prepare("UPDATE later_tasks SET completed_at = ? WHERE id = ?")
            defer { sqlite3_finalize(statement) }
            try bindInstant(completedAt, at: 1, to: statement)
            try bind(id.uuidString, at: 2, to: statement)
            try executeWrite(statement, id: id, operation: "set Later completion",
                             notFound: LaterTaskRepositoryError.notFound(id))
        }
    }

    func updateLater(id: UUID, text: String, categoryID: UUID?) throws {
        try transaction {
            if let categoryID { _ = try requireCategory(categoryID) }
            let statement = try prepare("UPDATE later_tasks SET text = ?, category_id = ? WHERE id = ?")
            defer { sqlite3_finalize(statement) }
            try bind(text, at: 1, to: statement)
            try bindCategoryID(categoryID, at: 2, to: statement)
            try bind(id.uuidString, at: 3, to: statement)
            try executeWrite(statement, id: id, operation: "update Later text and category",
                             notFound: LaterTaskRepositoryError.notFound(id))
        }
    }

    func deleteLater(id: UUID) throws {
        try transaction {
            let statement = try prepare("DELETE FROM later_tasks WHERE id = ?")
            defer { sqlite3_finalize(statement) }
            try bind(id.uuidString, at: 1, to: statement)
            try executeWrite(statement, id: id, operation: "delete Later task",
                             notFound: LaterTaskRepositoryError.notFound(id))
        }
    }

    func moveLaterToToday(id: UUID, dayKey: String) throws -> Note {
        try transaction {
            let readStatement = try prepare(
                "SELECT text, created_at, completed_at, category_id FROM later_tasks WHERE id = ?"
            )
            defer { sqlite3_finalize(readStatement) }
            try bind(id.uuidString, at: 1, to: readStatement)
            let step = sqlite3_step(readStatement)
            if step == SQLITE_DONE {
                throw LaterTaskRepositoryError.notFound(id)
            }
            try check(step, expected: SQLITE_ROW, operation: "read Later task for transfer")
            guard let createdAt = try instant(at: 1, from: readStatement) else {
                throw SQLiteNoteStoreError.invalidNoteRow
            }
            if sqlite3_column_type(readStatement, 2) != SQLITE_NULL {
                throw LaterTaskRepositoryError.alreadyCompleted(id)
            }
            let text = try self.text(at: 0, from: readStatement)
            let categoryID: UUID?
            if sqlite3_column_type(readStatement, 3) == SQLITE_NULL {
                categoryID = nil
            } else {
                guard let catUUID = UUID(uuidString: try self.text(at: 3, from: readStatement)) else {
                    throw SQLiteNoteStoreError.invalidNoteRow
                }
                _ = try requireCategory(catUUID)
                categoryID = catUUID
            }

            let collisionStatement = try prepare("SELECT 1 FROM notes WHERE id = ?")
            defer { sqlite3_finalize(collisionStatement) }
            try bind(id.uuidString, at: 1, to: collisionStatement)
            let collisionStep = sqlite3_step(collisionStatement)
            if collisionStep == SQLITE_ROW {
                throw LaterTaskRepositoryError.idCollision(id)
            }
            try check(collisionStep, expected: SQLITE_DONE, operation: "check destination note collision")

            // Transfers append to the day's saved order like Add and Quick Add.
            let order = try nextDailyOrder(for: dayKey)
            let insertStatement = try prepare(
                "INSERT INTO notes (id, text, day_key, created_at, completed_at, category_id, display_order) VALUES (?, ?, ?, ?, NULL, ?, ?)"
            )
            defer { sqlite3_finalize(insertStatement) }
            try bind(id.uuidString, at: 1, to: insertStatement)
            try bind(text, at: 2, to: insertStatement)
            try bind(dayKey, at: 3, to: insertStatement)
            try check(sqlite3_bind_double(insertStatement, 4, createdAt.timeIntervalSince1970),
                      operation: "bind created_at")
            try bindCategoryID(categoryID, at: 5, to: insertStatement)
            try check(sqlite3_bind_int64(insertStatement, 6, order), operation: "bind display_order")
            try check(sqlite3_step(insertStatement), expected: SQLITE_DONE, operation: "insert transferred note")

            let deleteStatement = try prepare("DELETE FROM later_tasks WHERE id = ?")
            defer { sqlite3_finalize(deleteStatement) }
            try bind(id.uuidString, at: 1, to: deleteStatement)
            try executeWrite(deleteStatement, id: id, operation: "delete transferred Later task",
                             notFound: LaterTaskRepositoryError.notFound(id))

            return Note(id: id, text: text, dayKey: dayKey, createdAt: createdAt,
                        completedAt: nil, categoryID: categoryID)
        }
    }

    func moveTodayToLater(id: UUID, dayKey: String) throws -> LaterTask {
        try transaction {
            let readStatement = try prepare(
                "SELECT text, day_key, created_at, completed_at, category_id, continued_on FROM notes WHERE id = ?"
            )
            defer { sqlite3_finalize(readStatement) }
            try bind(id.uuidString, at: 1, to: readStatement)
            let step = sqlite3_step(readStatement)
            if step == SQLITE_DONE {
                throw TodayToLaterError.notFound(id)
            }
            try check(step, expected: SQLITE_ROW, operation: "read daily task for transfer")
            guard try self.text(at: 1, from: readStatement) == dayKey else {
                throw TodayToLaterError.notToday(id)
            }
            guard let createdAt = try instant(at: 2, from: readStatement) else {
                throw SQLiteNoteStoreError.invalidNoteRow
            }
            if sqlite3_column_type(readStatement, 3) != SQLITE_NULL
                || sqlite3_column_type(readStatement, 5) != SQLITE_NULL {
                throw TodayToLaterError.alreadyCompleted(id)
            }
            let text = try self.text(at: 0, from: readStatement)
            let categoryID: UUID?
            if sqlite3_column_type(readStatement, 4) == SQLITE_NULL {
                categoryID = nil
            } else {
                guard let catUUID = UUID(uuidString: try self.text(at: 4, from: readStatement)) else {
                    throw SQLiteNoteStoreError.invalidNoteRow
                }
                _ = try requireCategory(catUUID)
                categoryID = catUUID
            }

            let collisionStatement = try prepare("SELECT 1 FROM later_tasks WHERE id = ?")
            defer { sqlite3_finalize(collisionStatement) }
            try bind(id.uuidString, at: 1, to: collisionStatement)
            let collisionStep = sqlite3_step(collisionStatement)
            if collisionStep == SQLITE_ROW {
                throw TodayToLaterError.idCollision(id)
            }
            try check(collisionStep, expected: SQLITE_DONE, operation: "check destination Later collision")

            // Later order is rowid order, so the insert appends like Add.
            let insertStatement = try prepare(
                "INSERT INTO later_tasks (id, text, created_at, completed_at, category_id) VALUES (?, ?, ?, NULL, ?)"
            )
            defer { sqlite3_finalize(insertStatement) }
            try bind(id.uuidString, at: 1, to: insertStatement)
            try bind(text, at: 2, to: insertStatement)
            try check(sqlite3_bind_double(insertStatement, 3, createdAt.timeIntervalSince1970),
                      operation: "bind created_at")
            try bindCategoryID(categoryID, at: 4, to: insertStatement)
            try check(sqlite3_step(insertStatement), expected: SQLITE_DONE, operation: "insert transferred Later task")

            let deleteStatement = try prepare("DELETE FROM notes WHERE id = ?")
            defer { sqlite3_finalize(deleteStatement) }
            try bind(id.uuidString, at: 1, to: deleteStatement)
            try executeWrite(deleteStatement, id: id, operation: "delete transferred daily task",
                             notFound: TodayToLaterError.notFound(id))

            return LaterTask(id: id, text: text, createdAt: createdAt, completedAt: nil, categoryID: categoryID)
        }
    }

    /// The first SELECT establishes the snapshot shared by all required reads.
    /// Unlike mutation transactions, this does not reserve the writer lock.
    private func readTransaction<Result>(_ body: () throws -> Result) throws -> Result {
        try Self.execute("BEGIN DEFERRED", in: database)
        do {
            let result = try body()
            try Self.execute("COMMIT", in: database)
            return result
        } catch {
            try? Self.execute("ROLLBACK", in: database)
            throw error
        }
    }

    private func transaction<Result>(_ body: () throws -> Result) throws -> Result {
        try Self.execute("BEGIN IMMEDIATE", in: database)
        do {
            let result = try body()
            try Self.execute("COMMIT", in: database)
            return result
        } catch {
            try? Self.execute("ROLLBACK", in: database)
            throw error
        }
    }

    private func category(from statement: OpaquePointer, offset: Int32 = 0) throws -> TaskCategory {
        do {
            guard let id = UUID(uuidString: try text(at: offset, from: statement)),
                  sqlite3_column_type(statement, offset + 3) == SQLITE_INTEGER else {
                throw TaskCategoryRepositoryError.invalidRow
            }
            let name = try text(at: offset + 1, from: statement)
            let saved = try TaskCategory(id: id, name: name,
                                         creationOrder: sqlite3_column_int64(statement, offset + 3))
            guard saved.name == name,
                  saved.nameKey == (try text(at: offset + 2, from: statement)) else {
                throw TaskCategoryRepositoryError.invalidRow
            }
            return saved
        } catch {
            throw TaskCategoryRepositoryError.invalidRow
        }
    }

    private func requireCategory(_ id: UUID) throws -> TaskCategory {
        let statement = try prepare("SELECT id, name, name_key, creation_order FROM categories WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, at: 1, to: statement)
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { throw TaskCategoryRepositoryError.notFound(id) }
        try check(step, expected: SQLITE_ROW, operation: "read category")
        return try category(from: statement)
    }

    private func checkCategoryNameAvailable(_ name: String, excluding id: UUID? = nil) throws {
        let statement = try prepare("SELECT id FROM categories WHERE name_key = ?")
        defer { sqlite3_finalize(statement) }
        try bind(TaskCategoryName.key(for: name), at: 1, to: statement)
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return }
        try check(step, expected: SQLITE_ROW, operation: "check category name")
        guard let existingID = UUID(uuidString: try text(at: 0, from: statement)) else {
            throw TaskCategoryRepositoryError.invalidRow
        }
        if existingID != id { throw TaskCategoryRepositoryError.duplicateName }
    }

    private func bindCategoryID(_ id: UUID?, at index: Int32, to statement: OpaquePointer) throws {
        if let id {
            try bind(id.uuidString, at: index, to: statement)
        } else {
            try check(sqlite3_bind_null(statement, index), operation: "bind category_id")
        }
    }

    private func executeWrite(_ statement: OpaquePointer, id: UUID,
                              operation: String, notFound: Error? = nil) throws {
        try check(sqlite3_step(statement), expected: SQLITE_DONE, operation: operation)
        guard sqlite3_changes(database) == 1 else {
            throw notFound ?? SQLiteNoteStoreError.noteNotFound(id)
        }
    }

    private func bindInstant(_ date: Date?, at index: Int32, to statement: OpaquePointer) throws {
        let result = date.map { sqlite3_bind_double(statement, index, $0.timeIntervalSince1970) }
            ?? sqlite3_bind_null(statement, index)
        try check(result, operation: "bind timestamp")
    }

    /// nil for SQL NULL; a non-numeric or non-finite value is an invalid row.
    private func instant(at index: Int32, from statement: OpaquePointer) throws -> Date? {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_NULL:
            return nil
        case SQLITE_FLOAT, SQLITE_INTEGER:
            let value = sqlite3_column_double(statement, index)
            guard value.isFinite else { throw SQLiteNoteStoreError.invalidNoteRow }
            return Date(timeIntervalSince1970: value)
        default:
            throw SQLiteNoteStoreError.invalidNoteRow
        }
    }

    private static func bootstrap(_ database: OpaquePointer) throws {
        let versionRows = try schemaRows("PRAGMA user_version", in: database)
        guard let value = versionRows.first?.first, let value, let version = Int(value) else {
            throw SQLiteNoteStoreError.incompatibleSchema("Missing schema version")
        }
        guard (0...schemaVersion).contains(version) else {
            throw SQLiteNoteStoreError.unsupportedSchemaVersion(version)
        }

        // This setting is connection-local and has no effect inside a transaction.
        try execute("PRAGMA foreign_keys = ON", in: database)
        guard try schemaRows("PRAGMA foreign_keys", in: database) == [["1"]] else {
            throw SQLiteNoteStoreError.incompatibleSchema("Foreign keys are unavailable")
        }

        let objects = try schemaRows(
            """
            SELECT type, name FROM sqlite_master
            WHERE type IN ('table', 'view') AND name NOT GLOB 'sqlite_*'
            ORDER BY name
            """, in: database
        )
        let isFresh = version == 0 && objects.isEmpty
        if !isFresh {
            let expected: [[String?]]
            switch version {
            case 6: expected = [["table", "categories"], ["table", "later_tasks"], ["table", "notes"],
                                ["table", "schedule_blocks"]]
            case 3, 4, 5: expected = [["table", "categories"], ["table", "later_tasks"], ["table", "notes"]]
            case 2: expected = [["table", "categories"], ["table", "notes"]]
            default: expected = [["table", "notes"]]
            }
            guard objects == expected else {
                throw SQLiteNoteStoreError.incompatibleSchema("Unexpected tables or views")
            }
            try validateSchema(version: version, in: database)
        }
        if version == schemaVersion {
            try validateIntegrity(in: database)
            return
        }

        // Every supported upgrade step runs in one transaction, so a failure leaves
        // the original tables, rows, and user_version exactly as they were.
        try execute("BEGIN IMMEDIATE", in: database)
        do {
            if version < 2 {
                try addCategories(toFreshStore: isFresh, in: database)
            }
            if version < 3 { try addLaterTasks(in: database) }
            if version < 4 { try addDisplayOrder(in: database) }
            if version < 5 {
                try execute("ALTER TABLE notes ADD COLUMN continued_on TEXT DEFAULT NULL", in: database)
            }
            if version < 6 { try addScheduleBlocks(in: database) }
            try validateSchema(version: schemaVersion, in: database)
            try validateIntegrity(in: database)
            try execute("PRAGMA user_version = \(schemaVersion)", in: database)
            try execute("COMMIT", in: database)
        } catch {
            try? execute("ROLLBACK", in: database)
            throw error
        }
    }

    /// Upgrade step for v0/v1 stores (and fresh files): the v2 category catalog
    /// and the optional daily-task association.
    private static func addCategories(toFreshStore isFresh: Bool, in database: OpaquePointer) throws {
        try execute(
            """
            CREATE TABLE categories (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                name_key TEXT NOT NULL UNIQUE,
                creation_order INTEGER NOT NULL UNIQUE CHECK(typeof(creation_order) = 'integer')
            )
            """, in: database
        )
        if isFresh {
            try execute(
                """
                CREATE TABLE notes (
                    id TEXT PRIMARY KEY NOT NULL,
                    text TEXT NOT NULL,
                    day_key TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    completed_at REAL,
                    category_id TEXT DEFAULT NULL REFERENCES categories(id) ON DELETE SET NULL
                )
                """, in: database
            )
        } else {
            // Keep the original table and rowids; rebuilding would risk task order.
            try execute(
                "ALTER TABLE notes ADD COLUMN category_id TEXT DEFAULT NULL REFERENCES categories(id) ON DELETE SET NULL",
                in: database
            )
        }
        try execute("CREATE INDEX IF NOT EXISTS notes_day_key_idx ON notes(day_key)", in: database)
        try execute("CREATE INDEX notes_category_id_idx ON notes(category_id)", in: database)
    }

    /// Upgrade step for every pre-v3 store: the undated Later list. It only adds a
    /// table, so existing notes and categories are never copied or rewritten.
    private static func addLaterTasks(in database: OpaquePointer) throws {
        try execute(
            """
            CREATE TABLE later_tasks (
                id TEXT PRIMARY KEY NOT NULL,
                text TEXT NOT NULL,
                created_at REAL NOT NULL,
                completed_at REAL,
                category_id TEXT DEFAULT NULL REFERENCES categories(id) ON DELETE SET NULL
            )
            """, in: database
        )
        try execute("CREATE INDEX later_tasks_category_id_idx ON later_tasks(category_id)", in: database)
    }

    /// Additive v4 migration: preserve rowids and rank each assigned day independently.
    private static func addDisplayOrder(in database: OpaquePointer) throws {
        try execute(
            "ALTER TABLE notes ADD COLUMN display_order INTEGER NOT NULL DEFAULT 0 CHECK(typeof(display_order) = 'integer')",
            in: database
        )
        try execute(
            """
            WITH ranks AS (
                SELECT rowid AS note_rowid,
                       ROW_NUMBER() OVER (PARTITION BY day_key ORDER BY rowid) - 1 AS rank
                FROM notes
            )
            UPDATE notes SET display_order = (
                SELECT rank FROM ranks WHERE note_rowid = notes.rowid
            )
            """, in: database
        )
        try execute("CREATE UNIQUE INDEX notes_day_display_order_idx ON notes(day_key, display_order)",
                    in: database)
    }

    /// Additive v6 migration: the standalone Calendar block table. It references
    /// no other table, so existing tasks, Later tasks and categories are untouched.
    /// Plain (non-STRICT) DDL keeps the store readable by older system SQLite.
    private static func addScheduleBlocks(in database: OpaquePointer) throws {
        try execute(
            """
            CREATE TABLE schedule_blocks (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                day_key TEXT NOT NULL,
                start_minute INTEGER NOT NULL CHECK(typeof(start_minute) = 'integer'),
                end_minute INTEGER NOT NULL CHECK(typeof(end_minute) = 'integer'),
                created_at REAL NOT NULL,
                CHECK(0 <= start_minute AND start_minute < end_minute AND end_minute <= 1440)
            )
            """, in: database
        )
        try execute("CREATE INDEX schedule_blocks_day_key_idx ON schedule_blocks(day_key)", in: database)
    }

    /// Checks the v6 table's declared constraints and every saved row against the
    /// block rules in `ScheduleBlockContent`. A violation is refused, never repaired.
    private static func validateScheduleBlocks(in database: OpaquePointer) throws {
        try validateColumns("schedule_blocks", expected: [
            ["id", "TEXT", "1", nil, "1", "0"],
            ["title", "TEXT", "1", nil, "0", "0"],
            ["day_key", "TEXT", "1", nil, "0", "0"],
            ["start_minute", "INTEGER", "1", nil, "0", "0"],
            ["end_minute", "INTEGER", "1", nil, "0", "0"],
            ["created_at", "REAL", "1", nil, "0", "0"]
        ], in: database)
        try validateRowidTable("schedule_blocks", in: database)
        try validateForeignKeys("schedule_blocks", expected: [], in: database)
        try validateIndex("schedule_blocks_day_key_idx", table: "schedule_blocks", column: "day_key",
                          required: true, in: database)
        let definitions = try schemaRows(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'schedule_blocks'", in: database
        )
        let compact = (definitions.first?.first.flatMap { $0 } ?? "").lowercased().filter { !$0.isWhitespace }
        let requiredChecks = [
            "check(typeof(start_minute)='integer')",
            "check(typeof(end_minute)='integer')",
            "check(0<=start_minuteandstart_minute<end_minuteandend_minute<=1440)"
        ]
        guard requiredChecks.allSatisfy(compact.contains) else {
            throw SQLiteNoteStoreError.incompatibleSchema("Missing schedule block constraints")
        }

        let slot = ScheduleBlockContent.slotMinutes
        guard try schemaRows(
            """
            SELECT 1 FROM schedule_blocks
            WHERE typeof(id) != 'text' OR typeof(title) != 'text' OR typeof(day_key) != 'text'
               OR typeof(start_minute) != 'integer' OR typeof(end_minute) != 'integer'
               OR typeof(created_at) != 'real'
               OR start_minute < 0 OR start_minute > \(ScheduleBlockContent.latestStartMinute)
               OR end_minute > \(ScheduleBlockContent.minutesPerDay)
               OR start_minute % \(slot) != 0 OR end_minute % \(slot) != 0
               OR end_minute - start_minute < \(slot)
            LIMIT 1
            """, in: database
        ).isEmpty else {
            throw SQLiteNoteStoreError.incompatibleSchema("Invalid schedule block times")
        }
        // Identity, title and day rules need Swift parsing; values were type-checked above.
        for row in try schemaRows("SELECT id, title, day_key FROM schedule_blocks", in: database) {
            guard let id = row[0], UUID(uuidString: id)?.uuidString == id,
                  let title = row[1], (try? ScheduleBlockContent.validateTitle(title)) == title,
                  let dayKey = row[2], (try? GregorianDay(key: dayKey))?.key == dayKey else {
                throw SQLiteNoteStoreError.incompatibleSchema("Invalid schedule block row")
            }
        }
    }

    private static func validateDisplayOrder(in database: OpaquePointer) throws {
        let indexes = try schemaRows("PRAGMA index_list(notes)", in: database)
        guard let index = indexes.first(where: { $0[1] == "notes_day_display_order_idx" }),
              index[2] == "1", index[4] == "0",
              try schemaRows(
                "SELECT name, desc, coll FROM pragma_index_xinfo('notes_day_display_order_idx') WHERE key = 1 ORDER BY seqno",
                in: database
              ) == [["day_key", "0", "BINARY"], ["display_order", "0", "BINARY"]] else {
            throw SQLiteNoteStoreError.incompatibleSchema("Unexpected daily ordering index")
        }
        let definitions = try schemaRows("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'notes'",
                                         in: database)
        let definition = definitions.first?.first.flatMap { $0 } ?? ""
        let compact = definition.lowercased().filter { !$0.isWhitespace }
        guard compact.contains("check(typeof(display_order)='integer')"),
              try schemaRows(
                "SELECT 1 FROM notes WHERE typeof(display_order) != 'integer' OR display_order < 0 LIMIT 1",
                in: database
              ).isEmpty,
              try schemaRows(
                "SELECT 1 FROM notes GROUP BY day_key, display_order HAVING COUNT(*) > 1 LIMIT 1",
                in: database
              ).isEmpty else {
            throw SQLiteNoteStoreError.incompatibleSchema("Invalid daily display order")
        }
    }

    private static func validateSchema(version: Int, in database: OpaquePointer) throws {
        // Defaults, nullability, primary keys, and hidden/generated columns are part
        // of the known format. Do not interpret an unknown v0 file as an empty store.
        let hasCategories = version >= 2
        let categoryReference: [[String?]] = [
            ["categories", "category_id", "id", "NO ACTION", "SET NULL", "NONE"]
        ]
        var noteColumns: [[String?]] = [
            ["id", "TEXT", "1", nil, "1", "0"],
            ["text", "TEXT", "1", nil, "0", "0"],
            ["day_key", "TEXT", "1", nil, "0", "0"],
            ["created_at", "REAL", "1", nil, "0", "0"],
            ["completed_at", "REAL", "0", nil, "0", "0"]
        ]
        if hasCategories {
            noteColumns.append(["category_id", "TEXT", "0", "NULL", "0", "0"])
        }
        if version >= 4 {
            noteColumns.append(["display_order", "INTEGER", "1", "0", "0", "0"])
        }
        if version >= 5 {
            noteColumns.append(["continued_on", "TEXT", "0", "NULL", "0", "0"])
            for row in try schemaRows("SELECT day_key, continued_on, completed_at FROM notes WHERE continued_on IS NOT NULL", in: database) {
                guard let source = row[0], let target = row[1], row[2] == nil,
                      try GregorianDay(key: source) < GregorianDay(key: target) else {
                    throw SQLiteNoteStoreError.incompatibleSchema("Invalid task continuation")
                }
            }
        }
        try validateColumns("notes", expected: noteColumns, in: database)
        if version >= 4 { try validateDisplayOrder(in: database) }
        try validateRowidTable("notes", in: database)
        try validateIndex("notes_day_key_idx", table: "notes", column: "day_key",
                          required: hasCategories, in: database)
        try validateForeignKeys("notes", expected: hasCategories ? categoryReference : [],
                                in: database)
        guard hasCategories else { return }

        try validateColumns("categories", expected: [
            ["id", "TEXT", "1", nil, "1", "0"],
            ["name", "TEXT", "1", nil, "0", "0"],
            ["name_key", "TEXT", "1", nil, "0", "0"],
            ["creation_order", "INTEGER", "1", nil, "0", "0"]
        ], in: database)
        let indexes = try schemaRows("PRAGMA index_list(categories)", in: database)
        for column in ["name_key", "creation_order"] {
            var hasUniqueIndex = false
            for index in indexes where index[2] == "1" && index[4] == "0" {
                guard let name = index[1] else { continue }
                // Index names come from the file, so quote them as SQL string literals.
                let quoted = name.replacingOccurrences(of: "'", with: "''")
                let columns = try schemaRows("SELECT name FROM pragma_index_info('\(quoted)') ORDER BY seqno",
                                             in: database)
                if columns == [[column]] { hasUniqueIndex = true }
            }
            guard hasUniqueIndex else {
                throw SQLiteNoteStoreError.incompatibleSchema("Missing category uniqueness: \(column)")
            }
        }
        try validateIndex("notes_category_id_idx", table: "notes", column: "category_id",
                          required: true, in: database)
        guard version >= 3 else { return }

        try validateColumns("later_tasks", expected: [
            ["id", "TEXT", "1", nil, "1", "0"],
            ["text", "TEXT", "1", nil, "0", "0"],
            ["created_at", "REAL", "1", nil, "0", "0"],
            ["completed_at", "REAL", "0", nil, "0", "0"],
            ["category_id", "TEXT", "0", "NULL", "0", "0"]
        ], in: database)
        try validateRowidTable("later_tasks", in: database)
        // Category removal must clear Later assignments, never delete the tasks.
        try validateForeignKeys("later_tasks", expected: categoryReference, in: database)
        try validateIndex("later_tasks_category_id_idx", table: "later_tasks", column: "category_id",
                          required: true, in: database)
        guard version >= 6 else { return }

        try validateScheduleBlocks(in: database)
    }

    /// WITHOUT ROWID is incompatible with the saved insertion-order contract.
    private static func validateRowidTable(_ table: String, in database: OpaquePointer) throws {
        let rowidRead = try prepare("SELECT rowid FROM \(table) LIMIT 0", in: database)
        sqlite3_finalize(rowidRead)
    }

    private static func validateForeignKeys(_ table: String, expected: [[String?]],
                                            in database: OpaquePointer) throws {
        let foreignKeys = try schemaRows(
            """
            SELECT "table", "from", "to", on_update, on_delete, "match"
            FROM pragma_foreign_key_list('\(table)') ORDER BY id, seq
            """, in: database
        )
        guard foreignKeys == expected else {
            throw SQLiteNoteStoreError.incompatibleSchema("Unexpected \(table) relationships")
        }
    }

    private static func validateColumns(_ table: String, expected: [[String?]],
                                        in database: OpaquePointer) throws {
        let columns = try schemaRows(
            "SELECT name, upper(type), \"notnull\", dflt_value, pk, hidden FROM pragma_table_xinfo('\(table)') ORDER BY cid",
            in: database
        )
        guard columns == expected else {
            throw SQLiteNoteStoreError.incompatibleSchema("Unexpected \(table) columns")
        }
    }

    private static func validateIndex(_ name: String, table: String, column: String,
                                      required: Bool, in database: OpaquePointer) throws {
        let indexes = try schemaRows("PRAGMA index_list(\(table))", in: database)
        guard let index = indexes.first(where: { $0[1] == name }) else {
            if required { throw SQLiteNoteStoreError.incompatibleSchema("Missing \(name)") }
            return
        }
        let columns = try schemaRows("SELECT name FROM pragma_index_info('\(name)') ORDER BY seqno",
                                     in: database)
        guard index[2] == "0", index[4] == "0", columns == [[column]] else {
            throw SQLiteNoteStoreError.incompatibleSchema("Unexpected \(name) definition")
        }
    }

    private static func validateIntegrity(in database: OpaquePointer) throws {
        guard try schemaRows("PRAGMA integrity_check", in: database) == [["ok"]],
              try schemaRows("PRAGMA foreign_key_check", in: database).isEmpty else {
            throw SQLiteNoteStoreError.incompatibleSchema("Database integrity check failed")
        }
    }

    private static func schemaRows(_ sql: String, in database: OpaquePointer) throws -> [[String?]] {
        let statement = try prepare(sql, in: database)
        defer { sqlite3_finalize(statement) }
        var rows: [[String?]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return rows }
            try check(step, expected: SQLITE_ROW, operation: "inspect schema", in: database)
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                sqlite3_column_text(statement, column).map { String(cString: $0) }
            })
        }
    }

    private static func execute(_ sql: String, in database: OpaquePointer) throws {
        try check(sqlite3_exec(database, sql, nil, nil, nil), operation: sql, in: database)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        try Self.prepare(sql, in: database)
    }

    private static func prepare(_ sql: String, in database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw failure(operation: "prepare statement", code: result, in: database)
        }
        return statement
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let result = value.withCString {
            sqlite3_bind_text(statement, index, $0, Int32(value.utf8.count), transient)
        }
        try check(result, operation: "bind text")
    }

    private func text(at index: Int32, from statement: OpaquePointer) throws -> String {
        guard sqlite3_column_type(statement, index) == SQLITE_TEXT,
              let bytes = sqlite3_column_text(statement, index),
              let value = String(bytes: UnsafeBufferPointer(
                start: bytes, count: Int(sqlite3_column_bytes(statement, index))
              ), encoding: .utf8) else {
            throw SQLiteNoteStoreError.invalidNoteRow
        }
        return value
    }

    private func check(_ result: Int32, expected: Int32 = SQLITE_OK,
                       operation: String) throws {
        try Self.check(result, expected: expected, operation: operation, in: database)
    }

    private static func check(_ result: Int32, expected: Int32 = SQLITE_OK,
                              operation: String, in database: OpaquePointer) throws {
        guard result == expected else {
            throw failure(operation: operation, code: result, in: database)
        }
    }

    private static func failure(operation: String, code: Int32,
                                in database: OpaquePointer) -> SQLiteNoteStoreError {
        .databaseError(operation: operation, code: code,
                       message: String(cString: sqlite3_errmsg(database)))
    }
}
