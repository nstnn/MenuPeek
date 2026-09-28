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
                            createdAt: today.createdAt, completedAt: Date(timeIntervalSince1970: 100))
        let yesterday = note("Yesterday", dayKey: "2026-09-26", createdAt: 1)

        XCTAssertEqual(finished.dayKey, today.dayKey)
        XCTAssertEqual(finished.createdAt, today.createdAt)
        XCTAssertEqual(NoteProgress(notes: [finished, yesterday], for: "2026-09-27"),
                       NoteProgress(completed: 1, total: 1))
        XCTAssertEqual(NoteProgress(notes: [today, yesterday], for: "2026-09-27"),
                       NoteProgress(completed: 0, total: 1))
        XCTAssertEqual(yesterday.dayKey, "2026-09-26")
    }

    func testOrderGroupsCompletedBelowIncompleteAndUsesCreationTime() {
        let oldest = note("Old", dayKey: "2026-09-27", createdAt: 1)
        let newest = note("New", dayKey: "2026-09-27", createdAt: 3)
        let completed = Note(id: UUID(), text: "Done", dayKey: "2026-09-27",
                             createdAt: Date(timeIntervalSince1970: 4),
                             completedAt: Date(timeIntervalSince1970: 5))

        XCTAssertEqual(NoteOrder.sorted([completed, oldest, newest]).map(\.text),
                       ["New", "Old", "Done"])
        XCTAssertEqual(NoteProgress(notes: [completed, oldest, newest], for: "2026-09-27"),
                       NoteProgress(completed: 1, total: 3))
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
