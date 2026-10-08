import AppKit
import Observation
import SQLite3
import XCTest
@testable import MenuPocket

@MainActor
final class DailyNotesStateTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Toronto")!

    func testDragScrollBoundsCancellationAndSourceUnmount() throws {
        let a = note("A", day: "2026-09-27", createdAt: 1)
        let state = makeState(store: FakeNoteRepository(notes: [a]),
                              now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 2000))
        scroll.documentView = document
        let source = TaskDragHandleView(frame: NSRect(x: 0, y: 0, width: 16, height: 24))
        document.addSubview(source)
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.orderFront(nil)
        let session = state.taskWindowPresentation.dragSession
        let payload = try XCTUnwrap(session.begin(taskID: a.id, state: state, source: source))
        defer { session.ended(token: payload.token); window.close() }
        // Lazy source removal must not invalidate a native drag still in flight.
        source.removeFromSuperview()
        XCTAssertEqual(session.active, payload)
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: 800))
        let pointer = window.convertPoint(toScreen: clip.convert(
            NSPoint(x: clip.bounds.midX, y: clip.bounds.minY + 1), to: nil))
        let before = clip.bounds.origin.y
        session.scrollAtPointer(screenPoint: pointer)
        XCTAssertNotEqual(clip.bounds.origin.y, before)
        XCTAssertLessThanOrEqual(abs(clip.bounds.origin.y - before), 12)
        session.cancel()
        let cancelled = clip.bounds.origin
        session.scrollAtPointer(screenPoint: pointer)
        XCTAssertEqual(clip.bounds.origin, cancelled)
        XCTAssertNil(session.active)
        XCTAssertTrue(session.isDragging, "Reservation lasts until native end")
        XCTAssertNil(session.begin(taskID: a.id, state: state, source: source))
        session.ended(token: payload.token)
        XCTAssertFalse(session.isDragging)
    }

    func testDragEdgeScrollingIsBoundedAndIgnoresOutsideAndCenter() {
        let viewport = NSRect(x: 0, y: 0, width: 300, height: 200)
        XCTAssertEqual(TaskDragSession.edgeStep(point: NSPoint(x: 50, y: 0), viewport: viewport), -12)
        XCTAssertEqual(TaskDragSession.edgeStep(point: NSPoint(x: 50, y: 20), viewport: viewport), -6)
        XCTAssertEqual(TaskDragSession.edgeStep(point: NSPoint(x: 50, y: 180), viewport: viewport), 6)
        for point in [NSPoint(x: 50, y: 100), NSPoint(x: -1, y: 180), NSPoint(x: 50, y: 201)] {
            XCTAssertEqual(TaskDragSession.edgeStep(point: point, viewport: viewport), 0)
        }
    }

    func testDragSessionBeginMintsOneReservedTokenForEligibleTodayTask() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let a = Note(id: UUID(), text: "A", dayKey: "2026-09-27", createdAt: Date(timeIntervalSince1970: 1),
                     completedAt: nil, categoryID: work.id)
        let b = note("B", day: a.dayKey, createdAt: 2)
        let old = note("Old", day: "2026-09-26", createdAt: 3)
        let state = makeState(store: FakeNoteRepository(notes: [a, b, old], categories: [work]),
                              now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let session = state.taskWindowPresentation.dragSession
        let source = TaskDragHandleView(frame: .zero)
        XCTAssertNil(session.begin(taskID: UUID(), state: state, source: source))
        XCTAssertNil(session.begin(taskID: old.id, state: state, source: source))
        XCTAssertFalse(session.isDragging)

        let first = try XCTUnwrap(session.begin(taskID: a.id, state: state, source: source))
        XCTAssertEqual(first.taskID, a.id)
        XCTAssertEqual(first.dayKey, a.dayKey)
        XCTAssertEqual(first.sourceGroup, .category(work.id))
        XCTAssertEqual(session.active, first)
        XCTAssertTrue(session.isDragging)
        XCTAssertNil(session.begin(taskID: b.id, state: state, source: TaskDragHandleView(frame: .zero)),
                     "Only one native session may be reserved")
        session.ended(token: UUID())
        XCTAssertEqual(session.active, first, "A foreign session end must not release the reservation")
        XCTAssertTrue(session.isDragging)
        session.ended(token: first.token)
        XCTAssertNil(session.active)
        XCTAssertFalse(session.isDragging)

        let second = try XCTUnwrap(session.begin(taskID: b.id, state: state, source: source))
        defer { session.ended(token: second.token) }
        XCTAssertEqual(second.sourceGroup, .general)
        XCTAssertNotEqual(second.token, first.token)
    }

    func testDragSessionBeginIsRefusedBehindEveryMovementGuard() throws {
        let a = note("A", day: "2026-09-27", createdAt: 1)
        let guards: [(String, (DailyNotesState) -> Void)] = [
            ("inline edit", { $0.beginEditing(id: a.id) }),
            ("deletion confirmation", { $0.taskWindowPresentation.requestDeletion(id: a.id, state: $0) }),
            ("category manager", { XCTAssertTrue($0.taskWindowPresentation.showCategoryManager(state: $0)) }),
            ("termination", { $0.stopForTermination() })
        ]
        for (name, apply) in guards {
            let state = makeState(store: FakeNoteRepository(notes: [a]),
                                  now: { self.instant("2026-09-27T12:00:00-04:00") })
            state.startup()
            apply(state)
            let session = state.taskWindowPresentation.dragSession
            XCTAssertNil(session.begin(taskID: a.id, state: state, source: TaskDragHandleView(frame: .zero)), name)
            XCTAssertFalse(session.isDragging, name)
            XCTAssertNil(session.active, name)
        }
        let store = FakeNoteRepository(notes: [a])
        store.failSnapshotRead = .notes
        let unavailable = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        unavailable.startup()
        XCTAssertNil(unavailable.taskWindowPresentation.dragSession.begin(
            taskID: a.id, state: unavailable, source: TaskDragHandleView(frame: .zero)), "unavailable read")
    }

    func testDragPayloadValidationAcceptsOnlyLiveLocalSourceAndPrivateToken() throws {
        let a = note("A", day: "2026-09-27", createdAt: 1)
        let state = makeState(store: FakeNoteRepository(notes: [a]),
                              now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let session = state.taskWindowPresentation.dragSession
        let source = TaskDragHandleView(frame: .zero)
        let payload = try XCTUnwrap(session.begin(taskID: a.id, state: state, source: source))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close(); session.ended(token: payload.token) }
        let info = MovementDraggingInfo(source: source, token: payload.token, window: window, point: .zero)
        defer { info.draggingPasteboard.releaseGlobally() }
        XCTAssertEqual(session.validatedPayload(for: info, state: state), payload)

        info.draggingSource = TaskDragHandleView(frame: .zero)
        XCTAssertNil(session.validatedPayload(for: info, state: state), "Another handle is not this session")
        info.draggingSource = nil
        XCTAssertNil(session.validatedPayload(for: info, state: state), "External drag")
        info.draggingSource = source

        let pasteboard = info.draggingPasteboard
        func write(_ items: [[NSPasteboard.PasteboardType: String]]) {
            pasteboard.clearContents()
            pasteboard.writeObjects(items.map { values in
                let item = NSPasteboardItem()
                for (type, value) in values { item.setString(value, forType: type) }
                return item
            })
        }
        let type = TaskDragSession.pasteboardType
        write([[type: UUID().uuidString]])
        XCTAssertNil(session.validatedPayload(for: info, state: state), "Unmatched token")
        write([[.string: payload.token.uuidString]])
        XCTAssertNil(session.validatedPayload(for: info, state: state), "Generic text")
        write([[type: payload.token.uuidString, .string: "A"]])
        XCTAssertNil(session.validatedPayload(for: info, state: state), "Extra representation")
        write([[type: payload.token.uuidString], [type: payload.token.uuidString]])
        XCTAssertNil(session.validatedPayload(for: info, state: state), "Bulk drag")
        write([[type: payload.token.uuidString]])
        XCTAssertEqual(session.validatedPayload(for: info, state: state), payload)

        state.beginEditing(id: a.id)
        XCTAssertNil(session.validatedPayload(for: info, state: state), "Guard appears mid-drag")
        state.cancelEditing()
        XCTAssertEqual(session.validatedPayload(for: info, state: state), payload)
        session.cancel()
        XCTAssertNil(session.validatedPayload(for: info, state: state), "Cancelled token")
        XCTAssertFalse(session.consume(payload))
        XCTAssertTrue(session.isDragging, "Native reservation lasts until source end")
    }

    func testDragPayloadIsInvalidatedWhenSourceTaskChangesGroupOrDay() throws {
        let a = note("A", day: "2026-09-27", createdAt: 1)
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        var now = instant("2026-09-27T12:00:00-04:00")
        let state = makeState(store: FakeNoteRepository(notes: [a], categories: [work]), now: { now })
        state.startup()
        let session = state.taskWindowPresentation.dragSession
        let source = TaskDragHandleView(frame: .zero)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let payload = try XCTUnwrap(session.begin(taskID: a.id, state: state, source: source))
        let info = MovementDraggingInfo(source: source, token: payload.token, window: window, point: .zero)
        defer { info.draggingPasteboard.releaseGlobally() }
        guard case .changed? = state.moveTask(moveRequest(a, destination: .category(work.id))) else {
            return XCTFail("Expected a saved move")
        }
        XCTAssertNil(session.validatedPayload(for: info, state: state), "Source group changed")
        session.ended(token: payload.token)

        let moved = try XCTUnwrap(state.notes.first)
        let next = try XCTUnwrap(session.begin(taskID: moved.id, state: state, source: source))
        let nextInfo = MovementDraggingInfo(source: source, token: next.token, window: window, point: .zero)
        defer { nextInfo.draggingPasteboard.releaseGlobally(); session.ended(token: next.token) }
        XCTAssertEqual(session.validatedPayload(for: nextInfo, state: state), next)
        now = instant("2026-09-28T00:01:00-04:00")
        state.refresh()
        XCTAssertNil(session.validatedPayload(for: nextInfo, state: state), "Day rolled over")
    }

    func testDragConsumeIsOneShotAndLifecycleCancellationClearsFeedback() throws {
        let a = note("A", day: "2026-09-27", createdAt: 1)
        let state = makeState(store: FakeNoteRepository(notes: [a]),
                              now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let presentation = state.taskWindowPresentation
        let session = presentation.dragSession
        let source = TaskDragHandleView(frame: .zero)

        let payload = try XCTUnwrap(session.begin(taskID: a.id, state: state, source: source))
        session.hoveredRequest = moveRequest(a)
        XCTAssertTrue(session.consume(payload))
        XCTAssertFalse(session.consume(payload), "A drop consumes a session once")
        XCTAssertNil(session.active)
        XCTAssertNil(session.hoveredRequest)
        XCTAssertTrue(session.isDragging)
        session.ended(token: payload.token)
        XCTAssertFalse(session.isDragging)

        let window = try XCTUnwrap(session.begin(taskID: a.id, state: state, source: source))
        session.hoveredRequest = moveRequest(a)
        presentation.cancelMovement() // Window close/teardown and modal routes.
        XCTAssertNil(session.active)
        XCTAssertNil(session.hoveredRequest)
        XCTAssertNil(session.begin(taskID: a.id, state: state, source: source),
                     "No new drag until the cancelled native session ends")
        session.ended(token: window.token)

        let terminating = try XCTUnwrap(session.begin(taskID: a.id, state: state, source: source))
        state.stopForTermination()
        XCTAssertNil(session.active)
        session.ended(token: terminating.token)
        XCTAssertFalse(session.isDragging)
    }

    func testDragHandleNeedsEnabledThresholdAndKeepsNativeControlsOutOfDragging() throws {
        let a = note("A", day: "2026-09-27", createdAt: 1)
        let state = makeState(store: FakeNoteRepository(notes: [a]),
                              now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let session = state.taskWindowPresentation.dragSession
        let handle = TaskDragHandleView(frame: NSRect(x: 10, y: 10, width: 16, height: 20))
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 60))
        content.addSubview(handle)
        let window = NSWindow(contentRect: content.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = content
        defer { window.close() }
        handle.taskID = a.id
        handle.state = state
        handle.session = session
        XCTAssertFalse(handle.acceptsFirstResponder, "The handle never takes keyboard focus")
        XCTAssertFalse(handle.mouseDownCanMoveWindow)

        func event(_ type: NSEvent.EventType, dx: CGFloat = 0) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: 18 + dx, y: 20),
                                             modifierFlags: [], timestamp: 0,
                                             windowNumber: window.windowNumber, context: nil,
                                             eventNumber: 0, clickCount: 1, pressure: 1))
        }
        handle.isEnabled = false
        handle.mouseDown(with: try event(.leftMouseDown))
        handle.mouseDragged(with: try event(.leftMouseDragged, dx: 20))
        XCTAssertFalse(session.isDragging, "A disabled handle never starts")

        handle.isEnabled = true
        handle.mouseDown(with: try event(.leftMouseDown))
        handle.mouseDragged(with: try event(.leftMouseDragged, dx: 3))
        XCTAssertFalse(session.isDragging, "Below the 4 pt threshold a click stays a click")
        handle.mouseUp(with: try event(.leftMouseUp, dx: 3))
        handle.mouseDragged(with: try event(.leftMouseDragged, dx: 20))
        XCTAssertFalse(session.isDragging, "Mouse-up ends tracking")
        handle.mouseDown(with: try event(.leftMouseDown))
        handle.clearMouseTracking() // SwiftUI dismantle/unmount.
        handle.mouseDragged(with: try event(.leftMouseDragged, dx: 20))
        XCTAssertFalse(session.isDragging)
        XCTAssertNil(session.active)
    }

    func testMenuMovesListDestinationsAndAdjacentReordersWithinGroup() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let done = instant("2026-09-27T09:00:00-04:00")
        let w1 = categorized("W1", work, createdAt: 1)
        let g1 = note("G1", day: w1.dayKey, createdAt: 2)
        let w2 = categorized("W2", work, createdAt: 3, completedAt: done)
        let w3 = categorized("W3", work, createdAt: 4)
        let state = makeState(store: FakeNoteRepository(notes: [w1, g1, w2, w3], categories: [work, home]),
                              now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let presentation = state.taskWindowPresentation

        let moves = try XCTUnwrap(presentation.menuMoves(for: w2.id, state: state))
        XCTAssertEqual(moves.destinations.map(\.title), ["Work", "Home", "General"])
        XCTAssertEqual(moves.destinations.map(\.isCurrent), [true, false, false])
        XCTAssertNil(moves.destinations[0].request, "The current group is marked, not offered")
        XCTAssertEqual(moves.destinations[1].request?.placement, .endOfGroup)
        XCTAssertEqual(moves.destinations[2].request?.destinationGroup, .general)
        XCTAssertEqual(moves.moveUp?.placement, .before(w1.id))
        XCTAssertEqual(moves.moveDown?.placement, .after(w3.id))
        XCTAssertNil(presentation.menuMoves(for: w1.id, state: state)?.moveUp, "Top of its group")
        XCTAssertNil(presentation.menuMoves(for: w3.id, state: state)?.moveDown, "Bottom of its group")
        let general = try XCTUnwrap(presentation.menuMoves(for: g1.id, state: state))
        XCTAssertNil(general.moveUp, "Another group's rows are not neighbours")
        XCTAssertNil(general.moveDown)
        XCTAssertEqual(general.destinations.map(\.isCurrent), [false, false, true])

        let progress = state.availableProgress
        XCTAssertEqual(state.moveTask(try XCTUnwrap(moves.moveUp)).map(isChanged), true)
        XCTAssertEqual(state.notes.map(\.id), [w2.id, w1.id, g1.id, w3.id])
        let down = try XCTUnwrap(presentation.menuMoves(for: w2.id, state: state)?.moveDown)
        XCTAssertEqual(down.placement, .after(w1.id))
        XCTAssertEqual(state.moveTask(down).map(isChanged), true)
        XCTAssertEqual(state.notes.map(\.id), [w1.id, w2.id, g1.id, w3.id])

        state.categoryPreferences.setCollapsed(true, for: .category(home.id))
        let toHome = try XCTUnwrap(presentation.menuMoves(for: w2.id, state: state)?.destinations[1].request)
        XCTAssertEqual(state.moveTask(toHome).map(isChanged), true)
        let moved = try XCTUnwrap(state.notes.first { $0.id == w2.id })
        XCTAssertEqual(moved.categoryID, home.id)
        XCTAssertEqual(moved.completedAt, done)
        XCTAssertEqual(state.availableProgress, progress)
        XCTAssertFalse(state.categoryPreferences.isCollapsed(.category(home.id)))
        XCTAssertEqual(presentation.movementReveal?.taskID, w2.id)
        XCTAssertEqual(presentation.menuMoves(for: w2.id, state: state)?.destinations.map(\.isCurrent),
                       [false, true, false])
    }

    func testMenuMovesAreDisabledBehindGuardsAndAbsentForUnknownTasks() throws {
        let a = note("A", day: "2026-09-27", createdAt: 1)
        let b = note("B", day: a.dayKey, createdAt: 2)
        let state = makeState(store: FakeNoteRepository(notes: [a, b]),
                              now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let presentation = state.taskWindowPresentation
        XCTAssertNil(presentation.menuMoves(for: UUID(), state: state))
        XCTAssertNotNil(presentation.menuMoves(for: b.id, state: state)?.moveUp)

        func assertDisabled(_ reason: String) throws {
            let moves = try XCTUnwrap(presentation.menuMoves(for: b.id, state: state), reason)
            XCTAssertNil(moves.moveUp, reason)
            XCTAssertNil(moves.moveDown, reason)
            XCTAssertTrue(moves.destinations.allSatisfy { $0.request == nil }, reason)
        }
        state.beginEditing(id: a.id)
        try assertDisabled("inline edit")
        state.cancelEditing()
        presentation.requestDeletion(id: a.id, state: state)
        try assertDisabled("deletion confirmation")
        presentation.cancelDeletion()
        XCTAssertNotNil(presentation.menuMoves(for: b.id, state: state)?.moveUp)
    }

    func testMenuMoveRequestsMatchDropRoutingForTheSamePlacement() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let w1 = categorized("W1", work, createdAt: 1)
        let w2 = categorized("W2", work, createdAt: 2)
        let g1 = note("G1", day: w1.dayKey, createdAt: 3)
        let state = makeState(store: FakeNoteRepository(notes: [w1, w2, g1], categories: [work]),
                              now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let moves = try XCTUnwrap(state.taskWindowPresentation.menuMoves(for: w2.id, state: state))
        let payload = TaskDragSession.Payload(token: UUID(), taskID: w2.id, dayKey: w2.dayKey,
                                              sourceGroup: .category(work.id))
        func drop(_ group: TaskGroupID, anchor: UUID?, upper: Bool) -> TaskMoveRequest? {
            TaskDropRouting.request(payload: payload, group: group, anchor: anchor, upperHalf: upper,
                                    dayKey: w2.dayKey, notes: state.notes, categories: state.categories)
        }
        XCTAssertEqual(moves.moveUp, drop(.category(work.id), anchor: w1.id, upper: true))
        XCTAssertEqual(moves.destinations.last?.request, drop(.general, anchor: nil, upper: false))
    }

    func testSavedMovementRevealIsSupersededAndCancelledByNewAction() throws {
        let a = note("A", day: "2026-09-27", createdAt: 1)
        let b = note("B", day: a.dayKey, createdAt: 2)
        let state = makeState(store: FakeNoteRepository(notes: [a, b]),
                              now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let presentation = state.taskWindowPresentation
        _ = state.moveTask(moveRequest(a))
        let first = try XCTUnwrap(presentation.movementReveal)
        XCTAssertEqual(first.taskID, a.id)
        _ = state.moveTask(moveRequest(b))
        let second = try XCTUnwrap(presentation.movementReveal)
        presentation.consumeMovementReveal(first)
        XCTAssertEqual(presentation.movementReveal, second)
        state.draft = "Retained"
        XCTAssertTrue(presentation.requestNewTask(state: state))
        XCTAssertNil(presentation.movementReveal)
        XCTAssertEqual(state.draft, "Retained")
        _ = state.moveTask(moveRequest(a))
        presentation.requestDeletion(id: b.id, state: state)
        XCTAssertNil(presentation.movementReveal)
        XCTAssertEqual(state.draft, "Retained")
    }

    func testNativeDropCallbacksRouteRowHalvesAndConsumeOnlyOnce() throws {
        let a = note("A", day: "2026-09-27", createdAt: 1)
        let b = note("B", day: a.dayKey, createdAt: 2)
        let c = note("C", day: a.dayKey, createdAt: 3)
        for upper in [true, false] {
            let store = FakeNoteRepository(notes: [a, b, c])
            let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
            state.startup()
            let session = state.taskWindowPresentation.dragSession
            let source = TaskDragHandleView(frame: .zero)
            let payload = try XCTUnwrap(session.begin(taskID: a.id, state: state, source: source))
            let target = TaskDropTargetView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
            let window = NSWindow(contentRect: target.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = target
            defer { window.close(); session.ended(token: payload.token) }
            target.state = state; target.session = session; target.group = .general; target.anchor = c.id
            let info = MovementDraggingInfo(source: source, token: payload.token, window: window,
                                            point: target.convert(NSPoint(x: 20, y: upper ? 5 : 35), to: nil))
            defer { info.draggingPasteboard.releaseGlobally() }
            XCTAssertEqual(target.draggingEntered(info), .move)
            XCTAssertEqual(session.hoveredRequest?.placement, upper ? .before(c.id) : .after(c.id))
            XCTAssertTrue(target.prepareForDragOperation(info))
            XCTAssertEqual(store.moveAttempts, 0)
            XCTAssertTrue(target.performDragOperation(info))
            XCTAssertFalse(target.performDragOperation(info))
            XCTAssertEqual(store.moveAttempts, 1)
            XCTAssertEqual(state.notes.map(\.id), upper ? [b.id, a.id, c.id] : [b.id, c.id, a.id])
            XCTAssertNil(session.active)
            XCTAssertNil(session.hoveredRequest)
        }
    }

    func testNativeDropRejectsExternalNoOpSelfAndNewGuardsWithoutWriting() throws {
        let a = note("A", day: "2026-09-27", createdAt: 1)
        let b = note("B", day: a.dayKey, createdAt: 2)
        let store = FakeNoteRepository(notes: [a, b])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let session = state.taskWindowPresentation.dragSession
        let source = TaskDragHandleView(frame: .zero)
        let payload = try XCTUnwrap(session.begin(taskID: a.id, state: state, source: source))
        let target = TaskDropTargetView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        let window = NSWindow(contentRect: target.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = target
        defer { window.close(); session.ended(token: payload.token) }
        target.state = state; target.session = session; target.group = .general
        let info = MovementDraggingInfo(source: source, token: payload.token, window: window,
                                        point: target.convert(NSPoint(x: 20, y: 5), to: nil))
        defer { info.draggingPasteboard.releaseGlobally() }
        info.draggingSource = nil
        XCTAssertEqual(target.draggingEntered(info), [])
        info.draggingSource = source
        target.anchor = a.id
        XCTAssertEqual(target.draggingUpdated(info), [])
        target.anchor = b.id // A is already before B.
        XCTAssertEqual(target.draggingUpdated(info), [])
        target.anchor = nil
        XCTAssertEqual(target.draggingUpdated(info), .move)
        state.beginEditing(id: b.id) // Guard changes between hover and drop.
        XCTAssertFalse(target.performDragOperation(info))
        XCTAssertEqual(store.moveAttempts, 0)
        XCTAssertEqual(state.notes, [a, b])
        XCTAssertNil(session.hoveredRequest)
        XCTAssertNil(session.active)
    }

    func testNativeHeaderDropFailurePreservesDraftCollapseAndClearsFeedback() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let a = note("A", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [a], categories: [work])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "Keep draft"
        state.categoryPreferences.setCollapsed(true, for: .category(work.id))
        let session = state.taskWindowPresentation.dragSession
        let source = TaskDragHandleView(frame: .zero)
        let payload = try XCTUnwrap(session.begin(taskID: a.id, state: state, source: source))
        let target = TaskDropTargetView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        let window = NSWindow(contentRect: target.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = target
        defer { window.close(); session.ended(token: payload.token) }
        target.state = state; target.session = session; target.group = .category(work.id)
        let info = MovementDraggingInfo(source: source, token: payload.token, window: window,
                                        point: target.convert(NSPoint(x: 20, y: 5), to: nil))
        defer { info.draggingPasteboard.releaseGlobally() }
        XCTAssertEqual(target.draggingEntered(info), .move)
        XCTAssertEqual(session.hoveredRequest?.placement, .endOfGroup)
        XCTAssertTrue(state.categoryPreferences.isCollapsed(.category(work.id)))
        store.failWrite = .move
        XCTAssertFalse(target.performDragOperation(info))
        XCTAssertFalse(target.performDragOperation(info))
        XCTAssertEqual(store.moveAttempts, 1)
        XCTAssertEqual(state.notes, [a])
        XCTAssertNil(state.taskWindowPresentation.movementReveal)
        XCTAssertEqual(state.draft, "Keep draft")
        XCTAssertTrue(state.categoryPreferences.isCollapsed(.category(work.id)))
        XCTAssertEqual(state.taskIssue, .move)
        XCTAssertNil(session.hoveredRequest)
        XCTAssertNil(session.active)
    }

    func testCatalogIsPublishedWithDailyRowsAndIncludesUnusedReusableCategories() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 2)
        let unused = try TaskCategory(name: "Unused", creationOrder: 8)
        let today = note("Today", day: "2026-09-27", createdAt: 1)
        let yesterday = note("Yesterday", day: "2026-09-26", createdAt: 2)
        let store = FakeNoteRepository(notes: [today, yesterday], categories: [unused, work])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        XCTAssertNil(state.availableCategories)
        state.startup()
        XCTAssertEqual(state.availableCategories, [work, unused])
        XCTAssertEqual(state.notes, [today])
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        let reopened = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        reopened.windowWillOpen()
        XCTAssertEqual(reopened.availableCategories, state.availableCategories)
        XCTAssertEqual(reopened.notes, [today])
    }

    func testReadFailuresRetainDailySnapshotAndScopeCatalogAvailabilityUntilRetry() throws {
        for failure in FakeSnapshotRead.allCases {
            let originalCategory = try TaskCategory(name: "Work", creationOrder: 0)
            let renamed = try TaskCategory(id: originalCategory.id, name: "Office", creationOrder: 0)
            let original = note("Original", day: "2026-09-27", createdAt: 1)
            let yesterday = note("Yesterday", day: "2026-09-26", createdAt: 2)
            let store = FakeNoteRepository(notes: [original, yesterday], categories: [originalCategory])
            defer {
                store.onCategoryRead = nil
                store.onRead = nil
            }
            let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
            state.startup()
            let replacement = Note(id: UUID(), text: "Replacement", dayKey: original.dayKey,
                                   createdAt: Date(), completedAt: Date(), categoryID: renamed.id)
            store.savedCategories = [renamed]
            store.saved = [replacement, yesterday, note("Another yesterday", day: yesterday.dayKey, createdAt: 3)]
            store.onCategoryRead = {
                XCTAssertEqual(state.categories, [originalCategory])
                XCTAssertEqual(state.notes, [original])
                XCTAssertEqual(state.yesterdayIncompleteCount, 1)
            }
            store.onRead = { _ in
                XCTAssertEqual(state.categories, [originalCategory])
                XCTAssertEqual(state.notes, [original])
            }
            store.failSnapshotRead = failure
            state.refresh()
            let sharedFailure = failure == .categories
            XCTAssertEqual(state.categories, sharedFailure ? [originalCategory] : [renamed],
                           "Failed at \(failure)")
            XCTAssertEqual(state.notes, [original])
            XCTAssertEqual(state.yesterdayIncompleteCount, 1)
            XCTAssertEqual(state.availableCategories, sharedFailure ? nil : [renamed])
            XCTAssertEqual(state.availableLaterTasks, sharedFailure ? nil : [])
            XCTAssertEqual(state.laterReadIssue, sharedFailure ? .load : nil)
            XCTAssertNil(state.availableProgress)
            XCTAssertEqual(state.readIssue, .load)
            // Retry must retain the last published snapshot until its reads finish.
            store.onCategoryRead = {
                XCTAssertEqual(state.categories, sharedFailure ? [originalCategory] : [renamed])
                XCTAssertEqual(state.notes, [original])
                XCTAssertEqual(state.yesterdayIncompleteCount, 1)
            }
            store.onRead = { _ in
                XCTAssertEqual(state.categories, sharedFailure ? [originalCategory] : [renamed])
                XCTAssertEqual(state.notes, [original])
            }
            store.failSnapshotRead = nil
            state.refresh()
            XCTAssertEqual(state.availableCategories, [renamed])
            XCTAssertEqual(state.notes, [replacement])
            XCTAssertEqual(state.yesterdayIncompleteCount, 2)
            XCTAssertEqual(state.availableProgress, NoteProgress(completed: 1, total: 1))
            XCTAssertNil(state.readIssue)
        }
    }

    func testInitialReadFailuresAndUnknownReferencesRespectScopedAvailability() throws {
        let category = try TaskCategory(name: "Work", creationOrder: 0)
        for failure in FakeSnapshotRead.allCases {
            let store = FakeNoteRepository(categories: [category])
            store.failSnapshotRead = failure
            let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
            state.startup()
            let sharedFailure = failure == .categories
            XCTAssertEqual(state.categories, sharedFailure ? [] : [category])
            XCTAssertTrue(state.notes.isEmpty)
            XCTAssertEqual(state.availableCategories, sharedFailure ? nil : [category])
            XCTAssertEqual(state.availableLaterTasks, sharedFailure ? nil : [])
            XCTAssertEqual(state.laterReadIssue, sharedFailure ? .load : nil)
            XCTAssertNil(state.availableProgress)
            store.failSnapshotRead = nil
            state.refresh()
            XCTAssertEqual(state.availableCategories, [category])
            XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 0))
        }
        let categorized = Note(id: UUID(), text: "Orphan", dayKey: "2026-09-27",
                               createdAt: Date(), completedAt: nil, categoryID: category.id)
        // Bypass the fake's own referential checks to challenge the state boundary.
        let store = FakeNoteRepository()
        store.uncheckedNotes = [categorized]
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertNil(state.availableProgress)
        XCTAssertEqual(state.readIssue, .load)
        store.savedCategories = [category]
        state.refresh()
        XCTAssertEqual(state.notes, [categorized])
        XCTAssertEqual(state.availableCategories, [category])
    }

    func testCategoryCommandsPublishCommittedValuesWithoutRedundantReads() throws {
        let category = try TaskCategory(name: "Work", creationOrder: 2)
        let other = try TaskCategory(name: "Other", creationOrder: 8)
        let categorized = Note(id: UUID(), text: "Done", dayKey: "2026-09-27",
                               createdAt: Date(timeIntervalSince1970: 1), completedAt: Date(), categoryID: category.id)
        let general = note("General", day: categorized.dayKey, createdAt: 2)
        let historical = Note(id: UUID(), text: "Earlier", dayKey: "2026-09-26",
                              createdAt: Date(), completedAt: nil, categoryID: category.id)
        let store = FakeNoteRepository(notes: [categorized, general, historical], categories: [category, other])
        defer { store.onCategoryWrite = nil }
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let progress = state.availableProgress
        let reads = store.readAttempts
        var expectedCategories = state.categories
        store.onCategoryWrite = {
            XCTAssertEqual(state.categories, expectedCategories)
            XCTAssertEqual(state.notes, [categorized, general])
            store.failSnapshotRead = .categories
        }
        let created = try XCTUnwrap(state.createCategory(name: "  Fitness  "))
        XCTAssertEqual(created.name, "Fitness")
        XCTAssertEqual(created.creationOrder, 9)
        XCTAssertEqual(state.categories, store.savedCategories)
        expectedCategories = state.categories
        let renamed = try XCTUnwrap(state.renameCategory(id: category.id, name: "Office"))
        XCTAssertEqual(renamed.id, category.id)
        XCTAssertEqual(renamed.creationOrder, category.creationOrder)
        XCTAssertEqual(state.categories, [renamed, other, created])
        XCTAssertEqual(state.notes, [categorized, general])
        expectedCategories = state.categories
        XCTAssertTrue(state.removeCategory(id: category.id))
        XCTAssertEqual(state.categories, [other, created])
        let uncategorized = Note(id: categorized.id, text: categorized.text, dayKey: categorized.dayKey,
                                 createdAt: categorized.createdAt, completedAt: categorized.completedAt)
        XCTAssertEqual(state.notes, [uncategorized, general])
        XCTAssertNil(store.saved.last?.categoryID)
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        XCTAssertEqual(state.availableProgress, progress)
        XCTAssertEqual(store.readAttempts, reads)
        XCTAssertNil(state.categoryIssue)
        XCTAssertNil(state.readIssue)
    }

    func testFailedCategoryWritesPreserveSavedSnapshotTaskErrorsAndBothDrafts() throws {
        let category = try TaskCategory(name: "Work", creationOrder: 0)
        let original = Note(id: UUID(), text: "Original", dayKey: "2026-09-27",
                            createdAt: Date(), completedAt: nil, categoryID: category.id)
        let store = FakeNoteRepository(notes: [original], categories: [category])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "New task draft"
        state.beginEditing(id: original.id)
        state.editDraft = "Unsaved edit"
        store.failWrite = .edit
        XCTAssertFalse(state.saveEdit())
        for failure in [CategoryCommandIssue.create, .rename, .remove] {
            store.failCategoryCommand = failure
            switch failure {
            case .create: XCTAssertNil(state.createCategory(name: "Fitness"))
            case .rename: XCTAssertNil(state.renameCategory(id: category.id, name: "Office"))
            case .remove: XCTAssertFalse(state.removeCategory(id: category.id))
            default: XCTFail("Unexpected write fixture")
            }
            XCTAssertEqual(state.categoryIssue, failure)
            XCTAssertEqual(state.categories, [category])
            XCTAssertEqual(state.notes, [original])
            XCTAssertEqual(store.savedCategories, [category])
            XCTAssertEqual(store.saved, [original])
            XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 1))
            XCTAssertEqual(state.taskIssue, .edit)
            XCTAssertEqual(state.issue, .edit)
            XCTAssertEqual(state.draft, "New task draft")
            XCTAssertEqual(state.editingNoteID, original.id)
            XCTAssertEqual(state.editDraft, "Unsaved edit")
        }
        store.failCategoryCommand = nil
        XCTAssertNotNil(state.createCategory(name: "Fitness"))
        XCTAssertNotNil(state.renameCategory(id: category.id, name: "Office"))
        XCTAssertEqual(state.taskIssue, .edit)
        XCTAssertEqual(state.editDraft, "Unsaved edit")
        // Removing the edit's own selected category cancels that edit for recovery.
        XCTAssertTrue(state.removeCategory(id: category.id))
        XCTAssertNil(state.categoryIssue)
        XCTAssertNil(state.editingNoteID)
        XCTAssertNil(state.taskIssue)
        XCTAssertEqual(state.recoveredEdit,
                       DailyNotesState.RecoveredEdit(text: "Unsaved edit", categoryID: category.id,
                                                     categoryName: "Office"))
        XCTAssertEqual(state.draft, "New task draft")
    }

    func testNameValidationAndUsageErrorsHaveIndependentBoundaries() throws {
        let category = try TaskCategory(name: "Work", creationOrder: 0)
        let olderDone = Note(id: UUID(), text: "Older done", dayKey: "2026-09-20",
                             createdAt: Date(), completedAt: Date(), categoryID: category.id)
        let yesterday = Note(id: UUID(), text: "Yesterday", dayKey: "2026-09-26",
                             createdAt: Date(), completedAt: nil, categoryID: category.id)
        let store = FakeNoteRepository(notes: [olderDone, yesterday], categories: [category])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "Keep this draft"
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        let reads = store.readAttempts
        for (input, error) in [("  ", TaskCategoryNameError.blank), ("A\nB", .multiline), ("general", .reserved)] {
            XCTAssertNil(state.createCategory(name: input))
            XCTAssertEqual(state.categoryNameIssue, .invalid(error))
            XCTAssertNil(state.categoryIssue)
            XCTAssertEqual(state.taskIssue, .add)
        }
        XCTAssertEqual(store.readAttempts, reads)
        // Renaming the same category to a case variant is valid.
        XCTAssertNotNil(state.renameCategory(id: category.id, name: "WORK"))
        XCTAssertNil(state.categoryNameIssue)
        XCTAssertNil(state.createCategory(name: "work"))
        XCTAssertEqual(state.categoryNameIssue, .duplicate)
        XCTAssertEqual(state.categoryUsageCount(id: category.id), 2)
        XCTAssertEqual(state.categoryNameIssue, .duplicate)
        store.failCategoryCommand = .usage
        XCTAssertNil(state.categoryUsageCount(id: category.id))
        XCTAssertEqual(state.categoryIssue, .usage)
        XCTAssertEqual(state.categoryNameIssue, .duplicate)
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 0))
        store.failCategoryCommand = nil
        XCTAssertEqual(state.categoryUsageCount(id: category.id), 2)
        XCTAssertNil(state.categoryIssue)
        let missing = UUID()
        XCTAssertNil(state.categoryUsageCount(id: missing))
        XCTAssertEqual(state.categoryIssue, .notFound)
        XCTAssertNil(state.renameCategory(id: missing, name: "Missing"))
        XCTAssertEqual(state.categoryIssue, .notFound)
        XCTAssertFalse(state.removeCategory(id: missing))
        XCTAssertEqual(state.categoryIssue, .notFound)
        XCTAssertEqual(state.taskIssue, .add)
        XCTAssertEqual(state.draft, "Keep this draft")
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        XCTAssertEqual(store.saved, [olderDone, yesterday])

        let last = try TaskCategory(name: "Last", creationOrder: .max)
        store.savedCategories.append(last)
        state.refresh()
        XCTAssertNil(state.createCategory(name: "Overflow"))
        XCTAssertEqual(state.categoryIssue, .orderExhausted)
        XCTAssertEqual(state.categories, store.savedCategories)
        XCTAssertEqual(state.taskIssue, .add)
    }

    func testReadRetryPreservesPendingTaskErrorAndCategoryValidation() {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "Unsaved"
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        XCTAssertNil(state.createCategory(name: "General"))
        store.failSnapshotRead = .categories
        state.refresh()
        XCTAssertEqual(state.issue, .load)
        XCTAssertEqual(state.taskIssue, .add)
        XCTAssertEqual(state.categoryNameIssue, .invalid(.reserved))
        XCTAssertNil(state.createCategory(name: "Work"))
        XCTAssertNil(state.renameCategory(id: UUID(), name: "Office"))
        XCTAssertFalse(state.removeCategory(id: UUID()))
        XCTAssertEqual(store.categoryWriteAttempts, 0)
        XCTAssertEqual(state.draft, "Unsaved")
        store.failSnapshotRead = nil
        XCTAssertNotNil(state.createCategory(name: "Work"))
        XCTAssertNil(state.readIssue)
        XCTAssertEqual(state.issue, .add)
        XCTAssertEqual(state.draft, "Unsaved")
        store.failWrite = nil
        XCTAssertTrue(state.addDraft())
        XCTAssertNil(state.issue)
    }

    func testDayChangeKeepsGlobalCatalogAndAllCategoryYesterdayCounts() throws {
        let category = try TaskCategory(name: "Work", creationOrder: 0)
        let unused = try TaskCategory(name: "Unused", creationOrder: 3)
        let old = Note(id: UUID(), text: "Old", dayKey: "2026-09-27",
                       createdAt: Date(), completedAt: nil, categoryID: category.id)
        let general = note("General", day: old.dayKey, createdAt: 2)
        let finished = note("Finished", day: old.dayKey, createdAt: 3, completedAt: Date())
        let today = note("New day", day: "2026-09-28", createdAt: 4)
        let store = FakeNoteRepository(notes: [old, general, finished, today], categories: [category, unused])
        defer { store.onCategoryRead = nil }
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = makeState(store: store, now: { current })
        state.startup()
        state.draft = "Retain new draft"
        state.beginEditing(id: old.id)
        state.editDraft = "Recover edit"
        store.failWrite = .edit
        XCTAssertFalse(state.saveEdit())
        XCTAssertEqual(state.taskIssue, .edit)
        current = instant("2026-09-28T00:01:00-04:00")
        store.onCategoryRead = {
            XCTAssertEqual(state.categories, [category, unused])
            XCTAssertEqual(state.availableCategories, [category, unused])
            XCTAssertEqual(state.availableLaterTasks, [])
            XCTAssertNil(state.availableProgress)
            XCTAssertTrue(state.notes.isEmpty)
        }
        store.failSnapshotRead = .count
        state.refreshIfDayChanged()
        XCTAssertNil(state.availableProgress)
        XCTAssertEqual(state.categories, [category, unused])
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertEqual(state.recoveredEditDraft, "Recover edit")
        XCTAssertNil(state.taskIssue)
        XCTAssertEqual(state.draft, "Retain new draft")
        store.failSnapshotRead = nil
        state.refresh()
        XCTAssertEqual(state.availableCategories, [category, unused])
        XCTAssertEqual(state.notes, [today])
        XCTAssertEqual(state.yesterdayIncompleteCount, 2)
        XCTAssertEqual(store.saved, [old, general, finished, today])
    }

    func testSQLiteBackedCategoryCommandsPreserveAllDaysAcrossReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DailyCatalog-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.sqlite")
        let current = instant("2026-09-27T12:00:00-04:00")
        let original: [Note]
        let category: TaskCategory
        do {
            let store = try SQLiteNoteRepository(databaseURL: url)
            category = try store.createCategory(name: "Work")
            original = ["2026-09-27", "2026-09-26", "2026-09-20"].map { key in
                Note(id: UUID(), text: key, dayKey: key, createdAt: current,
                     completedAt: key == "2026-09-20" ? current : nil, categoryID: category.id)
            }
            for note in original { try store.add(note) }
        }
        let state = DailyNotesState(repositoryFactory: { try SQLiteNoteRepository(databaseURL: url) },
                                   day: makeDay(now: { current }), notificationCenter: NotificationCenter(),
                                   workspaceNotificationCenter: NotificationCenter(),
                                   categoryPreferences: isolatedCategoryPreferences())
        state.startup()
        XCTAssertEqual(state.categories, [category])
        let survivor = try XCTUnwrap(state.createCategory(name: "Unused"))
        XCTAssertNotNil(state.renameCategory(id: category.id, name: "Office"))
        XCTAssertEqual(state.categoryUsageCount(id: category.id), 3)
        XCTAssertTrue(state.removeCategory(id: category.id))
        XCTAssertEqual(state.availableCategories, [survivor])
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 1))
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        state.stopForTermination()
        XCTAssertNil(state.createCategory(name: "After Quit"))
        XCTAssertFalse(state.removeCategory(id: survivor.id))
        let reopened = try SQLiteNoteRepository(databaseURL: url)
        XCTAssertEqual(try reopened.categories(), [survivor])
        for note in original {
            let expected = Note(id: note.id, text: note.text, dayKey: note.dayKey,
                                createdAt: note.createdAt, completedAt: note.completedAt)
            XCTAssertEqual(try reopened.notes(for: note.dayKey), [expected])
        }
    }

    func testCategorizedTaskRetainsAssociationAndOrderAcrossCompletionEditingAndRefresh() throws {
        let current = instant("2026-09-27T12:00:00-04:00")
        let category = try TaskCategory(name: "Work", creationOrder: 7)
        let original = Note(id: UUID(), text: "Categorized", dayKey: "2026-09-27",
                            createdAt: current, completedAt: nil, categoryID: category.id)
        let general = note("General task", day: original.dayKey, createdAt: 1)
        let store = FakeNoteRepository(notes: [original, general], categories: [category])
        let state = makeState(store: store, now: { current })
        state.startup()

        XCTAssertTrue(state.setCompleted(id: original.id, completed: true))
        let completed = Note(id: original.id, text: original.text, dayKey: original.dayKey,
                             createdAt: original.createdAt, completedAt: current,
                             categoryID: category.id)
        XCTAssertEqual(state.notes, [completed, general])
        XCTAssertEqual(store.saved, state.notes)
        XCTAssertEqual(state.progress, NoteProgress(completed: 1, total: 2))

        XCTAssertTrue(state.setCompleted(id: original.id, completed: false))
        XCTAssertEqual(state.notes, [original, general])
        XCTAssertEqual(store.saved, state.notes)
        state.beginEditing(id: original.id)
        state.editDraft = "  Updated text  "
        XCTAssertTrue(state.saveEdit())
        let edited = Note(id: original.id, text: "Updated text", dayKey: original.dayKey,
                          createdAt: original.createdAt, completedAt: nil,
                          categoryID: category.id)
        XCTAssertEqual(state.notes, [edited, general])
        XCTAssertEqual(store.saved, state.notes)
        XCTAssertEqual(state.progress, NoteProgress(completed: 0, total: 2))
        state.refresh()
        XCTAssertEqual(state.notes, [edited, general])
        let reopened = makeState(store: store, now: { current })
        reopened.startup()
        XCTAssertEqual(reopened.notes, [edited, general])
    }

    func testRejectedCategorizedTaskWritesPreserveAssociationAndEditDraft() throws {
        let current = instant("2026-09-27T12:00:00-04:00")
        let category = try TaskCategory(name: "Work", creationOrder: 0)
        let original = Note(id: UUID(), text: "Original", dayKey: "2026-09-27",
                            createdAt: current, completedAt: nil, categoryID: category.id)
        let store = FakeNoteRepository(notes: [original], categories: [category])
        let state = makeState(store: store, now: { current })
        state.startup()

        store.failWrite = .complete
        XCTAssertFalse(state.setCompleted(id: original.id, completed: true))
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(store.saved, [original])

        state.beginEditing(id: original.id)
        state.editDraft = "Unsaved edit"
        store.failWrite = .edit
        XCTAssertFalse(state.saveEdit())
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(store.saved, [original])
        XCTAssertEqual(state.progress, NoteProgress(completed: 0, total: 1))
        XCTAssertEqual(state.editingNoteID, original.id)
        XCTAssertEqual(state.editDraft, "Unsaved edit")
    }

    func testNewAndEditCategoryDraftsStayIndependentAndSaveAtomically() throws {
        let current = instant("2026-09-27T12:00:00-04:00")
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let original = Note(id: UUID(), text: "Original", dayKey: "2026-09-27",
                            createdAt: Date(timeIntervalSince1970: 1), completedAt: current,
                            categoryID: work.id)
        let later = note("Later", day: original.dayKey, createdAt: 2)
        let store = FakeNoteRepository(notes: [original, later], categories: [work, home])
        let state = makeState(store: store, now: { current })
        state.startup()
        XCTAssertNil(state.draftCategoryID)
        state.draft = "New task"
        state.draftCategoryID = home.id
        state.beginEditing(id: original.id)
        XCTAssertEqual(state.editCategoryID, work.id)

        // Same-day window reuse keeps both drafts and both selections.
        state.windowWillOpen()
        XCTAssertEqual(state.editingNoteID, original.id)
        XCTAssertEqual(state.editCategoryID, work.id)
        XCTAssertEqual(state.draftCategoryID, home.id)

        // A category-only edit saves; identity, completion, day, and order stay.
        state.editCategoryID = nil
        XCTAssertTrue(state.saveEdit())
        let reassigned = Note(id: original.id, text: original.text, dayKey: original.dayKey,
                              createdAt: original.createdAt, completedAt: current)
        XCTAssertEqual(state.notes, [reassigned, later])
        XCTAssertEqual(store.saved, state.notes)
        XCTAssertNil(state.editingNoteID)
        XCTAssertNil(state.editCategoryID)
        XCTAssertEqual(state.progress, NoteProgress(completed: 1, total: 2))
        XCTAssertEqual(state.draft, "New task")
        XCTAssertEqual(state.draftCategoryID, home.id)

        // The capture panel's add path stays General and leaves the window draft alone.
        XCTAssertEqual(state.add(text: "Captured"), .added)
        XCTAssertNil(store.saved.last?.categoryID)
        XCTAssertEqual(state.draftCategoryID, home.id)

        XCTAssertTrue(state.addDraft())
        XCTAssertEqual(store.saved.last?.text, "New task")
        XCTAssertEqual(store.saved.last?.categoryID, home.id)
        XCTAssertEqual(state.notes, store.saved)
        XCTAssertEqual(state.draft, "")
        XCTAssertNil(state.draftCategoryID)
    }

    func testFailedCategorizedSavesKeepTextAndSelectionAndCancelClearsOnlyItsDraft() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let original = note("Original", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [original], categories: [work, home])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "New task"
        state.draftCategoryID = work.id
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(state.taskIssue, .add)
        XCTAssertEqual(state.draft, "New task")
        XCTAssertEqual(state.draftCategoryID, work.id)

        state.beginEditing(id: original.id)
        XCTAssertNil(state.editCategoryID)
        state.editDraft = "Edited"
        state.editCategoryID = home.id
        store.failWrite = .edit
        XCTAssertFalse(state.saveEdit())
        XCTAssertEqual(state.taskIssue, .edit)
        XCTAssertEqual(state.editingNoteID, original.id)
        XCTAssertEqual(state.editDraft, "Edited")
        XCTAssertEqual(state.editCategoryID, home.id)
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(store.saved, [original])

        state.cancelEditing()
        XCTAssertNil(state.editCategoryID)
        XCTAssertEqual(state.draft, "New task")
        XCTAssertEqual(state.draftCategoryID, work.id)
        state.cancelDraft()
        XCTAssertEqual(state.draft, "")
        XCTAssertNil(state.draftCategoryID)
        XCTAssertNil(state.taskIssue)
        XCTAssertNil(state.refreshNotice)
        XCTAssertEqual(store.saved, [original])
    }

    func testSelectionOutsideTheCatalogIsNeverSavedOrPublished() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let original = note("Original", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [original], categories: [work])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let unknown = UUID()
        state.draft = "Keep me"
        state.draftCategoryID = unknown
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(store.saved, [original])
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(state.draft, "Keep me")
        XCTAssertNil(state.draftCategoryID)
        XCTAssertNil(state.taskIssue)
        XCTAssertNotNil(state.refreshNotice)
        XCTAssertEqual(state.add(text: "Panel", categoryID: unknown), .unavailable)
        XCTAssertEqual(store.saved, [original])

        state.beginEditing(id: original.id)
        state.editDraft = "Edited"
        state.editCategoryID = unknown
        XCTAssertFalse(state.saveEdit())
        XCTAssertEqual(store.saved, [original])
        XCTAssertEqual(state.notes, [original])
        XCTAssertNil(state.editingNoteID)
        XCTAssertEqual(state.recoveredEdit,
                       DailyNotesState.RecoveredEdit(text: "Edited", categoryID: unknown, categoryName: nil))

        // Storage that no longer has a loaded category rejects the write; nothing is published.
        store.savedCategories = []
        state.draftCategoryID = work.id
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(state.taskIssue, .add)
        XCTAssertEqual(state.draft, "Keep me")
        XCTAssertEqual(state.draftCategoryID, work.id)
        state.beginEditing(id: original.id)
        state.editCategoryID = work.id
        XCTAssertFalse(state.saveEdit())
        XCTAssertEqual(state.taskIssue, .edit)
        XCTAssertEqual(state.editingNoteID, original.id)
        XCTAssertEqual(state.editCategoryID, work.id)
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(store.saved, [original])
    }

    func testRemovingSelectedCategoriesFallsBackNewDraftAndRecoversEdit() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let categorized = Note(id: UUID(), text: "Categorized", dayKey: "2026-09-27",
                               createdAt: Date(timeIntervalSince1970: 1), completedAt: nil,
                               categoryID: work.id)
        let general = note("General", day: categorized.dayKey, createdAt: 2)
        let store = FakeNoteRepository(notes: [categorized, general], categories: [work, home])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "New task"
        state.draftCategoryID = work.id
        state.beginEditing(id: general.id)
        state.editDraft = "Edited"
        state.editCategoryID = work.id

        // An unrelated removal and a rename keep both drafts intact.
        XCTAssertTrue(state.removeCategory(id: home.id))
        XCTAssertNotNil(state.renameCategory(id: work.id, name: "Office"))
        XCTAssertEqual(state.draftCategoryID, work.id)
        XCTAssertEqual(state.editingNoteID, general.id)
        XCTAssertEqual(state.editCategoryID, work.id)
        XCTAssertNil(state.refreshNotice)

        XCTAssertTrue(state.removeCategory(id: work.id))
        XCTAssertEqual(state.draft, "New task")
        XCTAssertNil(state.draftCategoryID)
        XCTAssertNil(state.editingNoteID)
        XCTAssertEqual(state.recoveredEdit,
                       DailyNotesState.RecoveredEdit(text: "Edited", categoryID: work.id, categoryName: "Office"))
        XCTAssertNotNil(state.refreshNotice)
        XCTAssertEqual(store.saved.map(\.text), ["Categorized", "General"])
        XCTAssertTrue(store.saved.allSatisfy { $0.categoryID == nil })
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 2))
        XCTAssertTrue(state.addDraft())
        XCTAssertNil(store.saved.last?.categoryID)
    }

    func testRefreshAppliesRemovedCategoryAfterCatalogReadDespiteTodayFailure() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let original = Note(id: UUID(), text: "Original", dayKey: "2026-09-27",
                            createdAt: Date(), completedAt: nil, categoryID: work.id)
        let store = FakeNoteRepository(notes: [original], categories: [work])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "New task"
        state.draftCategoryID = work.id
        state.beginEditing(id: original.id)
        state.editDraft = "Edited"
        // A valid catalog confirms removal even when the Today count cannot load.
        try store.removeCategory(id: work.id)
        // A catalog failure supplies no evidence that a selection disappeared.
        store.failSnapshotRead = .categories
        state.refresh()
        XCTAssertNil(state.availableCategories)
        XCTAssertNil(state.availableLaterTasks)
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(state.draft, "New task")
        XCTAssertEqual(state.draftCategoryID, work.id)
        XCTAssertEqual(state.editingNoteID, original.id)
        XCTAssertEqual(state.editDraft, "Edited")
        XCTAssertEqual(state.editCategoryID, work.id)
        XCTAssertNil(state.recoveredEdit)

        store.failSnapshotRead = .count
        state.refresh()
        XCTAssertEqual(state.availableCategories, [])
        XCTAssertEqual(state.availableLaterTasks, [])
        XCTAssertNil(state.availableProgress)
        XCTAssertEqual(state.readIssue, .load)
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(state.draft, "New task")
        XCTAssertNil(state.draftCategoryID)
        XCTAssertNil(state.editingNoteID)
        XCTAssertNil(state.editCategoryID)
        let recovered = DailyNotesState.RecoveredEdit(text: "Edited", categoryID: work.id,
                                                      categoryName: "Work")
        XCTAssertEqual(state.recoveredEdit, recovered)
        XCTAssertNotNil(state.refreshNotice)
        XCTAssertFalse(state.saveEdit())
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(store.saved.map(\.text), ["Original"])
        XCTAssertNil(store.saved.first?.categoryID)
        XCTAssertEqual(state.draft, "New task")
        XCTAssertNil(state.draftCategoryID)
        XCTAssertNil(state.editingNoteID)
        XCTAssertEqual(state.recoveredEdit, recovered)

        store.failSnapshotRead = nil
        state.refresh()
        XCTAssertEqual(state.availableCategories, [])
        XCTAssertEqual(state.draft, "New task")
        XCTAssertNil(state.draftCategoryID)
        XCTAssertNil(state.editingNoteID)
        XCTAssertEqual(state.recoveredEdit,
                       DailyNotesState.RecoveredEdit(text: "Edited", categoryID: work.id, categoryName: "Work"))
        XCTAssertNotNil(state.refreshNotice)
    }

    func testRolloverRecoversEditCategoryAndKeepsNewDraftSelection() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let old = Note(id: UUID(), text: "Old", dayKey: "2026-09-27",
                       createdAt: Date(), completedAt: nil, categoryID: work.id)
        let store = FakeNoteRepository(notes: [old], categories: [work, home])
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = makeState(store: store, now: { current })
        state.startup()
        state.draft = "Tomorrow"
        state.draftCategoryID = home.id
        state.beginEditing(id: old.id)
        state.editDraft = "Unsaved"
        state.editCategoryID = home.id
        current = instant("2026-09-28T00:01:00-04:00")
        store.failCount = true
        XCTAssertFalse(state.saveEdit())
        XCTAssertNil(state.editingNoteID)
        XCTAssertNil(state.editCategoryID)
        XCTAssertEqual(state.recoveredEdit,
                       DailyNotesState.RecoveredEdit(text: "Unsaved", categoryID: home.id, categoryName: "Home"))
        XCTAssertEqual(store.saved, [old])
        XCTAssertEqual(state.draftCategoryID, home.id)

        store.failCount = false
        XCTAssertTrue(state.addDraft())
        let added = try XCTUnwrap(store.saved.last)
        XCTAssertEqual(added.text, "Tomorrow")
        XCTAssertEqual(added.dayKey, "2026-09-28")
        XCTAssertEqual(added.categoryID, home.id)
        XCTAssertEqual(store.saved.first, old)
    }

    func testSQLiteBackedCategorizedAddAndCategoryOnlyEditSurviveReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DailyCategoryDrafts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.sqlite")
        let current = instant("2026-09-27T12:00:00-04:00")
        let makeState = {
            DailyNotesState(repositoryFactory: { try SQLiteNoteRepository(databaseURL: url) },
                            day: self.makeDay(now: { current }), notificationCenter: NotificationCenter(),
                            workspaceNotificationCenter: NotificationCenter(),
                            categoryPreferences: self.isolatedCategoryPreferences())
        }
        let state = makeState()
        state.startup()
        let work = try XCTUnwrap(state.createCategory(name: "Work"))
        let home = try XCTUnwrap(state.createCategory(name: "Home"))
        state.draft = "First"
        state.draftCategoryID = work.id
        XCTAssertTrue(state.addDraft())
        // A successful add resets the selection, so this task is General.
        state.draft = "Second"
        XCTAssertTrue(state.addDraft())
        let first = try XCTUnwrap(state.notes.first)
        XCTAssertTrue(state.setCompleted(id: first.id, completed: true))
        state.beginEditing(id: first.id)
        XCTAssertEqual(state.editCategoryID, work.id)
        state.editCategoryID = home.id
        XCTAssertTrue(state.saveEdit())
        let expected = state.notes
        XCTAssertEqual(expected.map(\.text), ["First", "Second"])
        XCTAssertEqual(expected.map(\.categoryID), [home.id, nil])
        XCTAssertEqual(expected.first?.id, first.id)
        XCTAssertEqual(expected.first?.createdAt, first.createdAt)
        XCTAssertEqual(expected.first?.completedAt, current)
        state.stopForTermination()

        let reopened = makeState()
        reopened.startup()
        XCTAssertEqual(reopened.notes, expected)
        XCTAssertEqual(reopened.availableCategories, [work, home])
        XCTAssertEqual(reopened.progress, NoteProgress(completed: 1, total: 2))
    }

    func testSQLiteGroupsAndPresentationPreferencesSurviveReassignmentAndReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CategoryGroups-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.sqlite")
        let defaults = isolatedDefaults()
        let current = instant("2026-09-27T12:00:00-04:00")
        let makeState = {
            DailyNotesState(repositoryFactory: { try SQLiteNoteRepository(databaseURL: url) },
                            day: self.makeDay(now: { current }), notificationCenter: NotificationCenter(),
                            workspaceNotificationCenter: NotificationCenter(),
                            categoryPreferences: TaskCategoryPreferences(userDefaults: defaults))
        }
        let expectedNotes: [Note]
        let expectedGroups: [TaskGroup]
        let expectedCategories: [TaskCategory]
        let work: TaskCategory
        do {
            let state = makeState()
            state.startup()
            work = try XCTUnwrap(state.createCategory(name: "Work"))
            let home = try XCTUnwrap(state.createCategory(name: "Home"))
            XCTAssertNotNil(state.createCategory(name: "Unused"))
            let drafts: [(String, UUID?)] = [("First", work.id), ("Second", home.id),
                                           ("General task", nil), ("Fourth", work.id)]
            for (text, categoryID) in drafts {
                state.draft = text
                state.draftCategoryID = categoryID
                XCTAssertTrue(state.addDraft())
            }
            let first = try XCTUnwrap(state.notes.first)
            XCTAssertTrue(state.setCompleted(id: first.id, completed: true))
            state.beginEditing(id: first.id)
            state.editCategoryID = home.id
            XCTAssertTrue(state.saveEdit())
            XCTAssertNotNil(state.renameCategory(id: home.id, name: "Household"))
            state.categoryPreferences.setCollapsed(true, for: .category(work.id))
            state.categoryPreferences.setCollapsed(true, for: .general)
            XCTAssertEqual(state.groups.map(\.name), ["Work", "Household", "General"])
            XCTAssertEqual(groupTexts(state), [["Fourth"], ["First", "Second"], ["General task"]])
            assertGroupCounts(state, equal: NoteProgress(completed: 1, total: 4))
            expectedNotes = state.notes
            expectedGroups = state.groups
            expectedCategories = state.categories
            state.stopForTermination()
        }

        // Both the state and its SQLite connection have been released.
        let reopened = makeState()
        reopened.startup()
        XCTAssertEqual(reopened.notes, expectedNotes)
        XCTAssertEqual(reopened.groups, expectedGroups)
        XCTAssertEqual(reopened.availableCategories, expectedCategories)
        XCTAssertEqual(reopened.categoryPreferences.lastUsedCategoryID, work.id)
        XCTAssertEqual(reopened.categoryPreferences.collapsedGroupIDs, [.category(work.id), .general])
        assertGroupCounts(reopened, equal: NoteProgress(completed: 1, total: 4))
    }

    func testSQLiteRejectedReassignmentAndRemovalKeepGroupsProgressAndSavedRowsUntilRetry() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CategoryFailures-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.sqlite")
        let current = instant("2026-09-27T12:00:00-04:00")
        let store = try SQLiteNoteRepository(databaseURL: url)
        let work = try store.createCategory(name: "Work")
        let home = try store.createCategory(name: "Home")
        let today = Note(id: UUID(), text: "Done", dayKey: "2026-09-27", createdAt: current,
                         completedAt: current, categoryID: work.id)
        let yesterday = Note(id: UUID(), text: "Yesterday", dayKey: "2026-09-26", createdAt: current,
                             completedAt: nil, categoryID: work.id)
        let older = Note(id: UUID(), text: "Older", dayKey: "2026-09-20", createdAt: current,
                         completedAt: current, categoryID: work.id)
        for note in [today, yesterday, older] { try store.add(note) }
        let preferences = isolatedCategoryPreferences()
        let state = DailyNotesState(repositoryFactory: { store }, day: makeDay(now: { current }),
                                   notificationCenter: NotificationCenter(),
                                   workspaceNotificationCenter: NotificationCenter(),
                                   categoryPreferences: preferences)
        state.startup()
        preferences.rememberLastUsed(work.id)
        preferences.setCollapsed(true, for: .category(home.id))
        let groups = state.groups
        let progress = NoteProgress(completed: 1, total: 1)
        try executeCategoryFixtureSQL(
            """
            CREATE TRIGGER reject_edit AFTER UPDATE OF text ON notes
            BEGIN SELECT RAISE(FAIL, 'rejected after editing'); END;
            CREATE TRIGGER reject_removal AFTER UPDATE OF category_id ON notes
            WHEN NEW.day_key = '2026-09-20'
            BEGIN SELECT RAISE(FAIL, 'rejected after removing'); END;
            """, at: url)
        state.beginEditing(id: today.id)
        state.editDraft = "Changed"
        state.editCategoryID = home.id
        XCTAssertFalse(state.saveEdit())
        XCTAssertEqual(state.taskIssue, .edit)
        XCTAssertEqual(state.editDraft, "Changed")
        XCTAssertEqual(state.editCategoryID, home.id)
        XCTAssertFalse(state.removeCategory(id: work.id))
        XCTAssertEqual(state.categoryIssue, .remove)
        XCTAssertEqual(state.taskIssue, .edit)
        XCTAssertEqual(state.groups, groups)
        XCTAssertEqual(state.availableCategories, [work, home])
        assertGroupCounts(state, equal: progress)
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        XCTAssertEqual(preferences.lastUsedCategoryID, work.id)
        XCTAssertTrue(preferences.isCollapsed(.category(home.id)))
        for note in [today, yesterday, older] {
            XCTAssertEqual(try store.notes(for: note.dayKey), [note])
        }

        try executeCategoryFixtureSQL("DROP TRIGGER reject_edit; DROP TRIGGER reject_removal", at: url)
        XCTAssertTrue(state.saveEdit())
        XCTAssertFalse(preferences.isCollapsed(.category(home.id)))
        XCTAssertEqual(state.groups.first?.id, .category(home.id))
        XCTAssertTrue(state.removeCategory(id: work.id))
        XCTAssertNil(preferences.lastUsedCategoryID)
        assertGroupCounts(state, equal: progress)
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        let reopened = try SQLiteNoteRepository(databaseURL: url)
        XCTAssertEqual(try reopened.categories(), [home])
        XCTAssertEqual(try reopened.notes(for: today.dayKey), [
            Note(id: today.id, text: "Changed", dayKey: today.dayKey, createdAt: today.createdAt,
                 completedAt: today.completedAt, categoryID: home.id)
        ])
        for note in [yesterday, older] {
            XCTAssertEqual(try reopened.notes(for: note.dayKey), [
                Note(id: note.id, text: note.text, dayKey: note.dayKey, createdAt: note.createdAt,
                     completedAt: note.completedAt)
            ])
        }
    }

    func testGroupsFollowSavedSnapshotAndKeepDailyProgressThroughCategoryChanges() throws {
        let current = instant("2026-09-27T12:00:00-04:00")
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let report = Note(id: UUID(), text: "Report", dayKey: "2026-09-27",
                          createdAt: Date(timeIntervalSince1970: 1), completedAt: current, categoryID: work.id)
        let groceries = note("Groceries", day: report.dayKey, createdAt: 2)
        let reply = Note(id: UUID(), text: "Reply", dayKey: report.dayKey,
                         createdAt: Date(timeIntervalSince1970: 3), completedAt: nil, categoryID: work.id)
        let desk = note("Desk", day: report.dayKey, createdAt: 4, completedAt: current)
        let store = FakeNoteRepository(notes: [report, groceries, reply, desk], categories: [work, home])
        let state = makeState(store: store, now: { current })
        state.startup()
        let daily = NoteProgress(completed: 2, total: 4)

        // Home has no tasks today, so only Work and then General appear.
        XCTAssertEqual(state.availableCategories, [work, home])
        XCTAssertEqual(state.groups.map(\.id), [.category(work.id), .general])
        XCTAssertEqual(groupTexts(state), [["Report", "Reply"], ["Groceries", "Desk"]])
        assertGroupCounts(state, equal: daily)

        // Collapsing changes no group or daily count.
        state.categoryPreferences.setCollapsed(true, for: .category(work.id))
        XCTAssertEqual(state.groups.map(\.progress), [NoteProgress(completed: 1, total: 2),
                                                      NoteProgress(completed: 1, total: 2)])
        assertGroupCounts(state, equal: daily)

        // A reassigned task joins General at its original relative position.
        state.beginEditing(id: reply.id)
        state.editCategoryID = nil
        XCTAssertTrue(state.saveEdit())
        XCTAssertEqual(groupTexts(state), [["Report"], ["Groceries", "Reply", "Desk"]])
        assertGroupCounts(state, equal: daily)

        XCTAssertNotNil(state.renameCategory(id: work.id, name: "Office"))
        XCTAssertEqual(state.groups.first?.id, .category(work.id))
        XCTAssertEqual(state.groups.first?.name, "Office")
        XCTAssertTrue(state.categoryPreferences.isCollapsed(.category(work.id)))

        XCTAssertTrue(state.removeCategory(id: work.id))
        XCTAssertEqual(state.groups.map(\.id), [.general])
        XCTAssertEqual(groupTexts(state), [["Report", "Groceries", "Reply", "Desk"]])
        assertGroupCounts(state, equal: daily)

        state.refresh()
        XCTAssertEqual(groupTexts(state), [["Report", "Groceries", "Reply", "Desk"]])
    }

    func testOnlyASavedNewTaskFromTodaySetsTheLastUsedCategory() throws {
        let current = instant("2026-09-27T12:00:00-04:00")
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let original = note("Original", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [original], categories: [work, home])
        let defaults = isolatedDefaults()
        let state = makeState(store: store, now: { current },
                              preferences: TaskCategoryPreferences(userDefaults: defaults))
        state.startup()
        let preferences = state.categoryPreferences
        XCTAssertNil(preferences.lastUsedCategoryID)

        state.draft = "First"
        state.draftCategoryID = home.id
        XCTAssertTrue(state.addDraft())
        XCTAssertEqual(preferences.lastUsedCategoryID, home.id)
        XCTAssertNil(state.draftCategoryID)

        // Cancelled, rejected, and unavailable drafts leave it unchanged.
        state.draft = "Cancelled"
        state.draftCategoryID = work.id
        state.cancelDraft()
        state.draft = "Rejected"
        state.draftCategoryID = work.id
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        store.failWrite = nil
        state.draftCategoryID = UUID()
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(preferences.lastUsedCategoryID, home.id)

        // Edits and Quick Add's General saves are not new-task choices.
        state.cancelDraft()
        state.beginEditing(id: original.id)
        state.editCategoryID = work.id
        XCTAssertTrue(state.saveEdit())
        XCTAssertEqual(state.add(text: "Captured"), .added)
        XCTAssertEqual(preferences.lastUsedCategoryID, home.id)

        state.draft = "General task"
        XCTAssertTrue(state.addDraft())
        XCTAssertNil(preferences.lastUsedCategoryID)
        XCTAssertNil(defaults.object(forKey: TaskCategoryPreferences.lastUsedCategoryIDKey))

        state.draft = "Work task"
        state.draftCategoryID = work.id
        XCTAssertTrue(state.addDraft())
        XCTAssertEqual(TaskCategoryPreferences(userDefaults: defaults).lastUsedCategoryID, work.id)
    }

    func testNewDraftStartsFromSavedLastUsedCategoryOrGeneral() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let store = FakeNoteRepository(categories: [work])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let preferences = state.categoryPreferences

        // No remembered category starts in General, even with saved categories.
        state.startNewDraft()
        XCTAssertNil(state.draftCategoryID)

        preferences.rememberLastUsed(work.id)
        state.startNewDraft()
        XCTAssertEqual(state.draftCategoryID, work.id)
        state.draft = "General task"
        state.draftCategoryID = nil
        XCTAssertTrue(state.addDraft())
        XCTAssertNil(store.saved.last?.categoryID)

        // A remembered ID missing from the catalog never becomes a selection.
        preferences.rememberLastUsed(UUID())
        state.draftCategoryID = work.id
        state.startNewDraft()
        XCTAssertNil(state.draftCategoryID)

        // Starting a new draft never changes an active edit's selection.
        let task = try XCTUnwrap(store.saved.last)
        preferences.rememberLastUsed(work.id)
        state.beginEditing(id: task.id)
        state.startNewDraft()
        XCTAssertNil(state.editCategoryID)
        XCTAssertEqual(state.draftCategoryID, work.id)
    }

    func testSavedAddOrReassignmentExpandsOnlyItsCollapsedDestination() throws {
        let current = instant("2026-09-27T12:00:00-04:00")
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let general = note("General task", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [general], categories: [work, home])
        let state = makeState(store: store, now: { current })
        state.startup()
        let preferences = state.categoryPreferences
        let all: Set<TaskGroupID> = [.category(work.id), .category(home.id), .general]
        for group in all { preferences.setCollapsed(true, for: group) }

        // Rejected, unavailable, and Quick Add saves change no disclosure.
        state.draft = "Rejected"
        state.draftCategoryID = work.id
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        store.failWrite = nil
        XCTAssertEqual(state.add(text: "Captured"), .added)
        XCTAssertEqual(preferences.collapsedGroupIDs, all)

        XCTAssertTrue(state.addDraft())
        XCTAssertEqual(preferences.collapsedGroupIDs, [.category(home.id), .general])
        let saved = try XCTUnwrap(state.notes.last)
        XCTAssertEqual(saved.categoryID, work.id)

        // A text-only edit leaves its own collapsed group alone.
        state.beginEditing(id: general.id)
        state.editDraft = "General task, edited"
        XCTAssertTrue(state.saveEdit())
        XCTAssertTrue(preferences.isCollapsed(.general))

        state.beginEditing(id: general.id)
        state.editCategoryID = home.id
        store.failWrite = .edit
        XCTAssertFalse(state.saveEdit())
        XCTAssertTrue(preferences.isCollapsed(.category(home.id)))
        store.failWrite = nil
        XCTAssertTrue(state.saveEdit())
        XCTAssertEqual(preferences.collapsedGroupIDs, [.general])
        XCTAssertEqual(groupTexts(state), [["Rejected"], ["General task, edited"], ["Captured"]])

        // Moving a task back into a collapsed General shows General too.
        state.beginEditing(id: saved.id)
        state.editCategoryID = nil
        XCTAssertTrue(state.saveEdit())
        XCTAssertEqual(preferences.collapsedGroupIDs, [])
    }

    func testCategoryPreferencesForgetCategoriesOnlyAfterACompleteReadOrCommittedRemoval() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let missing = UUID()
        let defaults = isolatedDefaults()
        let preferences = TaskCategoryPreferences(userDefaults: defaults)
        preferences.rememberLastUsed(missing)
        let collapsed: Set<TaskGroupID> = [.category(work.id), .category(home.id), .category(missing), .general]
        for group in collapsed { preferences.setCollapsed(true, for: group) }
        let store = FakeNoteRepository(categories: [work, home])
        store.failSnapshotRead = .categories
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") },
                              preferences: preferences)

        // A failed read cannot tell which categories are gone.
        state.startup()
        XCTAssertNil(state.availableCategories)
        XCTAssertEqual(preferences.lastUsedCategoryID, missing)
        XCTAssertEqual(preferences.collapsedGroupIDs, collapsed)

        // A complete read keeps every saved category and General, even with no tasks today.
        store.failSnapshotRead = nil
        state.refresh()
        XCTAssertEqual(state.groups, [])
        XCTAssertNil(preferences.lastUsedCategoryID)
        XCTAssertEqual(preferences.collapsedGroupIDs, [.category(work.id), .category(home.id), .general])

        // Removal forgets a category only after storage commits it.
        preferences.rememberLastUsed(home.id)
        store.failCategoryCommand = .remove
        XCTAssertFalse(state.removeCategory(id: home.id))
        XCTAssertEqual(preferences.lastUsedCategoryID, home.id)
        XCTAssertTrue(preferences.isCollapsed(.category(home.id)))
        store.failCategoryCommand = nil
        XCTAssertTrue(state.removeCategory(id: home.id))
        let reopened = TaskCategoryPreferences(userDefaults: defaults)
        XCTAssertNil(reopened.lastUsedCategoryID)
        XCTAssertEqual(reopened.collapsedGroupIDs, [.category(work.id), .general])
    }

    func testStatusItemObservesSuccessiveSavedWritesWithoutAWindow() async throws {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        var clicks = 0
        let controller = TaskStatusItemController(state: state) { clicks += 1 }
        defer { controller.remove() }
        let button = try XCTUnwrap(controller.statusItem?.button)
        XCTAssertEqual(button.title, "—")
        XCTAssertNil(button.image)
        state.startup()
        try await waitForStatusTitle("0/0", controller: controller)
        state.draft = "First task"
        XCTAssertTrue(state.addDraft())
        try await waitForStatusTitle("0/1", controller: controller)
        let id = try XCTUnwrap(state.notes.first?.id)
        XCTAssertTrue(state.setCompleted(id: id, completed: true))
        try await waitForStatusTitle("1/1", controller: controller)
        XCTAssertEqual(button.accessibilityLabel(), "MenuPocket, today, 1 of 1 tasks completed")
        XCTAssertTrue(state.setCompleted(id: id, completed: false))
        try await waitForStatusTitle("0/1", controller: controller)
        XCTAssertTrue(state.delete(id: id))
        try await waitForStatusTitle("0/0", controller: controller)
        button.performClick(nil)
        button.performClick(nil)
        XCTAssertEqual(clicks, 2)
    }

    func testStatusItemDistinguishesReadFailureRetryAndRejectedWrites() async throws {
        let saved = note("Saved", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [saved])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let controller = TaskStatusItemController(state: state, showTasks: {})
        defer { controller.remove() }
        try await waitForStatusTitle("0/1", controller: controller)
        for failure in [DailyNotesIssue.add, .complete, .delete] {
            store.failWrite = failure
            switch failure {
            case .add:
                state.draft = "Rejected"
                XCTAssertFalse(state.addDraft())
            case .complete: XCTAssertFalse(state.setCompleted(id: saved.id, completed: true))
            case .delete: XCTAssertFalse(state.delete(id: saved.id))
            default: XCTFail("Unexpected fixture failure")
            }
            try await Task.sleep(for: .milliseconds(20))
            XCTAssertEqual(controller.statusItem?.button?.title, "0/1")
        }
        for failure in FakeSnapshotRead.allCases {
            store.failSnapshotRead = failure
            state.refresh()
            try await waitForStatusTitle("—", controller: controller)
            XCTAssertEqual(state.notes, [saved])
            XCTAssertNil(state.availableProgress)
            XCTAssertEqual(state.availableCategories, failure == .categories ? nil : [])
            XCTAssertEqual(state.availableLaterTasks, failure == .categories ? nil : [])
            XCTAssertTrue(controller.statusItem?.button?.accessibilityLabel()?.contains("unavailable") == true)
            store.failSnapshotRead = nil
            store.failWrite = nil
            state.refresh()
            try await waitForStatusTitle("0/1", controller: controller)
        }
    }

    func testStatusItemRefreshesClosedWindowDayAndExactMultiDigitCounts() async throws {
        let saved = (0..<12).map { note("Task \($0)", day: "2026-09-27", createdAt: Double($0), completedAt: Date()) }
        let store = FakeNoteRepository(notes: saved)
        var current = instant("2026-09-27T23:59:00-04:00")
        let center = NotificationCenter()
        let state = DailyNotesState(repositoryFactory: { store }, day: makeDay(now: { current }),
                                    notificationCenter: center, workspaceNotificationCenter: NotificationCenter(),
                                    categoryPreferences: isolatedCategoryPreferences())
        state.startup()
        let controller = TaskStatusItemController(state: state, showTasks: {})
        defer { controller.remove() }
        try await waitForStatusTitle("12/12", controller: controller)
        XCTAssertTrue(controller.statusItem?.button?.toolTip?.contains("12 of 12") == true)
        current = instant("2026-09-28T00:01:00-04:00")
        center.post(name: .NSCalendarDayChanged, object: nil)
        try await waitForStatusTitle("0/0", controller: controller)
        XCTAssertEqual(store.saved, saved)
    }

    func testRemovingStatusItemDoesNotRecreateItOrRetainController() async throws {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        var controller: TaskStatusItemController? = TaskStatusItemController(state: state, showTasks: {})
        weak var releasedController = controller
        state.startup() // Queue an update, then remove before it executes.
        controller?.remove()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(controller?.statusItem)
        state.draft = "After removal"
        XCTAssertTrue(state.addDraft())
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(controller?.statusItem)
        controller = nil
        XCTAssertNil(releasedController)
    }

    func testStatusItemRoutesRightAndControlClicksToADetachedGlance() async throws {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        var clicks = 0
        var builds = 0
        var attachedDuringTracking: [NSMenu?] = []
        weak var weakController: TaskStatusItemController?
        let controller = TaskStatusItemController(
            state: state, showTasks: { clicks += 1 },
            makeGlanceMenu: { builds += 1; return NSMenu(title: "Glance \(builds)") },
            presentGlanceMenu: { _ in
                attachedDuringTracking.append(weakController?.statusItem?.menu)
                // A click that arrives while the menu tracks neither nests nor opens Today.
                weakController?.handlePress(self.mouseEvent(.rightMouseUp))
                weakController?.handlePress(nil)
            }
        )
        weakController = controller
        defer { controller.remove() }
        let button = try XCTUnwrap(controller.statusItem?.button)

        controller.handlePress(mouseEvent(.rightMouseUp))
        controller.handlePress(mouseEvent(.leftMouseUp, modifiers: .control))
        XCTAssertEqual(builds, 2)
        XCTAssertEqual(attachedDuringTracking.map { $0?.title }, ["Glance 1", "Glance 2"])
        XCTAssertNil(controller.statusItem?.menu)
        XCTAssertEqual(clicks, 0)

        controller.handlePress(mouseEvent(.leftMouseUp))
        controller.handlePress(nil)
        button.performClick(nil)
        XCTAssertEqual(clicks, 3)
        XCTAssertEqual(builds, 2)
        XCTAssertNil(controller.statusItem?.menu)

        // The right-mouse-up bit is added to the primary click's original mask.
        let plain = TaskStatusItemController(state: state, showTasks: {})
        defer { plain.remove() }
        let plainButton = try XCTUnwrap(plain.statusItem?.button)
        let plainMask = plainButton.sendAction(on: .leftMouseUp)
        plainButton.sendAction(on: NSEvent.EventTypeMask(rawValue: UInt64(plainMask)))
        let mask = button.sendAction(on: .leftMouseUp)
        button.sendAction(on: NSEvent.EventTypeMask(rawValue: UInt64(mask)))
        XCTAssertEqual(UInt64(mask), NSEvent.EventTypeMask(rawValue: UInt64(plainMask)).union(.rightMouseUp).rawValue)

        // Tooltips mention the quick look only when the glance exists; the label is unchanged.
        let hint = "Right-click for a quick look."
        XCTAssertEqual(button.toolTip, "MenuPocket, today's tasks are unavailable. Open the task window to load or retry. \(hint)")
        XCTAssertFalse(plainButton.toolTip?.contains(hint) == true)
        state.startup()
        try await waitForStatusTitle("0/0", controller: controller)
        XCTAssertEqual(button.toolTip, "MenuPocket, today, 0 of 0 tasks completed. Click to show tasks. \(hint)")
        XCTAssertEqual(button.accessibilityLabel(), "MenuPocket, today, 0 of 0 tasks completed")
        XCTAssertFalse(plainButton.toolTip?.contains(hint) == true)

        // VoiceOver reaches the glance through a custom action on the button.
        let actions = try XCTUnwrap(button.accessibilityCustomActions())
        XCTAssertEqual(actions.map(\.name), ["Show quick look"])
        XCTAssertTrue(actions.first?.target === controller)
        XCTAssertNil(plainButton.accessibilityCustomActions()?.first)
    }

    func testRemovingStatusItemWhileTheGlanceTracksLeavesNoMenu() throws {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        weak var weakController: TaskStatusItemController?
        var clicks = 0
        var removedItem: NSStatusItem?
        var nestedResult: Bool?
        let controller = TaskStatusItemController(
            state: state, showTasks: { clicks += 1 }, makeGlanceMenu: { NSMenu(title: "Tracked") },
            presentGlanceMenu: { _ in
                removedItem = weakController?.statusItem
                XCTAssertEqual(removedItem?.menu?.title, "Tracked")
                nestedResult = weakController?.showGlance()
                weakController?.remove()
            }
        )
        weakController = controller
        defer { controller.remove() }
        XCTAssertTrue(controller.showGlance())
        XCTAssertEqual(nestedResult, false, "A glance already tracking is not presented again")
        XCTAssertNotNil(removedItem)
        XCTAssertNil(removedItem?.menu, "The removed item keeps no menu")
        XCTAssertNil(controller.statusItem)
        XCTAssertFalse(controller.showGlance())
        controller.handlePress(nil)
        XCTAssertEqual(clicks, 1)
        XCTAssertNil(controller.statusItem)

        // A provider with nothing to show reports that no glance appeared.
        var presented = false
        let empty = TaskStatusItemController(state: state, showTasks: {}, makeGlanceMenu: { nil },
                                             presentGlanceMenu: { _ in presented = true })
        defer { empty.remove() }
        XCTAssertFalse(empty.showGlance())
        XCTAssertFalse(presented)
        XCTAssertNil(empty.statusItem?.menu)
    }

    private func mouseEvent(_ type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags = []) -> NSEvent? {
        NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    }

    private func waitForStatusTitle(_ title: String, controller: TaskStatusItemController) async throws {
        for _ in 0..<100 {
            if controller.statusItem?.button?.title == title { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(controller.statusItem?.button?.title, title)
    }

    func testRefreshAndReopenPublishSavedDailySnapshot() {
        let today = note("Today", day: "2026-09-27", createdAt: 2)
        let finished = note("Finished", day: "2026-09-27", createdAt: 3,
                            completedAt: Date(timeIntervalSince1970: 4))
        let yesterday = note("Yesterday", day: "2026-09-26", createdAt: 1)
        let store = FakeNoteRepository(notes: [today, finished, yesterday])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })

        state.windowWillOpen()
        XCTAssertEqual(state.notes, [today, finished])
        XCTAssertEqual(state.progress, NoteProgress(completed: 1, total: 2))
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        XCTAssertNil(state.issue)

        let newest = note("New", day: "2026-09-27", createdAt: 5)
        store.saved.append(newest)
        state.windowWillOpen()
        XCTAssertEqual(state.notes, [today, finished, newest])
        XCTAssertEqual(state.progress, NoteProgress(completed: 1, total: 3))
    }

    func testDayChangeMovesOldNotesIntoYesterdayCountWithoutCarryover() {
        let previous = note("Unfinished", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [previous])
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = makeState(store: store, now: { current })

        state.windowWillOpen()
        XCTAssertEqual(state.notes, [previous])
        state.draft = "Keep this draft"
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        state.beginEditing(id: previous.id)
        current = instant("2026-09-28T00:01:00-04:00")
        state.refreshIfDayChanged()
        XCTAssertEqual(state.todayKey, "2026-09-28")
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertEqual(state.progress, NoteProgress(completed: 0, total: 0))
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        XCTAssertEqual(state.draft, "Keep this draft")
        XCTAssertEqual(state.taskIssue, .add)
        XCTAssertNil(state.editingNoteID)
        XCTAssertEqual(state.editDraft, "")
    }

    func testCalendarNotificationRefreshesObservableDay() async throws {
        let category = try TaskCategory(name: "Reusable", creationOrder: 0)
        let store = FakeNoteRepository(categories: [category])
        let center = NotificationCenter()
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = DailyNotesState(repositoryFactory: { store }, day: makeDay(now: { current }),
                                    notificationCenter: center, categoryPreferences: isolatedCategoryPreferences())
        state.windowWillOpen()
        let changed = expectation(description: "Observable day changed")
        withObservationTracking {
            _ = state.todayKey
        } onChange: {
            changed.fulfill()
        }

        current = instant("2026-09-28T00:01:00-04:00")
        center.post(name: .NSCalendarDayChanged, object: nil)
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(state.todayKey, "2026-09-28")
        XCTAssertEqual(state.availableCategories, [category])
    }

    func testReadFailureDoesNotPublishPartialSnapshotOrOldDayAsToday() {
        let old = note("Old", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [old])
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = makeState(store: store, now: { current })
        state.windowWillOpen()

        store.failCount = true
        state.refresh()
        XCTAssertEqual(state.notes, [old])
        XCTAssertEqual(state.yesterdayIncompleteCount, 0)
        XCTAssertEqual(state.issue, .load)

        current = instant("2026-09-28T00:01:00-04:00")
        state.refreshIfDayChanged()
        XCTAssertEqual(state.todayKey, "2026-09-28")
        XCTAssertFalse(state.hasLoadedToday)
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertEqual(state.yesterdayIncompleteCount, 0)
        XCTAssertEqual(state.issue, .load)

        store.failCount = false
        state.windowWillOpen()
        XCTAssertTrue(state.hasLoadedToday)
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        XCTAssertNil(state.issue)
    }

    func testOpenFailureCanBeRetried() {
        let store = FakeNoteRepository()
        var shouldFail = true
        let state = DailyNotesState(repositoryFactory: {
            if shouldFail { throw FakeFailure.failed }
            return store
        }, day: makeDay(now: { self.instant("2026-09-27T12:00:00-04:00") }),
        notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter(),
        categoryPreferences: isolatedCategoryPreferences())

        state.windowWillOpen()
        XCTAssertEqual(state.issue, .load)
        XCTAssertFalse(state.hasLoadedToday)
        shouldFail = false
        state.windowWillOpen()
        XCTAssertTrue(state.hasLoadedToday)
        XCTAssertNil(state.issue)
    }

    func testFailedAddKeepsDraftAndSuccessfulRetryPublishesOnlySavedNote() {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.windowWillOpen()
        state.draft = "  Book dentist  "
        store.failWrite = .add

        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(state.draft, "  Book dentist  ")
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertEqual(state.issue, .add)

        store.failWrite = nil
        XCTAssertTrue(state.addDraft())
        XCTAssertEqual(state.notes.map(\.text), ["Book dentist"])
        XCTAssertEqual(store.saved, state.notes)
        XCTAssertEqual(state.draft, "")
        XCTAssertNil(state.issue)

        state.draft = "  \n "
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(store.saved.count, 1)
    }

    func testCancelNewDraftClearsFailedAddWithoutChangingSavedTasks() {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.windowWillOpen()
        state.draft = "Retry or discard"
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        state.windowWillOpen()
        XCTAssertEqual(state.draft, "Retry or discard")
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(state.issue, .add)
        state.cancelDraft()
        XCTAssertEqual(state.draft, "")
        XCTAssertNil(state.issue)
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 0))
    }

    func testIndependentAddReportsOutcomesWithoutChangingWindowDraftOrIssue() {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "Half-typed window task"
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(state.issue, .add)

        XCTAssertEqual(state.add(text: "Rejected panel task"), .writeFailed)
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 0))

        store.failWrite = nil
        XCTAssertEqual(state.add(text: "  \n "), .empty)
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertEqual(state.add(text: "  Panel task  "), .added)
        XCTAssertEqual(state.notes.map(\.text), ["Panel task"])
        XCTAssertEqual(state.notes.first?.dayKey, "2026-09-27")
        XCTAssertNil(state.notes.first?.categoryID)
        XCTAssertEqual(store.saved, state.notes)
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 1))
        XCTAssertEqual(state.draft, "Half-typed window task")
        XCTAssertEqual(state.issue, .add)
    }

    func testIndependentAddIsUnavailableWhenSavedDataCannotBeRead() {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        store.failCount = true
        state.refresh()
        XCTAssertEqual(state.add(text: "Unavailable"), .unavailable)
        XCTAssertTrue(store.saved.isEmpty)

        let unopened = DailyNotesState(repositoryFactory: { throw FakeFailure.failed },
                                       day: makeDay(now: { self.instant("2026-09-27T12:00:00-04:00") }),
                                       notificationCenter: NotificationCenter(),
                                       workspaceNotificationCenter: NotificationCenter())
        XCTAssertEqual(unopened.add(text: "Never loaded"), .unavailable)
        XCTAssertTrue(unopened.notes.isEmpty)

        // An unloaded state becomes ready through the same one refresh as Add task.
        store.failCount = false
        let unloaded = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        XCTAssertEqual(unloaded.add(text: "Loads first"), .added)
        XCTAssertEqual(store.saved.map(\.text), ["Loads first"])
    }

    func testIndependentAddKeepsEditTargetAndDeletionConfirmation() {
        let edited = note("Being edited", day: "2026-09-27", createdAt: 1)
        let target = note("Delete me", day: "2026-09-27", createdAt: 2)
        let store = FakeNoteRepository(notes: [edited, target])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        let presentation = TaskWindowPresentation()
        state.startup()
        state.draft = "Window draft"
        presentation.requestDeletion(id: target.id, state: state)
        // Simulate retained contexts directly; UI guards prevent opening a
        // deletion confirmation over an edit. Independent capture preserves both.
        state.beginEditing(id: edited.id)
        state.editDraft = "Unsaved edit"

        XCTAssertEqual(state.add(text: "Captured"), .added)
        XCTAssertEqual(state.editingNoteID, edited.id)
        XCTAssertEqual(state.editDraft, "Unsaved edit")
        XCTAssertEqual(state.draft, "Window draft")
        XCTAssertNil(state.issue)
        XCTAssertNil(state.refreshNotice)
        presentation.validateDeletion(state: state)
        XCTAssertEqual(presentation.deletionTarget?.id, target.id)

        XCTAssertTrue(presentation.confirmDeletion(state: state))
        XCTAssertTrue(state.saveEdit())
        XCTAssertEqual(state.notes.map(\.text), ["Unsaved edit", "Captured"])
        XCTAssertEqual(store.saved, state.notes)
    }

    func testAddDraftAndIndependentAddSaveIdenticalNotes() {
        let current = instant("2026-09-27T12:00:00-04:00")
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { current })
        state.startup()
        state.draft = "  Same task  "
        XCTAssertTrue(state.addDraft())
        XCTAssertEqual(state.add(text: "  Same task  "), .added)

        XCTAssertEqual(store.saved.count, 2)
        for saved in store.saved {
            XCTAssertEqual(saved.text, "Same task")
            XCTAssertEqual(saved.dayKey, "2026-09-27")
            XCTAssertEqual(saved.createdAt, current)
            XCTAssertNil(saved.completedAt)
            XCTAssertNil(saved.categoryID)
        }
        XCTAssertNotEqual(store.saved[0].id, store.saved[1].id)

        // Empty input keeps the window's earlier write error, as before.
        store.failWrite = .add
        state.draft = "Rejected"
        XCTAssertFalse(state.addDraft())
        state.draft = "   "
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(state.issue, .add)
        XCTAssertEqual(state.draft, "   ")
    }

    func testBlankEditAndCancellationKeepSavedTaskAndSeparateNewDraft() {
        let original = note("Original", day: "2026-09-27", createdAt: 1,
                            completedAt: Date(timeIntervalSince1970: 2))
        let store = FakeNoteRepository(notes: [original])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "Separate new task"
        state.beginEditing(id: original.id)
        state.editDraft = "  \n "
        XCTAssertFalse(state.saveEdit())
        XCTAssertEqual(store.saved, [original])
        state.editDraft = "Unsaved correction"
        store.failWrite = .edit
        XCTAssertFalse(state.saveEdit())
        XCTAssertEqual(state.issue, .edit)
        state.cancelEditing()
        XCTAssertNil(state.editingNoteID)
        XCTAssertEqual(state.editDraft, "")
        XCTAssertNil(state.issue)
        XCTAssertEqual(state.draft, "Separate new task")
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(store.saved, [original])
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 1, total: 1))
    }

    func testFailedCompletionEditAndDeleteNeverChangeSavedDisplay() {
        let original = note("Original", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [original])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.windowWillOpen()

        store.failWrite = .complete
        XCTAssertFalse(state.setCompleted(id: original.id, completed: true))
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(state.progress, NoteProgress(completed: 0, total: 1))
        XCTAssertEqual(state.issue, .complete)

        state.beginEditing(id: original.id)
        state.editDraft = "  Corrected  "
        store.failWrite = .edit
        XCTAssertFalse(state.saveEdit())
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(state.editDraft, "  Corrected  ")
        XCTAssertEqual(state.editingNoteID, original.id)
        XCTAssertEqual(state.issue, .edit)

        store.failWrite = .delete
        XCTAssertFalse(state.delete(id: original.id))
        XCTAssertEqual(state.notes, [original])
        XCTAssertEqual(state.editDraft, "  Corrected  ")
        XCTAssertEqual(state.issue, .delete)

        store.failWrite = nil
        XCTAssertTrue(state.saveEdit())
        XCTAssertEqual(state.notes.map(\.text), ["Corrected"])
        XCTAssertTrue(state.setCompleted(id: original.id, completed: true))
        XCTAssertEqual(state.progress, NoteProgress(completed: 1, total: 1))
        XCTAssertTrue(state.delete(id: original.id))
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertTrue(store.saved.isEmpty)
    }

    func testFixedInsertionOrderSurvivesTaskChangesAndFreshStateWithSQLite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DailyNotesStateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("notes.sqlite")
        var current = instant("2026-09-27T12:00:00-04:00")
        let makeState = {
            DailyNotesState(
                repositoryFactory: { try SQLiteNoteRepository(databaseURL: databaseURL) },
                day: self.makeDay(now: { current }),
                notificationCenter: NotificationCenter(),
                categoryPreferences: self.isolatedCategoryPreferences()
            )
        }

        let firstSession = makeState()
        firstSession.windowWillOpen()
        firstSession.draft = "  First note  "
        XCTAssertTrue(firstSession.addDraft())
        firstSession.draft = "Second note"
        XCTAssertTrue(firstSession.addDraft())
        // Equal timestamps and a clock adjustment must not affect insertion order.
        current = current.addingTimeInterval(-60)
        firstSession.draft = "Third note"
        XCTAssertTrue(firstSession.addDraft())
        XCTAssertEqual(firstSession.notes.map(\.text), ["First note", "Second note", "Third note"])
        let originalIDs = firstSession.notes.map(\.id)
        let firstID = try XCTUnwrap(firstSession.notes.first(where: { $0.text == "First note" })?.id)
        XCTAssertTrue(firstSession.setCompleted(id: firstID, completed: true))
        XCTAssertEqual(firstSession.progress, NoteProgress(completed: 1, total: 3))
        XCTAssertEqual(firstSession.notes.map(\.id), originalIDs)
        firstSession.refresh()
        XCTAssertEqual(firstSession.notes.map(\.id), originalIDs)

        let secondSession = makeState()
        secondSession.windowWillOpen()
        XCTAssertEqual(secondSession.notes.map(\.id), originalIDs)
        XCTAssertEqual(secondSession.progress, NoteProgress(completed: 1, total: 3))
        XCTAssertTrue(secondSession.notes.first?.isCompleted == true)
        XCTAssertTrue(secondSession.setCompleted(id: firstID, completed: false))
        XCTAssertEqual(secondSession.notes.map(\.id), originalIDs)

        let thirdSession = makeState()
        thirdSession.windowWillOpen()
        XCTAssertEqual(thirdSession.progress, NoteProgress(completed: 0, total: 3))
        XCTAssertEqual(thirdSession.notes.map(\.id), originalIDs)
        XCTAssertFalse(try XCTUnwrap(thirdSession.notes.first(where: { $0.id == firstID })).isCompleted)
        thirdSession.beginEditing(id: firstID)
        thirdSession.editDraft = "  Updated note  "
        XCTAssertTrue(thirdSession.saveEdit())
        XCTAssertEqual(thirdSession.notes.map(\.id), originalIDs)
        let secondID = try XCTUnwrap(thirdSession.notes.first(where: { $0.text == "Second note" })?.id)
        XCTAssertTrue(thirdSession.delete(id: secondID))
        XCTAssertEqual(thirdSession.notes.map(\.id), [originalIDs[0], originalIDs[2]])
        thirdSession.draft = "Fourth note"
        XCTAssertTrue(thirdSession.addDraft())
        XCTAssertEqual(thirdSession.notes.map(\.text), ["Updated note", "Third note", "Fourth note"])

        let fourthSession = makeState()
        fourthSession.windowWillOpen()
        XCTAssertEqual(fourthSession.notes, thirdSession.notes)
        XCTAssertEqual(fourthSession.progress, NoteProgress(completed: 0, total: 3))
        XCTAssertEqual(fourthSession.notes.first?.id, firstID)
    }

    func testSQLiteBackedTextEditPreservesCategoryThroughCompletionRefreshAndReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DailyNotesStateCategories-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("notes.sqlite")
        let current = instant("2026-09-27T12:00:00-04:00")
        let original: Note
        do {
            let store = try SQLiteNoteRepository(databaseURL: databaseURL)
            let category = try store.createCategory(name: "Work")
            original = Note(id: UUID(), text: "Original", dayKey: "2026-09-27",
                            createdAt: current, completedAt: nil, categoryID: category.id)
            try store.add(original)
        }
        let makeState = {
            DailyNotesState(repositoryFactory: { try SQLiteNoteRepository(databaseURL: databaseURL) },
                            day: self.makeDay(now: { current }),
                            notificationCenter: NotificationCenter(),
                            workspaceNotificationCenter: NotificationCenter(),
                            categoryPreferences: self.isolatedCategoryPreferences())
        }
        do {
            let state = makeState()
            state.startup()
            XCTAssertEqual(state.notes, [original])
            XCTAssertTrue(state.setCompleted(id: original.id, completed: true))
            state.beginEditing(id: original.id)
            state.editDraft = "  Updated  "
            XCTAssertTrue(state.saveEdit())
            state.refresh()
            XCTAssertEqual(state.notes.first?.categoryID, original.categoryID)
            XCTAssertEqual(state.notes.first?.text, "Updated")
            XCTAssertEqual(state.progress, NoteProgress(completed: 1, total: 1))
        }
        let reopened = makeState()
        reopened.startup()
        XCTAssertEqual(reopened.notes, [
            Note(id: original.id, text: "Updated", dayKey: original.dayKey,
                 createdAt: original.createdAt, completedAt: current, categoryID: original.categoryID)
        ])
        XCTAssertTrue(reopened.setCompleted(id: original.id, completed: false))
        reopened.refresh()
        XCTAssertEqual(reopened.notes.first?.categoryID, original.categoryID)
        XCTAssertEqual(reopened.progress, NoteProgress(completed: 0, total: 1))
    }

    func testAvailabilityDistinguishesEmptyReadFailureAndRejectedWrite() {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        XCTAssertNil(state.availableProgress)
        state.startup()
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 0))
        state.draft = "Unsaved"
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 0))
        store.failCount = true
        state.refresh()
        XCTAssertNil(state.availableProgress)
        XCTAssertFalse(state.hasLoadedToday)
        XCTAssertFalse(state.addDraft())
        XCTAssertTrue(store.saved.isEmpty)
        store.failCount = false
        store.failWrite = nil
        state.refresh()
        XCTAssertTrue(state.addDraft())
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 1))
    }

    func testWakeAndClockNotificationsRefreshWithoutOpeningWindow() async throws {
        let old = note("Yesterday", day: "2026-09-27", createdAt: 1)
        let category = try TaskCategory(name: "Reusable", creationOrder: 0)
        let store = FakeNoteRepository(notes: [old], categories: [category])
        let center = NotificationCenter()
        let workspace = NotificationCenter()
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = DailyNotesState(repositoryFactory: { store }, day: makeDay(now: { current }),
                                    notificationCenter: center, workspaceNotificationCenter: workspace,
                                    categoryPreferences: isolatedCategoryPreferences())
        state.startup()
        for (eventCenter, name) in [(workspace, NSWorkspace.didWakeNotification),
                                    (center, Notification.Name.NSSystemClockDidChange)] {
            let changed = expectation(description: "Closed-window event refreshed day")
            withObservationTracking { _ = state.todayKey } onChange: { changed.fulfill() }
            current = current.addingTimeInterval(86400)
            store.savedCategories.append(try TaskCategory(name: "Day \(current.timeIntervalSince1970)",
                                                         creationOrder: Int64(store.savedCategories.count)))
            eventCenter.post(name: name, object: nil)
            await fulfillment(of: [changed], timeout: 2)
            XCTAssertEqual(state.todayKey, makeDay(now: { current }).keys().today)
            XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 0))
            XCTAssertEqual(state.availableCategories, store.savedCategories)
        }
    }

    func testTimeZoneNotificationRecalculatesDayWithoutReassigningSavedRows() async throws {
        let saved = note("Assigned day", day: "2026-09-26", createdAt: 1)
        let category = try TaskCategory(name: "Reusable", creationOrder: 0)
        let store = FakeNoteRepository(notes: [saved], categories: [category])
        let center = NotificationCenter()
        var zone = TimeZone(identifier: "America/Toronto")!
        let day = NoteDay(now: { self.instant("2026-09-27T00:30:00Z") }, timeZone: { zone })
        let state = DailyNotesState(repositoryFactory: { store }, day: day,
                                    notificationCenter: center, workspaceNotificationCenter: NotificationCenter(),
                                    categoryPreferences: isolatedCategoryPreferences())
        state.startup()
        XCTAssertEqual(state.notes, [saved])
        let changed = expectation(description: "Time-zone refresh")
        withObservationTracking { _ = state.todayKey } onChange: { changed.fulfill() }
        zone = TimeZone(secondsFromGMT: 0)!
        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(state.todayKey, "2026-09-27")
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        XCTAssertEqual(store.saved, [saved])
        XCTAssertEqual(state.availableCategories, [category])
    }

    func testRolloverCancelsStaleActionsAndRecoversEditEvenWhenReadFails() {
        let old = note("Original", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [old])
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = makeState(store: store, now: { current })
        state.startup()
        state.beginEditing(id: old.id)
        state.editDraft = "Recover my changes"
        state.draft = "New draft"
        current = instant("2026-09-28T00:01:00-04:00")
        store.failCount = true
        XCTAssertFalse(state.saveEdit())
        XCTAssertNil(state.editingNoteID)
        XCTAssertEqual(state.recoveredEditDraft, "Recover my changes")
        XCTAssertNotNil(state.refreshNotice)
        XCTAssertNil(state.availableProgress)
        XCTAssertTrue(state.notes.isEmpty)
        XCTAssertFalse(state.delete(id: old.id))
        XCTAssertFalse(state.setCompleted(id: old.id, completed: true))
        XCTAssertEqual(store.saved, [old])
        store.failCount = false
        XCTAssertTrue(state.addDraft())
        XCTAssertEqual(store.saved.first(where: { $0.text == "New draft" })?.dayKey, "2026-09-28")
        XCTAssertEqual(store.saved.first(where: { $0.id == old.id }), old)
    }

    func testSameDayRefreshKeepsEditOrRecoversRemovedTarget() {
        let original = note("Original", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [original])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.beginEditing(id: original.id)
        state.editDraft = "Recover me"
        state.windowWillOpen()
        XCTAssertEqual(state.editingNoteID, original.id)
        XCTAssertEqual(state.editDraft, "Recover me")
        store.saved = []
        state.refresh()
        XCTAssertNil(state.editingNoteID)
        XCTAssertEqual(state.recoveredEditDraft, "Recover me")
        XCTAssertNotNil(state.refreshNotice)
        XCTAssertFalse(state.saveEdit())
    }

    func testRolloverClearsOldProgressBeforeRepositoryReadAndRejectsPendingDelete() {
        let old = note("Yesterday", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [old])
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = makeState(store: store, now: { current })
        state.startup()
        current = instant("2026-09-28T00:01:00-04:00")
        store.onRead = { key in
            XCTAssertEqual(key, "2026-09-28")
            XCTAssertEqual(state.todayKey, key)
            XCTAssertNil(state.availableProgress)
            XCTAssertTrue(state.notes.isEmpty)
        }
        XCTAssertFalse(state.delete(id: old.id))
        XCTAssertEqual(store.saved, [old])
        XCTAssertEqual(state.yesterdayIncompleteCount, 1)
        store.onRead = nil
    }

    func testObserversDoNotRetainReleasedStateOrRefreshAfterRelease() async {
        let store = FakeNoteRepository()
        let center = NotificationCenter()
        let workspace = NotificationCenter()
        var state: DailyNotesState? = DailyNotesState(repositoryFactory: { store },
            day: makeDay(now: { self.instant("2026-09-27T12:00:00-04:00") }),
            notificationCenter: center, workspaceNotificationCenter: workspace,
            categoryPreferences: isolatedCategoryPreferences())
        state?.startup()
        weak var released = state
        state = nil
        XCTAssertNil(released)
        store.onRead = { _ in XCTFail("Released state should not read") }
        center.post(name: .NSCalendarDayChanged, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        await Task.yield()
    }

    func testMovePublishesCommittedSnapshotAndOnlyExpandsDestination() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let source = note("Done", day: "2026-09-27", createdAt: 1, completedAt: Date())
        let anchor = Note(id: UUID(), text: "Work", dayKey: source.dayKey,
                          createdAt: Date(), completedAt: nil, categoryID: work.id)
        let store = FakeNoteRepository(notes: [source, anchor], categories: [work])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "Pending new task"
        state.draftCategoryID = work.id
        state.beginEditing(id: anchor.id)
        state.editDraft = "Recovery text"
        store.saved.removeAll { $0.id == anchor.id }
        state.refresh()
        state.editDraft = "Unowned edit draft"
        state.editCategoryID = work.id
        let recovery = state.recoveredEdit
        state.categoryPreferences.rememberLastUsed(work.id)
        state.categoryPreferences.setCollapsed(true, for: .general)
        state.categoryPreferences.setCollapsed(true, for: .category(work.id))
        let progress = state.availableProgress
        store.onMove = {
            XCTAssertEqual(state.notes, [source], "No proposal published before commit")
            XCTAssertTrue(state.categoryPreferences.isCollapsed(.category(work.id)))
        }
        let request = moveRequest(source, destination: .category(work.id))
        let outcome = state.moveTask(request)
        guard case let .changed(saved) = outcome else { return XCTFail("Expected saved change") }
        XCTAssertEqual(state.notes, saved)
        XCTAssertEqual(state.notes.map(\.id), [source.id])
        XCTAssertEqual(state.notes.first?.categoryID, work.id)
        XCTAssertEqual(state.availableProgress, progress)
        XCTAssertEqual(state.notes.first?.completedAt, source.completedAt)
        XCTAssertEqual(state.notes.first?.createdAt, source.createdAt)
        XCTAssertEqual(state.notes.first?.text, source.text)
        XCTAssertEqual(state.draft, "Pending new task")
        XCTAssertEqual(state.draftCategoryID, work.id)
        XCTAssertEqual(state.editDraft, "Unowned edit draft")
        XCTAssertEqual(state.editCategoryID, work.id)
        XCTAssertEqual(state.recoveredEdit, recovery)
        XCTAssertEqual(state.categoryPreferences.lastUsedCategoryID, work.id)
        XCTAssertEqual(state.categoryPreferences.collapsedGroupIDs, [.general])
        XCTAssertNil(state.taskIssue)
    }

    func testMoveFailureRetryAndReadRecoveryKeepDistinctIssues() {
        let a = note("A", day: "2026-09-27", createdAt: 1)
        let b = note("B", day: a.dayKey, createdAt: 2)
        let store = FakeNoteRepository(notes: [a, b])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "Keep"
        state.editDraft = "Also keep"
        state.categoryPreferences.setCollapsed(true, for: .general)
        let request = moveRequest(a)
        store.failWrite = .move
        let failedRevision = state.historyRevision
        XCTAssertNil(state.moveTask(request))
        XCTAssertEqual(state.historyRevision, failedRevision)
        XCTAssertEqual(state.notes, [a, b])
        XCTAssertEqual(state.taskIssue, .move)
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 2))
        store.failSnapshotRead = .notes
        state.refresh()
        let attempts = store.moveAttempts
        XCTAssertFalse(state.taskWindowPresentation.canMoveTask(state: state))
        XCTAssertNil(state.moveTask(request))
        XCTAssertEqual(store.moveAttempts, attempts)
        XCTAssertEqual(state.issue, .load)
        XCTAssertEqual(state.taskIssue, .move)
        store.failSnapshotRead = nil
        state.refresh()
        XCTAssertEqual(state.issue, .move)
        XCTAssertEqual(state.notes, [a, b])
        XCTAssertEqual(state.draft, "Keep")
        XCTAssertEqual(state.editDraft, "Also keep")
        XCTAssertTrue(state.categoryPreferences.isCollapsed(.general))
        store.failWrite = nil
        XCTAssertEqual(state.moveTask(request), .changed([b, a]))
        XCTAssertEqual(state.notes, [b, a])
        XCTAssertNil(state.issue)
    }

    func testMoveGuardsRevalidateEditDeletionManagerAndTermination() {
        let a = note("A", day: "2026-09-27", createdAt: 1)
        let b = note("B", day: a.dayKey, createdAt: 2)
        let store = FakeNoteRepository(notes: [a, b])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        let presentation = state.taskWindowPresentation
        let request = moveRequest(a)
        XCTAssertTrue(presentation.canMoveTask(state: state))
        state.beginEditing(id: a.id)
        state.editDraft = "Unsaved edit"
        XCTAssertFalse(presentation.canMoveTask(state: state))
        XCTAssertNil(state.moveTask(request))
        XCTAssertEqual(state.editDraft, "Unsaved edit")
        state.cancelEditing()
        presentation.requestDeletion(id: b.id, state: state)
        XCTAssertFalse(presentation.canMoveTask(state: state))
        XCTAssertNil(state.moveTask(request))
        presentation.cancelDeletion()
        XCTAssertTrue(presentation.showCategoryManager(state: state))
        XCTAssertFalse(presentation.canMoveTask(state: state))
        XCTAssertNil(state.moveTask(request))
        presentation.dismissCategoryManager()
        state.stopForTermination()
        XCTAssertFalse(presentation.canMoveTask(state: state))
        XCTAssertNil(state.moveTask(request))
        XCTAssertEqual(store.moveAttempts, 0)
        XCTAssertEqual(state.notes, [a, b])
    }

    func testMoveUnchangedAndStaleRequestsPreserveSnapshotAndCollapse() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let a = note("A", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [a], categories: [work])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "Draft"
        state.editDraft = "Edit draft"
        state.categoryPreferences.setCollapsed(true, for: .general)
        state.categoryPreferences.setCollapsed(true, for: .category(work.id))
        let collapsed = state.categoryPreferences.collapsedGroupIDs
        let revision = state.historyRevision
        XCTAssertEqual(state.moveTask(moveRequest(a)), .unchanged)
        let missing = note("Missing", day: a.dayKey, createdAt: 2)
        XCTAssertEqual(state.moveTask(moveRequest(missing)), .rejected(.taskNotFound))
        XCTAssertEqual(state.moveTask(moveRequest(a, destination: .category(UUID()))),
                       .rejected(.destinationNotFound))
        let wrongSource = TaskMoveRequest(taskID: a.id, expectedDayKey: a.dayKey,
                                         expectedSourceGroup: .category(work.id),
                                         destinationGroup: .general, placement: .endOfGroup)
        XCTAssertEqual(state.moveTask(wrongSource), .rejected(.sourceChanged))
        XCTAssertEqual(state.moveTask(moveRequest(a, placement: .before(UUID()))), .rejected(.invalidAnchor))
        // Storage sees a removal that the displayed snapshot has not seen yet.
        store.savedCategories = []
        XCTAssertEqual(state.moveTask(moveRequest(a, destination: .category(work.id))),
                       .rejected(.destinationNotFound))
        store.saved = []
        XCTAssertEqual(state.moveTask(moveRequest(a)), .rejected(.taskNotFound))
        XCTAssertEqual(state.historyRevision, revision)
        XCTAssertEqual(state.notes, [a])
        XCTAssertEqual(state.draft, "Draft")
        XCTAssertEqual(state.editDraft, "Edit draft")
        XCTAssertEqual(state.categoryPreferences.collapsedGroupIDs, collapsed)
    }

    func testMoveRolloverRejectsPayloadEvenAfterNewDayRefresh() {
        let a = note("A", day: "2026-09-27", createdAt: 1)
        let store = FakeNoteRepository(notes: [a])
        var current = instant("2026-09-27T23:59:00-04:00")
        let state = makeState(store: store, now: { current })
        state.startup()
        state.draft = "Keep new"
        state.beginEditing(id: a.id)
        state.editDraft = "Keep recovered"
        let request = moveRequest(a)
        current = instant("2026-09-28T00:01:00-04:00")
        XCTAssertFalse(state.taskWindowPresentation.canMoveTask(state: state))
        XCTAssertEqual(state.moveTask(request), .rejected(.dayChanged))
        XCTAssertEqual(state.todayKey, "2026-09-28")
        XCTAssertEqual(state.moveTask(request), .rejected(.dayChanged))
        XCTAssertEqual(state.recoveredEditDraft, "Keep recovered")
        XCTAssertEqual(state.draft, "Keep new")
        XCTAssertEqual(store.moveAttempts, 0)
        XCTAssertEqual(store.saved, [a])
    }

    func testSQLiteStateMovePersistsOnRefreshAndReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StateMove-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.sqlite")
        let store = try SQLiteNoteRepository(databaseURL: url)
        let category = try store.createCategory(name: "Work")
        let a = note("A", day: "2026-09-27", createdAt: 1)
        let b = note("B", day: a.dayKey, createdAt: 2)
        try store.add(a)
        try store.add(b)
        let state = DailyNotesState(repositoryFactory: { store },
                                   day: makeDay(now: { self.instant("2026-09-27T12:00:00-04:00") }),
                                   notificationCenter: NotificationCenter(),
                                   workspaceNotificationCenter: NotificationCenter(),
                                   categoryPreferences: isolatedCategoryPreferences())
        state.startup()
        guard case .changed = state.moveTask(moveRequest(a, destination: .category(category.id))) else {
            return XCTFail("Expected committed move")
        }
        let saved = state.notes
        state.refresh()
        XCTAssertEqual(state.notes, saved)
        XCTAssertEqual(try SQLiteNoteRepository(databaseURL: url).notes(for: a.dayKey), saved)
        XCTAssertEqual(saved.map(\.id), [b.id, a.id])
        XCTAssertEqual(saved.last?.categoryID, category.id)
    }

    /// Task 9 integration: menu and drop-shaped requests through SQLite-backed
    /// state, then the existing daily writes, across refresh and fresh reopens.
    func testIntegratedSQLiteMovementSurvivesReopenAndLaterDailyWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IntegratedMove-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.sqlite")
        let defaults = isolatedDefaults()
        let makeState = {
            DailyNotesState(repositoryFactory: { try SQLiteNoteRepository(databaseURL: url) },
                            day: self.makeDay(now: { self.instant("2026-09-27T12:00:00-04:00") }),
                            notificationCenter: NotificationCenter(),
                            workspaceNotificationCenter: NotificationCenter(),
                            categoryPreferences: TaskCategoryPreferences(userDefaults: defaults))
        }
        let seed = try SQLiteNoteRepository(databaseURL: url)
        let yesterday = note("Yesterday", day: "2026-09-26", createdAt: 1)
        try seed.add(yesterday)
        let later = LaterTask(id: UUID(), text: "Later", createdAt: Date(timeIntervalSince1970: 2),
                              completedAt: nil, categoryID: nil)
        try seed.addLater(later)

        let first = makeState()
        first.windowWillOpen()
        let work = try XCTUnwrap(first.createCategory(name: "Work"))
        let study = try XCTUnwrap(first.createCategory(name: "Study"))
        let empty = try XCTUnwrap(first.createCategory(name: "Empty"))
        for (text, category) in [("W1", work.id), ("G1", nil), ("W2", work.id), ("S1", study.id), ("W3", work.id)] {
            first.draft = text
            first.draftCategoryID = category
            XCTAssertTrue(first.addDraft())
        }
        func id(_ text: String, in state: DailyNotesState) throws -> UUID {
            try XCTUnwrap(state.notes.first(where: { $0.text == text })?.id)
        }
        XCTAssertTrue(first.setCompleted(id: try id("W2", in: first), completed: true))
        let original = Dictionary(uniqueKeysWithValues: first.notes.map { ($0.id, $0) })
        first.categoryPreferences.setCollapsed(true, for: .category(study.id))
        first.draft = "Unsaved"
        first.draftCategoryID = study.id
        let progress = first.availableProgress
        XCTAssertEqual(progress, NoteProgress(completed: 1, total: 5))
        XCTAssertEqual(first.categoryPreferences.lastUsedCategoryID, work.id)

        // Row-menu Move Up within Work.
        let menu = try XCTUnwrap(first.taskWindowPresentation.menuMoves(for: try id("W3", in: first), state: first))
        XCTAssertTrue(isChanged(try XCTUnwrap(first.moveTask(try XCTUnwrap(menu.moveUp)))))
        XCTAssertEqual(groupTexts(first), [["W1", "W3", "W2"], ["S1"], ["G1"]])
        // Drop-shaped request: completed task after an anchor in the collapsed Study group.
        let w2 = try XCTUnwrap(original[try id("W2", in: first)])
        let s1 = try id("S1", in: first)
        XCTAssertTrue(isChanged(try XCTUnwrap(first.moveTask(
            moveRequest(w2, destination: .category(study.id), placement: .after(s1))))))
        XCTAssertFalse(first.categoryPreferences.isCollapsed(.category(study.id)))
        // Row-menu Move To General, then General to an empty category.
        let toGeneral = try XCTUnwrap(first.taskWindowPresentation.menuMoves(for: try id("W1", in: first), state: first)?
            .destinations.first(where: { $0.group == .general })?.request)
        XCTAssertTrue(isChanged(try XCTUnwrap(first.moveTask(toGeneral))))
        let g1 = try XCTUnwrap(first.notes.first(where: { $0.text == "G1" }))
        XCTAssertTrue(isChanged(try XCTUnwrap(first.moveTask(moveRequest(g1, destination: .category(empty.id))))))
        // An equivalent visible placement is not a write.
        let movedW2 = try XCTUnwrap(first.notes.first(where: { $0.id == w2.id }))
        XCTAssertEqual(first.moveTask(moveRequest(movedW2, destination: .category(study.id), placement: .after(s1))),
                       .unchanged)

        let expectedOrder = ["W1", "W3", "S1", "W2", "G1"]
        let expectedGroups = [["W3"], ["S1", "W2"], ["G1"], ["W1"]]
        XCTAssertEqual(first.notes.map(\.text), expectedOrder)
        XCTAssertEqual(groupTexts(first), expectedGroups)
        for moved in first.notes {
            let before = try XCTUnwrap(original[moved.id])
            XCTAssertEqual([moved.text, moved.dayKey], [before.text, before.dayKey])
            XCTAssertEqual(moved.createdAt, before.createdAt)
            XCTAssertEqual(moved.completedAt, before.completedAt)
        }
        XCTAssertEqual(first.availableProgress, progress)
        assertGroupCounts(first, equal: try XCTUnwrap(progress))
        XCTAssertEqual(first.draft, "Unsaved")
        XCTAssertEqual(first.draftCategoryID, study.id)
        XCTAssertEqual(first.categoryPreferences.lastUsedCategoryID, work.id)
        XCTAssertTrue(first.categoryPreferences.collapsedGroupIDs.isEmpty)
        XCTAssertNil(first.issue)
        let movedSnapshot = first.notes
        first.refresh()
        XCTAssertEqual(first.notes, movedSnapshot)

        let second = makeState()
        second.windowWillOpen()
        XCTAssertEqual(second.notes, movedSnapshot)
        XCTAssertEqual(groupTexts(second), expectedGroups)
        XCTAssertEqual(second.availableProgress, progress)
        XCTAssertEqual(second.categoryPreferences.lastUsedCategoryID, work.id)
        XCTAssertTrue(second.categoryPreferences.collapsedGroupIDs.isEmpty)
        XCTAssertEqual(second.draft, "", "Unsaved drafts are process-local")

        // Today Add (remembered Work) and Quick Add (General) append after the reorder.
        second.startNewDraft()
        XCTAssertEqual(second.draftCategoryID, work.id)
        second.draft = "W4"
        XCTAssertTrue(second.addDraft())
        XCTAssertEqual(second.add(text: "Quick"), .added)
        XCTAssertEqual(second.categoryPreferences.lastUsedCategoryID, work.id)
        XCTAssertEqual(groupTexts(second), [["W3", "W4"], ["S1", "W2"], ["G1"], ["W1", "Quick"]])
        // Category-only Edit keeps S1's daily rank, unlike an explicit Move To (append).
        second.beginEditing(id: try id("S1", in: second))
        second.editCategoryID = work.id
        XCTAssertTrue(second.saveEdit())
        XCTAssertEqual(groupTexts(second), [["W3", "S1", "W4"], ["W2"], ["G1"], ["W1", "Quick"]])
        XCTAssertTrue(second.setCompleted(id: try id("W3", in: second), completed: true))
        XCTAssertTrue(second.delete(id: try id("W1", in: second)))
        XCTAssertEqual(second.notes.map(\.text), ["W3", "S1", "W2", "G1", "W4", "Quick"])
        // Removal merges Work into General in saved daily order.
        XCTAssertTrue(second.removeCategory(id: work.id))
        XCTAssertEqual(groupTexts(second), [["W2"], ["G1"], ["W3", "S1", "W4", "Quick"]])
        XCTAssertEqual(second.availableProgress, NoteProgress(completed: 2, total: 6))
        assertGroupCounts(second, equal: NoteProgress(completed: 2, total: 6))

        let third = makeState()
        third.windowWillOpen()
        XCTAssertEqual(third.notes, second.notes)
        XCTAssertEqual(third.categories.map(\.id), [study.id, empty.id])
        XCTAssertNil(third.categoryPreferences.lastUsedCategoryID, "Removed category falls back to General")
        XCTAssertEqual(third.laterTasks, [later])
        // Later → Today appends after the reordered day, like Add.
        XCTAssertTrue(third.moveLaterToToday(id: later.id))
        XCTAssertEqual(third.notes.map(\.text), ["W3", "S1", "W2", "G1", "W4", "Quick", "Later"])
        XCTAssertEqual(third.availableProgress, NoteProgress(completed: 2, total: 7))
        let reopened = try SQLiteNoteRepository(databaseURL: url)
        XCTAssertEqual(try reopened.notes(for: "2026-09-27"), third.notes)
        XCTAssertEqual(try reopened.notes(for: yesterday.dayKey), [yesterday])
        XCTAssertEqual(try reopened.laterTasks(), [])
    }

    /// Task 9 scale probe. Asserts correctness only; latency is logged, not gated,
    /// because hosted Debug timing varies with the machine and its load.
    func testScaleProbeMovesAndReadsOneThousandTasksAcrossCategories() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ScaleProbe-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.sqlite")
        let store = try SQLiteNoteRepository(databaseURL: url)
        let categories = try (0..<10).map { try store.createCategory(name: "Category \($0)") }
        let day = "2026-09-27"
        let clock = ContinuousClock()
        var seeded: [Note] = []
        let seedTime = try clock.measure {
            for index in 0..<1_000 {
                // Interleave ten categories and General across the canonical day.
                let category = index % 11 == 10 ? nil : categories[index % 11].id
                let row = Note(id: UUID(), text: "Task \(index)", dayKey: day,
                               createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                               completedAt: index % 3 == 0 ? Date(timeIntervalSince1970: TimeInterval(index) + 0.5) : nil,
                               categoryID: category)
                try store.add(row)
                seeded.append(row)
            }
        }
        let state = DailyNotesState(repositoryFactory: { store },
                                   day: makeDay(now: { self.instant("2026-09-27T12:00:00-04:00") }),
                                   notificationCenter: NotificationCenter(),
                                   workspaceNotificationCenter: NotificationCenter(),
                                   categoryPreferences: isolatedCategoryPreferences())
        let readTime = clock.measure { state.startup() }
        XCTAssertEqual(state.notes, seeded)
        let progress = try XCTUnwrap(state.availableProgress)
        var groups: [TaskGroup] = []
        let groupTime = clock.measure { groups = state.groups }
        XCTAssertEqual(groups.count, 11)
        let menuTime = clock.measure {
            _ = state.taskWindowPresentation.menuMoves(for: seeded[999].id, state: state)
        }

        var moveTimes: [Duration] = []
        func timedMove(_ request: TaskMoveRequest) throws {
            let before = state.notes
            var outcome: TaskMoveOutcome?
            moveTimes.append(clock.measure { outcome = state.moveTask(request) })
            guard case let .changed(saved)? = outcome else { return XCTFail("Expected committed move") }
            // Every other task keeps its relative order; nothing is duplicated or lost.
            XCTAssertEqual(saved.filter { $0.id != request.taskID }, before.filter { $0.id != request.taskID })
            XCTAssertEqual(Set(saved.map(\.id)).count, 1_000)
        }
        for round in 0..<10 {
            // Worst-case same-group reorder: the group's last task to its first position.
            let category = TaskGroupID.category(categories[round].id)
            let siblings = state.notes.filter { TaskGroupID(categoryID: $0.categoryID) == category }
            let last = try XCTUnwrap(siblings.last)
            try timedMove(moveRequest(last, destination: category, placement: .before(siblings[0].id)))
            XCTAssertEqual(state.notes.first(where: { TaskGroupID(categoryID: $0.categoryID) == category })?.id, last.id)
            // Cross-category: the day's first task to the end of the next group.
            let head = state.notes[0]
            let next = TaskGroupID.category(categories[(round + 5) % 10].id)
            let target = TaskGroupID(categoryID: head.categoryID) == next ? TaskGroupID.general : next
            try timedMove(moveRequest(head, destination: target))
            XCTAssertEqual(state.notes.last(where: { TaskGroupID(categoryID: $0.categoryID) == target })?.id, head.id)
        }
        XCTAssertEqual(state.availableProgress, progress)
        let reopenTime = try clock.measure {
            XCTAssertEqual(try SQLiteNoteRepository(databaseURL: url).notes(for: day), state.notes)
        }

        let sorted = moveTimes.sorted()
        let report = """
        SCALE-PROBE tasks=1000 categories=10+General moves=\(moveTimes.count)
        SCALE-PROBE seed1000Adds=\(seedTime) stateRead=\(readTime) grouping=\(groupTime) menuMoves=\(menuTime)
        SCALE-PROBE moveMedian=\(sorted[sorted.count / 2]) moveMax=\(sorted.last!) moveMin=\(sorted.first!)
        SCALE-PROBE freshReopenRead=\(reopenTime)
        """
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "scale-probe"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func moveRequest(_ note: Note, destination: TaskGroupID = .general,
                             placement: TaskMovePlacement = .endOfGroup) -> TaskMoveRequest {
        TaskMoveRequest(taskID: note.id, expectedDayKey: note.dayKey,
                        expectedSourceGroup: TaskGroupID(categoryID: note.categoryID),
                        destinationGroup: destination, placement: placement)
    }

    private func categorized(_ text: String, _ category: TaskCategory, createdAt: TimeInterval,
                             completedAt: Date? = nil) -> Note {
        Note(id: UUID(), text: text, dayKey: "2026-09-27", createdAt: Date(timeIntervalSince1970: createdAt),
             completedAt: completedAt, categoryID: category.id)
    }

    private func isChanged(_ outcome: TaskMoveOutcome) -> Bool {
        if case .changed = outcome { true } else { false }
    }

    func testHistoryFacadeUsesOneConnectionWithoutLoadingOrRefreshingToday() throws {
        let old = note("Historical", day: "2026-09-26", createdAt: 1)
        let store = FakeNoteRepository(notes: [old])
        var opens = 0
        var current = instant("2026-09-27T12:00:00-04:00")
        let state = DailyNotesState(repositoryFactory: { opens += 1; return store },
            day: makeDay(now: { current }), notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            categoryPreferences: isolatedCategoryPreferences())
        let cutoff = try GregorianDay(key: "2026-09-27")
        let range = try HistoryDayRange.month(containing: cutoff)
        XCTAssertEqual(try state.historyDaySnapshot(for: old.dayKey).notes, [old])
        XCTAssertEqual(try state.daySummaries(in: range).map(\.dayKey), [old.dayKey])
        XCTAssertEqual(try state.unfinishedDayPage(before: cutoff, limit: 31).summaries.map(\.dayKey),
                       [old.dayKey])
        XCTAssertNil(state.todayKey)
        XCTAssertNil(state.availableProgress)
        XCTAssertEqual(state.historyRevision, 0)
        state.startup()
        current = instant("2026-09-28T12:00:00-04:00")
        _ = try state.historyDaySnapshot(for: old.dayKey)
        XCTAssertEqual(state.todayKey, "2026-09-27")
        XCTAssertEqual(state.historyRevision, 1)
        XCTAssertEqual(opens, 1)
        XCTAssertEqual(store.saved, [old])
    }

    func testHistorySuccessAndFailurePreserveTodayErrorsAndBothDrafts() throws {
        let today = note("Today", day: "2026-09-27", createdAt: 1)
        let category = try TaskCategory(name: "Work", creationOrder: 0)
        let store = FakeNoteRepository(notes: [today], categories: [category])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.draft = "Keep new draft"
        state.draftCategoryID = category.id
        state.beginEditing(id: today.id)
        state.editDraft = "Keep edit draft"
        state.editCategoryID = category.id
        store.failWrite = .edit
        XCTAssertFalse(state.saveEdit())
        XCTAssertNil(state.createCategory(name: " "))
        store.failCategoryCommand = .usage
        XCTAssertNil(state.categoryUsageCount(id: category.id))
        store.failCount = true
        state.refresh()
        let revision = state.historyRevision
        let cutoff = try GregorianDay(key: "2026-09-27")
        let range = try HistoryDayRange.month(containing: cutoff)
        for fails in [false, true] {
            store.failSnapshotRead = fails ? .notes : nil
            if fails {
                XCTAssertThrowsError(try state.historyDaySnapshot(for: today.dayKey))
                XCTAssertThrowsError(try state.daySummaries(in: range))
                XCTAssertThrowsError(try state.unfinishedDayPage(before: cutoff, limit: 31))
            } else {
                XCTAssertEqual(try state.historyDaySnapshot(for: today.dayKey).notes, [today])
                XCTAssertEqual(try state.daySummaries(in: range).count, 1)
                XCTAssertTrue(try state.unfinishedDayPage(before: cutoff, limit: 31).summaries.isEmpty)
            }
            XCTAssertEqual(state.todayKey, today.dayKey)
            XCTAssertEqual(state.notes, [today])
            XCTAssertEqual(state.categories, [category])
            XCTAssertNil(state.availableProgress)
            XCTAssertEqual(state.readIssue, .load)
            XCTAssertEqual(state.taskIssue, .edit)
            XCTAssertEqual(state.categoryIssue, .usage)
            XCTAssertEqual(state.categoryNameIssue, .invalid(.blank))
            XCTAssertEqual(state.draft, "Keep new draft")
            XCTAssertEqual(state.draftCategoryID, category.id)
            XCTAssertEqual(state.editingNoteID, today.id)
            XCTAssertEqual(state.editDraft, "Keep edit draft")
            XCTAssertEqual(state.editCategoryID, category.id)
            XCTAssertEqual(state.historyRevision, revision)
        }
    }

    func testHistoryInvalidationFollowsCommittedWritesAndSettledRefreshes() throws {
        let store = FakeNoteRepository()
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        XCTAssertEqual(state.historyRevision, 1)
        let category = try XCTUnwrap(state.createCategory(name: "Work"))
        XCTAssertEqual(state.historyRevision, 2)
        XCTAssertNotNil(state.renameCategory(id: category.id, name: "Renamed"))
        XCTAssertEqual(state.historyRevision, 3)
        XCTAssertEqual(state.add(text: "Saved", categoryID: category.id), .added)
        XCTAssertEqual(state.historyRevision, 4)
        let id = try XCTUnwrap(state.notes.first?.id)
        XCTAssertTrue(state.setCompleted(id: id, completed: true))
        XCTAssertEqual(state.historyRevision, 5)
        state.beginEditing(id: id)
        state.editDraft = "Edited"
        XCTAssertTrue(state.saveEdit())
        XCTAssertEqual(state.historyRevision, 6)
        XCTAssertTrue(state.removeCategory(id: category.id))
        XCTAssertEqual(state.historyRevision, 7)
        XCTAssertTrue(state.delete(id: id))
        XCTAssertEqual(state.historyRevision, 8)
        state.refreshIfDayChanged()
        XCTAssertEqual(state.historyRevision, 8)
        state.windowWillOpen()
        XCTAssertEqual(state.historyRevision, 9)
        store.failCount = true
        state.refresh()
        XCTAssertEqual(state.historyRevision, 10)
        store.failWrite = .add
        XCTAssertEqual(state.add(text: "Unavailable"), .unavailable)
        // Readiness attempted a refresh; no committed write signal was added.
        XCTAssertEqual(state.historyRevision, 11)
        store.failCount = false
        state.refresh()
        XCTAssertEqual(state.historyRevision, 12)
        XCTAssertEqual(state.add(text: "Rejected"), .writeFailed)
        XCTAssertEqual(state.historyRevision, 12)
    }

    func testRejectedTaskAndCategoryWritesDoNotInvalidateHistory() throws {
        let saved = note("Saved", day: "2026-09-27", createdAt: 1)
        let category = try TaskCategory(name: "Work", creationOrder: 0)
        let store = FakeNoteRepository(notes: [saved], categories: [category])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        for failure in [DailyNotesIssue.add, .complete, .edit, .delete] {
            store.failWrite = failure
            switch failure {
            case .add: XCTAssertEqual(state.add(text: "Rejected"), .writeFailed)
            case .complete: XCTAssertFalse(state.setCompleted(id: saved.id, completed: true))
            case .edit:
                state.beginEditing(id: saved.id)
                state.editDraft = "Rejected"
                XCTAssertFalse(state.saveEdit())
            case .delete: XCTAssertFalse(state.delete(id: saved.id))
            default: XCTFail("Not a daily write")
            }
            XCTAssertEqual(state.historyRevision, 1)
        }
        for failure in [CategoryCommandIssue.create, .rename, .remove] {
            store.failCategoryCommand = failure
            switch failure {
            case .create: XCTAssertNil(state.createCategory(name: "Rejected"))
            case .rename: XCTAssertNil(state.renameCategory(id: category.id, name: "Rejected"))
            case .remove: XCTAssertFalse(state.removeCategory(id: category.id))
            default: XCTFail("Not a write")
            }
            XCTAssertEqual(state.historyRevision, 1)
        }
        XCTAssertNil(state.createCategory(name: " "))
        XCTAssertEqual(state.historyRevision, 1)
        XCTAssertEqual(store.saved, [saved])
        XCTAssertEqual(store.savedCategories, [category])
    }

    func testHistoryReadsAndQueuedLifecycleEventsCannotReopenAfterTermination() async throws {
        for loaded in [false, true] {
            let store = FakeNoteRepository()
            let center = NotificationCenter()
            var opens = 0
            let state = DailyNotesState(repositoryFactory: { opens += 1; return store },
                day: makeDay(now: { self.instant("2026-09-27T12:00:00-04:00") }),
                notificationCenter: center, workspaceNotificationCenter: NotificationCenter(),
                categoryPreferences: isolatedCategoryPreferences())
            if loaded { state.startup() }
            center.post(name: .NSCalendarDayChanged, object: nil)
            state.stopForTermination()
            let revision = state.historyRevision
            let cutoff = try GregorianDay(key: "2026-09-27")
            let range = try HistoryDayRange.month(containing: cutoff)
            XCTAssertThrowsError(try state.historyDaySnapshot(for: cutoff.key)) {
                XCTAssertEqual($0 as? HistoryReadError, .terminated)
            }
            XCTAssertThrowsError(try state.daySummaries(in: range)) {
                XCTAssertEqual($0 as? HistoryReadError, .terminated)
            }
            XCTAssertThrowsError(try state.unfinishedDayPage(before: cutoff, limit: 31)) {
                XCTAssertEqual($0 as? HistoryReadError, .terminated)
            }
            state.refresh()
            XCTAssertEqual(state.add(text: "After termination"), .unavailable)
            await Task.yield()
            XCTAssertEqual(opens, loaded ? 1 : 0)
            XCTAssertEqual(state.historyRevision, revision)
        }
    }

    private func makeState(store: FakeNoteRepository, now: @escaping () -> Date,
                           preferences: TaskCategoryPreferences? = nil) -> DailyNotesState {
        DailyNotesState(repositoryFactory: { store }, day: makeDay(now: now),
                        notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter(),
                        categoryPreferences: preferences ?? isolatedCategoryPreferences())
    }

    private func groupTexts(_ state: DailyNotesState) -> [[String]] {
        state.groups.map { $0.notes.map(\.text) }
    }

    private func executeCategoryFixtureSQL(_ sql: String, at url: URL) throws {
        var database: OpaquePointer?
        let result = sqlite3_open(url.path, &database)
        defer { if let database { sqlite3_close(database) } }
        XCTAssertEqual(result, SQLITE_OK)
        let opened = try XCTUnwrap(database)
        XCTAssertEqual(sqlite3_exec(opened, sql, nil, nil, nil), SQLITE_OK,
                       String(cString: sqlite3_errmsg(opened)))
    }

    private func assertGroupCounts(_ state: DailyNotesState, equal daily: NoteProgress,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let groups = state.groups
        XCTAssertEqual(state.availableProgress, daily, file: file, line: line)
        XCTAssertEqual(NoteProgress(completed: groups.map(\.progress.completed).reduce(0, +),
                                    total: groups.map(\.progress.total).reduce(0, +)),
                       daily, file: file, line: line)
    }

    private func makeDay(now: @escaping () -> Date) -> NoteDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return NoteDay(calendar: calendar, now: now)
    }

    private func instant(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func note(_ text: String, day: String, createdAt: TimeInterval,
                      completedAt: Date? = nil) -> Note {
        Note(id: UUID(), text: text, dayKey: day,
             createdAt: Date(timeIntervalSince1970: createdAt), completedAt: completedAt)
    }

    private func laterTask(_ text: String, createdAt: TimeInterval,
                           completedAt: Date? = nil, categoryID: UUID? = nil) -> LaterTask {
        LaterTask(id: UUID(), text: text,
                  createdAt: Date(timeIntervalSince1970: createdAt),
                  completedAt: completedAt, categoryID: categoryID)
    }

    func testLaterCommandsPreserveTodayOrderMetadataAndScopedPreferences() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let today = note("Today", day: "2026-09-27", createdAt: 1)
        let first = laterTask("First", createdAt: 2, categoryID: work.id)
        let second = laterTask("Second", createdAt: 3)
        let store = FakeNoteRepository(notes: [today], categories: [work, home], laterTasks: [first, second])
        let preferences = isolatedCategoryPreferences()
        preferences.rememberLastUsed(home.id)
        preferences.setCollapsed(true, for: .category(work.id))
        preferences.setCollapsed(true, for: .category(work.id), in: .later)
        let current = instant("2026-09-27T12:00:00-04:00")
        let state = makeState(store: store, now: { current }, preferences: preferences)
        state.startup()
        state.draft = "Today draft"
        state.draftCategoryID = home.id
        store.failWrite = .add
        XCTAssertFalse(state.addDraft())
        let todayProgress = state.availableProgress

        state.laterDraft = " \n "
        XCTAssertFalse(state.addLaterDraft())
        XCTAssertEqual(store.laterWriteAttempts, 0)
        state.laterDraft = "  Added later  "
        state.laterDraftCategoryID = work.id
        XCTAssertTrue(state.addLaterDraft())
        let added = try XCTUnwrap(state.laterTasks.last)
        XCTAssertEqual(added.text, "Added later")
        XCTAssertEqual(added.createdAt, current)
        XCTAssertEqual(added.categoryID, work.id)
        XCTAssertEqual(state.laterDraft, "")
        XCTAssertNil(state.laterDraftCategoryID)
        XCTAssertEqual(preferences.laterLastUsedCategoryID, work.id)
        XCTAssertFalse(preferences.isCollapsed(.category(work.id), in: .later))
        XCTAssertTrue(preferences.isCollapsed(.category(work.id)))

        XCTAssertTrue(state.setLaterCompleted(id: first.id, completed: true))
        XCTAssertEqual(state.laterTasks.first?.completedAt, current)
        preferences.setCollapsed(true, for: .category(work.id), in: .later)
        state.beginEditingLater(id: first.id)
        state.laterEditDraft = " "
        let attempts = store.laterWriteAttempts
        XCTAssertFalse(state.saveLaterEdit())
        XCTAssertEqual(store.laterWriteAttempts, attempts)
        state.laterEditDraft = "  Renamed  "
        XCTAssertTrue(state.saveLaterEdit())
        XCTAssertTrue(preferences.isCollapsed(.category(work.id), in: .later))
        preferences.setCollapsed(true, for: .category(home.id), in: .later)
        state.beginEditingLater(id: first.id)
        state.laterEditCategoryID = home.id
        XCTAssertTrue(state.saveLaterEdit())
        XCTAssertFalse(preferences.isCollapsed(.category(home.id), in: .later))
        XCTAssertEqual(state.laterTasks.map(\.id), [first.id, second.id, added.id])
        XCTAssertEqual(state.laterTasks.first?.createdAt, first.createdAt)
        XCTAssertEqual(state.laterTasks.first?.completedAt, current)
        XCTAssertTrue(state.setLaterCompleted(id: first.id, completed: false))
        XCTAssertNil(state.laterTasks.first?.completedAt)
        XCTAssertTrue(state.deleteLater(id: second.id))
        XCTAssertEqual(state.laterTasks.map(\.id), [first.id, added.id])
        XCTAssertEqual(state.notes, [today])
        XCTAssertEqual(state.availableProgress, todayProgress)
        XCTAssertEqual(state.draft, "Today draft")
        XCTAssertEqual(state.draftCategoryID, home.id)
        XCTAssertEqual(state.taskIssue, .add)
        XCTAssertEqual(preferences.lastUsedCategoryID, home.id)
        XCTAssertEqual(preferences.laterLastUsedCategoryID, work.id)

        // Quick Add remains Today/General, independent of Later's active edit/draft.
        state.laterDraft = "Next Later draft"
        state.laterDraftCategoryID = work.id
        state.beginEditingLater(id: first.id)
        state.laterEditDraft = "Pending Later edit"
        store.failWrite = nil
        XCTAssertEqual(state.add(text: "Capture"), .added)
        XCTAssertNil(state.notes.last?.categoryID)
        XCTAssertEqual(state.laterDraft, "Next Later draft")
        XCTAssertEqual(state.laterDraftCategoryID, work.id)
        XCTAssertEqual(state.laterEditDraft, "Pending Later edit")
        XCTAssertEqual(preferences.lastUsedCategoryID, home.id)
        XCTAssertEqual(preferences.laterLastUsedCategoryID, work.id)
    }

    func testEveryFailedLaterWriteKeepsSnapshotsDraftsAndPreferencesUntilRetry() throws {
        for failure in [DailyNotesIssue.add, .complete, .edit, .delete] {
            let work = try TaskCategory(name: "Work", creationOrder: 0)
            let original = laterTask("Original", createdAt: 2, categoryID: work.id)
            let today = note("Today", day: "2026-09-27", createdAt: 1)
            let store = FakeNoteRepository(notes: [today], categories: [work], laterTasks: [original])
            let preferences = isolatedCategoryPreferences()
            preferences.setCollapsed(true, for: .category(work.id), in: .later)
            let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") },
                                  preferences: preferences)
            state.startup()
            state.laterDraft = "New Later draft"
            state.laterDraftCategoryID = work.id
            if failure == .edit {
                state.beginEditingLater(id: original.id)
                state.laterEditDraft = "Changed"
                state.laterEditCategoryID = nil
            }
            let command: () -> Bool = {
                switch failure {
                case .add: state.addLaterDraft()
                case .complete: state.setLaterCompleted(id: original.id, completed: true)
                case .edit: state.saveLaterEdit()
                case .delete: state.deleteLater(id: original.id)
                default: false
                }
            }
            store.failLaterWrite = failure
            XCTAssertFalse(command())
            XCTAssertEqual(state.laterTaskIssue, failure)
            XCTAssertEqual(state.laterTasks, [original])
            XCTAssertEqual(store.savedLaterTasks, [original])
            XCTAssertEqual(state.availableLaterRemainingCount, 1)
            XCTAssertEqual(state.notes, [today])
            XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 1))
            XCTAssertEqual(state.laterDraft, "New Later draft")
            XCTAssertEqual(state.laterDraftCategoryID, work.id)
            XCTAssertNil(preferences.laterLastUsedCategoryID)
            XCTAssertTrue(preferences.isCollapsed(.category(work.id), in: .later))
            if failure == .edit {
                XCTAssertEqual(state.editingLaterTaskID, original.id)
                XCTAssertEqual(state.laterEditDraft, "Changed")
                XCTAssertNil(state.laterEditCategoryID)
            }
            store.failLaterRead = true
            state.refresh()
            XCTAssertEqual(state.laterIssue, .load)
            XCTAssertEqual(state.laterTaskIssue, failure)
            store.failLaterRead = false
            state.refresh()
            XCTAssertEqual(state.laterIssue, failure)
            store.failLaterWrite = nil
            XCTAssertTrue(command())
            XCTAssertNil(state.laterTaskIssue)
            XCTAssertEqual(state.laterTasks, store.savedLaterTasks)
        }
    }

    func testLaterAndSharedCategoryWritesRemainUsableWhenOnlyTodayReadFails() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let original = laterTask("Original", createdAt: 2, categoryID: work.id)
        let store = FakeNoteRepository(categories: [work], laterTasks: [original])
        store.failSnapshotRead = .notes
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.laterDraft = "New"
        state.laterDraftCategoryID = work.id
        XCTAssertTrue(state.addLaterDraft())
        XCTAssertTrue(state.setLaterCompleted(id: original.id, completed: true))
        state.beginEditingLater(id: original.id)
        state.laterEditDraft = "Edited"
        XCTAssertTrue(state.saveLaterEdit())
        XCTAssertNotNil(state.createCategory(name: "Unused"))
        XCTAssertNotNil(state.renameCategory(id: work.id, name: "Office"))
        XCTAssertEqual(state.categoryUsageCount(id: work.id), 2)
        XCTAssertEqual(state.laterGroups.first?.name, "Office")
        XCTAssertTrue(state.removeCategory(id: work.id))
        XCTAssertTrue(state.laterTasks.allSatisfy { $0.categoryID == nil })
        XCTAssertTrue(state.deleteLater(id: original.id))
        let remaining = try XCTUnwrap(state.laterTasks.first)
        XCTAssertFalse(state.moveLaterToToday(id: remaining.id))
        XCTAssertEqual(store.moveAttempts, 0)
        XCTAssertNil(state.availableProgress)
        XCTAssertEqual(state.readIssue, .load)
        XCTAssertTrue(state.hasLoadedLater)
    }

    func testUnavailableLaterOrCatalogAndTerminationRejectAllLaterWrites() throws {
        for catalogFailure in [false, true] {
            let original = laterTask("Original", createdAt: 1)
            let store = FakeNoteRepository(laterTasks: [original])
            let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
            state.startup()
            state.beginEditingLater(id: original.id)
            state.laterEditDraft = "Pending edit"
            state.laterDraft = "Pending add"
            if catalogFailure { store.failSnapshotRead = .categories } else { store.failLaterRead = true }
            state.refresh()
            XCTAssertFalse(state.addLaterDraft())
            XCTAssertFalse(state.setLaterCompleted(id: original.id, completed: true))
            XCTAssertFalse(state.saveLaterEdit())
            XCTAssertFalse(state.deleteLater(id: original.id))
            XCTAssertFalse(state.moveLaterToToday(id: original.id))
            XCTAssertEqual(store.laterWriteAttempts, 0)
            XCTAssertEqual(store.savedLaterTasks, [original])
            XCTAssertEqual(state.laterDraft, "Pending add")
            XCTAssertEqual(state.laterEditDraft, "Pending edit")
            store.failSnapshotRead = nil
            store.failLaterRead = false
            state.refresh()
            state.stopForTermination()
            XCTAssertFalse(state.addLaterDraft())
            XCTAssertFalse(state.saveLaterEdit())
            XCTAssertFalse(state.setLaterCompleted(id: original.id, completed: true))
            XCTAssertFalse(state.deleteLater(id: original.id))
            XCTAssertFalse(state.moveLaterToToday(id: original.id))
            XCTAssertEqual(store.laterWriteAttempts, 0)
        }
    }

    func testMoveUsesOneActionClockSampleAcrossMidnightAndTimeZoneChanges() throws {
        for timeZoneChange in [false, true] {
            let work = try TaskCategory(name: "Work", creationOrder: 0)
            let source = laterTask("Old task", createdAt: 1, categoryID: work.id)
            let oldDay = note("Old day", day: "2026-09-27", createdAt: 2)
            let destination = note("Already today", day: "2026-09-28", createdAt: 3)
            let store = FakeNoteRepository(notes: [oldDay, destination], categories: [work], laterTasks: [source])
            var current = instant("2026-09-27T23:59:00-04:00")
            var zone = self.zone
            var clockReads = 0
            var advanceAfterSample = false
            let preferences = isolatedCategoryPreferences()
            preferences.setCollapsed(true, for: .category(work.id))
            let state = DailyNotesState(repositoryFactory: { store },
                                       day: NoteDay(now: {
                                           clockReads += 1
                                           let result = current
                                           if advanceAfterSample { current = current.addingTimeInterval(86_400) }
                                           return result
                                       }, timeZone: { zone }),
                                       notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter(),
                                       categoryPreferences: preferences)
            state.startup()
            state.laterDraft = "Keep Later draft"
            state.draft = "Keep Today draft"
            if timeZoneChange { zone = TimeZone(secondsFromGMT: 0)! }
            else { current = instant("2026-09-28T00:01:00-04:00") }
            advanceAfterSample = true
            clockReads = 0
            XCTAssertTrue(state.moveLaterToToday(id: source.id))
            XCTAssertEqual(clockReads, 1)
            XCTAssertEqual(state.todayKey, "2026-09-28")
            XCTAssertEqual(state.notes.map(\.id), [destination.id, source.id])
            let moved = try XCTUnwrap(state.notes.last)
            XCTAssertEqual(moved.dayKey, "2026-09-28")
            XCTAssertEqual(moved.text, source.text)
            XCTAssertEqual(moved.categoryID, source.categoryID)
            XCTAssertEqual(moved.createdAt, source.createdAt)
            XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 2))
            XCTAssertEqual(state.availableLaterRemainingCount, 0)
            XCTAssertEqual(state.yesterdayIncompleteCount, 1)
            XCTAssertFalse(preferences.isCollapsed(.category(work.id)))
            XCTAssertNil(preferences.lastUsedCategoryID)
            XCTAssertNil(preferences.laterLastUsedCategoryID)
            XCTAssertEqual(state.laterDraft, "Keep Later draft")
            XCTAssertEqual(state.draft, "Keep Today draft")
            XCTAssertEqual(store.moveAttempts, 1)
        }
    }

    func testMoveFailureRetryAndCommittedResultDoNotDependOnFollowUpReads() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let home = try TaskCategory(name: "Home", creationOrder: 1)
        let source = laterTask("Cached text", createdAt: 1, categoryID: work.id)
        let today = note("Today", day: "2026-09-27", createdAt: 2)
        let store = FakeNoteRepository(notes: [today], categories: [work, home], laterTasks: [source])
        defer { store.onMove = nil }
        let preferences = isolatedCategoryPreferences()
        preferences.rememberLastUsed(work.id)
        preferences.rememberLastUsed(work.id, in: .later)
        preferences.setCollapsed(true, for: .category(home.id))
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") }, preferences: preferences)
        state.startup()
        state.laterDraft = "Pending Later draft"
        let revision = state.historyRevision
        store.failLaterWrite = .moveToToday
        XCTAssertFalse(state.moveLaterToToday(id: source.id))
        XCTAssertEqual(state.laterTaskIssue, .moveToToday)
        XCTAssertEqual(state.historyRevision, revision)
        XCTAssertEqual(state.laterTasks, [source])
        XCTAssertEqual(state.notes, [today])
        XCTAssertEqual(state.laterDraft, "Pending Later draft")
        XCTAssertTrue(preferences.isCollapsed(.category(home.id)))
        store.failLaterWrite = nil
        store.onMove = {
            store.savedLaterTasks = [LaterTask(id: source.id, text: "Persisted text", createdAt: source.createdAt,
                                               completedAt: nil, categoryID: home.id)]
            // Any optional reread after this saved result would fail.
            store.failSnapshotRead = .categories
            store.failLaterRead = true
        }
        let reads = store.readAttempts
        XCTAssertTrue(state.moveLaterToToday(id: source.id))
        XCTAssertEqual(store.readAttempts, reads)
        // A saved move adds a Today task, so History must reread.
        XCTAssertEqual(state.historyRevision, revision + 1)
        XCTAssertNil(state.laterTaskIssue)
        XCTAssertEqual(state.notes.last?.text, "Persisted text")
        XCTAssertEqual(state.notes.last?.categoryID, home.id)
        XCTAssertEqual(state.notes.last?.createdAt, source.createdAt)
        XCTAssertEqual(state.laterRefreshNotice, "Moved task to Today.")
        XCTAssertFalse(preferences.isCollapsed(.category(home.id)))
        XCTAssertEqual(preferences.lastUsedCategoryID, work.id)
        XCTAssertEqual(preferences.laterLastUsedCategoryID, work.id)
        XCTAssertFalse(state.moveLaterToToday(id: source.id))
        XCTAssertEqual(store.moveAttempts, 2)
        XCTAssertEqual(store.saved.filter { $0.id == source.id }.count, 1)
        state.refresh()
        XCTAssertEqual(state.laterIssue, .load)
        XCTAssertNil(state.laterTaskIssue)
        store.failSnapshotRead = nil
        store.failLaterRead = false
        state.refresh()
        XCTAssertEqual(state.notes, store.saved)
        XCTAssertEqual(state.laterTasks, [])
        XCTAssertFalse(state.moveLaterToToday(id: source.id))
        XCTAssertEqual(store.moveAttempts, 2)
    }

    func testLaterStaleTargetsAndCategoriesRecoverWithoutSavingElsewhere() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let source = laterTask("Original", createdAt: 1, categoryID: work.id)
        let store = FakeNoteRepository(categories: [work], laterTasks: [source])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.beginEditingLater(id: source.id)
        state.laterEditDraft = "Recover removed task"
        store.savedLaterTasks = []
        XCTAssertFalse(state.saveLaterEdit())
        XCTAssertNil(state.editingLaterTaskID)
        XCTAssertEqual(state.laterRecoveredEdit?.text, "Recover removed task")
        XCTAssertEqual(state.laterTasks, [])

        state.laterDraft = "Never autosave as General"
        state.laterDraftCategoryID = work.id
        store.savedCategories = []
        XCTAssertFalse(state.addLaterDraft())
        XCTAssertEqual(store.savedLaterTasks, [])
        XCTAssertEqual(state.laterDraft, "Never autosave as General")
        XCTAssertNil(state.laterDraftCategoryID)
        XCTAssertNotNil(state.laterRefreshNotice)

        let completed = LaterTask(id: source.id, text: source.text, createdAt: source.createdAt,
                                  completedAt: instant("2026-09-27T10:00:00-04:00"))
        store.savedLaterTasks = [LaterTask(id: source.id, text: source.text, createdAt: source.createdAt, completedAt: nil)]
        state.refresh()
        store.savedLaterTasks = [completed]
        XCTAssertFalse(state.moveLaterToToday(id: source.id))
        XCTAssertEqual(state.laterTasks, [completed])
        XCTAssertEqual(state.laterTaskIssue, .moveToToday)
        XCTAssertEqual(store.saved, [])
        let attempts = store.moveAttempts
        XCTAssertFalse(state.moveLaterToToday(id: source.id))
        XCTAssertEqual(store.moveAttempts, attempts)
        XCTAssertTrue(state.setLaterCompleted(id: source.id, completed: false))
        store.saved = [Note(id: source.id, text: "History collision", dayKey: "2026-09-26",
                            createdAt: source.createdAt, completedAt: nil)]
        XCTAssertFalse(state.moveLaterToToday(id: source.id))
        XCTAssertEqual(state.laterTaskIssue, .moveToToday)
        XCTAssertEqual(store.savedLaterTasks.count, 1)
        XCTAssertEqual(state.notes, [])
    }

    func testLaterAddReadinessRefreshDoesNotAutosaveADeletedCategoryAsGeneral() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let store = FakeNoteRepository(categories: [work])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })
        state.startup()
        state.laterDraft = "Keep for explicit retry"
        state.laterDraftCategoryID = work.id
        store.failLaterRead = true
        state.refresh()
        store.failLaterRead = false
        store.savedCategories = []
        XCTAssertFalse(state.addLaterDraft())
        XCTAssertEqual(store.laterWriteAttempts, 0)
        XCTAssertEqual(store.savedLaterTasks, [])
        XCTAssertEqual(state.laterDraft, "Keep for explicit retry")
        XCTAssertNil(state.laterDraftCategoryID)
        XCTAssertNotNil(state.laterRefreshNotice)
        XCTAssertTrue(state.addLaterDraft())
        XCTAssertNil(store.savedLaterTasks.first?.categoryID)
    }

    func testSQLiteBackedLaterCommandsMoveRollbackAndReopenPublishOnlySavedValues() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaterStateCommands-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.sqlite")
        let current = instant("2026-09-27T12:00:00-04:00")
        let makeState = {
            DailyNotesState(repositoryFactory: { try SQLiteNoteRepository(databaseURL: url) },
                            day: self.makeDay(now: { current }), notificationCenter: NotificationCenter(),
                            workspaceNotificationCenter: NotificationCenter(),
                            categoryPreferences: self.isolatedCategoryPreferences())
        }
        let state = makeState()
        state.startup()
        let work = try XCTUnwrap(state.createCategory(name: "Work"))
        state.draft = "Existing Today"
        XCTAssertTrue(state.addDraft())
        state.laterDraft = "First Later"
        state.laterDraftCategoryID = work.id
        XCTAssertTrue(state.addLaterDraft())
        state.laterDraft = "Second Later"
        XCTAssertTrue(state.addLaterDraft())
        let first = try XCTUnwrap(state.laterTasks.first)
        let second = try XCTUnwrap(state.laterTasks.last)
        XCTAssertTrue(state.setLaterCompleted(id: first.id, completed: true))
        state.beginEditingLater(id: first.id)
        state.laterEditDraft = "Edited first"
        XCTAssertTrue(state.saveLaterEdit())
        XCTAssertEqual(state.laterTasks.map(\.id), [first.id, second.id])
        let savedBeforeMove = state.laterTasks
        let todayBeforeMove = state.notes
        state.stopForTermination()
        let reopened = makeState()
        reopened.startup()
        XCTAssertEqual(reopened.laterTasks, savedBeforeMove)
        XCTAssertEqual(reopened.notes, todayBeforeMove)
        XCTAssertFalse(reopened.moveLaterToToday(id: first.id))
        XCTAssertTrue(reopened.setLaterCompleted(id: first.id, completed: false))
        try executeCategoryFixtureSQL("CREATE TRIGGER reject_move BEFORE DELETE ON later_tasks BEGIN SELECT RAISE(ABORT, 'reject move'); END", at: url)
        let beforeRejectedMove = reopened.laterTasks
        XCTAssertFalse(reopened.moveLaterToToday(id: first.id))
        XCTAssertEqual(reopened.laterTasks, beforeRejectedMove)
        XCTAssertEqual(reopened.notes, todayBeforeMove)
        let observer = try SQLiteNoteRepository(databaseURL: url)
        XCTAssertEqual(try observer.laterTasks(), beforeRejectedMove)
        XCTAssertEqual(try observer.notes(for: "2026-09-27"), todayBeforeMove)
        try executeCategoryFixtureSQL("DROP TRIGGER reject_move", at: url)
        XCTAssertTrue(reopened.moveLaterToToday(id: first.id))
        XCTAssertFalse(reopened.moveLaterToToday(id: first.id))
        XCTAssertEqual(reopened.notes.map(\.id), todayBeforeMove.map(\.id) + [first.id])
        XCTAssertEqual(reopened.notes.last?.text, "Edited first")
        XCTAssertEqual(reopened.notes.last?.categoryID, work.id)
        XCTAssertEqual(reopened.notes.last?.createdAt, first.createdAt)
        XCTAssertEqual(reopened.availableLaterRemainingCount, 1)
        XCTAssertEqual(reopened.availableProgress, NoteProgress(completed: 0, total: 2))
        XCTAssertTrue(reopened.deleteLater(id: second.id))
        let finalNotes = reopened.notes
        reopened.stopForTermination()
        let finalState = makeState()
        finalState.startup()
        XCTAssertEqual(finalState.notes, finalNotes)
        XCTAssertEqual(finalState.laterTasks, [])
        XCTAssertEqual(try observer.notes(for: "2026-09-27"), finalNotes)
        XCTAssertEqual(try observer.laterTasks(), [])
        finalState.stopForTermination()
    }

    func testIntegratedChangedDataReopenPreservesBothTablesAndScopedPreferences() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaterIntegratedReopen-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.sqlite")
        let defaults = isolatedDefaults()
        var appPreferences = AppPreferences.defaultValue
        appPreferences.theme = .dark
        appPreferences.quickAddEnabled = true
        let preferencesBytes = try JSONEncoder().encode(appPreferences)
        defaults.set(preferencesBytes, forKey: PreferencesStore.storageKey)
        defaults.set(true, forKey: UserDefaultsOnboardingStore.storageKey)
        let current = instant("2026-10-06T12:00:00-04:00")
        let makeState = {
            DailyNotesState(repositoryFactory: { try SQLiteNoteRepository(databaseURL: url) },
                            day: self.makeDay(now: { current }), notificationCenter: NotificationCenter(),
                            workspaceNotificationCenter: NotificationCenter(),
                            categoryPreferences: TaskCategoryPreferences(userDefaults: defaults))
        }
        // Read rowids as well as every saved field, independently of state snapshots.
        func rows(_ table: String) throws -> [[String?]] {
            var connection: OpaquePointer?
            XCTAssertEqual(sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
            let database = try XCTUnwrap(connection)
            defer { sqlite3_close(database) }
            var prepared: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(database, "SELECT rowid, * FROM \(table) ORDER BY rowid",
                                              -1, &prepared, nil), SQLITE_OK)
            let statement = try XCTUnwrap(prepared)
            defer { sqlite3_finalize(statement) }
            var result: [[String?]] = []
            var step = sqlite3_step(statement)
            while step == SQLITE_ROW {
                result.append((0..<sqlite3_column_count(statement)).map {
                    sqlite3_column_text(statement, $0).map { String(cString: $0) }
                })
                step = sqlite3_step(statement)
            }
            XCTAssertEqual(step, SQLITE_DONE)
            return result
        }
        let state = makeState()
        defer { state.stopForTermination() }
        state.startup()
        let work = try XCTUnwrap(state.createCategory(name: "Work"))
        let personal = try XCTUnwrap(state.createCategory(name: "Personal"))
        let history = Note(id: UUID(), text: "Saved history", dayKey: "2026-10-05",
                           createdAt: Date(timeIntervalSince1970: 10),
                           completedAt: Date(timeIntervalSince1970: 20), categoryID: work.id)
        do {
            let repository = try SQLiteNoteRepository(databaseURL: url)
            try repository.add(history)
        }
        state.draft = "Existing Today"
        state.draftCategoryID = personal.id
        XCTAssertTrue(state.addDraft())
        let todayBefore = try rows("notes")
        state.categoryPreferences.setCollapsed(true, for: .general, in: .today)
        let todayChoice = defaults.object(forKey: TaskCategoryPreferences.lastUsedCategoryIDKey) as? String
        let todayCollapse = defaults.object(forKey: TaskCategoryPreferences.collapsedGroupIDsKey) as? [String]
        state.laterDraft = "Complete and edit"
        state.laterDraftCategoryID = work.id
        XCTAssertTrue(state.addLaterDraft())
        let completed = try XCTUnwrap(state.laterTasks.first)
        state.laterDraft = "Move once"
        state.laterDraftCategoryID = personal.id
        XCTAssertTrue(state.addLaterDraft())
        let moved = try XCTUnwrap(state.laterTasks.last)
        state.laterDraft = "Keep in Later"
        state.laterDraftCategoryID = work.id
        XCTAssertTrue(state.addLaterDraft())
        let retained = try XCTUnwrap(state.laterTasks.last)
        XCTAssertTrue(state.setLaterCompleted(id: completed.id, completed: true))
        state.beginEditingLater(id: completed.id)
        state.laterEditDraft = "Edited ' task 📝"
        XCTAssertTrue(state.saveLaterEdit())
        XCTAssertEqual(try rows("notes"), todayBefore)
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 1))
        XCTAssertTrue(state.moveLaterToToday(id: moved.id))
        XCTAssertFalse(state.moveLaterToToday(id: moved.id))
        XCTAssertEqual(state.notes.last?.id, moved.id)
        XCTAssertEqual(state.notes.last?.createdAt, moved.createdAt)
        XCTAssertEqual(state.notes.last?.dayKey, "2026-10-06")
        XCTAssertNotNil(state.renameCategory(id: personal.id, name: "Home"))
        XCTAssertEqual(state.categoryUsageCount(id: work.id), 3)
        XCTAssertTrue(state.removeCategory(id: work.id))
        XCTAssertEqual(state.laterTasks, [
            LaterTask(id: completed.id, text: "Edited ' task 📝", createdAt: completed.createdAt,
                      completedAt: current),
            LaterTask(id: retained.id, text: retained.text, createdAt: retained.createdAt, completedAt: nil)
        ])
        XCTAssertEqual(state.categories.map(\.name), ["Home"])
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 2))
        XCTAssertEqual(state.availableLaterRemainingCount, 1)
        // Shared removal only clears assignments; history metadata and rowids survive.
        XCTAssertEqual(try rows("notes").map { Array($0.prefix(6)) }.prefix(2),
                       todayBefore.map { Array($0.prefix(6)) }.prefix(2))
        // Column 6 is category_id; schema v4 appends display_order after it.
        XCTAssertNil(try rows("notes").first?[6] ?? nil)
        let notesAfter = try rows("notes")
        let laterAfter = try rows("later_tasks")
        let categoriesAfter = try rows("categories")
        let defaultsAfter = defaults.dictionaryRepresentation() as NSDictionary
        let savedToday = state.notes
        let savedLater = state.laterTasks
        state.stopForTermination()

        // Fresh connection and preference owner; no seed runs on reopen.
        let reopened = makeState()
        defer { reopened.stopForTermination() }
        reopened.startup()
        XCTAssertEqual(reopened.notes, savedToday)
        XCTAssertEqual(reopened.laterTasks, savedLater)
        XCTAssertEqual(reopened.categories.map(\.name), ["Home"])
        XCTAssertEqual(try rows("notes"), notesAfter)
        XCTAssertEqual(try rows("later_tasks"), laterAfter)
        XCTAssertEqual(try rows("categories"), categoriesAfter)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, defaultsAfter)
        XCTAssertEqual(defaults.data(forKey: PreferencesStore.storageKey), preferencesBytes)
        XCTAssertTrue(defaults.bool(forKey: UserDefaultsOnboardingStore.storageKey))
        XCTAssertEqual(defaults.string(forKey: TaskCategoryPreferences.lastUsedCategoryIDKey), todayChoice)
        XCTAssertEqual(defaults.stringArray(forKey: TaskCategoryPreferences.collapsedGroupIDsKey), todayCollapse)
        XCTAssertEqual(reopened.categoryPreferences.lastUsedCategoryID, personal.id)
        XCTAssertNil(reopened.categoryPreferences.laterLastUsedCategoryID)
    }

    func testLaterReadFailureDoesNotInvalidateTodayOrMenuBarProgress() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let today = note("Today note", day: "2026-09-27", createdAt: 1)
        let later = laterTask("Later task", createdAt: 2, categoryID: work.id)
        let store = FakeNoteRepository(notes: [today], categories: [work], laterTasks: [later])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })

        store.failLaterRead = true
        state.startup()

        XCTAssertTrue(state.hasLoadedToday)
        XCTAssertEqual(state.notes, [today])
        XCTAssertEqual(state.availableProgress, NoteProgress(completed: 0, total: 1))
        XCTAssertEqual(state.availableCategories, [work])
        XCTAssertNil(state.readIssue)

        XCTAssertFalse(state.hasLoadedLater)
        XCTAssertNil(state.availableLaterTasks)
        XCTAssertNil(state.availableLaterRemainingCount)
        XCTAssertEqual(state.laterReadIssue, .load)

        store.failLaterRead = false
        state.refresh()
        XCTAssertTrue(state.hasLoadedLater)
        XCTAssertEqual(state.availableLaterTasks, [later])
        XCTAssertEqual(state.availableLaterRemainingCount, 1)
        XCTAssertNil(state.laterReadIssue)
    }

    func testTodayReadFailureDoesNotInvalidateLaterSnapshot() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let today = note("Today note", day: "2026-09-27", createdAt: 1)
        let later = laterTask("Later task", createdAt: 2, categoryID: work.id)
        let store = FakeNoteRepository(notes: [today], categories: [work], laterTasks: [later])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })

        store.failSnapshotRead = .notes
        state.startup()

        XCTAssertFalse(state.hasLoadedToday)
        XCTAssertNil(state.availableProgress)
        XCTAssertEqual(state.readIssue, .load)

        XCTAssertTrue(state.hasLoadedLater)
        XCTAssertEqual(state.laterTasks, [later])
        XCTAssertEqual(state.availableLaterTasks, [later])
        XCTAssertEqual(state.availableLaterRemainingCount, 1)
        XCTAssertEqual(state.availableCategories, [work])
        XCTAssertNil(state.laterReadIssue)
        XCTAssertEqual(state.laterGroups.count, 1)
        XCTAssertEqual(state.laterGroups[0].name, "Work")
    }

    func testCatalogReadFailureInvalidatesBothTodayAndLater() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let today = note("Today note", day: "2026-09-27", createdAt: 1)
        let later = laterTask("Later task", createdAt: 2, categoryID: work.id)
        let store = FakeNoteRepository(notes: [today], categories: [work], laterTasks: [later])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") })

        store.failSnapshotRead = .categories
        state.startup()

        XCTAssertFalse(state.hasLoadedCatalog)
        XCTAssertFalse(state.hasLoadedToday)
        XCTAssertFalse(state.hasLoadedLater)
        XCTAssertNil(state.availableCategories)
        XCTAssertNil(state.availableProgress)
        XCTAssertNil(state.availableLaterTasks)
        XCTAssertEqual(state.readIssue, .load)
        XCTAssertEqual(state.laterReadIssue, .load)
    }

    func testDayChangeInvalidatesTodayEditingButPreservesLaterEditingAndDraft() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let today = note("Today note", day: "2026-09-27", createdAt: 1)
        let later = laterTask("Later task", createdAt: 2, categoryID: work.id)
        let store = FakeNoteRepository(notes: [today], categories: [work], laterTasks: [later])
        var currentInstant = instant("2026-09-27T23:59:00-04:00")
        let state = makeState(store: store, now: { currentInstant })
        state.startup()

        state.beginEditing(id: today.id)
        state.editDraft = "Updated today draft"

        state.beginEditingLater(id: later.id)
        state.laterEditDraft = "Updated later draft"
        state.laterDraft = "New later item draft"
        state.laterDraftCategoryID = work.id

        currentInstant = instant("2026-09-28T00:01:00-04:00")
        state.refresh()

        XCTAssertNil(state.editingNoteID)
        XCTAssertEqual(state.recoveredEdit?.text, "Updated today draft")
        XCTAssertNotNil(state.refreshNotice)

        XCTAssertEqual(state.editingLaterTaskID, later.id)
        XCTAssertEqual(state.laterEditDraft, "Updated later draft")
        XCTAssertEqual(state.laterDraft, "New later item draft")
        XCTAssertEqual(state.laterDraftCategoryID, work.id)
        XCTAssertNil(state.laterRecoveredEdit)
    }

    func testLaterDraftAndEditLifecycleAndCategoryReconciliation() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let later = laterTask("Later task", createdAt: 2, categoryID: work.id)
        let defaults = isolatedDefaults()
        let preferences = TaskCategoryPreferences(userDefaults: defaults)
        preferences.rememberLastUsed(work.id, in: .later)

        let store = FakeNoteRepository(categories: [work], laterTasks: [later])
        let state = makeState(store: store, now: { self.instant("2026-09-27T12:00:00-04:00") }, preferences: preferences)
        state.startup()

        state.startNewLaterDraft()
        XCTAssertEqual(state.laterDraftCategoryID, work.id)
        state.cancelLaterDraft()
        XCTAssertEqual(state.laterDraft, "")
        XCTAssertNil(state.laterDraftCategoryID)

        state.beginEditingLater(id: later.id)
        state.laterEditDraft = "Editing text"
        state.startNewLaterDraft()
        state.laterDraft = "Draft text"

        XCTAssertTrue(state.removeCategory(id: work.id))

        XCTAssertNil(state.laterDraftCategoryID)
        XCTAssertEqual(state.laterDraft, "Draft text")

        XCTAssertNil(state.editingLaterTaskID)
        XCTAssertEqual(state.laterRecoveredEdit?.text, "Editing text")
        XCTAssertEqual(state.laterRecoveredEdit?.categoryName, "Work")
        XCTAssertNotNil(state.laterRefreshNotice)
    }
}

