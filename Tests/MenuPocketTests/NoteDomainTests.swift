import XCTest
@testable import MenuPocket

final class NoteDomainTests: XCTestCase {
    func testKeysEitherSideOfMidnightAndYearBoundary() {
        let zone = TimeZone(identifier: "America/Toronto")!
        let before = instant("2026-12-31T23:59:59-05:00")
        let after = instant("2027-01-01T00:00:01-05:00")
        var current = before
        let days = NoteDay(calendar: calendar(in: zone), now: { current })

        XCTAssertEqual(days.keys().today, "2026-12-31")
        XCTAssertEqual(days.keys().yesterday, "2026-12-30")
        current = after
        XCTAssertEqual(days.keys().today, "2027-01-01")
        XCTAssertEqual(days.keys().yesterday, "2026-12-31")
    }

    func testYesterdayUsesCalendarArithmeticAcrossDaylightSavingChanges() {
        let days = NoteDay(calendar: calendar(in: TimeZone(identifier: "America/Toronto")!))

        XCTAssertEqual(days.key(for: instant("2026-03-08T00:30:00-05:00")), "2026-03-08")
        XCTAssertEqual(days.key(for: instant("2026-03-08T23:30:00-04:00")), "2026-03-08")
        XCTAssertEqual(days.key(for: instant("2026-11-01T00:30:00-04:00")), "2026-11-01")
        XCTAssertEqual(days.key(for: instant("2026-11-01T23:30:00-05:00")), "2026-11-01")

        let spring = NoteDay(calendar: days.calendar,
                             now: { self.instant("2026-03-09T00:30:00-04:00") })
        XCTAssertEqual(spring.keys().yesterday, "2026-03-08")
        let fall = NoteDay(calendar: days.calendar,
                           now: { self.instant("2026-11-02T00:30:00-05:00") })
        XCTAssertEqual(fall.keys().yesterday, "2026-11-01")
    }

    func testDayKeyUsesInjectedTimeZone() {
        let point = instant("2026-09-27T00:30:00Z")
        XCTAssertEqual(NoteDay(calendar: calendar(in: TimeZone(secondsFromGMT: 0)!)).key(for: point),
                       "2026-09-27")
        XCTAssertEqual(NoteDay(calendar: calendar(in: TimeZone(identifier: "America/Toronto")!))
            .key(for: point), "2026-09-26")
    }

    func testLiveTimeZoneProviderAndFixedCalendarHaveSeparateContracts() {
        let point = instant("2026-09-27T00:30:00Z")
        var zone = TimeZone(identifier: "America/Toronto")!
        let live = NoteDay(now: { point }, timeZone: { zone })
        let fixed = NoteDay(calendar: calendar(in: zone), now: { point })
        XCTAssertEqual(live.keys().today, "2026-09-26")
        zone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(live.keys().today, "2026-09-27")
        XCTAssertEqual(live.keys().yesterday, "2026-09-26")
        XCTAssertEqual(fixed.keys().today, "2026-09-26")
    }

    func testCompletionKeepsAssignedDayAndProgressCountsTodayOnly() {
        let today = note("Today", dayKey: "2026-09-27", createdAt: 2)
        let finished = Note(id: today.id, text: today.text, dayKey: today.dayKey,
                            createdAt: today.createdAt, completedAt: Date(timeIntervalSince1970: 100),
                            categoryID: today.categoryID)
        let yesterday = note("Yesterday", dayKey: "2026-09-26", createdAt: 1)

        XCTAssertEqual(finished.dayKey, today.dayKey)
        XCTAssertEqual(finished.createdAt, today.createdAt)
        XCTAssertEqual(NoteProgress(notes: [finished, yesterday], for: "2026-09-27"),
                       NoteProgress(completed: 1, total: 1))
        XCTAssertEqual(NoteProgress(notes: [today, yesterday], for: "2026-09-27"),
                       NoteProgress(completed: 0, total: 1))
        XCTAssertEqual(yesterday.dayKey, "2026-09-26")
    }

    func testExistingTaskConstructionDefaultsToGeneralWithoutACategoryID() {
        let task = note("Existing task", dayKey: "2026-09-27", createdAt: 1)
        XCTAssertNil(task.categoryID)
        XCTAssertEqual(TaskCategoryName.general, "General")
        XCTAssertThrowsError(try TaskCategory(name: TaskCategoryName.general, creationOrder: 0)) {
            XCTAssertEqual($0 as? TaskCategoryNameError, .reserved)
        }
    }

    func testCategoryNameRulesTrimDisplaySpellingAndCompareCanonicalCaseFoldedKeys() throws {
        let work = try TaskCategory(name: "  Work\t", creationOrder: 0)
        let lower = try TaskCategory(name: "work", creationOrder: 1)
        XCTAssertEqual(work.name, "Work")
        XCTAssertEqual(work.nameKey, lower.nameKey)

        let composed = try TaskCategory(name: "CAFÉ", creationOrder: 2)
        let decomposed = try TaskCategory(name: "Cafe\u{301}", creationOrder: 3)
        let unaccented = try TaskCategory(name: "Cafe", creationOrder: 4)
        XCTAssertEqual(composed.nameKey, decomposed.nameKey)
        XCTAssertNotEqual(composed.nameKey, unaccented.nameKey)
        XCTAssertEqual(Array(decomposed.name.unicodeScalars), Array("Cafe\u{301}".unicodeScalars))
        XCTAssertEqual(TaskCategoryName.key(for: "Straße"), TaskCategoryName.key(for: "STRASSE"))
        XCTAssertEqual(TaskCategoryName.key(for: "I"), TaskCategoryName.key(for: "i"))
    }

    func testCategoryNamesRejectBlankMultilineAndReservedNames() {
        for input in ["", " \t ", "\n\r"] {
            XCTAssertThrowsError(try TaskCategory(name: input, creationOrder: 0)) {
                XCTAssertEqual($0 as? TaskCategoryNameError, .blank)
            }
        }
        for separator in ["\n", "\r", "\r\n", "\u{85}", "\u{2028}", "\u{2029}"] {
            for input in ["Work\(separator)Home", "\(separator)Work", "Work\(separator)"] {
                XCTAssertThrowsError(try TaskCategory(name: input, creationOrder: 0)) {
                    XCTAssertEqual($0 as? TaskCategoryNameError, .multiline)
                }
            }
        }
        for input in ["General", "general", " GENERAL ", "gEnErAl"] {
            XCTAssertThrowsError(try TaskCategory(name: input, creationOrder: 0)) {
                XCTAssertEqual($0 as? TaskCategoryNameError, .reserved)
            }
        }
    }

    func testCategoryRenameRetainsIdentityAndSavedOrderWithoutANameLengthLimit() throws {
        let original = try TaskCategory(name: "Work", creationOrder: 42)
        let longName = String(repeating: "Exercise ", count: 100).trimmingCharacters(in: .whitespaces)
        let renamed = try TaskCategory(id: original.id, name: longName,
                                       creationOrder: original.creationOrder)
        XCTAssertEqual(renamed.id, original.id)
        XCTAssertEqual(renamed.creationOrder, original.creationOrder)
        XCTAssertEqual(renamed.name, longName)
        XCTAssertNotEqual(renamed.nameKey, original.nameKey)
    }

    private func calendar(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private func instant(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func note(_ text: String, dayKey: String, createdAt: TimeInterval) -> Note {
        Note(id: UUID(), text: text, dayKey: dayKey,
             createdAt: Date(timeIntervalSince1970: createdAt), completedAt: nil)
    }
}
