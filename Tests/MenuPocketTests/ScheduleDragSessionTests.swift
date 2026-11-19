import XCTest
@testable import MenuPocket

/// Every path the Day/Week grid's create and resize drags take, checked on the
/// value the view draws its preview from and saves on release.
final class ScheduleDragSessionTests: XCTestCase {
    private let monday = try! GregorianDay(key: "2026-11-16")
    private let tuesday = try! GregorianDay(key: "2026-11-17")
    private var week: [GregorianDay] { [monday, tuesday] }
    /// One point per minute, like the app at 100%.
    private let metrics = ScheduleGridMetrics(hourHeight: 60)
    private let columnWidth: CGFloat = 100

    private func block(_ start: Int, _ end: Int, day: GregorianDay? = nil) throws -> ScheduleBlock {
        try ScheduleBlock(id: UUID(), title: "Focus", day: day ?? monday, startMinute: start, endMinute: end,
                          createdAt: Date(timeIntervalSince1970: 0))
    }

    private func create(from start: CGPoint, to end: CGPoint) -> ScheduleDragSession? {
        guard var session = ScheduleDragSession.create(at: start, columnWidth: columnWidth, days: week,
                                                       metrics: metrics) else { return nil }
        session.update(to: end)
        return session
    }

    // MARK: Create

    func testDrawingTenToElevenThirtyGivesThatSpan() throws {
        let session = try XCTUnwrap(create(from: CGPoint(x: 150, y: 603), to: CGPoint(x: 150, y: 689)))
        XCTAssertEqual(session.kind, .create(day: tuesday))
        let result = try XCTUnwrap(session.result(metrics: metrics))
        XCTAssertEqual(result, .create(day: tuesday, span: try XCTUnwrap(ScheduleTimeSpan(startMinute: 600,
                                                                                          endMinute: 690))))
        XCTAssertEqual(result.timeText, "10:00–11:30")
        // The editor opens with exactly those times and an empty title.
        guard case let .create(day, span) = result else { return XCTFail("not a create") }
        let request = ScheduleEditorRequest.drawn(day: day, span: span)
        XCTAssertEqual(request.origin, .slot(day: tuesday, startMinute: 600))
        XCTAssertTrue(request.draft.isNew)
        XCTAssertEqual(request.draft.title, "")
        XCTAssertEqual(request.draft.day, tuesday)
        XCTAssertEqual(request.draft.startMinute, 600)
        XCTAssertEqual(request.draft.endMinute, 690)
        XCTAssertEqual(request.draft.validated(), .failure(.blankTitle))
    }

    func testDrawingUpwardsGivesTheSameSpan() throws {
        let down = try XCTUnwrap(create(from: CGPoint(x: 10, y: 600), to: CGPoint(x: 10, y: 690)))
        let up = try XCTUnwrap(create(from: CGPoint(x: 10, y: 690), to: CGPoint(x: 10, y: 600)))
        XCTAssertEqual(down.result(metrics: metrics), up.result(metrics: metrics))
    }

    func testDrawnBlockStaysInTheStartingColumn() throws {
        let session = try XCTUnwrap(create(from: CGPoint(x: 20, y: 600), to: CGPoint(x: 180, y: 660)))
        XCTAssertEqual(session.result(metrics: metrics)?.day, monday)
    }

    func testDrawingPastTheDayClampsToMidnight() throws {
        let below = try XCTUnwrap(create(from: CGPoint(x: 10, y: 1380), to: CGPoint(x: 10, y: 1700)))
        XCTAssertEqual(below.result(metrics: metrics)?.startMinute, 1380)
        XCTAssertEqual(below.result(metrics: metrics)?.endMinute, 1440)
        let above = try XCTUnwrap(create(from: CGPoint(x: 10, y: 60), to: CGPoint(x: 10, y: -200)))
        XCTAssertEqual(above.result(metrics: metrics)?.startMinute, 0)
        XCTAssertEqual(above.result(metrics: metrics)?.endMinute, 60)
    }

