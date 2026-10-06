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
        try seedLegacy(version: 0)
        let before = try legacyRows()

        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            XCTAssertEqual(try store.notes(for: "2026-09-27").map(\.text),
                           ["Today ' quote 📝", "Today completed"])
            XCTAssertEqual(try store.incompleteCount(for: "2026-09-27"), 1)
            XCTAssertEqual(try store.incompleteCount(for: "2026-09-26"), 1)
        }
        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try legacyRows(), before)
        XCTAssertTrue(try reopened.notes(for: "2026-09-27").allSatisfy { $0.categoryID == nil })
        XCTAssertTrue(try reopened.notes(for: "2026-09-26").allSatisfy { $0.categoryID == nil })
        XCTAssertEqual(try schemaVersion(), SQLiteNoteRepository.schemaVersion)
        XCTAssertEqual(try laterRows(), [])
    }

    func testExistingVersionOneTodayAndYesterdayRowsSurviveOpenWriteAndReopen() throws {
        // Seed the existing format directly, independently of repository bootstrap.
        try seedLegacy(version: 1)
        let before = try legacyRows()
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
            XCTAssertEqual(try legacyRows(), before)
            XCTAssertEqual(try rawRows("SELECT category_id FROM notes ORDER BY rowid"),
                           [[nil], [nil], [nil], [nil]])
            try store.add(added)
        }

        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.notes(for: "2026-09-27"), today + [added])
        XCTAssertEqual(try reopened.notes(for: "2026-09-26"), yesterday)
        XCTAssertEqual(try reopened.incompleteCount(for: "2026-09-27"), 2)
        XCTAssertEqual(try reopened.incompleteCount(for: "2026-09-26"), 1)
        XCTAssertEqual(Array(try legacyRows().prefix(before.count)), before)
        XCTAssertEqual(try schemaVersion(), 3)
        XCTAssertEqual(try laterRows(), [])
    }

    func testNewerSchemaIsRejectedWithoutChangingDatabase() throws {
        try executeRaw(
            """
            CREATE TABLE future_data (id INTEGER PRIMARY KEY, payload TEXT NOT NULL);
            INSERT INTO future_data VALUES (1, 'Preserve unknown future data 📝');
            PRAGMA user_version = 4;
            """
        )
        let originalBytes = try Data(contentsOf: databaseURL)

        XCTAssertThrowsError(try SQLiteNoteRepository(databaseURL: databaseURL)) { error in
            guard case SQLiteNoteStoreError.unsupportedSchemaVersion(4) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try schemaVersion(), 4)
        XCTAssertEqual(try Data(contentsOf: databaseURL), originalBytes)
    }

    func testFreshSchemaEnforcesCategoryConstraintsAndRemovalPreservesTasksAcrossDays() throws {
        let today = note("Today", day: "2026-09-27", createdAt: 10)
        let yesterday = note("Yesterday", day: "2026-09-26", createdAt: 20)
        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            XCTAssertEqual(try schemaVersion(), 3)
            XCTAssertEqual(try rawRows("SELECT * FROM categories"), [])
            XCTAssertEqual(try laterRows(), [])
            try store.add(today)
            try store.add(yesterday)
        }
        let before = try legacyRows()
        try executeRaw("INSERT INTO categories VALUES ('work-id', 'Work', 'work', 7)")
        for invalidInsert in [
            "INSERT INTO categories VALUES ('duplicate-name', 'work', 'work', 8)",
            "INSERT INTO categories VALUES ('duplicate-order', 'Fitness', 'fitness', 7)",
            "INSERT INTO categories VALUES ('fractional-order', 'Fitness', 'fitness', 8.5)",
            "INSERT INTO categories VALUES ('missing-name', NULL, 'fitness', 8)"
        ] {
            XCTAssertEqual(try rawResult(invalidInsert), SQLITE_CONSTRAINT)
        }
        XCTAssertEqual(try rawResult("UPDATE notes SET category_id = 'missing-id'"), SQLITE_CONSTRAINT)
        XCTAssertEqual(try rawResult(
            "INSERT INTO later_tasks (id, text, created_at, category_id) VALUES ('later-missing', 'Rejected', 1, 'missing-id')"
        ), SQLITE_CONSTRAINT)
        try executeRaw("UPDATE notes SET category_id = 'work-id'")
        try executeRaw(
            "INSERT INTO later_tasks (id, text, created_at, category_id) VALUES ('later-id', 'Someday', 30, 'work-id')"
        )
        XCTAssertEqual(try rawRows("SELECT category_id FROM notes ORDER BY rowid"),
                       [["work-id"], ["work-id"]])
        try executeRaw("DELETE FROM categories WHERE id = 'work-id'")
        XCTAssertEqual(try rawRows("SELECT category_id FROM notes ORDER BY rowid"), [[nil], [nil]])
        // Removing a category clears the Later assignment and keeps the task.
        XCTAssertEqual(try laterRows(), [["1", "later-id", "Someday", "30.0", nil, nil]])
        XCTAssertEqual(try legacyRows(), before)
        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.notes(for: today.dayKey), [today])
        XCTAssertEqual(try reopened.notes(for: yesterday.dayKey), [yesterday])
        XCTAssertEqual(try reopened.incompleteCount(for: today.dayKey), 1)
        XCTAssertEqual(try reopened.incompleteCount(for: yesterday.dayKey), 1)
    }

    func testForeignKeysAreEnforcedOnEveryRepositoryConnection() throws {
        let saved = note("Saved", day: "2026-09-27", createdAt: 10)
        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            try store.add(saved)
        }
        // The trigger runs on the repository's connection, not the fixture writer's.
        try executeRaw(
            """
            CREATE TRIGGER invalid_assignment BEFORE UPDATE OF text ON notes
            BEGIN UPDATE notes SET category_id = 'missing-id' WHERE id = NEW.id; END;
            """
        )
        for _ in 0..<2 {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            XCTAssertThrowsError(try store.update(id: saved.id, text: "Rejected", categoryID: saved.categoryID)) { error in
                guard case SQLiteNoteStoreError.databaseError(_, let code, _) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(code, SQLITE_CONSTRAINT)
            }
            XCTAssertEqual(try store.notes(for: saved.dayKey), [saved])
            XCTAssertEqual(try rawRows("SELECT category_id FROM notes"), [[nil]])
        }
    }

    func testVersionThreeReopenDoesNotChangeSchemaDataOrDatabaseBytes() throws {
        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            try store.add(note("Keep 📝", day: "2026-09-27", createdAt: 10))
        }
        try executeRaw(
            "INSERT INTO later_tasks (id, text, created_at) VALUES ('\(UUID().uuidString)', 'Someday 📝', 20)"
        )
        let schema = try schemaSnapshot()
        let rows = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
        let later = try laterRows()
        let bytes = try Data(contentsOf: databaseURL)
        for _ in 0..<2 {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            XCTAssertEqual(try store.notes(for: "2026-09-27").count, 1)
            XCTAssertEqual(try schemaVersion(), 3)
            XCTAssertEqual(try schemaSnapshot(), schema)
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), rows)
            XCTAssertEqual(try laterRows(), later)
            XCTAssertEqual(try Data(contentsOf: databaseURL), bytes)
        }
    }

    func testVersionTwoUpgradeAddsEmptyLaterListAndPreservesTasksCategoriesAndRowids() throws {
        try seedVersionTwo()
        let schema = try schemaSnapshot()
        let rows = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
        let categories = try rawRows("SELECT * FROM categories ORDER BY creation_order")
        let work = try XCTUnwrap(UUID(uuidString: Self.workCategoryID))
        let added = note("Added after upgrade", day: "2026-09-27", createdAt: 50, categoryID: work)

        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            XCTAssertEqual(try schemaVersion(), 3)
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), rows)
            XCTAssertEqual(try rawRows("SELECT * FROM categories ORDER BY creation_order"), categories)
            XCTAssertEqual(try laterRows(), [])
            // The upgrade only adds objects; every v2 table, index, and definition is unchanged.
            let upgraded = try schemaSnapshot()
            XCTAssertEqual(upgraded.filter { $0[2] != "later_tasks" }, schema)
            XCTAssertEqual(upgraded.filter { $0[2] == "later_tasks" }.map { $0[1] },
                           ["later_tasks_category_id_idx", "sqlite_autoindex_later_tasks_1", "later_tasks"])
            XCTAssertEqual(try store.notes(for: "2026-09-27").map(\.categoryID), [work, nil])
            XCTAssertEqual(try store.notes(for: "2026-09-26").map(\.categoryID), [work, nil])
            XCTAssertEqual(try store.categoryUsageCount(id: work), 2)
            try store.add(added)
        }

        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try schemaVersion(), 3)
        XCTAssertEqual(Array(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid").prefix(rows.count)), rows)
        XCTAssertEqual(try reopened.notes(for: "2026-09-27").map(\.text),
                       ["Today ' quote 📝", "Today completed", "Added after upgrade"])
        XCTAssertEqual(try reopened.categories().map(\.name), ["Work", "School"])
        XCTAssertEqual(try laterRows(), [])
    }

    func testIncompatibleLegacySchemasAreRejectedWithoutChangingDatabase() throws {
        let knownColumns = "id TEXT PRIMARY KEY NOT NULL, text TEXT NOT NULL, day_key TEXT NOT NULL, created_at REAL NOT NULL, completed_at REAL"
        let schemas = [
            "CREATE TABLE unrelated (payload TEXT); INSERT INTO unrelated VALUES ('Keep');",
            "CREATE TABLE sqlitex_unknown (payload TEXT); INSERT INTO sqlitex_unknown VALUES ('Keep');",
            "CREATE TABLE notes (id TEXT PRIMARY KEY NOT NULL, text TEXT);",
            "CREATE TABLE notes (id TEXT NOT NULL, text TEXT NOT NULL, day_key TEXT NOT NULL, created_at REAL NOT NULL, completed_at REAL);",
            "CREATE TABLE notes (\(knownColumns), extra TEXT);",
            "CREATE TABLE notes (\(knownColumns)) WITHOUT ROWID;",
            "CREATE TABLE notes (\(knownColumns)); CREATE INDEX notes_day_key_idx ON notes(text);",
            "CREATE TABLE notes (\(knownColumns)); CREATE TABLE future_data (payload TEXT);"
        ]
        for version in [0, 1] {
            for schema in schemas {
                try executeRaw(schema + " PRAGMA user_version = \(version);")
                let bytes = try Data(contentsOf: databaseURL)
                XCTAssertThrowsError(try SQLiteNoteRepository(databaseURL: databaseURL)) { error in
                    XCTAssertTrue(error is SQLiteNoteStoreError, "Unexpected error: \(error)")
                }
                XCTAssertEqual(try schemaVersion(), version)
                XCTAssertEqual(try Data(contentsOf: databaseURL), bytes)
                try FileManager.default.removeItem(at: databaseURL)
            }
        }
    }

    func testIncompleteVersionTwoIsRejectedWithoutRepairingDatabase() throws {
        try seedVersionTwo()
        try executeRaw("DROP INDEX notes_category_id_idx")
        let bytes = try Data(contentsOf: databaseURL)
        XCTAssertThrowsError(try SQLiteNoteRepository(databaseURL: databaseURL)) { error in
            guard case SQLiteNoteStoreError.incompatibleSchema = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try schemaVersion(), 2)
        XCTAssertEqual(try Data(contentsOf: databaseURL), bytes)
    }

    func testPartialOrIncompatibleVersionThreeLayoutsAreRejectedWithoutRepair() throws {
        let columns = "id TEXT PRIMARY KEY NOT NULL, text TEXT NOT NULL, created_at REAL NOT NULL, completed_at REAL"
        let reference = "REFERENCES categories(id) ON DELETE SET NULL"
        let index = "CREATE INDEX later_tasks_category_id_idx ON later_tasks(category_id);"
        let replaceLater = "DROP TABLE later_tasks;"
        // Each case changes exactly one known v3 property.
        let cases: [(name: String, seedVersionTwo: Bool, sql: String)] = [
            ("v2 already holding later_tasks", true,
             "CREATE TABLE later_tasks (\(columns), category_id TEXT DEFAULT NULL \(reference)); \(index)"),
            ("v3 label without later_tasks", true, "PRAGMA user_version = 3;"),
            ("missing Later index", false, "DROP INDEX later_tasks_category_id_idx;"),
            ("Later index on wrong column", false,
             "DROP INDEX later_tasks_category_id_idx; CREATE INDEX later_tasks_category_id_idx ON later_tasks(text);"),
            ("cascading category deletion", false,
             "\(replaceLater) CREATE TABLE later_tasks (\(columns), category_id TEXT DEFAULT NULL REFERENCES categories(id) ON DELETE CASCADE); \(index)"),
            ("missing category relationship", false,
             "\(replaceLater) CREATE TABLE later_tasks (\(columns), category_id TEXT DEFAULT NULL); \(index)"),
            ("missing completion column", false,
             "\(replaceLater) CREATE TABLE later_tasks (id TEXT PRIMARY KEY NOT NULL, text TEXT NOT NULL, created_at REAL NOT NULL, category_id TEXT DEFAULT NULL \(reference)); \(index)"),
            ("extra scheduling column", false,
             "\(replaceLater) CREATE TABLE later_tasks (\(columns), category_id TEXT DEFAULT NULL \(reference), due_at REAL); \(index)"),
            ("WITHOUT ROWID", false,
             "\(replaceLater) CREATE TABLE later_tasks (\(columns), category_id TEXT DEFAULT NULL \(reference)) WITHOUT ROWID; \(index)"),
            ("unknown extra table", false, "CREATE TABLE future_data (payload TEXT);")
        ]
        for testCase in cases {
            if testCase.seedVersionTwo {
                try seedVersionTwo()
            } else {
                do {
                    let store = try SQLiteNoteRepository(databaseURL: databaseURL)
                    try store.add(note("Keep", day: "2026-09-27", createdAt: 10))
                }
            }
            try executeRaw(testCase.sql)
            let version = try schemaVersion()
            let bytes = try Data(contentsOf: databaseURL)
            XCTAssertThrowsError(try SQLiteNoteRepository(databaseURL: databaseURL), testCase.name) { error in
                XCTAssertTrue(error is SQLiteNoteStoreError, "\(testCase.name): \(error)")
            }
            XCTAssertEqual(try schemaVersion(), version, testCase.name)
            XCTAssertEqual(try Data(contentsOf: databaseURL), bytes, testCase.name)
            try FileManager.default.removeItem(at: databaseURL)
        }
    }

    func testFailedMigrationRollsBackSchemaDataAndVersionThenRetriesSafely() throws {
        // A valid extra index on notes collides with a name the upgrade creates. The
        // later_tasks collision fails after every other step, exercising real DDL rollback.
        let collisions: [(version: Int, index: String)] = [
            (0, "notes_category_id_idx"), (1, "notes_category_id_idx"),
            (0, "later_tasks_category_id_idx"), (1, "later_tasks_category_id_idx"),
            (2, "later_tasks_category_id_idx")
        ]
        for (version, index) in collisions {
            if version == 2 { try seedVersionTwo() } else { try seedLegacy(version: version) }
            try executeRaw("CREATE INDEX \(index) ON notes(text)")
            let beforeSchema = try schemaSnapshot()
            let beforeRows = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
            XCTAssertThrowsError(try SQLiteNoteRepository(databaseURL: databaseURL)) { error in
                guard case SQLiteNoteStoreError.databaseError = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
            XCTAssertEqual(try schemaSnapshot(), beforeSchema)
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), beforeRows)
            XCTAssertEqual(try schemaVersion(), version)

            try executeRaw("DROP INDEX \(index)")
            let expectedCategories: [[String?]] = version == 2 ? [[Self.workCategoryID], [nil], [Self.workCategoryID], [nil]]
                : [[nil], [nil], [nil], [nil]]
            do {
                let retried = try SQLiteNoteRepository(databaseURL: databaseURL)
                XCTAssertEqual(try schemaVersion(), 3)
                XCTAssertEqual(try legacyRows(), beforeRows.map { Array($0.prefix(6)) })
                XCTAssertEqual(try retried.incompleteCount(for: "2026-09-27"), 1)
                XCTAssertEqual(try retried.incompleteCount(for: "2026-09-26"), 1)
                XCTAssertEqual(try rawRows("SELECT category_id FROM notes ORDER BY rowid"), expectedCategories)
                XCTAssertEqual(try laterRows(), [])
            }
            do {
                let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
                XCTAssertEqual(try reopened.notes(for: "2026-09-27").count, 2)
                XCTAssertEqual(try legacyRows(), beforeRows.map { Array($0.prefix(6)) })
            }
            try FileManager.default.removeItem(at: databaseURL)
        }
        print("Migration fixtures used system SQLite \(String(cString: sqlite3_libversion()))")
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
                               createdAt: original.createdAt, completedAt: nil,
                               categoryID: original.categoryID)
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
            try store.update(id: first.id, text: "Edited ' note 📝", categoryID: first.categoryID)
            try store.delete(id: second.id)
        }

        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.notes(for: first.dayKey), [
            Note(id: first.id, text: "Edited ' note 📝", dayKey: first.dayKey,
                 createdAt: first.createdAt, completedAt: nil,
                 categoryID: first.categoryID)
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
            { try store.update(id: missing, text: "Missing", categoryID: nil) },
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
            { try store.update(id: saved.id, text: "Unsaved", categoryID: saved.categoryID) },
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

    func testCategoryCatalogValidationRenameAndCreationOrderSurviveReopen() throws {
        var expected: [TaskCategory] = []
        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            XCTAssertEqual(try store.categories(), [])
            let work = try store.createCategory(name: "  Work ' 📝  ")
            let cafe = try store.createCategory(name: "CAFÉ")
            let fitness = try store.createCategory(name: "Fitness")
            XCTAssertEqual(work.name, "Work ' 📝")
            XCTAssertEqual([work.creationOrder, cafe.creationOrder, fitness.creationOrder], [0, 1, 2])
            for name in ["work ' 📝", "Cafe\u{301}"] {
                XCTAssertThrowsError(try store.createCategory(name: name)) {
                    XCTAssertEqual($0 as? TaskCategoryRepositoryError, .duplicateName)
                }
            }
            for name in ["", " \t ", "Work\nHome", " general "] {
                XCTAssertThrowsError(try store.createCategory(name: name))
                XCTAssertThrowsError(try store.renameCategory(id: work.id, name: name))
            }
            XCTAssertThrowsError(try store.renameCategory(id: work.id, name: "café")) {
                XCTAssertEqual($0 as? TaskCategoryRepositoryError, .duplicateName)
            }
            let renamed = try store.renameCategory(id: work.id, name: "  School  ")
            XCTAssertEqual(renamed.id, work.id)
            XCTAssertEqual(renamed.creationOrder, work.creationOrder)
            XCTAssertEqual(try store.renameCategory(id: work.id, name: "School"), renamed)
            XCTAssertEqual(try store.categoryUsageCount(id: cafe.id), 0)
            try store.removeCategory(id: cafe.id)
            let later = try store.createCategory(name: "Later")
            XCTAssertEqual(later.creationOrder, 3)
            expected = [renamed, fitness, later]
            XCTAssertEqual(try store.categories(), expected)
        }
        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.categories(), expected)
    }

    func testCategoryWriteFailuresRollBackThenRetryWithoutConsumingOrder() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let work = try store.createCategory(name: "Work")
        let before = try rawRows("SELECT * FROM categories ORDER BY creation_order")
        try executeRaw(
            """
            CREATE TRIGGER reject_category_create AFTER INSERT ON categories
            BEGIN SELECT RAISE(FAIL, 'write rejected after insert'); END;
            CREATE TRIGGER reject_category_rename AFTER UPDATE OF name ON categories
            BEGIN SELECT RAISE(FAIL, 'write rejected after rename'); END;
            """
        )
        XCTAssertThrowsError(try store.createCategory(name: "School"))
        XCTAssertThrowsError(try store.renameCategory(id: work.id, name: "Changed"))
        XCTAssertEqual(try rawRows("SELECT * FROM categories ORDER BY creation_order"), before)
        XCTAssertEqual(try store.categories(), [work])
        try executeRaw("DROP TRIGGER reject_category_create; DROP TRIGGER reject_category_rename")
        let school = try store.createCategory(name: "School")
        XCTAssertEqual(school.creationOrder, 1)
        let renamed = try store.renameCategory(id: work.id, name: "Changed")
        XCTAssertEqual(try store.categories(), [renamed, school])
        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.categories(), [renamed, school])
    }

    func testCategorizedAddsAndAtomicEditsPreserveTaskIdentityOrderAndCounts() throws {
        var expected: [Note] = []
        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            let work = try store.createCategory(name: "Work")
            let school = try store.createCategory(name: "School")
            let first = note("First", day: "2026-09-27", createdAt: 100, categoryID: work.id)
            let second = note("Second", day: first.dayKey, createdAt: 10)
            let third = note("Third", day: first.dayKey, createdAt: 10, categoryID: school.id)
            for task in [first, second, third] { try store.add(task) }
            XCTAssertEqual(try store.notes(for: first.dayKey), [first, second, third])
            XCTAssertEqual(try rawRows("SELECT category_id FROM notes ORDER BY rowid"),
                           [[work.id.uuidString], [nil], [school.id.uuidString]])
            let protectedFields = try rawRows("SELECT rowid, id, day_key, created_at, completed_at FROM notes ORDER BY rowid")
            try store.update(id: first.id, text: "Edited ' 📝", categoryID: school.id)
            try store.update(id: second.id, text: second.text, categoryID: work.id)
            try store.update(id: third.id, text: third.text, categoryID: nil)
            expected = [
                Note(id: first.id, text: "Edited ' 📝", dayKey: first.dayKey,
                     createdAt: first.createdAt, completedAt: nil, categoryID: school.id),
                Note(id: second.id, text: second.text, dayKey: second.dayKey,
                     createdAt: second.createdAt, completedAt: nil, categoryID: work.id),
                Note(id: third.id, text: third.text, dayKey: third.dayKey,
                     createdAt: third.createdAt, completedAt: nil)
            ]
            XCTAssertEqual(try store.notes(for: first.dayKey), expected)
            XCTAssertEqual(try rawRows("SELECT rowid, id, day_key, created_at, completed_at FROM notes ORDER BY rowid"), protectedFields)
            let completion = Date(timeIntervalSince1970: 200)
            try store.setCompleted(id: first.id, completedAt: completion)
            XCTAssertEqual(try store.notes(for: first.dayKey).first?.categoryID, school.id)
            XCTAssertEqual(try store.incompleteCount(for: first.dayKey), 2)
            try store.setCompleted(id: first.id, completedAt: nil)
            XCTAssertEqual(try store.notes(for: first.dayKey), expected)
            XCTAssertEqual(try store.incompleteCount(for: first.dayKey), 3)
        }
        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.notes(for: "2026-09-27"), expected)
    }

    func testMissingCategoryAndTaskTargetsThrowWithoutChangingSavedRows() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let category = try store.createCategory(name: "Work")
        let saved = note("Saved", day: "2026-09-27", createdAt: 10, categoryID: category.id)
        try store.add(saved)
        let missing = UUID()
        let rows = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
        let operations: [() throws -> Void] = [
            { _ = try store.renameCategory(id: missing, name: "Missing") },
            { _ = try store.categoryUsageCount(id: missing) },
            { try store.removeCategory(id: missing) },
            { try store.add(self.note("Rejected", day: saved.dayKey, createdAt: 20, categoryID: missing)) },
            { try store.update(id: saved.id, text: "Rejected", categoryID: missing) }
        ]
        for operation in operations {
            XCTAssertThrowsError(try operation()) {
                XCTAssertEqual($0 as? TaskCategoryRepositoryError, .notFound(missing))
            }
        }
        XCTAssertThrowsError(try store.update(id: missing, text: "Missing", categoryID: category.id)) {
            guard case SQLiteNoteStoreError.noteNotFound(missing) = $0 else {
                return XCTFail("Unexpected error: \($0)")
            }
        }
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), rows)
        XCTAssertEqual(try store.categories(), [category])
        XCTAssertEqual(try store.notes(for: saved.dayKey), [saved])
    }

    func testFailedCategorizedAddAndEditRollBackBothFieldsIncludingAfterWriteFailure() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let work = try store.createCategory(name: "Work")
        let school = try store.createCategory(name: "School")
        let saved = note("Saved", day: "2026-09-27", createdAt: 10,
                         completedAt: Date(timeIntervalSince1970: 20), categoryID: work.id)
        try store.add(saved)
        let rows = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
        try executeRaw(
            """
            CREATE TRIGGER reject_task_add AFTER INSERT ON notes
            BEGIN SELECT RAISE(FAIL, 'write rejected after insert'); END;
            CREATE TRIGGER reject_task_edit AFTER UPDATE OF text ON notes
            BEGIN SELECT RAISE(FAIL, 'write rejected after edit'); END;
            """
        )
        XCTAssertThrowsError(try store.add(note("Unsaved", day: saved.dayKey, createdAt: 30, categoryID: school.id)))
        XCTAssertThrowsError(try store.update(id: saved.id, text: "Unsaved", categoryID: school.id))
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), rows)
        XCTAssertEqual(try store.notes(for: saved.dayKey), [saved])
        XCTAssertEqual(try store.incompleteCount(for: saved.dayKey), 0)
        try executeRaw("DROP TRIGGER reject_task_add; DROP TRIGGER reject_task_edit")
        try store.update(id: saved.id, text: "Retry", categoryID: school.id)
        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.notes(for: saved.dayKey), [
            Note(id: saved.id, text: "Retry", dayKey: saved.dayKey,
                 createdAt: saved.createdAt, completedAt: saved.completedAt, categoryID: school.id)
        ])
    }

    func testCategoryRemovalRollsBackAcrossAllDaysThenPreservesTasksAndCountsOnRetry() throws {
        let days = ["2026-09-27", "2026-09-26", "2026-09-25"]
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let work = try store.createCategory(name: "Work")
        let other = try store.createCategory(name: "Other")
        for (index, day) in days.enumerated() {
            try store.add(note("Unfinished", day: day, createdAt: Double(index), categoryID: work.id))
            try store.add(note("Finished", day: day, createdAt: Double(index),
                               completedAt: Date(timeIntervalSince1970: 30), categoryID: work.id))
            try store.add(note("Other", day: day, createdAt: Double(index), categoryID: other.id))
            try store.add(note("General", day: day, createdAt: Double(index)))
        }
        XCTAssertEqual(try store.categoryUsageCount(id: work.id), 6)
        XCTAssertEqual(try store.categoryUsageCount(id: other.id), 3)
        let before = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
        let fields = try legacyRows()
        let progress = try days.map { NoteProgress(notes: try store.notes(for: $0), for: $0) }
        let counts = try days.map { try store.incompleteCount(for: $0) }
        try executeRaw(
            """
            CREATE TRIGGER reject_old_assignment AFTER UPDATE OF category_id ON notes
            WHEN NEW.day_key = '2026-09-25'
            BEGIN SELECT RAISE(FAIL, 'write rejected after reassignment'); END;
            """
        )
        XCTAssertThrowsError(try store.removeCategory(id: work.id))
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), before)
        XCTAssertEqual(try store.categories(), [work, other])
        XCTAssertEqual(try store.categoryUsageCount(id: work.id), 6)
        try executeRaw("DROP TRIGGER reject_old_assignment")
        try store.removeCategory(id: work.id)
        XCTAssertEqual(try legacyRows(), fields)
        XCTAssertEqual(try store.categories(), [other])
        XCTAssertEqual(try days.map { NoteProgress(notes: try store.notes(for: $0), for: $0) }, progress)
        XCTAssertEqual(try days.map { try store.incompleteCount(for: $0) }, counts)
        XCTAssertEqual(try rawRows("SELECT category_id FROM notes ORDER BY rowid"),
                       Array(repeating: [[nil], [nil], [other.id.uuidString], [nil]], count: 3).flatMap { $0 })
        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.categories(), [other])
        XCTAssertEqual(try reopened.categoryUsageCount(id: other.id), 3)
        XCTAssertEqual(try legacyRows(), fields)
        for day in days {
            XCTAssertEqual(try reopened.notes(for: day).map(\.categoryID), [nil, nil, other.id, nil])
        }
        XCTAssertThrowsError(try reopened.removeCategory(id: work.id)) {
            XCTAssertEqual($0 as? TaskCategoryRepositoryError, .notFound(work.id))
        }
    }

    func testInvalidCategoryRowsAndAssociationsAreReadErrorsWithoutRepair() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let category = try store.createCategory(name: "Work")
        let saved = note("Saved", day: "2026-09-27", createdAt: 10, categoryID: category.id)
        try store.add(saved)
        for invalidChange in ["name = 'General'", "name_key = 'wrong-key'", "name = ' Work '"] {
            try executeRaw("UPDATE categories SET \(invalidChange)")
            let before = try rawRows("SELECT * FROM categories")
            XCTAssertThrowsError(try store.categories()) {
                XCTAssertEqual($0 as? TaskCategoryRepositoryError, .invalidRow)
            }
            XCTAssertThrowsError(try store.notes(for: saved.dayKey))
            XCTAssertEqual(try rawRows("SELECT * FROM categories"), before)
            try executeRaw("UPDATE categories SET name = 'Work', name_key = 'work'")
        }
        for invalidID in ["not-a-uuid", UUID().uuidString] {
            // Only the isolated fixture writer disables its own connection's enforcement.
            try executeRaw("PRAGMA foreign_keys = OFF; UPDATE notes SET category_id = '\(invalidID)'")
            let before = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
            XCTAssertThrowsError(try store.notes(for: saved.dayKey))
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), before)
        }
        try executeRaw("UPDATE notes SET category_id = NULL; UPDATE categories SET id = 'not-a-uuid'")
        XCTAssertThrowsError(try store.categories()) {
            XCTAssertEqual($0 as? TaskCategoryRepositoryError, .invalidRow)
        }
    }

    func testCategoryOrderOverflowThrowsWithoutReplacingCatalog() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let category = try store.createCategory(name: "Work")
        try executeRaw("UPDATE categories SET creation_order = \(Int64.max)")
        let before = try rawRows("SELECT * FROM categories")
        XCTAssertThrowsError(try store.createCategory(name: "School")) {
            XCTAssertEqual($0 as? TaskCategoryRepositoryError, .orderExhausted)
        }
        XCTAssertEqual(try rawRows("SELECT * FROM categories"), before)
        XCTAssertEqual(try store.categories().first?.id, category.id)
    }

    func testDaySummariesAreSparseOrderedAssignedDayCountsAndPreserveStorage() throws {
        let range = try HistoryDayRange.month(containing: GregorianDay(key: "2025-12-15"))
        let beforeMonth = note("Excluded", day: "2025-11-30", createdAt: 1)
        let first = note("First", day: "2025-12-01", createdAt: 2)
        let nextMonth = note("Excluded next", day: "2026-01-01", createdAt: 3)
        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            let category = try store.createCategory(name: "Work")
            let done = note("Done outside assigned month", day: "2025-12-01", createdAt: 4,
                            completedAt: Date(timeIntervalSince1970: 1), categoryID: category.id)
            let last = note("All completed", day: "2025-12-31", createdAt: 5,
                            completedAt: Date(timeIntervalSince1970: 2))
            let middle = note("All incomplete", day: "2025-12-15", createdAt: 6)
            for row in [last, nextMonth, beforeMonth, done, middle, first] { try store.add(row) }
            let rows = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
            let categories = try rawRows("SELECT rowid, * FROM categories ORDER BY rowid")
            let later = try laterRows()
            let schema = try schemaSnapshot()
            let version = try schemaVersion()
            let suite = "HistorySummaryTests-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set("Keep", forKey: "unrelated")
            let preferences = defaults.persistentDomain(forName: suite)

            let summaries = try store.daySummaries(in: range)
            XCTAssertEqual(summaries.map(\.dayKey), ["2025-12-01", "2025-12-15", "2025-12-31"])
            XCTAssertEqual(summaries.map(\.progress), [NoteProgress(completed: 1, total: 2),
                                                      NoteProgress(completed: 0, total: 1),
                                                      NoteProgress(completed: 1, total: 1)])
            for summary in summaries {
                XCTAssertEqual(summary.progress,
                               NoteProgress(notes: try store.notes(for: summary.dayKey), for: summary.dayKey))
            }
            XCTAssertEqual(try store.daySummaries(in: .month(containing: GregorianDay(key: "2026-01-20")))
                .map(\.dayKey), ["2026-01-01"])
            XCTAssertEqual(try store.daySummaries(in: .month(containing: GregorianDay(key: "2024-02-29"))), [])
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), rows)
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM categories ORDER BY rowid"), categories)
            XCTAssertEqual(try laterRows(), later)
            XCTAssertEqual(try schemaSnapshot(), schema)
            XCTAssertEqual(try schemaVersion(), version)
            XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, preferences as NSDictionary?)
        }
        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.daySummaries(in: range).map(\.dayKey),
                       ["2025-12-01", "2025-12-15", "2025-12-31"])
        let plan = try rawRows("""
            EXPLAIN QUERY PLAN SELECT day_key, COUNT(*), COUNT(completed_at),
            SUM(CASE WHEN completed_at IS NULL OR
                (typeof(completed_at) IN ('integer', 'real') AND
                 completed_at BETWEEN -1.7976931348623157e308 AND 1.7976931348623157e308)
                THEN 0 ELSE 1 END)
            FROM notes WHERE day_key >= '2025-12-01' AND day_key < '2026-01-01'
            GROUP BY day_key ORDER BY day_key ASC
            """)
        XCTAssertTrue(plan.contains { ($0.last ?? nil)?.contains("SEARCH notes USING INDEX notes_day_key_idx") == true })
        print("History summary query plan: \(plan)")
    }

    func testDaySummariesRejectInvalidCompletionOnlyWithinRequestedRange() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        try store.add(note("In range", day: "2024-02-29", createdAt: 1))
        try store.add(note("Outside", day: "2024-03-01", createdAt: 2))
        let range = try HistoryDayRange.month(containing: GregorianDay(key: "2024-02-29"))
        try executeRaw("UPDATE notes SET completed_at = 'invalid' WHERE day_key = '2024-03-01'")
        XCTAssertEqual(try store.daySummaries(in: range).first?.progress, NoteProgress(completed: 0, total: 1))
        for representation in ["'invalid'", "X'0102'", "1e999", "-1e999"] {
            try executeRaw("UPDATE notes SET completed_at = \(representation) WHERE day_key = '2024-02-29'")
            XCTAssertThrowsError(try store.daySummaries(in: range)) { error in
                guard case SQLiteNoteStoreError.invalidNoteRow = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
        for representation in ["0", "-1", "1.5", "NULL"] {
            try executeRaw("UPDATE notes SET completed_at = \(representation) WHERE day_key = '2024-02-29'")
            XCTAssertEqual(try store.daySummaries(in: range).first?.progress.completed,
                           representation == "NULL" ? 0 : 1)
        }
    }

    func testDaySummariesRejectMalformedInRangeDayAndQueryFailures() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        try store.add(note("Malformed day", day: "2025-02-30", createdAt: 1))
        let range = try HistoryDayRange.month(containing: GregorianDay(key: "2025-02-01"))
        XCTAssertThrowsError(try store.daySummaries(in: range))
        try executeRaw("DELETE FROM notes; DROP TABLE notes")
        XCTAssertThrowsError(try store.daySummaries(in: range)) { error in
            guard case SQLiteNoteStoreError.databaseError = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testHistoryDaySnapshotPreservesFullRowsOrderCatalogAndStorage() throws {
        let day = "2025-12-31"
        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            let work = try store.createCategory(name: "Work")
            let unused = try store.createCategory(name: "Unused")
            let first = note("First", day: day, createdAt: 10, categoryID: work.id)
            let second = note("Second", day: day, createdAt: 10,
                              completedAt: Date(timeIntervalSince1970: 100), categoryID: work.id)
            let general = note("General", day: day, createdAt: 1)
            for saved in [first, second, general, note("Other day", day: "2026-01-01", createdAt: 0)] {
                try store.add(saved)
            }
            try executeRaw("INSERT INTO later_tasks (id, text, created_at) VALUES ('\(UUID().uuidString)', 'Later', 2)")
            let rows = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
            let catalog = try rawRows("SELECT rowid, * FROM categories ORDER BY rowid")
            let later = try laterRows()
            let schema = try schemaSnapshot()
            let version = try schemaVersion()

            let snapshot = try store.historyDaySnapshot(for: day)
            XCTAssertEqual(snapshot.notes, [first, second, general])
            XCTAssertEqual(snapshot.categories, [work, unused])
            XCTAssertEqual(snapshot.progress, NoteProgress(completed: 1, total: 3))
            XCTAssertEqual(snapshot.filteredNotes(.unfinished), [first, general])
            XCTAssertEqual(snapshot.groups, TaskGroup.groups(categories: [work, unused], notes: [first, second, general]))
            let empty = try store.historyDaySnapshot(for: "2024-02-29")
            XCTAssertEqual(empty.notes, [])
            XCTAssertEqual(empty.categories, [work, unused])
            XCTAssertEqual(empty.progress, NoteProgress(completed: 0, total: 0))
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), rows)
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM categories ORDER BY rowid"), catalog)
            XCTAssertEqual(try laterRows(), later)
            XCTAssertEqual(try schemaSnapshot(), schema)
            XCTAssertEqual(try schemaVersion(), version)
        }
        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.historyDaySnapshot(for: day).notes.map(\.text), ["First", "Second", "General"])
    }

    func testHistoryDaySnapshotUsesRenamedCatalogAndRemovedCategoryBecomesGeneral() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let category = try store.createCategory(name: "Work")
        let saved = note("Saved", day: "2025-12-31", createdAt: 1, categoryID: category.id)
        try store.add(saved)
        let initial = try store.historyDaySnapshot(for: saved.dayKey)
        let renamed = try store.renameCategory(id: category.id, name: "Projects")
        let snapshot = try store.historyDaySnapshot(for: saved.dayKey)
        XCTAssertEqual(snapshot.categories, [renamed])
        XCTAssertEqual(snapshot.notes, initial.notes)
        XCTAssertEqual(snapshot.progress, initial.progress)
        try store.removeCategory(id: category.id)
        let removed = try store.historyDaySnapshot(for: saved.dayKey)
        let general = Note(id: saved.id, text: saved.text, dayKey: saved.dayKey,
                           createdAt: saved.createdAt, completedAt: saved.completedAt, categoryID: nil)
        XCTAssertEqual(removed.categories, [])
        XCTAssertEqual(removed.notes, [general])
        XCTAssertEqual(removed.progress, initial.progress)
    }

    func testHistoryDaySnapshotFailuresLeaveNoTransactionAndRetryAfterRepair() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let category = try store.createCategory(name: "Work")
        let saved = note("Saved", day: "2025-12-31", createdAt: 1, categoryID: category.id)
        try store.add(saved)
        XCTAssertThrowsError(try store.historyDaySnapshot(for: "2025-02-30"))
        let faults = [
            ("UPDATE categories SET name_key = 'wrong'", "UPDATE categories SET name_key = 'work'"),
            ("UPDATE notes SET created_at = 'invalid'", "UPDATE notes SET created_at = 1"),
            ("UPDATE notes SET completed_at = 'invalid'", "UPDATE notes SET completed_at = NULL"),
            ("PRAGMA foreign_keys = OFF; UPDATE notes SET category_id = '\(UUID().uuidString)'",
             "UPDATE notes SET category_id = '\(category.id.uuidString)'"),
            ("ALTER TABLE notes RENAME TO hidden_notes", "ALTER TABLE hidden_notes RENAME TO notes")
        ]
        for (fault, repair) in faults {
            try executeRaw(fault)
            XCTAssertThrowsError(try store.historyDaySnapshot(for: saved.dayKey), fault)
            // Another connection can repair the fault only after the read lock is released.
            try executeRaw(repair)
            XCTAssertEqual(try store.historyDaySnapshot(for: saved.dayKey).notes, [saved])
            // A mutation's BEGIN IMMEDIATE also proves no transaction was left open.
            try store.setCompleted(id: saved.id, completedAt: nil)
        }
    }

    func testHistoryDaySnapshotReadsCommittedDataWhileAnotherWriterIsActive() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let category = try store.createCategory(name: "Work")
        let saved = note("Saved", day: "2025-12-31", createdAt: 1, categoryID: category.id)
        try store.add(saved)
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &connection), SQLITE_OK)
        let writer = try XCTUnwrap(connection)
        defer { sqlite3_close(writer) }
        XCTAssertEqual(sqlite3_exec(writer, "BEGIN IMMEDIATE", nil, nil, nil), SQLITE_OK)
        defer { sqlite3_exec(writer, "ROLLBACK", nil, nil, nil) }
        XCTAssertEqual(sqlite3_exec(writer, "UPDATE categories SET name = 'Projects', name_key = 'projects'; UPDATE notes SET text = 'Changed'", nil, nil, nil), SQLITE_OK)
        // A history BEGIN IMMEDIATE would fail here with SQLITE_BUSY.
        let beforeCommit = try store.historyDaySnapshot(for: saved.dayKey)
        XCTAssertEqual(beforeCommit.categories, [category])
        XCTAssertEqual(beforeCommit.notes, [saved])
        XCTAssertEqual(sqlite3_exec(writer, "COMMIT", nil, nil, nil), SQLITE_OK)
        let afterCommit = try store.historyDaySnapshot(for: saved.dayKey)
        XCTAssertEqual(afterCommit.categories.first?.name, "Projects")
        XCTAssertEqual(afterCommit.notes.first?.text, "Changed")
    }

    func testUnfinishedPagesCoverPriorYearsWithWholeDayCountsAndPreserveStorage() throws {
        let cutoff = try GregorianDay(key: "2026-10-06")
        let expected = ["2026-10-05", "2026-09-01", "2025-12-31", "2024-02-29", "2001-01-01"]
        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            let category = try store.createCategory(name: "Work")
            for day in expected.reversed() {
                try store.add(note("Unfinished", day: day, createdAt: 1, categoryID: category.id))
            }
            // The newest day is 3/5, even when filtering for unfinished days.
            try store.add(note("Another unfinished", day: expected[0], createdAt: 2))
            for index in 0..<3 {
                try store.add(note("Completed", day: expected[0], createdAt: Double(index),
                                   completedAt: Date(timeIntervalSince1970: 999)))
            }
            try store.add(note("Completed-only day", day: "2026-10-04", createdAt: 1,
                               completedAt: Date(timeIntervalSince1970: 0)))
            for day in [cutoff.key, "2027-01-01"] {
                try store.add(note("Excluded", day: day, createdAt: 1))
            }
            try executeRaw("INSERT INTO later_tasks (id, text, created_at) VALUES ('\(UUID().uuidString)', 'Later', 2)")
            let rows = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
            let catalog = try rawRows("SELECT rowid, * FROM categories ORDER BY rowid")
            let later = try laterRows()
            let schema = try schemaSnapshot()
            let version = try schemaVersion()
            var before = cutoff
            var days: [String] = []
            repeat {
                let page = try store.unfinishedDayPage(before: before, limit: 2)
                days += page.summaries.map(\.dayKey)
                if days.count == 2 {
                    XCTAssertEqual(page.summaries[0].progress, NoteProgress(completed: 3, total: 5))
                    XCTAssertEqual(page.summaries[0].incomplete, 2)
                    XCTAssertEqual(page.nextBefore?.key, expected[1])
                }
                guard let next = page.nextBefore else { break }
                before = next
            } while days.count <= expected.count
            XCTAssertEqual(days, expected)
            let end = try store.unfinishedDayPage(before: GregorianDay(key: expected.last!), limit: 2)
            XCTAssertEqual(end.summaries, [])
            XCTAssertNil(end.nextBefore)
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), rows)
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM categories ORDER BY rowid"), catalog)
            XCTAssertEqual(try laterRows(), later)
            XCTAssertEqual(try schemaSnapshot(), schema)
            XCTAssertEqual(try schemaVersion(), version)
        }
        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        let exact = try reopened.unfinishedDayPage(before: cutoff, limit: expected.count)
        XCTAssertEqual(exact.summaries.map(\.dayKey), expected)
        XCTAssertNil(exact.nextBefore)
        let single = try reopened.unfinishedDayPage(before: cutoff, limit: 1)
        XCTAssertEqual(single.summaries.map(\.dayKey), [expected[0]])
        XCTAssertEqual(single.nextBefore?.key, expected[0])
        let plan = try rawRows("""
            EXPLAIN QUERY PLAN SELECT day_key, COUNT(*), COUNT(completed_at)
            FROM notes WHERE day_key < '2026-10-06'
            GROUP BY day_key HAVING COUNT(*) > COUNT(completed_at)
            ORDER BY day_key DESC LIMIT 3
            """)
        XCTAssertTrue(plan.contains { ($0.last ?? nil)?.contains("SEARCH notes USING INDEX notes_day_key_idx") == true })
    }

    func testUnfinishedPageRejectsInvalidLimitsAndEmptySuccessIsDistinctFromFailure() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let cutoff = try GregorianDay(key: "2026-10-06")
        for limit in [-1, 0, Int.max] {
            XCTAssertThrowsError(try store.unfinishedDayPage(before: cutoff, limit: limit)) { error in
                XCTAssertEqual(error as? TaskHistoryDomainError, .invalidPage)
            }
        }
        let empty = try store.unfinishedDayPage(before: cutoff, limit: 31)
        XCTAssertEqual(empty.summaries, [])
        XCTAssertNil(empty.nextBefore)
        try executeRaw("DROP TABLE notes")
        XCTAssertThrowsError(try store.unfinishedDayPage(before: cutoff, limit: 31)) { error in
            guard case SQLiteNoteStoreError.databaseError = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testUnfinishedPageValidatesCompletionIncludingCompletedOnlyDaysAndLookahead() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let cutoff = try GregorianDay(key: "2026-10-06")
        try store.add(note("Newest", day: "2026-10-05", createdAt: 1))
        try store.add(note("Lookahead", day: "2026-10-04", createdAt: 1))
        try store.add(note("Outside cutoff", day: cutoff.key, createdAt: 1))
        try executeRaw("UPDATE notes SET completed_at = 'invalid' WHERE day_key = '2026-10-06'")
        XCTAssertEqual(try store.unfinishedDayPage(before: cutoff, limit: 1).nextBefore?.key, "2026-10-05")
        for representation in ["'invalid'", "X'0102'", "1e999", "-1e999"] {
            // This day has no NULL completion left, but corruption cannot hide as completed-only.
            try executeRaw("UPDATE notes SET completed_at = \(representation) WHERE day_key = '2026-10-04'")
            XCTAssertThrowsError(try store.unfinishedDayPage(before: cutoff, limit: 1))
        }
        for representation in ["0", "-1", "1.5"] {
            try executeRaw("UPDATE notes SET completed_at = \(representation) WHERE day_key = '2026-10-04'")
            XCTAssertNil(try store.unfinishedDayPage(before: cutoff, limit: 1).nextBefore)
        }
        try executeRaw("UPDATE notes SET completed_at = NULL WHERE day_key = '2026-10-04'")
        XCTAssertEqual(try store.unfinishedDayPage(before: cutoff, limit: 1).nextBefore?.key, "2026-10-05")
    }

    func testUnfinishedLoadMoreThrowsOnMalformedDayThenCanRetrySameCursor() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let cutoff = try GregorianDay(key: "2026-10-06")
        for day in ["2026-10-05", "2026-10-04", "2025-02-28"] {
            try store.add(note("Saved", day: day, createdAt: 1))
        }
        let first = try store.unfinishedDayPage(before: cutoff, limit: 1)
        let next = try XCTUnwrap(first.nextBefore)
        // Add a malformed day in the next page's lookahead after the first read.
        try store.add(note("Malformed", day: "2025-02-30", createdAt: 1))
        let rows = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
        XCTAssertThrowsError(try store.unfinishedDayPage(before: next, limit: 1)) { error in
            XCTAssertEqual(error as? TaskHistoryDomainError, .invalidDayKey("2025-02-30"))
        }
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), rows)
        try executeRaw("DELETE FROM notes WHERE day_key = '2025-02-30'")
        let retry = try store.unfinishedDayPage(before: next, limit: 1)
        XCTAssertEqual(retry.summaries.map(\.dayKey), ["2026-10-04"])
        XCTAssertEqual(retry.nextBefore?.key, "2026-10-04")
        let last = try store.unfinishedDayPage(before: XCTUnwrap(retry.nextBefore), limit: 1)
        XCTAssertEqual(last.summaries.map(\.dayKey), ["2025-02-28"])
        XCTAssertNil(last.nextBefore)
    }

    private func note(_ text: String, day: String, createdAt: TimeInterval,
                      completedAt: Date? = nil, categoryID: UUID? = nil) -> Note {
        Note(id: UUID(), text: text, dayKey: day,
             createdAt: Date(timeIntervalSince1970: createdAt), completedAt: completedAt,
             categoryID: categoryID)
    }

    private func executeRaw(_ sql: String) throws {
        XCTAssertEqual(try rawResult(sql), SQLITE_OK, sql)
    }

    private func rawResult(_ sql: String) throws -> Int32 {
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &connection), SQLITE_OK)
        let database = try XCTUnwrap(connection)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "PRAGMA foreign_keys = ON", nil, nil, nil), SQLITE_OK)
        return sqlite3_exec(database, sql, nil, nil, nil)
    }

    private func rawRows(_ sql: String) throws -> [[String?]] {
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &connection), SQLITE_OK)
        let database = try XCTUnwrap(connection)
        defer { sqlite3_close(database) }
        var prepared: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, sql, -1, &prepared, nil), SQLITE_OK)
        let statement = try XCTUnwrap(prepared)
        defer { sqlite3_finalize(statement) }
        var rows: [[String?]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return rows }
            XCTAssertEqual(step, SQLITE_ROW)
            guard step == SQLITE_ROW else { return rows }
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                sqlite3_column_text(statement, column).map { String(cString: $0) }
            })
        }
    }

    private func legacyRows() throws -> [[String?]] {
        try rawRows("SELECT rowid, id, text, day_key, created_at, completed_at FROM notes ORDER BY rowid")
    }

    private func schemaSnapshot() throws -> [[String?]] {
        try rawRows("SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name")
    }

    private func seedLegacy(version: Int) throws {
        try executeRaw(
            """
            CREATE TABLE notes (
                id TEXT PRIMARY KEY NOT NULL, text TEXT NOT NULL,
                day_key TEXT NOT NULL, created_at REAL NOT NULL, completed_at REAL
            );
            INSERT INTO notes (rowid, id, text, day_key, created_at, completed_at) VALUES
                (7, '00000000-0000-0000-0000-000000000001', 'Today '' quote 📝', '2026-09-27', 10, NULL),
                (21, '00000000-0000-0000-0000-000000000002', 'Today completed', '2026-09-27', 20, 25),
                (35, '00000000-0000-0000-0000-000000000003', 'Yesterday unfinished', '2026-09-26', 30, NULL),
                (80, '00000000-0000-0000-0000-000000000004', 'Yesterday completed', '2026-09-26', 40, 45);
            PRAGMA user_version = \(version);
            """
        )
        if version == 1 {
            try executeRaw("CREATE INDEX notes_day_key_idx ON notes(day_key)")
        }
    }

    private static let workCategoryID = "00000000-0000-0000-0000-0000000000A1"

    /// Writes the known v2 format directly (as a v1 store upgraded by a v2 build),
    /// independently of the repository's current bootstrap.
    private func seedVersionTwo() throws {
        try seedLegacy(version: 1)
        try executeRaw(
            """
            CREATE TABLE categories (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                name_key TEXT NOT NULL UNIQUE,
                creation_order INTEGER NOT NULL UNIQUE CHECK(typeof(creation_order) = 'integer')
            );
            ALTER TABLE notes ADD COLUMN category_id TEXT DEFAULT NULL REFERENCES categories(id) ON DELETE SET NULL;
            CREATE INDEX notes_category_id_idx ON notes(category_id);
            INSERT INTO categories VALUES
                ('\(Self.workCategoryID)', 'Work', 'work', 0),
                ('00000000-0000-0000-0000-0000000000A2', 'School', 'school', 1);
            UPDATE notes SET category_id = '\(Self.workCategoryID)'
                WHERE id IN ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003');
            PRAGMA user_version = 2;
            """
        )
    }

    private func laterRows() throws -> [[String?]] {
        try rawRows("SELECT rowid, id, text, created_at, completed_at, category_id FROM later_tasks ORDER BY rowid")
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