private enum FakeFailure: Error { case failed }

private enum FakeSnapshotRead: CaseIterable {
    case categories, notes, count
}

private final class FakeNoteRepository: NoteRepository {
    var saved: [Note]
    var savedCategories: [TaskCategory]
    var savedLaterTasks: [LaterTask]
    var onRead: ((String) -> Void)?
    var onCategoryRead: (() -> Void)?
    var onCategoryWrite: (() -> Void)?
    var onLaterRead: (() -> Void)?
    var uncheckedNotes: [Note]?
    var uncheckedLaterTasks: [LaterTask]?
    var failSnapshotRead: FakeSnapshotRead?
    var failLaterRead = false
    var failCategoryCommand: CategoryCommandIssue?
    var readAttempts = 0
    var categoryWriteAttempts = 0
    var failCount = false
    var failWrite: DailyNotesIssue?
    var failLaterWrite: DailyNotesIssue?
    var laterWriteAttempts = 0
    var moveAttempts = 0
    var onMove: (() -> Void)?

    init(notes: [Note] = [], categories: [TaskCategory] = [], laterTasks: [LaterTask] = []) {
        saved = notes
        savedCategories = categories
        savedLaterTasks = laterTasks
    }

    func historyDaySnapshot(for dayKey: String) throws -> HistoryDaySnapshot {
        _ = try GregorianDay(key: dayKey)
        let catalog = try categories()
        return try HistoryDaySnapshot(dayKey: dayKey, notes: notes(for: dayKey), categories: catalog)
    }

