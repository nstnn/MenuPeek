import Foundation
import XCTest
@testable import MenuPocket

final class ScheduleBlockDraftTests: XCTestCase {
    private func day(_ key: String) throws -> GregorianDay { try GregorianDay(key: key) }

    /// Monday 16 ... Sunday 22 November 2026.
    private func week() throws -> [GregorianDay] {
        try SchedulePeriod(mode: .week, anchor: day("2026-11-18")).days
    }

    private func now(_ key: String, _ minute: Double) throws -> ScheduleCurrentTime {
        ScheduleCurrentTime(day: try day(key), minute: minute)
    }

    // MARK: Prefill

    func testSlotPrefillStartsAtTheClickedSlotAndLastsOneHour() throws {
        let draft = ScheduleBlockDraft(newOn: try day("2026-11-19"), startMinute: 10 * 60 + 20)
        XCTAssertTrue(draft.isNew)
        XCTAssertNil(draft.blockID)
        XCTAssertEqual(draft.title, "")
        XCTAssertEqual(draft.day, try day("2026-11-19"))
        XCTAssertEqual(draft.startMinute, 615, "10:20 is in the 10:15 slot")
        XCTAssertEqual(draft.endMinute, 675)
        XCTAssertEqual(draft.durationText, "1 h")

        let request = ScheduleEditorRequest.slot(day: try day("2026-11-19"), startMinute: 622)
        XCTAssertEqual(request.origin, .slot(day: try day("2026-11-19"), startMinute: 615))
        XCTAssertEqual(request.draft.startMinute, 615)
        XCTAssertTrue(request.origin.isOnGrid)
    }

    func testSlotPrefillNearMidnightEndsAt2400() throws {
        let late = ScheduleBlockDraft(newOn: try day("2026-11-19"), startMinute: 23 * 60 + 30)
        XCTAssertEqual(late.startMinute, 1410)
        XCTAssertEqual(late.endMinute, 1440)
        XCTAssertEqual(late.endText, "24:00")
        XCTAssertEqual(late.durationText, "30 min")

        let past = ScheduleBlockDraft(newOn: try day("2026-11-19"), startMinute: 1440)
        XCTAssertEqual(past.startMinute, 1425, "the last slot starts at 23:45")
        XCTAssertEqual(past.endMinute, 1440)
        let before = ScheduleBlockDraft(newOn: try day("2026-11-19"), startMinute: -30)
        XCTAssertEqual(before.startMinute, 0)
        XCTAssertEqual(before.endMinute, 60)
    }

    func testNewBlockButtonPrefillsTodayAtTheNextWholeHour() throws {
        let draft = try XCTUnwrap(ScheduleBlockDraft.newBlock(
            days: week(), today: day("2026-11-18"), selectedDay: day("2026-11-20"),
            now: now("2026-11-18", 10 * 60 + 20.5)))
        XCTAssertEqual(draft.day, try day("2026-11-18"), "today wins over the selected day")
        XCTAssertEqual(draft.startText, "11:00")
        XCTAssertEqual(draft.endText, "12:00")

        let onTheHour = try XCTUnwrap(ScheduleBlockDraft.newBlock(
            days: week(), today: day("2026-11-18"), selectedDay: nil, now: now("2026-11-18", 600)))
        XCTAssertEqual(onTheHour.startText, "11:00")

        let late = try XCTUnwrap(ScheduleBlockDraft.newBlock(
            days: week(), today: day("2026-11-18"), selectedDay: nil, now: now("2026-11-18", 23 * 60 + 10)))
        XCTAssertEqual(late.startText, "23:00", "never later than one hour before midnight")
        XCTAssertEqual(late.endText, "24:00")
    }

    func testNewBlockButtonUsesSelectedThenFirstVisibleDayAt0900() throws {
        let nextWeek = try SchedulePeriod(mode: .week, anchor: day("2026-11-25")).days
        let selected = try XCTUnwrap(ScheduleBlockDraft.newBlock(
            days: nextWeek, today: day("2026-11-18"), selectedDay: day("2026-11-26"),
            now: now("2026-11-18", 600)))
        XCTAssertEqual(selected.day, try day("2026-11-26"))
        XCTAssertEqual(selected.startText, "09:00")
        XCTAssertEqual(selected.endText, "10:00")

        let first = try XCTUnwrap(ScheduleBlockDraft.newBlock(
            days: nextWeek, today: day("2026-11-18"), selectedDay: day("2026-11-18"), now: nil))
        XCTAssertEqual(first.day, try day("2026-11-23"), "a selected day outside the period is ignored")
        XCTAssertEqual(first.startText, "09:00")

        XCTAssertNil(ScheduleBlockDraft.newBlock(days: [], today: try day("2026-11-18"), selectedDay: nil, now: nil))
    }

