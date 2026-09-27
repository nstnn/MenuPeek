import Foundation
import SQLite3

/// Opening, schema, and query failures stay distinct so daily state can show
/// a recoverable storage error without publishing an unsaved change.
enum SQLiteNoteStoreError: Error {
    case openFailed(String)
    case unsupportedSchemaVersion(Int)
    case databaseError(operation: String, code: Int32, message: String)
    case invalidNoteRow
    case noteNotFound(UUID)
}

/// One connection to the app's local notes database. SQLite stores dates as
/// seconds since the Unix epoch and keeps the assigned local day separately.
final class SQLiteNoteRepository: NoteRepository {
    static let schemaVersion = 1

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

    func add(_ note: Note) throws {
        let statement = try prepare(
            "INSERT INTO notes (id, text, day_key, created_at, completed_at) VALUES (?, ?, ?, ?, ?)"
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
        try check(sqlite3_step(statement), expected: SQLITE_DONE, operation: "insert note")
    }

    func notes(for dayKey: String) throws -> [Note] {
        let statement = try prepare(
            """
            SELECT id, text, day_key, created_at, completed_at
            FROM notes WHERE day_key = ?
            ORDER BY completed_at IS NOT NULL, created_at DESC, id ASC
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
            result.append(Note(id: id, text: try text(at: 1, from: statement),
                               dayKey: try text(at: 2, from: statement),
                               createdAt: Date(timeIntervalSince1970: createdAt),
                               completedAt: completedAt))
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
        let statement = try prepare("UPDATE notes SET completed_at = ? WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        let timestampResult = completedAt.map {
            sqlite3_bind_double(statement, 1, $0.timeIntervalSince1970)
        } ?? sqlite3_bind_null(statement, 1)
        try check(timestampResult, operation: "bind completed_at")
        try bind(id.uuidString, at: 2, to: statement)
        try executeWrite(statement, id: id, operation: "set completion")
    }

    func updateText(id: UUID, text: String) throws {
        let statement = try prepare("UPDATE notes SET text = ? WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bind(text, at: 1, to: statement)
        try bind(id.uuidString, at: 2, to: statement)
        try executeWrite(statement, id: id, operation: "update note text")
    }

    func delete(id: UUID) throws {
        let statement = try prepare("DELETE FROM notes WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, at: 1, to: statement)
        try executeWrite(statement, id: id, operation: "delete note")
    }

    private func executeWrite(_ statement: OpaquePointer, id: UUID,
                              operation: String) throws {
        try check(sqlite3_step(statement), expected: SQLITE_DONE, operation: operation)
        guard sqlite3_changes(database) == 1 else {
            throw SQLiteNoteStoreError.noteNotFound(id)
        }
    }

    private static func bootstrap(_ database: OpaquePointer) throws {
        let version: Int = try {
            let statement = try prepare("PRAGMA user_version", in: database)
            defer { sqlite3_finalize(statement) }
            try check(sqlite3_step(statement), expected: SQLITE_ROW,
                      operation: "read schema version", in: database)
            return Int(sqlite3_column_int(statement, 0))
        }()
        guard (0...schemaVersion).contains(version) else {
            throw SQLiteNoteStoreError.unsupportedSchemaVersion(version)
        }
        guard version == 0 else { return }

        try execute("BEGIN IMMEDIATE", in: database)
        do {
            try execute(
                """
                CREATE TABLE IF NOT EXISTS notes (
                    id TEXT PRIMARY KEY NOT NULL,
                    text TEXT NOT NULL,
                    day_key TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    completed_at REAL
                )
                """, in: database
            )
            try execute("CREATE INDEX IF NOT EXISTS notes_day_key_idx ON notes(day_key)",
                        in: database)
            try execute("PRAGMA user_version = 1", in: database)
            try execute("COMMIT", in: database)
        } catch {
            try? execute("ROLLBACK", in: database)
            throw error
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