    func unfinishedDayPage(before: GregorianDay, limit: Int) throws -> UnfinishedDayPage {
        guard limit > 0, limit < Int.max else { throw TaskHistoryDomainError.invalidPage }
        if failSnapshotRead != nil { throw FakeFailure.failed }
        let notes = try saved.filter { try GregorianDay(key: $0.dayKey) < before }
        let summaries = try Dictionary(grouping: notes, by: \.dayKey).keys.sorted(by: >).map { dayKey in
            try DayTaskSummary(dayKey: dayKey, progress: NoteProgress(notes: notes, for: dayKey))
        }.filter { $0.incomplete > 0 }
        return try UnfinishedDayPage(before: before, limit: limit,
                                     summaries: Array(summaries.prefix(limit)),
                                     hasMore: summaries.count > limit)
    }

    func daySummaries(in range: HistoryDayRange) throws -> [DayTaskSummary] {
        if failSnapshotRead != nil { throw FakeFailure.failed }
        let notes = try saved.filter { range.contains(try GregorianDay(key: $0.dayKey)) }
        return try Dictionary(grouping: notes, by: \.dayKey).keys.sorted().map { dayKey in
            try DayTaskSummary(dayKey: dayKey, progress: NoteProgress(notes: notes, for: dayKey))
        }
    }