    func testEditPrefillCopiesTheSavedBlock() throws {
        let block = try ScheduleBlock(id: UUID(), title: "Design review", day: day("2026-11-18"),
                                      startMinute: 600, endMinute: 690, createdAt: Date())
        let request = ScheduleEditorRequest.edit(block)
        XCTAssertEqual(request.origin, .block(block.id))
        XCTAssertEqual(request.draft.blockID, block.id)
        XCTAssertFalse(request.draft.isNew)
        XCTAssertEqual(request.draft.title, "Design review")
        XCTAssertEqual(request.draft.durationText, "1 h 30 min")
        XCTAssertEqual(request.draft.validated(), .success(block.content))
        XCTAssertNotEqual(ScheduleEditorRequest.edit(block).id, request.id, "each opening is a new request")
    }

    // MARK: Times

    func testOptionsCoverEveryValidSlot() {
        XCTAssertEqual(ScheduleBlockDraft.startOptions.count, 96)
        XCTAssertEqual(ScheduleBlockDraft.startOptions.first, 0)
        XCTAssertEqual(ScheduleBlockDraft.startOptions.last, 1425)
        XCTAssertEqual(ScheduleBlockDraft.endOptions.count, 96)
        XCTAssertEqual(ScheduleBlockDraft.endOptions.first, 15)
        XCTAssertEqual(ScheduleBlockDraft.endOptions.last, 1440)
        XCTAssertTrue((ScheduleBlockDraft.startOptions + ScheduleBlockDraft.endOptions).allSatisfy { $0 % 15 == 0 })
    }

    func testEndFollowsStartKeepingTheDuration() throws {
        var draft = ScheduleBlockDraft(newOn: try day("2026-11-18"), startMinute: 600)
        draft.setEnd(690)
        XCTAssertEqual(draft.durationMinutes, 90)

        draft.setStart(780)
        XCTAssertEqual(draft.startText, "13:00")
        XCTAssertEqual(draft.endText, "14:30")

        draft.setStart(1380)
        XCTAssertEqual(draft.startText, "23:00")
        XCTAssertEqual(draft.endText, "24:00", "the end stops at midnight")

        draft.setStart(1425)
        XCTAssertEqual(draft.endMinute, 1440)
        XCTAssertEqual(draft.durationMinutes, 15)

        draft.setStart(487)
        XCTAssertEqual(draft.startMinute, 480, "off-grid input snaps to its slot")
        XCTAssertEqual(draft.endMinute, 495)
    }

    func testEndAtOrBeforeStartMovesStartEarlier() throws {
        var draft = ScheduleBlockDraft(newOn: try day("2026-11-18"), startMinute: 600)
        draft.title = "Block"
        draft.setEnd(600)
        XCTAssertEqual(draft.startText, "09:00")
        XCTAssertEqual(draft.endText, "10:00")

        draft.setEnd(540)
        XCTAssertEqual(draft.startText, "08:00")
        XCTAssertEqual(draft.endText, "09:00")

        draft.setEnd(30)
        XCTAssertEqual(draft.startMinute, 0, "the start stops at midnight")
        XCTAssertEqual(draft.endMinute, 30)

        draft.setEnd(0)
        XCTAssertEqual(draft.endMinute, 15, "the end is at least 00:15")
        XCTAssertEqual(draft.startMinute, 0)

        draft.setEnd(2000)
        XCTAssertEqual(draft.endMinute, 1440)
        draft.setEnd(52)
        XCTAssertEqual(draft.endMinute, 45, "off-grid input snaps to the nearest line")
        XCTAssertEqual(draft.validated().map(\.durationMinutes), .success(45))
    }

    func testDayMovesKeepTimesAndStopAtTheStorableYears() throws {
        var draft = ScheduleBlockDraft(newOn: try day("2026-11-30"), startMinute: 600)
        XCTAssertTrue(draft.moveDay(by: 1))
        XCTAssertEqual(draft.day, try day("2026-12-01"))
        XCTAssertEqual(draft.dayText, "Tuesday, December 1, 2026")
        XCTAssertTrue(draft.moveDay(by: -2))
        XCTAssertEqual(draft.day, try day("2026-11-29"))
        XCTAssertEqual(draft.startText, "10:00")

        var last = ScheduleBlockDraft(newOn: try day("9999-12-31"), startMinute: 600)
        XCTAssertFalse(last.moveDay(by: 1))
        XCTAssertEqual(last.day, try day("9999-12-31"))
    }

    // MARK: Validation

