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
        XCTAssertEqual(try schemaVersion(), 4)
        XCTAssertEqual(try laterRows(), [])
    }

    func testNewerSchemaIsRejectedWithoutChangingDatabase() throws {
        try executeRaw(
            """
            CREATE TABLE future_data (id INTEGER PRIMARY KEY, payload TEXT NOT NULL);
            INSERT INTO future_data VALUES (1, 'Preserve unknown future data 📝');
            PRAGMA user_version = 5;
            """
        )
        let originalBytes = try Data(contentsOf: databaseURL)

        XCTAssertThrowsError(try SQLiteNoteRepository(databaseURL: databaseURL)) { error in
            guard case SQLiteNoteStoreError.unsupportedSchemaVersion(5) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try schemaVersion(), 5)
        XCTAssertEqual(try Data(contentsOf: databaseURL), originalBytes)
    }

    func testFreshSchemaEnforcesCategoryConstraintsAndRemovalPreservesTasksAcrossDays() throws {
        let today = note("Today", day: "2026-09-27", createdAt: 10)
        let yesterday = note("Yesterday", day: "2026-09-26", createdAt: 20)
        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            XCTAssertEqual(try schemaVersion(), 4)
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

    func testVersionFourReopenDoesNotChangeSchemaDataOrDatabaseBytes() throws {
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
            XCTAssertEqual(try schemaVersion(), 4)
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
            XCTAssertEqual(try schemaVersion(), 4)
            XCTAssertEqual(try rawRows("SELECT rowid, id, text, day_key, created_at, completed_at, category_id FROM notes ORDER BY rowid"), rows)
            XCTAssertEqual(try rawRows("SELECT * FROM categories ORDER BY creation_order"), categories)
            XCTAssertEqual(try laterRows(), [])
            // Category and existing index definitions survive; notes gains one column.
            let upgraded = try schemaSnapshot()
            XCTAssertEqual(upgraded.filter { $0[2] != "later_tasks" && $0[1] != "notes" && $0[1] != "notes_day_display_order_idx" },
                           schema.filter { $0[1] != "notes" })
            XCTAssertEqual(upgraded.filter { $0[2] == "later_tasks" }.map { $0[1] },
                           ["later_tasks_category_id_idx", "sqlite_autoindex_later_tasks_1", "later_tasks"])
            XCTAssertEqual(try store.notes(for: "2026-09-27").map(\.categoryID), [work, nil])
            XCTAssertEqual(try store.notes(for: "2026-09-26").map(\.categoryID), [work, nil])
            XCTAssertEqual(try store.categoryUsageCount(id: work), 2)
            try store.add(added)
        }

        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try schemaVersion(), 4)
        XCTAssertEqual(Array(try rawRows("SELECT rowid, id, text, day_key, created_at, completed_at, category_id FROM notes ORDER BY rowid").prefix(rows.count)), rows)
        XCTAssertEqual(try reopened.notes(for: "2026-09-27").map(\.text),
                       ["Today ' quote 📝", "Today completed", "Added after upgrade"])
        XCTAssertEqual(try reopened.categories().map(\.name), ["Work", "School"])
        XCTAssertEqual(try laterRows(), [])
    }

    func testAllHistoricalVersionsBackfillEachDayAndPreserveUnrelatedData() throws {
        for version in 0...3 {
            if version == 3 { try seedVersionThree() }
            else if version == 2 { try seedVersionTwo() }
            else { try seedLegacy(version: version) }
            // Interleave assigned days in rowid order; completion/categories already differ.
            try executeRaw("UPDATE notes SET day_key = '2026-09-26' WHERE rowid = 21; UPDATE notes SET day_key = '2026-09-27' WHERE rowid = 35;")
            let before = try legacyRows()
            let categories = version >= 2 ? try rawRows("SELECT * FROM categories ORDER BY creation_order") : []
            let later = version == 3 ? try laterRows() : []
            do {
                let store = try SQLiteNoteRepository(databaseURL: databaseURL)
                XCTAssertEqual(try schemaVersion(), 4)
                XCTAssertEqual(try legacyRows(), before)
                XCTAssertEqual(try rawRows("SELECT rowid, display_order FROM notes ORDER BY rowid"),
                               [["7", "0"], ["21", "0"], ["35", "1"], ["80", "1"]])
                XCTAssertEqual(try store.notes(for: "2026-09-27").map(\.text),
                               ["Today ' quote 📝", "Yesterday unfinished"])
                XCTAssertEqual(try rawRows("SELECT * FROM categories ORDER BY creation_order"), categories)
                XCTAssertEqual(try laterRows(), later)
            }
            // Sparse committed ranks survive reopen without normalization.
            try executeRaw("UPDATE notes SET display_order = display_order + 10")
            let rows = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
            let bytes = try Data(contentsOf: databaseURL)
            do { _ = try SQLiteNoteRepository(databaseURL: databaseURL) }
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), rows)
            XCTAssertEqual(try Data(contentsOf: databaseURL), bytes)
            try FileManager.default.removeItem(at: databaseURL)
        }
    }

    func testFailureAfterOrderingBackfillRollsBackAllVersionsAndRetries() throws {
        for version in 0...3 {
            if version == 3 { try seedVersionThree() }
            else if version == 2 { try seedVersionTwo() }
            else { try seedLegacy(version: version) }
            // Index-name collision occurs after ALTER and backfill, before version advance.
            try executeRaw("CREATE INDEX notes_day_display_order_idx ON notes(text)")
            let schema = try schemaSnapshot()
            let rows = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
            let later = version == 3 ? try laterRows() : []
            XCTAssertThrowsError(try SQLiteNoteRepository(databaseURL: databaseURL))
            XCTAssertEqual(try schemaSnapshot(), schema)
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), rows)
            XCTAssertEqual(try schemaVersion(), version)
            if version == 3 { XCTAssertEqual(try laterRows(), later) }
            try executeRaw("DROP INDEX notes_day_display_order_idx")
            do {
                _ = try SQLiteNoteRepository(databaseURL: databaseURL)
                XCTAssertEqual(try schemaVersion(), 4)
                XCTAssertEqual(try legacyRows(), rows.map { Array($0.prefix(6)) })
                XCTAssertEqual(try laterRows(), later)
            }
            try FileManager.default.removeItem(at: databaseURL)
        }
    }

    func testMalformedVersionFourOrderIsRefusedWithoutRepair() throws {
        let cases = [
            "UPDATE notes SET display_order = -1 WHERE rowid = 7",
            "PRAGMA ignore_check_constraints = ON; UPDATE notes SET display_order = 0.5 WHERE rowid = 7",
            "DROP INDEX notes_day_display_order_idx",
            "DROP INDEX notes_day_display_order_idx; CREATE INDEX notes_day_display_order_idx ON notes(day_key, display_order)",
            "DROP INDEX notes_day_display_order_idx; CREATE UNIQUE INDEX notes_day_display_order_idx ON notes(display_order, day_key)",
            "DROP INDEX notes_day_display_order_idx; CREATE UNIQUE INDEX notes_day_display_order_idx ON notes(day_key, display_order) WHERE display_order >= 0",
            "DROP INDEX notes_day_display_order_idx; UPDATE notes SET display_order = 0"
        ]
        for sql in cases {
            try seedVersionThree()
            do { _ = try SQLiteNoteRepository(databaseURL: databaseURL) }
            try executeRaw(sql)
            let bytes = try Data(contentsOf: databaseURL)
            let rows = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
            XCTAssertThrowsError(try SQLiteNoteRepository(databaseURL: databaseURL), sql)
            XCTAssertEqual(try schemaVersion(), 4)
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), rows)
            XCTAssertEqual(try Data(contentsOf: databaseURL), bytes)
            try FileManager.default.removeItem(at: databaseURL)
        }
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
                XCTAssertEqual(try schemaVersion(), 4)
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

    func testLaterActionsPreserveIdentityOrderAndTodayAndSurviveReopen() throws {
        let today = note("Today", day: "2026-10-05", createdAt: 1)
        let first = later("First", createdAt: 10)
        let second = later("Second", createdAt: 20, completedAt: Date(timeIntervalSince1970: 25))
        let third = later("Third ' quote 📝", createdAt: 30)
        let work: TaskCategory
        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            work = try store.createCategory(name: "Work")
            try store.add(today)
            for task in [first, second, third] { try store.addLater(task) }
            XCTAssertEqual(try store.laterTasks(), [first, second, third])
            let rowids = try laterRows().map { $0[0] }

            try store.setLaterCompleted(id: first.id, completedAt: Date(timeIntervalSince1970: 40))
            try store.setLaterCompleted(id: second.id, completedAt: nil)
            try store.updateLater(id: third.id, text: "Third edited", categoryID: work.id)
            XCTAssertEqual(try store.laterTasks(), [
                LaterTask(id: first.id, text: "First", createdAt: first.createdAt,
                          completedAt: Date(timeIntervalSince1970: 40)),
                LaterTask(id: second.id, text: "Second", createdAt: second.createdAt, completedAt: nil),
                LaterTask(id: third.id, text: "Third edited", createdAt: third.createdAt,
                          completedAt: nil, categoryID: work.id),
            ])
            // Completion and edits keep each row's saved position.
            XCTAssertEqual(try laterRows().map { $0[0] }, rowids)
            try store.updateLater(id: third.id, text: "Third edited", categoryID: nil)
            try store.updateLater(id: third.id, text: "Third final", categoryID: work.id)
            try store.deleteLater(id: second.id)
            XCTAssertEqual(try laterRows().map { $0[0] }, [rowids[0], rowids[2]])
            try store.addLater(second)
            XCTAssertEqual(try store.laterTasks().map(\.id), [first.id, third.id, second.id])
        }

        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.laterTasks(), [
            LaterTask(id: first.id, text: "First", createdAt: first.createdAt,
                      completedAt: Date(timeIntervalSince1970: 40)),
            LaterTask(id: third.id, text: "Third final", createdAt: third.createdAt,
                      completedAt: nil, categoryID: work.id),
            second,
        ])
        // Later actions never change daily tasks or Today's progress.
        XCTAssertEqual(try reopened.notes(for: today.dayKey), [today])
        XCTAssertEqual(try reopened.incompleteCount(for: today.dayKey), 1)
    }

    func testLaterMissingTargetsDuplicatesAndMissingCategoriesThrowWithoutChangingRows() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let work = try store.createCategory(name: "Work")
        let saved = later("Saved", createdAt: 10, categoryID: work.id)
        try store.addLater(saved)
        let daily = note("Daily", day: "2026-10-05", createdAt: 1)
        try store.add(daily)
        let before = try laterRows()
        let missing = UUID()
        let unknownCategory = UUID()

        let missingTargets: [() throws -> Void] = [
            { try store.setLaterCompleted(id: missing, completedAt: Date()) },
            { try store.updateLater(id: missing, text: "Edited", categoryID: nil) },
            { try store.deleteLater(id: missing) },
            // A daily task's ID is not a Later target.
            { try store.deleteLater(id: daily.id) },
        ]
        for operation in missingTargets {
            XCTAssertThrowsError(try operation()) {
                let error = $0 as? LaterTaskRepositoryError
                XCTAssertTrue(error == .notFound(missing) || error == .notFound(daily.id), "\($0)")
            }
            XCTAssertEqual(try laterRows(), before)
        }
        XCTAssertThrowsError(try store.addLater(later("Duplicate", createdAt: 99, id: saved.id)))
        let missingCategoryWrites: [() throws -> Void] = [
            { try store.addLater(self.later("Unknown", createdAt: 11, categoryID: unknownCategory)) },
            { try store.updateLater(id: saved.id, text: "Edited", categoryID: unknownCategory) },
        ]
        for operation in missingCategoryWrites {
            XCTAssertThrowsError(try operation()) {
                XCTAssertEqual($0 as? TaskCategoryRepositoryError, .notFound(unknownCategory))
            }
        }
        XCTAssertEqual(try laterRows(), before)
        XCTAssertEqual(try store.laterTasks(), [saved])
        XCTAssertEqual(try store.notes(for: daily.dayKey), [daily])
    }

    func testLaterWriteFailuresRollBackThenRetrySafely() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let work = try store.createCategory(name: "Work")
        let saved = later("Saved", createdAt: 10)
        try store.addLater(saved)
        let before = try laterRows()
        let added = later("Added", createdAt: 20)
        try executeRaw(
            """
            CREATE TRIGGER reject_later_add AFTER INSERT ON later_tasks
            BEGIN SELECT RAISE(FAIL, 'write rejected'); END;
            CREATE TRIGGER reject_later_completion AFTER UPDATE OF completed_at ON later_tasks
            BEGIN SELECT RAISE(FAIL, 'write rejected'); END;
            CREATE TRIGGER reject_later_edit AFTER UPDATE OF text ON later_tasks
            BEGIN SELECT RAISE(FAIL, 'write rejected'); END;
            CREATE TRIGGER reject_later_delete BEFORE DELETE ON later_tasks
            BEGIN SELECT RAISE(FAIL, 'write rejected'); END;
            """
        )
        let operations: [() throws -> Void] = [
            { try store.addLater(added) },
            { try store.setLaterCompleted(id: saved.id, completedAt: Date(timeIntervalSince1970: 30)) },
            { try store.updateLater(id: saved.id, text: "Edited", categoryID: work.id) },
            { try store.deleteLater(id: saved.id) },
        ]
        for operation in operations {
            XCTAssertThrowsError(try operation())
            // The edit's text and category are rolled back together.
            XCTAssertEqual(try laterRows(), before)
        }
        try executeRaw(
            """
            DROP TRIGGER reject_later_add; DROP TRIGGER reject_later_completion;
            DROP TRIGGER reject_later_edit; DROP TRIGGER reject_later_delete;
            """
        )
        for operation in operations.dropLast() { try operation() }
        XCTAssertEqual(try store.laterTasks(), [
            LaterTask(id: saved.id, text: "Edited", createdAt: saved.createdAt,
                      completedAt: Date(timeIntervalSince1970: 30), categoryID: work.id),
            added,
        ])
        try operations.last!()
        XCTAssertEqual(try SQLiteNoteRepository(databaseURL: databaseURL).laterTasks(), [added])
    }

    func testInvalidLaterRowsAreReadErrorsWithoutRepair() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let work = try store.createCategory(name: "Work")
        let saved = later("Saved", createdAt: 10, categoryID: work.id)
        try store.addLater(saved)
        let invalidChanges = [
            "id = 'not-a-uuid'",
            "created_at = 'not-a-time'",
            "completed_at = 'not-a-time'",
            "text = CAST(x'FF' AS TEXT)",
            "category_id = 'not-a-uuid'",
            "category_id = '\(UUID().uuidString)'",
        ]
        for change in invalidChanges {
            // Only the isolated fixture writer disables its own connection's enforcement.
            try executeRaw("PRAGMA foreign_keys = OFF; UPDATE later_tasks SET \(change)")
            let corrupted = try laterRows()
            XCTAssertThrowsError(try store.laterTasks(), change)
            XCTAssertEqual(try laterRows(), corrupted, change)
            try executeRaw(
                """
                DELETE FROM later_tasks;
                INSERT INTO later_tasks VALUES ('\(saved.id.uuidString)', 'Saved', 10, NULL, '\(work.id.uuidString)');
                """
            )
            XCTAssertEqual(try store.laterTasks(), [saved])
        }
        try executeRaw("UPDATE categories SET name_key = 'wrong-key'")
        XCTAssertThrowsError(try store.laterTasks())
    }

    func testCategoryUsageAndRemovalCoverDailyHistoryAndLaterAtomically() throws {
        let days = ["2026-10-05", "2026-10-04"]
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let work = try store.createCategory(name: "Work")
        let other = try store.createCategory(name: "Other")
        for (index, day) in days.enumerated() {
            try store.add(note("Unfinished", day: day, createdAt: Double(index), categoryID: work.id))
            try store.add(note("Finished", day: day, createdAt: Double(index),
                               completedAt: Date(timeIntervalSince1970: 30), categoryID: work.id))
            try store.add(note("Other", day: day, createdAt: Double(index), categoryID: other.id))
        }
        let laterTasks = [
            later("Later unfinished", createdAt: 40, categoryID: work.id),
            later("Later finished", createdAt: 41, completedAt: Date(timeIntervalSince1970: 45),
                  categoryID: work.id),
            later("Later other", createdAt: 42, categoryID: other.id),
            later("Later general", createdAt: 43),
        ]
        for task in laterTasks { try store.addLater(task) }
        // Four daily tasks across two days plus two Later tasks, including completed ones.
        XCTAssertEqual(try store.categoryUsageCount(id: work.id), 6)
        XCTAssertEqual(try store.categoryUsageCount(id: other.id), 3)
        let unused = try store.createCategory(name: "Unused")
        XCTAssertEqual(try store.categoryUsageCount(id: unused.id), 0)
        let notesBefore = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
        let laterBefore = try laterRows()

        // A failure while clearing Later assignments must also undo the daily ones.
        try executeRaw(
            """
            CREATE TRIGGER reject_later_assignment AFTER UPDATE OF category_id ON later_tasks
            BEGIN SELECT RAISE(FAIL, 'write rejected after reassignment'); END;
            """
        )
        XCTAssertThrowsError(try store.removeCategory(id: work.id))
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), notesBefore)
        XCTAssertEqual(try laterRows(), laterBefore)
        XCTAssertEqual(try store.categories(), [work, other, unused])
        XCTAssertEqual(try store.categoryUsageCount(id: work.id), 6)
        try executeRaw("DROP TRIGGER reject_later_assignment")

        try store.removeCategory(id: work.id)
        let expectedLater = laterTasks.map { task in
            LaterTask(id: task.id, text: task.text, createdAt: task.createdAt, completedAt: task.completedAt,
                      categoryID: task.categoryID == work.id ? nil : task.categoryID)
        }
        XCTAssertEqual(try store.laterTasks(), expectedLater)
        XCTAssertEqual(try laterRows().map { Array($0.prefix(5)) }, laterBefore.map { Array($0.prefix(5)) })
        XCTAssertEqual(try rawRows("SELECT category_id FROM notes ORDER BY rowid"),
                       Array(repeating: [[nil], [nil], [other.id.uuidString]], count: 2).flatMap { $0 })
        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.categories(), [other, unused])
        XCTAssertEqual(try reopened.categoryUsageCount(id: other.id), 3)
        XCTAssertEqual(try reopened.laterTasks(), expectedLater)
        XCTAssertThrowsError(try reopened.categoryUsageCount(id: work.id)) {
            XCTAssertEqual($0 as? TaskCategoryRepositoryError, .notFound(work.id))
        }
    }

    private func later(_ text: String, createdAt: TimeInterval, completedAt: Date? = nil,
                       categoryID: UUID? = nil, id: UUID = UUID()) -> LaterTask {
        LaterTask(id: id, text: text, createdAt: Date(timeIntervalSince1970: createdAt),
                  completedAt: completedAt, categoryID: categoryID)
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

    /// Independent historical v3 fixture, including categorized/completed Later rows.
    private func seedVersionThree() throws {
        try seedVersionTwo()
        try executeRaw(
            """
            CREATE TABLE later_tasks (
                id TEXT PRIMARY KEY NOT NULL, text TEXT NOT NULL,
                created_at REAL NOT NULL, completed_at REAL,
                category_id TEXT DEFAULT NULL REFERENCES categories(id) ON DELETE SET NULL
            );
            CREATE INDEX later_tasks_category_id_idx ON later_tasks(category_id);
            INSERT INTO later_tasks VALUES
                ('00000000-0000-0000-0000-0000000000B1', 'Later work', 60, NULL, '\(Self.workCategoryID)'),
                ('00000000-0000-0000-0000-0000000000B2', 'Later done', 70, 75, NULL);
            PRAGMA user_version = 3;
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