    func moveTask(_ request: TaskMoveRequest) throws -> TaskMoveOutcome {
        moveAttempts += 1
        onMove?()
        if failWrite == .move { throw FakeFailure.failed }
        let outcome = TaskMovePlanner.plan(request, dayKey: request.expectedDayKey,
                                           notes: try notes(for: request.expectedDayKey),
                                           categories: try categories())
        if case let .changed(ordered) = outcome {
            saved.removeAll { $0.dayKey == request.expectedDayKey }
            saved.append(contentsOf: ordered)
        }
        return outcome
    }

    func categories() throws -> [TaskCategory] {
        readAttempts += 1
        onCategoryRead?()
        if failSnapshotRead == .categories { throw FakeFailure.failed }
        return savedCategories.sorted { $0.creationOrder < $1.creationOrder }
    }

    func createCategory(name: String) throws -> TaskCategory {
        categoryWriteAttempts += 1
        if failCategoryCommand == .create { throw FakeFailure.failed }
        let name = try TaskCategoryName.validate(name)
        guard !savedCategories.contains(where: { $0.nameKey == TaskCategoryName.key(for: name) }) else {
            throw TaskCategoryRepositoryError.duplicateName
        }
        let next = (savedCategories.map(\.creationOrder).max() ?? -1).addingReportingOverflow(1)
        guard !next.overflow else { throw TaskCategoryRepositoryError.orderExhausted }
        let category = try TaskCategory(name: name, creationOrder: next.partialValue)
        savedCategories.append(category)
        onCategoryWrite?()
        return category
    }