    func testShortDrawGrowsToFifteenMinutes() throws {
        let session = try XCTUnwrap(create(from: CGPoint(x: 10, y: 600), to: CGPoint(x: 10, y: 605)))
        XCTAssertEqual(session.result(metrics: metrics)?.startMinute, 600)
        XCTAssertEqual(session.result(metrics: metrics)?.endMinute, 615)
        let atMidnight = try XCTUnwrap(create(from: CGPoint(x: 10, y: 1436), to: CGPoint(x: 10, y: 1439)))
        XCTAssertNil(atMidnight.result(metrics: metrics), "3 pt is still a click")
        let lastSlot = try XCTUnwrap(create(from: CGPoint(x: 10, y: 1433), to: CGPoint(x: 10, y: 1439)))
        XCTAssertEqual(lastSlot.result(metrics: metrics)?.startMinute, 1425)
        XCTAssertEqual(lastSlot.result(metrics: metrics)?.endMinute, 1440)
    }

    func testDrawUsesTheZoomedScale() throws {
        let zoomed = ScheduleGridMetrics(hourHeight: 90)
        var session = try XCTUnwrap(ScheduleDragSession.create(at: CGPoint(x: 10, y: 900), columnWidth: columnWidth,
                                                               days: week, metrics: zoomed))
        session.update(to: CGPoint(x: 10, y: 1035))
        XCTAssertEqual(session.result(metrics: zoomed)?.startMinute, 600)
        XCTAssertEqual(session.result(metrics: zoomed)?.endMinute, 690)
    }

    func testCreateIsRefusedOutsideTheDayOrWithoutColumns() {
        XCTAssertNil(ScheduleDragSession.create(at: CGPoint(x: 10, y: -1), columnWidth: columnWidth, days: week,
                                                metrics: metrics))
        XCTAssertNil(ScheduleDragSession.create(at: CGPoint(x: 10, y: 1440), columnWidth: columnWidth, days: week,
                                                metrics: metrics))
        XCTAssertNil(ScheduleDragSession.create(at: CGPoint(x: 10, y: 10), columnWidth: columnWidth, days: [],
                                                metrics: metrics))
        XCTAssertNil(ScheduleDragSession.create(at: CGPoint(x: 10, y: CGFloat.nan), columnWidth: columnWidth, days: week,
                                                metrics: metrics))
    }

    // MARK: Click versus drag

    func testMovementUnderTheMinimumIsAClick() throws {
        var session = try XCTUnwrap(ScheduleDragSession.create(at: CGPoint(x: 10, y: 600), columnWidth: columnWidth,
                                                               days: week, metrics: metrics))
        XCTAssertFalse(session.isDragging)
        XCTAssertNil(session.result(metrics: metrics))
        session.update(to: CGPoint(x: 12, y: 602))
        XCTAssertFalse(session.isDragging, "2.8 pt is a click")
        XCTAssertNil(session.result(metrics: metrics))
        // The click still lands on the slot under the mouse-down point.
        let slot = ScheduleSlotHitTest.slot(at: session.anchor, columnWidth: columnWidth, days: week,
                                            metrics: metrics)
        XCTAssertEqual(slot?.day, monday)
        XCTAssertEqual(slot?.startMinute, 600)
        session.update(to: CGPoint(x: 10, y: 604))
        XCTAssertTrue(session.isDragging)
        // Coming back to the anchor keeps it a drag (a 15-minute block).
        session.update(to: CGPoint(x: 10, y: 600))
        XCTAssertTrue(session.isDragging)
        XCTAssertEqual(session.result(metrics: metrics)?.endMinute, 615)
    }

    func testNonFinitePointsAreIgnored() throws {
        var session = try XCTUnwrap(create(from: CGPoint(x: 10, y: 600), to: CGPoint(x: 10, y: 660)))
        session.update(to: CGPoint(x: CGFloat.nan, y: 700))
        XCTAssertEqual(session.current, CGPoint(x: 10, y: 660))
        XCTAssertNil(ScheduleDragSession.resize(try block(600, 660), at: CGPoint(x: 0, y: CGFloat.infinity)))
    }