    func testBlankAndMultilineTitlesAreRefusedWithMessages() throws {
        var draft = ScheduleBlockDraft(newOn: try day("2026-11-18"), startMinute: 600)
        XCTAssertEqual(draft.validated(), .failure(.blankTitle))
        draft.title = "  \n "
        XCTAssertEqual(draft.validated(), .failure(.blankTitle))
        XCTAssertEqual(ScheduleBlockDraftIssue.blankTitle.message, "Enter a title for the block.")
        draft.title = "One\nTwo"
        XCTAssertEqual(draft.validated(), .failure(.multilineTitle))
        XCTAssertEqual(ScheduleBlockDraftIssue.multilineTitle.message, "Use a title on one line.")
        XCTAssertEqual(ScheduleBlockDraftIssue.invalidRange.message, "End time must be after start time.")

        draft.title = "  Focus  "
        let content = try draft.validated().get()
        XCTAssertEqual(content.title, "Focus")
        XCTAssertEqual(content.day, try day("2026-11-18"))
        XCTAssertEqual(content.startMinute, 600)
        XCTAssertEqual(content.endMinute, 660)
    }

    func testEveryReachableDraftIsAValidRange() throws {
        // Any sequence of start and end choices leaves a savable range.
        var draft = ScheduleBlockDraft(newOn: try day("2026-11-18"), startMinute: 0)
        draft.title = "Block"
        for (index, minute) in stride(from: -30, through: 1470, by: 7).enumerated() {
            if index.isMultiple(of: 2) { draft.setStart(minute) } else { draft.setEnd(minute) }
            XCTAssertNoThrow(try draft.validated().get(), "after \(minute)")
        }
    }

    func testDurationText() {
        XCTAssertEqual(ScheduleBlockDraft.durationText(minutes: 15), "15 min")
        XCTAssertEqual(ScheduleBlockDraft.durationText(minutes: 60), "1 h")
        XCTAssertEqual(ScheduleBlockDraft.durationText(minutes: 135), "2 h 15 min")
        XCTAssertEqual(ScheduleBlockDraft.durationText(minutes: 1440), "24 h")
    }

    // MARK: Slot hit-testing and focus return

    func testSlotHitTestFindsTheDayAndSlotUnderTheClick() throws {
        let metrics = ScheduleTimeGridSize.metrics
        let days = try week()
        let slot = try XCTUnwrap(ScheduleSlotHitTest.slot(at: CGPoint(x: 2 * 80 + 10, y: 622.5),
                                                          columnWidth: 80, days: days, metrics: metrics))
        XCTAssertEqual(slot.day, try day("2026-11-18"))
        XCTAssertEqual(slot.startMinute, 615)

        let edge = try XCTUnwrap(ScheduleSlotHitTest.slot(at: CGPoint(x: 7 * 80 + 5, y: 1439),
                                                          columnWidth: 80, days: days, metrics: metrics))
        XCTAssertEqual(edge.day, try day("2026-11-22"), "past the last column stays on Sunday")
        XCTAssertEqual(edge.startMinute, 1425)

        XCTAssertNil(ScheduleSlotHitTest.slot(at: CGPoint(x: 10, y: -1), columnWidth: 80, days: days, metrics: metrics))
        XCTAssertNil(ScheduleSlotHitTest.slot(at: CGPoint(x: 10, y: 1440), columnWidth: 80, days: days, metrics: metrics))
        XCTAssertNil(ScheduleSlotHitTest.slot(at: CGPoint(x: 10, y: 10), columnWidth: 80, days: [], metrics: metrics))
    }

    func testFocusReturnsToTheOpener() throws {
        let id = UUID()
        let saved = UUID()
        let slot = ScheduleEditorOrigin.slot(day: try day("2026-11-18"), startMinute: 600)
        XCTAssertEqual(ScheduleFocusTarget.afterEditor(.newBlockButton, .cancelled), .newBlock)
        XCTAssertEqual(ScheduleFocusTarget.afterEditor(.newBlockButton, .saved(saved)), .newBlock)
        XCTAssertEqual(ScheduleFocusTarget.afterEditor(.block(id), .cancelled), .block(id))
        XCTAssertEqual(ScheduleFocusTarget.afterEditor(.block(id), .saved(id)), .block(id))
        XCTAssertEqual(ScheduleFocusTarget.afterEditor(.block(id), .deleted), .newBlock)
        XCTAssertEqual(ScheduleFocusTarget.afterEditor(slot, .saved(saved)), .block(saved))
        XCTAssertNil(ScheduleFocusTarget.afterEditor(slot, .cancelled))
        XCTAssertFalse(ScheduleEditorOrigin.newBlockButton.isOnGrid)
        XCTAssertTrue(ScheduleEditorOrigin.block(id).isOnGrid)
    }
}