    func renameCategory(id: UUID, name: String) throws -> TaskCategory {
        categoryWriteAttempts += 1
        if failCategoryCommand == .rename { throw FakeFailure.failed }
        let name = try TaskCategoryName.validate(name)
        let original = try requireCategory(id)
        guard !savedCategories.contains(where: { $0.id != id && $0.nameKey == TaskCategoryName.key(for: name) }) else {
            throw TaskCategoryRepositoryError.duplicateName
        }
        let category = try TaskCategory(id: id, name: name, creationOrder: original.creationOrder)
        savedCategories[savedCategories.firstIndex(where: { $0.id == id })!] = category
        onCategoryWrite?()
        return category
    }

    func categoryUsageCount(id: UUID) throws -> Int {
        if failCategoryCommand == .usage { throw FakeFailure.failed }
        _ = try requireCategory(id)
        return saved.count { $0.categoryID == id } + savedLaterTasks.count { $0.categoryID == id }
    }

    func removeCategory(id: UUID) throws {
        categoryWriteAttempts += 1
        if failCategoryCommand == .remove { throw FakeFailure.failed }
        _ = try requireCategory(id)
        saved = saved.map { note in
            Note(id: note.id, text: note.text, dayKey: note.dayKey,
                 createdAt: note.createdAt, completedAt: note.completedAt,
                 categoryID: note.categoryID == id ? nil : note.categoryID)
        }
        savedLaterTasks = savedLaterTasks.map { task in
            LaterTask(id: task.id, text: task.text, createdAt: task.createdAt,
                      completedAt: task.completedAt,
                      categoryID: task.categoryID == id ? nil : task.categoryID)
        }
        savedCategories.removeAll { $0.id == id }
        onCategoryWrite?()
    }