    // MARK: Resize

    private func resize(_ block: ScheduleBlock, grabbedAt y: CGFloat, to end: CGFloat) throws -> ScheduleDragResult? {
        var session = try XCTUnwrap(ScheduleDragSession.resize(block, at: CGPoint(x: 30, y: y)))
        XCTAssertEqual(session.resizingBlockID, block.id)
        session.update(to: CGPoint(x: 30, y: end))
        return session.result(metrics: metrics)
    }

    func testResizingElevenToTwelveFifteen() throws {
        let saved = try block(600, 660)
        let result = try XCTUnwrap(try resize(saved, grabbedAt: 658, to: 733))
        guard case let .resize(original, content) = result else { return XCTFail("not a resize") }
        XCTAssertEqual(original, saved)
        XCTAssertEqual(content.title, "Focus")
        XCTAssertEqual(content.day, monday)
        XCTAssertEqual(content.startMinute, 600)
        XCTAssertEqual(content.endMinute, 735)
        XCTAssertEqual(result.timeText, "10:00–12:15")
        XCTAssertTrue(result.changesSavedBlock)
    }

    func testResizeFollowsPointerTravelNotItsPosition() throws {
        // Grabbed 4 pt above the edge: moving 20 pt adds 20 minutes, it does not jump.
        let result = try resize(try block(600, 660), grabbedAt: 656, to: 676)
        XCTAssertEqual(result?.endMinute, 675)
    }

    func testResizeAboveTheStartLeavesFifteenMinutes() throws {
        let result = try resize(try block(600, 660), grabbedAt: 660, to: 400)
        XCTAssertEqual(result?.startMinute, 600)
        XCTAssertEqual(result?.endMinute, 615)
    }

    func testResizeStopsAtMidnight() throws {
        let result = try resize(try block(1380, 1410), grabbedAt: 1410, to: 1900)
        XCTAssertEqual(result?.endMinute, 1440)
    }

    func testResizeBackToTheSavedEndChangesNothing() throws {
        let result = try XCTUnwrap(try resize(try block(600, 660), grabbedAt: 660, to: 666))
        XCTAssertEqual(result.endMinute, 660)
        XCTAssertFalse(result.changesSavedBlock)
    }

    func testResizeUnderTheMinimumIsAClick() throws {
        XCTAssertNil(try resize(try block(600, 660), grabbedAt: 660, to: 662))
    }

    func testCreateIsNotAResize() throws {
        let session = try XCTUnwrap(create(from: CGPoint(x: 10, y: 600), to: CGPoint(x: 10, y: 660)))
        XCTAssertNil(session.resizingBlockID)
        XCTAssertTrue(try XCTUnwrap(session.result(metrics: metrics)).changesSavedBlock)
    }

    // MARK: Auto-scroll

    func testAutoScrollOnlyNearOrPastTheEdges() {
        XCTAssertEqual(ScheduleDragAutoScroll.step(pointerY: 200, viewportHeight: 400), 0)
        XCTAssertEqual(ScheduleDragAutoScroll.step(pointerY: 40, viewportHeight: 400), 0)
        XCTAssertEqual(ScheduleDragAutoScroll.step(pointerY: 20, viewportHeight: 400), -6, accuracy: 0.001)
        XCTAssertEqual(ScheduleDragAutoScroll.step(pointerY: 0, viewportHeight: 400), -12)
        XCTAssertEqual(ScheduleDragAutoScroll.step(pointerY: -80, viewportHeight: 400), -12)
        XCTAssertEqual(ScheduleDragAutoScroll.step(pointerY: 380, viewportHeight: 400), 6, accuracy: 0.001)
        XCTAssertEqual(ScheduleDragAutoScroll.step(pointerY: 900, viewportHeight: 400), 12)
        // A short viewport splits into two bands with no dead zone wider than zero.
        XCTAssertEqual(ScheduleDragAutoScroll.step(pointerY: 30, viewportHeight: 60), 0)
        XCTAssertLessThan(ScheduleDragAutoScroll.step(pointerY: 10, viewportHeight: 60), 0)
        XCTAssertEqual(ScheduleDragAutoScroll.step(pointerY: 10, viewportHeight: 0), 0)
        XCTAssertEqual(ScheduleDragAutoScroll.step(pointerY: CGFloat.nan, viewportHeight: 400), 0)
    }
}

