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
    static let schemaVersion = 3

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
            let statement = try prepare(
                "INSERT INTO notes (id, text, day_key, created_at, completed_at, category_id) VALUES (?, ?, ?, ?, ?, ?)"
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
            try check(sqlite3_step(statement), expected: SQLITE_DONE, operation: "insert note")
        }
    }

    func notes(for dayKey: String) throws -> [Note] {
        // The existing table's rowid preserves insertion order across task updates.
        // Do not rebuild this table without preserving that relative order.
        let statement = try prepare(
            """
            SELECT notes.id, text, day_key, created_at, completed_at, category_id,
                   categories.id, name, name_key, creation_order
            FROM notes LEFT JOIN categories ON categories.id = notes.category_id
            WHERE day_key = ? ORDER BY notes.rowid ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(dayKey, at: 1, to: statement)

        var result: [Note] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            try check(step, expected: SQLITE_ROW, operation: "read notes")
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
            result.append(Note(id: id, text: try text(at: 1, from: statement),
                               dayKey: try text(at: 2, from: statement),
                               createdAt: Date(timeIntervalSince1970: createdAt),
                               completedAt: completedAt, categoryID: categoryID))
        }
    }

    func incompleteCount(for dayKey: String) throws -> Int {
        let statement = try prepare(
            "SELECT COUNT(*) FROM notes WHERE day_key = ? AND completed_at IS NULL"
        )
        defer { sqlite3_finalize(statement) }
        try bind(dayKey, at: 1, to: statement)
        try check(sqlite3_step(statement), expected: SQLITE_ROW, operation: "count notes")
        return Int(sqlite3_column_int64(statement, 0))
    }

    func setCompleted(id: UUID, completedAt: Date?) throws {
        try transaction {
            let statement = try prepare("UPDATE notes SET completed_at = ? WHERE id = ?")
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
            let statement = try prepare("UPDATE notes SET text = ?, category_id = ? WHERE id = ?")
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

    // The transfer arrives in TASK-004; until then it fails without touching the database.
    func moveLaterToToday(id: UUID, dayKey: String) throws -> Note {
        throw LaterTaskRepositoryError.unsupported("moveLaterToToday")
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
            case 3: expected = [["table", "categories"], ["table", "later_tasks"], ["table", "notes"]]
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
            try addLaterTasks(in: database)
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
        try validateColumns("notes", expected: noteColumns, in: database)
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