    func notes(for dayKey: String) throws -> [Note] {
        readAttempts += 1
        onRead?(dayKey)
        if failSnapshotRead == .notes { throw FakeFailure.failed }
        if let uncheckedNotes { return uncheckedNotes }
        let notes = saved.filter { $0.dayKey == dayKey }
        for note in notes {
            if let id = note.categoryID { _ = try requireCategory(id) }
        }
        return notes
    }

    func incompleteCount(for dayKey: String) throws -> Int {
        readAttempts += 1
        if failCount || failSnapshotRead == .count { throw FakeFailure.failed }
        return saved.count { $0.dayKey == dayKey && !$0.isCompleted }
    }

    func add(_ note: Note) throws {
        if failWrite == .add { throw FakeFailure.failed }
        if let id = note.categoryID { _ = try requireCategory(id) }
        guard !saved.contains(where: { $0.id == note.id }) else { throw FakeFailure.failed }
        saved.append(note)
    }

    func setCompleted(id: UUID, completedAt: Date?) throws {
        if failWrite == .complete { throw FakeFailure.failed }
        try mutate(id: id) { note in
            Note(id: note.id, text: note.text, dayKey: note.dayKey,
                 createdAt: note.createdAt, completedAt: completedAt,
                 categoryID: note.categoryID)
        }
    }