/// A save that fails after a resize leaves the published block as it was, so
/// the grid draws its previous size, and the state reports the message shown.
@MainActor
final class ScheduleResizeSaveTests: XCTestCase {
    func testResizeSaveAndFailedSave() throws {
        let monday = try GregorianDay(key: "2026-11-16")
        let repository = InMemoryScheduleRepository()
        let saved = try ScheduleBlock(id: UUID(), title: "Focus", day: monday, startMinute: 600, endMinute: 660,
                                      createdAt: Date(timeIntervalSince1970: 0))
        repository.blocks = [saved]
        let state = try ScheduleState(noteDay: ScheduleDragTestClock.noteDay, repository: { repository })
        state.setVisible(true)
        XCTAssertTrue(state.showDay(monday))
        XCTAssertEqual(state.blocks, [saved])

        var session = try XCTUnwrap(ScheduleDragSession.resize(saved, at: CGPoint(x: 0, y: 660)))
        session.update(to: CGPoint(x: 0, y: 735))
        guard case let .resize(_, content) = try XCTUnwrap(session.result(metrics: ScheduleTimeGridSize.metrics))
        else { return XCTFail("not a resize") }
        XCTAssertEqual(try state.update(id: saved.id, to: content).get().endMinute, 735)
        XCTAssertEqual(state.blocks?.first?.endMinute, 735)
        XCTAssertEqual(repository.blocks.first?.endMinute, 735)

        repository.failWrites = true
        let shorter = try ScheduleBlockContent(title: "Focus", day: monday, startMinute: 600, endMinute: 615)
        XCTAssertEqual(state.update(id: saved.id, to: shorter).failureValue, .update)
        XCTAssertEqual(ScheduleCommandFailure.update.message, "Could not save block changes. Try again.")
        XCTAssertEqual(state.blocks?.first?.endMinute, 735, "the block keeps its saved size")
        XCTAssertEqual(repository.blocks.first?.endMinute, 735)
    }
}

private extension Result {
    var failureValue: Failure? {
        if case let .failure(failure) = self { failure } else { nil }
    }
}

private enum ScheduleDragTestClock {
    static var noteDay: NoteDay {
        NoteDay(now: { ISO8601DateFormatter().date(from: "2026-11-18T12:00:00Z")! },
                timeZone: { TimeZone(secondsFromGMT: 0)! })
    }
}

/// Saved blocks in memory; `failWrites` makes every write throw.
private final class InMemoryScheduleRepository: ScheduleRepository {
    private enum Failure: Error { case storage }
    var blocks: [ScheduleBlock] = []
    var failWrites = false

    func scheduleBlocks(in range: HistoryDayRange) throws -> [ScheduleBlock] {
        blocks.filter { range.contains($0.day) }.sorted(by: ScheduleBlock.isOrderedBefore)
    }

    func addScheduleBlock(_ block: ScheduleBlock) throws {
        if failWrites { throw Failure.storage }
        blocks.append(block)
    }

    func updateScheduleBlock(id: UUID, to content: ScheduleBlockContent) throws -> ScheduleBlock {
        if failWrites { throw Failure.storage }
        guard let index = blocks.firstIndex(where: { $0.id == id }) else {
            throw ScheduleRepositoryError.notFound(id)
        }
        blocks[index] = blocks[index].replacingContent(content)
        return blocks[index]
    }

    func deleteScheduleBlock(id: UUID) throws {
        if failWrites { throw Failure.storage }
        blocks.removeAll { $0.id == id }
    }
}
