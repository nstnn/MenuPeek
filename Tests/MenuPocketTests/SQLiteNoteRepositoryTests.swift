import Foundation
import SQLite3
import XCTest
@testable import MenuPocket

final class SQLiteNoteRepositoryTests: XCTestCase {
    private var directory: URL!
    private var databaseURL: URL { directory.appendingPathComponent("notes.sqlite") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteNoteRepositoryTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
        directory = nil
    }

    func testAddAndDayReadsSurviveReopeningInDisplayOrder() throws {
        let old = note("Old", day: "2026-09-27", createdAt: 10)
        let new = note("Quote ' and emoji 📝", day: "2026-09-27", createdAt: 20)
        let yesterday = note("Yesterday", day: "2026-09-26", createdAt: 30)
        let completed = Note(id: UUID(), text: "Done", dayKey: "2026-09-27",
                             createdAt: Date(timeIntervalSince1970: 40),
                             completedAt: Date(timeIntervalSince1970: 50))

        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            try store.add(old)
            try store.add(new)
            try store.add(yesterday)
            try store.add(completed)
            XCTAssertEqual(try store.notes(for: "2026-09-27"), [old, new, completed])
            XCTAssertEqual(try store.incompleteCount(for: "2026-09-27"), 2)
        }

        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.notes(for: "2026-09-27"), [old, new, completed])
        XCTAssertEqual(try reopened.notes(for: "2026-09-26"), [yesterday])
        XCTAssertEqual(try reopened.incompleteCount(for: "2026-09-26"), 1)
        XCTAssertEqual(try reopened.notes(for: "2026-09-27' OR 1=1 --"), [])
        XCTAssertEqual(try reopened.incompleteCount(for: "2026-09-28"), 0)
        XCTAssertEqual(try schemaVersion(), SQLiteNoteRepository.schemaVersion)
    }

    func testUnversionedExistingTableKeepsItsRows() throws {
        try executeRaw(
            """
            CREATE TABLE notes (
                id TEXT PRIMARY KEY NOT NULL, text TEXT NOT NULL,
                day_key TEXT NOT NULL, created_at REAL NOT NULL, completed_at REAL
            );
            INSERT INTO notes VALUES (
                '00000000-0000-0000-0000-000000000001', 'Existing',
                '2026-09-27', 10, NULL
            );
            """
        )

        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try store.notes(for: "2026-09-27").map(\.text), ["Existing"])
        XCTAssertEqual(try schemaVersion(), SQLiteNoteRepository.schemaVersion)
    }

    func testExistingVersionOneTodayAndYesterdayRowsSurviveOpenWriteAndReopen() throws {
        // Seed the existing format directly, independently of repository bootstrap.
        try executeRaw(
            """
            CREATE TABLE notes (
                id TEXT PRIMARY KEY NOT NULL, text TEXT NOT NULL,
                day_key TEXT NOT NULL, created_at REAL NOT NULL, completed_at REAL
            );
            CREATE INDEX notes_day_key_idx ON notes(day_key);
            INSERT INTO notes VALUES
                ('00000000-0000-0000-0000-000000000001', 'Today '' quote 📝',
                 '2026-09-27', 10, NULL),
                ('00000000-0000-0000-0000-000000000002', 'Today completed',
                 '2026-09-27', 20, 25),
                ('00000000-0000-0000-0000-000000000003', 'Yesterday unfinished',
                 '2026-09-26', 30, NULL),
                ('00000000-0000-0000-0000-000000000004', 'Yesterday completed',
                 '2026-09-26', 40, 45);
            PRAGMA user_version = 1;
            """
        )
        let today = [
            Note(id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
                 text: "Today ' quote 📝", dayKey: "2026-09-27",
                 createdAt: Date(timeIntervalSince1970: 10), completedAt: nil),
            Note(id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
                 text: "Today completed", dayKey: "2026-09-27",
                 createdAt: Date(timeIntervalSince1970: 20),
                 completedAt: Date(timeIntervalSince1970: 25))
        ]
        let yesterday = [
            Note(id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003")),
                 text: "Yesterday unfinished", dayKey: "2026-09-26",
                 createdAt: Date(timeIntervalSince1970: 30), completedAt: nil),
            Note(id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000004")),
                 text: "Yesterday completed", dayKey: "2026-09-26",
                 createdAt: Date(timeIntervalSince1970: 40),
                 completedAt: Date(timeIntervalSince1970: 45))
        ]
        let added = note("Added after transition", day: "2026-09-27", createdAt: 50)

        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            XCTAssertEqual(try store.notes(for: "2026-09-27"), today)
            XCTAssertEqual(try store.notes(for: "2026-09-26"), yesterday)
            try store.add(added)
        }

        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.notes(for: "2026-09-27"), today + [added])
        XCTAssertEqual(try reopened.notes(for: "2026-09-26"), yesterday)
        XCTAssertEqual(try reopened.incompleteCount(for: "2026-09-27"), 2)
        XCTAssertEqual(try reopened.incompleteCount(for: "2026-09-26"), 1)
        XCTAssertEqual(try schemaVersion(), 1)
    }

    func testNewerSchemaIsRejectedWithoutChangingDatabase() throws {
        try executeRaw(
            """
            CREATE TABLE future_data (id INTEGER PRIMARY KEY, payload TEXT NOT NULL);
            INSERT INTO future_data VALUES (1, 'Preserve unknown future data 📝');
            PRAGMA user_version = 2;
            """
        )
        let originalBytes = try Data(contentsOf: databaseURL)

        XCTAssertThrowsError(try SQLiteNoteRepository(databaseURL: databaseURL)) { error in
            guard case SQLiteNoteStoreError.unsupportedSchemaVersion(2) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try schemaVersion(), 2)
        XCTAssertEqual(try Data(contentsOf: databaseURL), originalBytes)
    }

    func testOpenFailureIsReported() throws {
        let pathThatIsDirectory = directory.appendingPathComponent("notes.sqlite", isDirectory: true)
        try FileManager.default.createDirectory(at: pathThatIsDirectory,
                                                withIntermediateDirectories: false)

        XCTAssertThrowsError(try SQLiteNoteRepository(databaseURL: pathThatIsDirectory)) { error in
            guard case SQLiteNoteStoreError.openFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testDuplicateIDThrowsWithoutReplacingSavedNote() throws {
        let original = note("Original", day: "2026-09-27", createdAt: 10)
        let replacement = Note(id: original.id, text: "Replacement", dayKey: original.dayKey,
                               createdAt: original.createdAt, completedAt: nil)
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        try store.add(original)

        XCTAssertThrowsError(try store.add(replacement)) { error in
            guard case SQLiteNoteStoreError.databaseError = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try store.notes(for: original.dayKey), [original])
    }

    func testCompletionEditAndDeletionSurviveReopening() throws {
        let first = note("First", day: "2026-09-27", createdAt: 10)
        let second = note("Second", day: "2026-09-27", createdAt: 20)
        let completedAt = Date(timeIntervalSince1970: 30)

        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            try store.add(first)
            try store.add(second)
            try store.setCompleted(id: second.id, completedAt: completedAt)
            XCTAssertEqual(try store.notes(for: first.dayKey).map(\.id), [first.id, second.id])
            XCTAssertEqual(try store.incompleteCount(for: first.dayKey), 1)
        }

        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            XCTAssertEqual(try store.notes(for: first.dayKey)[1].completedAt, completedAt)
            try store.setCompleted(id: second.id, completedAt: nil)
            try store.updateText(id: first.id, text: "Edited ' note 📝")
            try store.delete(id: second.id)
        }

        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.notes(for: first.dayKey), [
            Note(id: first.id, text: "Edited ' note 📝", dayKey: first.dayKey,
                 createdAt: first.createdAt, completedAt: nil)
        ])
        XCTAssertEqual(try reopened.incompleteCount(for: first.dayKey), 1)
    }

    func testMissingIDsThrowForEveryWriteAndPreserveExistingNote() throws {
        let saved = note("Saved", day: "2026-09-27", createdAt: 10)
        let missing = UUID()
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        try store.add(saved)

        let writes: [() throws -> Void] = [
            { try store.setCompleted(id: missing, completedAt: Date()) },
            { try store.updateText(id: missing, text: "Missing") },
            { try store.delete(id: missing) }
        ]
        for write in writes {
            XCTAssertThrowsError(try write()) { error in
                guard case SQLiteNoteStoreError.noteNotFound(missing) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
        XCTAssertEqual(try store.notes(for: saved.dayKey), [saved])
    }

    func testSQLiteWriteFailuresThrowAndLeaveSavedNoteIntact() throws {
        let saved = note("Saved", day: "2026-09-27", createdAt: 10)
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        try store.add(saved)
        try executeRaw(
            """
            CREATE TRIGGER reject_completion BEFORE UPDATE OF completed_at ON notes
            BEGIN SELECT RAISE(ABORT, 'write rejected'); END;
            CREATE TRIGGER reject_edit BEFORE UPDATE OF text ON notes
            BEGIN SELECT RAISE(ABORT, 'write rejected'); END;
            CREATE TRIGGER reject_delete BEFORE DELETE ON notes
            BEGIN SELECT RAISE(ABORT, 'write rejected'); END;
            """
        )

        let writes: [() throws -> Void] = [
            { try store.setCompleted(id: saved.id, completedAt: Date()) },
            { try store.updateText(id: saved.id, text: "Unsaved") },
            { try store.delete(id: saved.id) }
        ]
        for write in writes {
            XCTAssertThrowsError(try write()) { error in
                guard case SQLiteNoteStoreError.databaseError = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
        XCTAssertEqual(try store.notes(for: saved.dayKey), [saved])
        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.notes(for: saved.dayKey), [saved])
    }

    private func note(_ text: String, day: String, createdAt: TimeInterval) -> Note {
        Note(id: UUID(), text: text, dayKey: day,
             createdAt: Date(timeIntervalSince1970: createdAt), completedAt: nil)
    }

    private func executeRaw(_ sql: String) throws {
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &connection), SQLITE_OK)
        let database = try XCTUnwrap(connection)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
    }

    private func schemaVersion() throws -> Int {
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &connection), SQLITE_OK)
        let database = try XCTUnwrap(connection)
        defer { sqlite3_close(database) }
        var prepared: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &prepared, nil),
                       SQLITE_OK)
        let statement = try XCTUnwrap(prepared)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        return Int(sqlite3_column_int(statement, 0))
    }
}