    func update(id: UUID, text: String, categoryID: UUID?) throws {
        if failWrite == .edit { throw FakeFailure.failed }
        if let categoryID { _ = try requireCategory(categoryID) }
        try mutate(id: id) { note in
            Note(id: note.id, text: text, dayKey: note.dayKey,
                 createdAt: note.createdAt, completedAt: note.completedAt,
                 categoryID: categoryID)
        }
    }

    private func requireCategory(_ id: UUID) throws -> TaskCategory {
        guard let category = savedCategories.first(where: { $0.id == id }) else {
            throw TaskCategoryRepositoryError.notFound(id)
        }
        return category
    }

    func delete(id: UUID) throws {
        if failWrite == .delete { throw FakeFailure.failed }
        guard saved.contains(where: { $0.id == id }) else { throw FakeFailure.failed }
        saved.removeAll { $0.id == id }
    }

    func laterTasks() throws -> [LaterTask] {
        readAttempts += 1
        onLaterRead?()
        if failLaterRead { throw FakeFailure.failed }
        if let uncheckedLaterTasks { return uncheckedLaterTasks }
        for task in savedLaterTasks {
            if let id = task.categoryID { _ = try requireCategory(id) }
        }
        return savedLaterTasks
    }

    func addLater(_ task: LaterTask) throws {
        try checkLaterWrite(.add)
        if let id = task.categoryID { _ = try requireCategory(id) }
        guard !savedLaterTasks.contains(where: { $0.id == task.id }) else { throw FakeFailure.failed }
        savedLaterTasks.append(task)
    }
    func setLaterCompleted(id: UUID, completedAt: Date?) throws {
        try checkLaterWrite(.complete)
        try mutateLater(id: id) { task in
            LaterTask(id: task.id, text: task.text, createdAt: task.createdAt,
                      completedAt: completedAt, categoryID: task.categoryID)
        }
    }
    func updateLater(id: UUID, text: String, categoryID: UUID?) throws {
        try checkLaterWrite(.edit)
        if let categoryID { _ = try requireCategory(categoryID) }
        try mutateLater(id: id) { task in
            LaterTask(id: task.id, text: text, createdAt: task.createdAt,
                      completedAt: task.completedAt, categoryID: categoryID)
        }
    }
    func deleteLater(id: UUID) throws {
        try checkLaterWrite(.delete)
        guard savedLaterTasks.contains(where: { $0.id == id }) else { throw LaterTaskRepositoryError.notFound(id) }
        savedLaterTasks.removeAll { $0.id == id }
    }
    func moveLaterToToday(id: UUID, dayKey: String) throws -> Note {
        moveAttempts += 1
        try checkLaterWrite(.moveToToday)
        onMove?()
        guard let task = savedLaterTasks.first(where: { $0.id == id }) else {
            throw LaterTaskRepositoryError.notFound(id)
        }
        guard !task.isCompleted else { throw LaterTaskRepositoryError.alreadyCompleted(id) }
        if let categoryID = task.categoryID { _ = try requireCategory(categoryID) }
        guard !saved.contains(where: { $0.id == id }) else { throw LaterTaskRepositoryError.idCollision(id) }
        let note = Note(id: task.id, text: task.text, dayKey: dayKey, createdAt: task.createdAt,
                        completedAt: nil, categoryID: task.categoryID)
        saved.append(note)
        savedLaterTasks.removeAll { $0.id == id }
        return note
    }

