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
        XCTAssertTrue(usesDayKeyIndexSearch(plan), "\(plan)")
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
        XCTAssertTrue(usesDayKeyIndexSearch(plan), "\(plan)")
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

    func testCategoryMovesReopenAndPreserveSchemaTaskRowsAndCategoryFields() throws {
        let saved = try { () throws -> [TaskCategory] in
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            let work = try store.createCategory(name: "Work")
            let empty = try store.createCategory(name: "Empty")
            let personal = try store.createCategory(name: "Personal")
            let learning = try store.createCategory(name: "Learning")
            let day = "2026-10-13"
            for row in [note("Work ' 📝", day: day, createdAt: 10, categoryID: work.id),
                        note("Done", day: day, createdAt: 20,
                             completedAt: Date(timeIntervalSince1970: 25), categoryID: personal.id),
                        note("General", day: day, createdAt: 30),
                        note("Older", day: "2026-10-12", createdAt: 40, categoryID: work.id)] {
                try store.add(row)
            }
            try store.addLater(later("Later", createdAt: 50, categoryID: learning.id))
            try store.addLater(later("Done later", createdAt: 60,
                                     completedAt: Date(timeIntervalSince1970: 65), categoryID: work.id))
            try executeRaw("UPDATE notes SET display_order = display_order + 50")
            // Any task UPDATE fails, even one that would restore the same values.
            for table in ["notes", "later_tasks"] {
                try executeRaw("CREATE TRIGGER protect_\(table) BEFORE UPDATE ON \(table) BEGIN SELECT RAISE(ABORT, 'task update'); END")
            }
            let tasks = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
            let laterTasks = try rawRows("SELECT rowid, * FROM later_tasks ORDER BY rowid")
            let fields = try rawRows("SELECT rowid, id, name, name_key FROM categories ORDER BY rowid")
            let schema = try schemaSnapshot()
            let version = try rawRows("PRAGMA user_version")
            var catalog = try store.categories()
            func move(_ source: UUID, _ placement: CategoryMovePlacement, ids: [UUID]) throws {
                let outcome = try store.moveCategory(CategoryMoveRequest(categoryID: source,
                    expectedOrderIDs: catalog.map(\.id), placement: placement))
                guard case let .changed(result) = outcome else { return XCTFail("Expected saved reorder") }
                XCTAssertEqual(result.map(\.id), ids)
                XCTAssertEqual(result.map(\.creationOrder), [0, 1, 2, 3])
                XCTAssertEqual(try store.categories(), result)
                XCTAssertEqual(try SQLiteNoteRepository(databaseURL: databaseURL).categories(), result)
                XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), tasks)
                XCTAssertEqual(try rawRows("SELECT rowid, * FROM later_tasks ORDER BY rowid"), laterTasks)
                XCTAssertEqual(try rawRows("SELECT rowid, id, name, name_key FROM categories ORDER BY rowid"), fields)
                XCTAssertEqual(try schemaSnapshot(), schema)
                XCTAssertEqual(try rawRows("PRAGMA user_version"), version)
                catalog = result
            }
            // UUID anchors place a visible source around the unused category.
            try move(personal.id, .before(work.id), ids: [personal.id, work.id, empty.id, learning.id])
            try move(work.id, .after(learning.id), ids: [personal.id, empty.id, learning.id, work.id])
            try move(empty.id, .before(personal.id), ids: [empty.id, personal.id, learning.id, work.id])
            XCTAssertEqual(try store.incompleteCount(for: day), 2)
            return catalog
        }()
        // The original repository connection has now closed completely.
        XCTAssertEqual(try SQLiteNoteRepository(databaseURL: databaseURL).categories(), saved)
        XCTAssertEqual(try rawRows("PRAGMA integrity_check"), [["ok"]])
    }

    func testCategoryNoOpAndRejectionsNeverUpdateAndKeepLegacyRanks() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let a = try store.createCategory(name: "A")
        let b = try store.createCategory(name: "B")
        let c = try store.createCategory(name: "C")
        try executeRaw("UPDATE categories SET creation_order = -10 WHERE id = '\(a.id.uuidString)'")
        try executeRaw("UPDATE categories SET creation_order = 50 WHERE id = '\(b.id.uuidString)'")
        try executeRaw("UPDATE categories SET creation_order = \(Int64.max) WHERE id = '\(c.id.uuidString)'")
        let before = try rawRows("SELECT rowid, * FROM categories ORDER BY rowid")
        try executeRaw("CREATE TRIGGER reject_category_update BEFORE UPDATE ON categories BEGIN SELECT RAISE(ABORT, 'unexpected update'); END")
        func request(_ source: UUID? = nil, ids: [UUID]? = nil,
                     placement: CategoryMovePlacement? = nil) -> CategoryMoveRequest {
            CategoryMoveRequest(categoryID: source ?? a.id, expectedOrderIDs: ids ?? [a.id, b.id, c.id],
                                placement: placement ?? .before(b.id))
        }
        XCTAssertEqual(try store.moveCategory(request()), .unchanged)
        XCTAssertEqual(try store.moveCategory(request(c.id, placement: .after(b.id))), .unchanged)
        XCTAssertEqual(try store.moveCategory(request(ids: [a.id, a.id, c.id])), .rejected(.invalidExpectedOrder))
        XCTAssertEqual(try store.moveCategory(request(ids: [c.id, b.id, a.id])), .rejected(.catalogChanged))
        XCTAssertEqual(try store.moveCategory(request(ids: [a.id, c.id])), .rejected(.catalogChanged))
        XCTAssertEqual(try store.moveCategory(request(UUID())), .rejected(.categoryNotFound))
        XCTAssertEqual(try store.moveCategory(request(placement: .after(a.id))), .rejected(.invalidAnchor))
        XCTAssertEqual(try store.moveCategory(request(placement: .before(UUID()))), .rejected(.invalidAnchor))
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM categories ORDER BY rowid"), before)
        _ = try SQLiteNoteRepository(databaseURL: databaseURL).categories()
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM categories ORDER BY rowid"), before)
    }

    func testCategoryMoveRejectsStaleCatalogFromAnotherConnection() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let a = try store.createCategory(name: "A")
        let b = try store.createCategory(name: "B")
        let other = try SQLiteNoteRepository(databaseURL: databaseURL)
        _ = try other.moveCategory(CategoryMoveRequest(categoryID: b.id,
            expectedOrderIDs: [a.id, b.id], placement: .before(a.id)))
        let before = try rawRows("SELECT rowid, * FROM categories ORDER BY rowid")
        try executeRaw("CREATE TRIGGER reject_stale_update BEFORE UPDATE ON categories BEGIN SELECT RAISE(ABORT, 'stale update'); END")
        XCTAssertEqual(try store.moveCategory(CategoryMoveRequest(categoryID: b.id,
            expectedOrderIDs: [a.id, b.id], placement: .before(a.id))), .rejected(.catalogChanged))
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM categories ORDER BY rowid"), before)
    }

    func testCategoryMoveStagesAroundNegativeSparseAndExtremeRanks() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let ranks: [Int64] = [.min, .min + 1, -2, -1, 100, .max - 1, .max]
        var original: [TaskCategory] = []
        for index in ranks.indices {
            let category = try store.createCategory(name: "Category \(index)")
            original.append(category)
        }
        // Seed after all creates, since max-rank append must remain checked.
        for (category, rank) in zip(original, ranks) {
            try executeRaw("UPDATE categories SET creation_order = \(rank) WHERE id = '\(category.id.uuidString)'")
        }
        let before = try rawRows("SELECT rowid, * FROM categories ORDER BY rowid")
        XCTAssertEqual(try store.categories().map(\.creationOrder), ranks)
        XCTAssertThrowsError(try store.createCategory(name: "Overflow")) {
            XCTAssertEqual($0 as? TaskCategoryRepositoryError, .orderExhausted)
        }
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM categories ORDER BY rowid"), before)
        let last = try XCTUnwrap(original.last)
        guard case let .changed(saved) = try store.moveCategory(CategoryMoveRequest(categoryID: last.id,
            expectedOrderIDs: original.map(\.id), placement: .before(original[0].id))) else {
            return XCTFail("Expected legacy reorder")
        }
        XCTAssertEqual(saved.map(\.id), [last.id] + original.dropLast().map(\.id))
        XCTAssertEqual(saved.map(\.creationOrder), Array(0..<Int64(ranks.count)))
        XCTAssertEqual(try SQLiteNoteRepository(databaseURL: databaseURL).categories(), saved)
        XCTAssertEqual(try rawRows("SELECT rowid, id, name, name_key FROM categories ORDER BY rowid"),
                       before.map { Array($0.dropLast()) })
    }

    func testCategoryStagingRangeChecksFinalRanksOverflowAndExhaustion() throws {
        XCTAssertEqual(try SQLiteNoteRepository.categoryStagingStart(avoiding: [.min, .min + 2], count: 3), .min + 3)
        // A large arithmetic model exercises positive fallback without allocating
        // billions of categories. Final 0..<count ranks must also be excluded.
        let count = Int64.max / 2
        XCTAssertEqual(try SQLiteNoteRepository.categoryStagingStart(avoiding: [.min, .min / 2 - 1, -2], count: count), count)
        for count in [Int64(0), -1, .max] {
            XCTAssertThrowsError(try SQLiteNoteRepository.categoryStagingStart(avoiding: [.min, -2], count: count)) {
                XCTAssertEqual($0 as? TaskCategoryRepositoryError, .orderExhausted)
            }
        }
    }

    func testCategoryMoveFailuresRollBackBothRankPassesAndAllowRetry() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let a = try store.createCategory(name: "A")
        let b = try store.createCategory(name: "B")
        try store.add(note("Today", day: "2026-10-13", createdAt: 10, categoryID: a.id))
        try store.addLater(later("Later", createdAt: 20, categoryID: b.id))
        let before = try rawRows("SELECT rowid, * FROM categories ORDER BY rowid")
        let tasks = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
        let laterTasks = try rawRows("SELECT rowid, * FROM later_tasks ORDER BY rowid")
        let request = CategoryMoveRequest(categoryID: b.id, expectedOrderIDs: [a.id, b.id], placement: .before(a.id))
        for condition in ["NEW.creation_order = \(Int64.min + 1)",
                          "OLD.creation_order < 0 AND NEW.creation_order = 1"] {
            try executeRaw("CREATE TRIGGER reject_category_move AFTER UPDATE ON categories WHEN \(condition) BEGIN SELECT RAISE(FAIL, 'rank write failed'); END")
            XCTAssertThrowsError(try store.moveCategory(request))
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM categories ORDER BY rowid"), before)
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), tasks)
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM later_tasks ORDER BY rowid"), laterTasks)
            XCTAssertEqual(try SQLiteNoteRepository(databaseURL: databaseURL).categories(), [a, b])
            try executeRaw("DROP TRIGGER reject_category_move")
        }
        try executeRaw("CREATE TRIGGER ignore_category_move BEFORE UPDATE ON categories WHEN NEW.creation_order = \(Int64.min + 1) BEGIN SELECT RAISE(IGNORE); END")
        XCTAssertThrowsError(try store.moveCategory(request)) {
            XCTAssertEqual($0 as? TaskCategoryRepositoryError, .notFound(a.id))
        }
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM categories ORDER BY rowid"), before)
        try executeRaw("DROP TRIGGER ignore_category_move")
        guard case let .changed(saved) = try store.moveCategory(request) else { return XCTFail("Retry failed") }
        XCTAssertEqual(saved.map(\.id), [b.id, a.id])
    }

    func testCategoryMoveCommitFailureRollsBackAndAllowsRetry() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let a = try store.createCategory(name: "A")
        let b = try store.createCategory(name: "B")
        try store.add(note("Today", day: "2026-10-13", createdAt: 10, categoryID: a.id))
        try store.addLater(later("Later", createdAt: 20, categoryID: b.id))
        let before = try rawRows("SELECT rowid, * FROM categories ORDER BY rowid")
        let tasks = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
        let laterTasks = try rawRows("SELECT rowid, * FROM later_tasks ORDER BY rowid")
        var reader: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &reader), SQLITE_OK)
        let connection = try XCTUnwrap(reader)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(sqlite3_exec(connection, "BEGIN; SELECT * FROM categories", nil, nil, nil), SQLITE_OK)
        let request = CategoryMoveRequest(categoryID: b.id, expectedOrderIDs: [a.id, b.id], placement: .before(a.id))
        XCTAssertThrowsError(try store.moveCategory(request)) { error in
            guard case let SQLiteNoteStoreError.databaseError(operation, code, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(operation, "COMMIT")
            XCTAssertEqual(code, SQLITE_BUSY)
        }
        XCTAssertEqual(sqlite3_exec(connection, "ROLLBACK", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM categories ORDER BY rowid"), before)
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), tasks)
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM later_tasks ORDER BY rowid"), laterTasks)
        XCTAssertEqual(try store.categories(), [a, b])
        guard case let .changed(saved) = try store.moveCategory(request) else { return XCTFail("Retry failed") }
        XCTAssertEqual(try SQLiteNoteRepository(databaseURL: databaseURL).categories(), saved)
        XCTAssertEqual(saved.map(\.id), [b.id, a.id])
    }

    func testCategoryCRUDKeepsSavedOrderAfterReorder() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let a = try store.createCategory(name: "A")
        let b = try store.createCategory(name: "B")
        let c = try store.createCategory(name: "C")
        _ = try store.moveCategory(CategoryMoveRequest(categoryID: c.id,
            expectedOrderIDs: [a.id, b.id, c.id], placement: .before(a.id)))
        let appended = try store.createCategory(name: "Appended")
        XCTAssertEqual(appended.creationOrder, 3)
        let renamed = try store.renameCategory(id: a.id, name: "Renamed")
        XCTAssertEqual(renamed.creationOrder, 1)
        XCTAssertThrowsError(try store.createCategory(name: "renamed")) {
            XCTAssertEqual($0 as? TaskCategoryRepositoryError, .duplicateName)
        }
        XCTAssertThrowsError(try store.renameCategory(id: b.id, name: "RENAMED")) {
            XCTAssertEqual($0 as? TaskCategoryRepositoryError, .duplicateName)
        }
        try store.removeCategory(id: b.id)
        let catalog = try SQLiteNoteRepository(databaseURL: databaseURL).categories()
        XCTAssertEqual(catalog.map(\.id), [c.id, a.id, appended.id])
        XCTAssertEqual(catalog.map(\.creationOrder), [0, 1, 3])
        XCTAssertEqual(catalog[1], renamed)
        XCTAssertThrowsError(try store.removeCategory(id: b.id)) {
            XCTAssertEqual($0 as? TaskCategoryRepositoryError, .notFound(b.id))
        }
    }

    func testSavedMovesReopenWithExactOrderAndPreserveOtherData() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let work = try store.createCategory(name: "Work")
        let study = try store.createCategory(name: "Study")
        let empty = try store.createCategory(name: "Empty")
        let day = "2026-10-07"
        let a = note("A", day: day, createdAt: 10, categoryID: work.id)
        let b = note("B", day: day, createdAt: 20, categoryID: study.id)
        let c = note("C", day: day, createdAt: 30, completedAt: Date(timeIntervalSince1970: 35), categoryID: work.id)
        let d = note("D", day: day, createdAt: 40, categoryID: study.id)
        let old = note("Other day", day: "2026-10-06", createdAt: 50)
        for row in [a, b, c, d, old] { try store.add(row) }
        try store.addLater(later("Later", createdAt: 60, categoryID: work.id))
        let fields = try rawRows("SELECT rowid, id, text, day_key, created_at, completed_at FROM notes ORDER BY rowid")
        let otherDay = try rawRows("SELECT * FROM notes WHERE day_key = '2026-10-06'")
        let laterBefore = try laterRows()
        let catalog = try store.categories()
        func move(_ source: Note, from: TaskGroupID, to: TaskGroupID,
                  placement: TaskMovePlacement, ids: [UUID]) throws {
            let outcome = try store.moveTask(TaskMoveRequest(taskID: source.id, expectedDayKey: day,
                expectedSourceGroup: from, destinationGroup: to, placement: placement))
            guard case let .changed(saved) = outcome else { return XCTFail("Expected committed move") }
            XCTAssertEqual(saved.map(\.id), ids)
            XCTAssertEqual(try SQLiteNoteRepository(databaseURL: databaseURL).notes(for: day), saved)
        }
        try move(c, from: .category(work.id), to: .category(work.id), placement: .before(a.id), ids: [c.id, a.id, b.id, d.id])
        try move(c, from: .category(work.id), to: .category(study.id), placement: .after(b.id), ids: [a.id, b.id, c.id, d.id])
        try move(c, from: .category(study.id), to: .general, placement: .endOfGroup, ids: [a.id, b.id, d.id, c.id])
        try move(c, from: .general, to: .category(empty.id), placement: .endOfGroup, ids: [a.id, b.id, d.id, c.id])
        try move(c, from: .category(empty.id), to: .category(study.id), placement: .before(b.id), ids: [a.id, c.id, b.id, d.id])
        XCTAssertEqual(try rawRows("SELECT rowid, id, text, day_key, created_at, completed_at FROM notes ORDER BY rowid"), fields)
        XCTAssertEqual(try rawRows("SELECT * FROM notes WHERE day_key = '2026-10-06'"), otherDay)
        XCTAssertEqual(try laterRows(), laterBefore)
        XCTAssertEqual(try store.categories(), catalog)
        XCTAssertEqual(try store.incompleteCount(for: day), 3)
    }

    func testRejectedAndEquivalentMovesNeverUpdateSavedRows() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let work = try store.createCategory(name: "Work")
        let a = note("A", day: "2026-10-07", createdAt: 10)
        let b = note("B", day: a.dayKey, createdAt: 20, categoryID: work.id)
        let c = note("C", day: a.dayKey, createdAt: 30)
        for row in [a, b, c] { try store.add(row) }
        let before = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
        try executeRaw("CREATE TRIGGER reject_any_update BEFORE UPDATE ON notes BEGIN SELECT RAISE(ABORT, 'unexpected update'); END")
        func request(_ id: UUID, day: String = "2026-10-07", source: TaskGroupID = .general,
                     destination: TaskGroupID = .general, placement: TaskMovePlacement = .endOfGroup) -> TaskMoveRequest {
            TaskMoveRequest(taskID: id, expectedDayKey: day, expectedSourceGroup: source,
                            destinationGroup: destination, placement: placement)
        }
        XCTAssertEqual(try store.moveTask(request(a.id, placement: .before(c.id))), .unchanged)
        XCTAssertEqual(try store.moveTask(request(c.id)), .unchanged)
        XCTAssertEqual(try store.moveTask(request(UUID())), .rejected(.taskNotFound))
        XCTAssertEqual(try store.moveTask(request(a.id, day: "2026-10-06")), .rejected(.taskNotFound))
        XCTAssertEqual(try store.moveTask(request(a.id, source: .category(work.id))), .rejected(.sourceChanged))
        XCTAssertEqual(try store.moveTask(request(a.id, destination: .category(UUID()))), .rejected(.destinationNotFound))
        for anchor in [a.id, b.id, UUID()] {
            XCTAssertEqual(try store.moveTask(request(a.id, placement: .after(anchor))), .rejected(.invalidAnchor))
        }
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), before)
    }

    func testMoveSQLFailuresRollBackBothRankPassesAndCategoryThenRetry() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let work = try store.createCategory(name: "Work")
        let a = note("A", day: "2026-10-07", createdAt: 10)
        let b = note("B", day: a.dayKey, createdAt: 20)
        try store.add(a); try store.add(b)
        let request = TaskMoveRequest(taskID: b.id, expectedDayKey: a.dayKey,
            expectedSourceGroup: .general, destinationGroup: .category(work.id), placement: .endOfGroup)
        let before = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
        // Fail after an actual write in each phase, including category reassignment.
        for condition in ["NEW.display_order = -2", "OLD.display_order < 0 AND NEW.display_order = 1", "NEW.category_id IS NOT NULL"] {
            try executeRaw("CREATE TRIGGER reject_move AFTER UPDATE ON notes WHEN \(condition) BEGIN SELECT RAISE(FAIL, 'move failed'); END")
            XCTAssertThrowsError(try store.moveTask(request))
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), before)
            XCTAssertEqual(try SQLiteNoteRepository(databaseURL: databaseURL).notes(for: a.dayKey), [a, b])
            try executeRaw("DROP TRIGGER reject_move")
        }
        guard case let .changed(saved) = try store.moveTask(request) else { return XCTFail("Retry failed") }
        XCTAssertEqual(saved.map(\.id), [a.id, b.id])
        XCTAssertEqual(saved.last?.categoryID, work.id)
        XCTAssertEqual(try store.moveTask(TaskMoveRequest(taskID: b.id, expectedDayKey: a.dayKey,
            expectedSourceGroup: .category(work.id), destinationGroup: .category(work.id), placement: .endOfGroup)), .unchanged)
    }

    func testMoveCommitFailureRollsBackAndAllowsRetryOnSameConnection() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let a = note("A", day: "2026-10-07", createdAt: 10)
        let b = note("B", day: a.dayKey, createdAt: 20)
        try store.add(a); try store.add(b)
        let before = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
        var reader: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &reader), SQLITE_OK)
        let connection = try XCTUnwrap(reader)
        defer { sqlite3_close(connection) }
        // A rollback-journal reader allows BEGIN IMMEDIATE and writes, but blocks COMMIT.
        XCTAssertEqual(sqlite3_exec(connection, "BEGIN; SELECT * FROM notes", nil, nil, nil), SQLITE_OK)
        let request = TaskMoveRequest(taskID: b.id, expectedDayKey: a.dayKey,
            expectedSourceGroup: .general, destinationGroup: .general, placement: .before(a.id))
        XCTAssertThrowsError(try store.moveTask(request)) { error in
            guard case let SQLiteNoteStoreError.databaseError(operation, code, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(operation, "COMMIT")
            XCTAssertEqual(code, SQLITE_BUSY)
        }
        XCTAssertEqual(sqlite3_exec(connection, "ROLLBACK", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), before)
        XCTAssertEqual(try store.notes(for: a.dayKey), [a, b])
        XCTAssertEqual(try store.moveTask(request), .changed([b, a]))
        XCTAssertEqual(try SQLiteNoteRepository(databaseURL: databaseURL).notes(for: a.dayKey), [b, a])
    }

    func testAddAfterMoveAndExistingWritesPreserveRanks() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let work = try store.createCategory(name: "Work")
        let a = note("A", day: "2026-10-07", createdAt: 10)
        let b = note("B", day: a.dayKey, createdAt: 20)
        try store.add(a); try store.add(b)
        _ = try store.moveTask(TaskMoveRequest(taskID: b.id, expectedDayKey: a.dayKey,
            expectedSourceGroup: .general, destinationGroup: .general, placement: .before(a.id)))
        let c = note("C", day: a.dayKey, createdAt: 30)
        try store.add(c)
        XCTAssertEqual(try store.notes(for: a.dayKey).map(\.id), [b.id, a.id, c.id])
        let ranks = try rawRows("SELECT id, display_order FROM notes ORDER BY display_order")
        try store.update(id: a.id, text: "Edited", categoryID: work.id)
        try store.setCompleted(id: b.id, completedAt: Date(timeIntervalSince1970: 40))
        try store.removeCategory(id: work.id)
        XCTAssertEqual(try rawRows("SELECT id, display_order FROM notes ORDER BY display_order"), ranks)
        try store.delete(id: a.id)
        XCTAssertEqual(try rawRows("SELECT id, display_order FROM notes ORDER BY display_order"), [ranks[0], ranks[2]])
        XCTAssertEqual(try SQLiteNoteRepository(databaseURL: databaseURL).notes(for: a.dayKey).map(\.id), [b.id, c.id])
    }

    func testAppendCompactsExhaustedRanksWithoutChangingFieldsOrOtherDays() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let a = note("A", day: "2026-10-07", createdAt: 10)
        let b = note("B", day: a.dayKey, createdAt: 20)
        let old = note("Old", day: "2026-10-06", createdAt: 30)
        for row in [a, b, old] { try store.add(row) }
        try executeRaw("UPDATE notes SET display_order = 9223372036854775807 WHERE id = '\(a.id.uuidString)'")
        let before = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
        let c = note("C", day: a.dayKey, createdAt: 40)
        try executeRaw("CREATE TRIGGER reject_add AFTER INSERT ON notes BEGIN SELECT RAISE(FAIL, 'failed after compaction'); END")
        XCTAssertThrowsError(try store.add(c))
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), before)
        try executeRaw("DROP TRIGGER reject_add")
        try store.add(c)
        XCTAssertEqual(try store.notes(for: a.dayKey), [b, a, c])
        XCTAssertEqual(try rawRows("SELECT display_order FROM notes WHERE day_key = '2026-10-07' ORDER BY display_order"), [["0"], ["1"], ["2"]])
        XCTAssertEqual(try rawRows("SELECT rowid, id, text, day_key, created_at, completed_at, category_id FROM notes WHERE id != '\(c.id.uuidString)' ORDER BY rowid"), before.map { Array($0.dropLast()) })
        XCTAssertEqual(try SQLiteNoteRepository(databaseURL: databaseURL).notes(for: old.dayKey), [old])
    }

    func testRuntimeMalformedRanksFailReadsMovesAndAddsWithoutRepair() throws {
        for corruption in ["UPDATE notes SET display_order = -1", "PRAGMA ignore_check_constraints = ON; UPDATE notes SET display_order = 'bad'", "DROP INDEX notes_day_display_order_idx; UPDATE notes SET display_order = 0"] {
            let url = directory.appendingPathComponent("\(UUID().uuidString).sqlite")
            let store = try SQLiteNoteRepository(databaseURL: url)
            let a = note("A", day: "2026-10-07", createdAt: 10)
            let b = note("B", day: a.dayKey, createdAt: 20)
            try store.add(a); try store.add(b)
            var raw: OpaquePointer?
            XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
            let connection = try XCTUnwrap(raw)
            defer { sqlite3_close(connection) }
            // Negative corruption targets one row to avoid an unrelated unique collision.
            let sql = corruption == "UPDATE notes SET display_order = -1"
                ? "UPDATE notes SET display_order = -1 WHERE id = '\(a.id.uuidString)'" : corruption
            // Noninteger corruption also targets one row for the same reason.
            let targeted = sql.contains("'bad'") ? sql + " WHERE id = '\(a.id.uuidString)'" : sql
            XCTAssertEqual(sqlite3_exec(connection, targeted, nil, nil, nil), SQLITE_OK)
            let before = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid", at: url)
            XCTAssertThrowsError(try store.notes(for: a.dayKey))
            XCTAssertThrowsError(try store.moveTask(TaskMoveRequest(taskID: b.id, expectedDayKey: a.dayKey,
                expectedSourceGroup: .general, destinationGroup: .general, placement: .before(a.id))))
            XCTAssertThrowsError(try store.add(note("Unsaved", day: a.dayKey, createdAt: 30)))
            XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid", at: url), before)
            // Reopening must still reject the corrupt store; operations did not repair it.
            XCTAssertThrowsError(try SQLiteNoteRepository(databaseURL: url))
        }
    }

    func testMoveLaterToTodayPreservesFieldsAppendsToDailyRowsAndSurvivesReopen() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let work = try store.createCategory(name: "Work")
        let existing1 = note("First Today", day: "2026-10-05", createdAt: 10, categoryID: work.id)
        let existing2 = note("Second Today", day: "2026-10-05", createdAt: 20,
                             completedAt: Date(timeIntervalSince1970: 25))
        try store.add(existing1)
        try store.add(existing2)

        let source = later("Unscheduled task", createdAt: 5, categoryID: work.id)
        let otherLater = later("Stay in Later", createdAt: 30)
        try store.addLater(source)
        try store.addLater(otherLater)

        let moved = try store.moveLaterToToday(id: source.id, dayKey: "2026-10-05")
        XCTAssertEqual(moved.id, source.id)
        XCTAssertEqual(moved.text, source.text)
        XCTAssertEqual(moved.dayKey, "2026-10-05")
        XCTAssertEqual(moved.createdAt, source.createdAt)
        XCTAssertNil(moved.completedAt)
        XCTAssertEqual(moved.categoryID, work.id)

        XCTAssertEqual(try store.notes(for: "2026-10-05"), [existing1, existing2, moved])
        XCTAssertEqual(try store.incompleteCount(for: "2026-10-05"), 2)
        XCTAssertEqual(try store.laterTasks(), [otherLater])
        XCTAssertEqual(try rawRows("SELECT id FROM notes WHERE id = '\(source.id.uuidString)'"),
                       [[source.id.uuidString]])
        XCTAssertEqual(try rawRows("SELECT id FROM later_tasks WHERE id = '\(source.id.uuidString)'"), [])

        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.notes(for: "2026-10-05"), [existing1, existing2, moved])
        XCTAssertEqual(try reopened.incompleteCount(for: "2026-10-05"), 2)
        XCTAssertEqual(try reopened.laterTasks(), [otherLater])
    }

    func testMoveLaterToTodayRejectsMissingCompletedCollidingAndMissingCategoryTasks() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let work = try store.createCategory(name: "Work")

        let missingID = UUID()
        XCTAssertThrowsError(try store.moveLaterToToday(id: missingID, dayKey: "2026-10-05")) {
            XCTAssertEqual($0 as? LaterTaskRepositoryError, .notFound(missingID))
        }

        let done = later("Already finished", createdAt: 10, completedAt: Date(timeIntervalSince1970: 20))
        try store.addLater(done)
        XCTAssertThrowsError(try store.moveLaterToToday(id: done.id, dayKey: "2026-10-05")) {
            XCTAssertEqual($0 as? LaterTaskRepositoryError, .alreadyCompleted(done.id))
        }
        XCTAssertEqual(try store.laterTasks(), [done])
        XCTAssertEqual(try store.notes(for: "2026-10-05"), [])

        let valid = later("Move once", createdAt: 15)
        try store.addLater(valid)
        let moved = try store.moveLaterToToday(id: valid.id, dayKey: "2026-10-05")
        XCTAssertEqual(moved.id, valid.id)
        XCTAssertThrowsError(try store.moveLaterToToday(id: valid.id, dayKey: "2026-10-05")) {
            XCTAssertEqual($0 as? LaterTaskRepositoryError, .notFound(valid.id))
        }
        XCTAssertEqual(try store.notes(for: "2026-10-05"), [moved])

        let collisionID = UUID()
        let dailyNote = Note(id: collisionID, text: "Existing daily", dayKey: "2026-10-05",
                             createdAt: Date(timeIntervalSince1970: 1), completedAt: nil)
        try store.add(dailyNote)
        try executeRaw(
            """
            INSERT INTO later_tasks (id, text, created_at, completed_at, category_id)
            VALUES ('\(collisionID.uuidString)', 'Colliding later', 2, NULL, NULL);
            """
        )
        XCTAssertThrowsError(try store.moveLaterToToday(id: collisionID, dayKey: "2026-10-05")) {
            XCTAssertEqual($0 as? LaterTaskRepositoryError, .idCollision(collisionID))
        }
        XCTAssertEqual(try store.notes(for: "2026-10-05"), [moved, dailyNote])
        XCTAssertEqual(try store.laterTasks().map(\.id), [done.id, collisionID])

        let badCatID = UUID()
        let badTaskID = UUID()
        try executeRaw(
            """
            PRAGMA foreign_keys = OFF;
            INSERT INTO later_tasks (id, text, created_at, completed_at, category_id)
            VALUES ('\(badTaskID.uuidString)', 'Bad category', 3, NULL, '\(badCatID.uuidString)');
            """
        )
        XCTAssertThrowsError(try store.moveLaterToToday(id: badTaskID, dayKey: "2026-10-05")) {
            XCTAssertEqual($0 as? TaskCategoryRepositoryError, .notFound(badCatID))
        }
    }

    func testMoveLaterToTodayRollsBackOnInsertOrDeleteFailuresAndPreservesState() throws {
        let store = try SQLiteNoteRepository(databaseURL: databaseURL)
        let work = try store.createCategory(name: "Work")
        let today = note("Existing", day: "2026-10-05", createdAt: 10, categoryID: work.id)
        try store.add(today)
        let candidate = later("Candidate", createdAt: 20, categoryID: work.id)
        try store.addLater(candidate)
        let notesBefore = try rawRows("SELECT rowid, * FROM notes ORDER BY rowid")
        let laterBefore = try laterRows()

        try executeRaw(
            """
            CREATE TRIGGER reject_transfer_insert BEFORE INSERT ON notes
            BEGIN SELECT RAISE(FAIL, 'write rejected on transfer insert'); END;
            """
        )
        XCTAssertThrowsError(try store.moveLaterToToday(id: candidate.id, dayKey: "2026-10-05"))
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), notesBefore)
        XCTAssertEqual(try laterRows(), laterBefore)
        try executeRaw("DROP TRIGGER reject_transfer_insert")

        try executeRaw(
            """
            CREATE TRIGGER reject_transfer_delete BEFORE DELETE ON later_tasks
            BEGIN SELECT RAISE(FAIL, 'write rejected on transfer delete'); END;
            """
        )
        XCTAssertThrowsError(try store.moveLaterToToday(id: candidate.id, dayKey: "2026-10-05"))
        XCTAssertEqual(try rawRows("SELECT rowid, * FROM notes ORDER BY rowid"), notesBefore)
        XCTAssertEqual(try laterRows(), laterBefore)
        try executeRaw("DROP TRIGGER reject_transfer_delete")

        let savedNote = try store.moveLaterToToday(id: candidate.id, dayKey: "2026-10-05")
        XCTAssertEqual(savedNote.id, candidate.id)
        XCTAssertEqual(try store.notes(for: "2026-10-05"), [today, savedNote])
        XCTAssertEqual(try store.laterTasks(), [])

        let reopened = try SQLiteNoteRepository(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.notes(for: "2026-10-05"), [today, savedNote])
        XCTAssertEqual(try reopened.laterTasks(), [])
    }

    /// Schema v4 adds a second index that starts with day_key, and SQLite versions
    /// differ in which one they choose. Either keeps the read a bounded day_key search.
    private func usesDayKeyIndexSearch(_ plan: [[String?]]) -> Bool {
        plan.contains { row in
            guard let detail = row.last ?? nil else { return false }
            return ["notes_day_key_idx", "notes_day_display_order_idx"].contains {
                detail.contains("SEARCH notes USING INDEX \($0) (day_key")
            }
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

    private func rawRows(_ sql: String, at url: URL? = nil) throws -> [[String?]] {
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open((url ?? databaseURL).path, &connection), SQLITE_OK)
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