    private func checkLaterWrite(_ issue: DailyNotesIssue) throws {
        laterWriteAttempts += 1
        if failLaterWrite == issue { throw FakeFailure.failed }
    }

    private func mutateLater(id: UUID, change: (LaterTask) -> LaterTask) throws {
        guard let index = savedLaterTasks.firstIndex(where: { $0.id == id }) else {
            throw LaterTaskRepositoryError.notFound(id)
        }
        savedLaterTasks[index] = change(savedLaterTasks[index])
    }

    private func mutate(id: UUID, change: (Note) -> Note) throws {
        guard let index = saved.firstIndex(where: { $0.id == id }) else { throw FakeFailure.failed }
        saved[index] = change(saved[index])
    }
}

/// Callback-level fixture; this does not simulate the system's native drag loop.
@MainActor
private final class MovementDraggingInfo: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .move
    var draggingLocation: NSPoint
    var draggedImageLocation: NSPoint { .zero }
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard(name: .init(UUID().uuidString))
    var draggingSource: Any?
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    init(source: TaskDragHandleView, token: UUID, window: NSWindow, point: NSPoint) {
        draggingSource = source
        draggingDestinationWindow = window
        draggingLocation = point
        super.init()
        let item = NSPasteboardItem()
        item.setString(token.uuidString, forType: TaskDragSession.pasteboardType)
        draggingPasteboard.writeObjects([item])
    }
    func resetSpringLoading() {}
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
