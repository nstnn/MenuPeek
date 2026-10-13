import AppKit
import SwiftUI
import XCTest
@testable import MenuPocket

@MainActor
final class MenuBarGlanceMenuTests: XCTestCase {
    private let day = "2026-10-07"
    private let actionTitles = ["Open Today", "Add Task…", "Settings…", "Quit MenuPocket"]
    private var calls: [String] = []

    override func setUp() async throws {
        calls = []
    }

    // MARK: Structure per state

    func testTasksStateListsRowsOverflowLaterLineAndActionsInTheAgreedOrder() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let notes = (1...7).map { note("Task \($0)", $0.isMultiple(of: 2) ? work : nil) }

        let menu = make(notes: notes, categories: [work], laterCount: 3)

        XCTAssertEqual(layout(menu), ["header", "-",
                                      "Task 1\tGeneral", "Task 3\tGeneral", "Task 5\tGeneral",
                                      "Task 7\tGeneral", "Task 2\tWork", "2 more in Today", "-",
                                      "Later · 3 remaining", "-"] + actionTitles)
    }

    func testOneGroupShowsPlainTitlesAndNoOverflowAtTheLimit() {
        let notes = (1...5).map { note("Task \($0)", nil) }

        let menu = make(notes: notes)

        XCTAssertEqual(layout(menu), ["header", "-", "Task 1", "Task 2", "Task 3", "Task 4", "Task 5", "-"]
                       + actionTitles)
        XCTAssertTrue(menu.items[2...6].allSatisfy { $0.attributedTitle == nil })
    }

    func testEmptyAllDoneAndUnavailableStatesShowTheirDisabledRow() {
        let empty = make(progress: NoteProgress(completed: 0, total: 0))
        XCTAssertEqual(layout(empty), ["header", "-", "No tasks yet", "-"] + actionTitles)
        XCTAssertFalse(empty.items[2].isEnabled)

        let allDone = make(notes: [note("A", nil, completed: true)])
        XCTAssertEqual(layout(allDone), ["header", "-", "All done", "-"] + actionTitles)
        XCTAssertFalse(allDone.items[2].isEnabled)

        let unavailable = make(progress: nil)
        XCTAssertEqual(layout(unavailable), ["header", "-", "Tasks are unavailable.", "Retry", "-"] + actionTitles)
        XCTAssertFalse(unavailable.items[2].isEnabled)
        XCTAssertTrue(unavailable.items[3].isEnabled)
    }

    func testLaterLineAppearsInEveryTodayStateOnlyForAPositiveCount() {
        let states: [(NoteProgress?, [Note])] = [
            (NoteProgress(completed: 0, total: 0), []),
            (nil, []),
            (NoteProgress(completed: 1, total: 1), [note("A", nil, completed: true)]),
            (NoteProgress(completed: 0, total: 1), [note("A", nil)]),
        ]
        for (progress, notes) in states {
            for count in [nil, 0, 1, 3] as [Int?] {
                let titles = layout(make(progress: progress, notes: notes, laterCount: count))
                let later = titles.filter { $0.hasPrefix("Later") }
                if let count, count > 0 {
                    XCTAssertEqual(later, ["Later · \(count) remaining"])
                    let index = titles.firstIndex(of: later[0])!
                    XCTAssertEqual(titles[index - 1], "-", "The Later line has its own section")
                    XCTAssertEqual(titles[index + 1], "-")
                } else {
                    XCTAssertEqual(later, [], "count \(String(describing: count))")
                }
            }
        }
    }

    // MARK: Items

    func testHeaderIsADisabledCustomViewItemThatTracksTheMenuWidth() throws {
        for menu in [make(notes: [note("A", nil)]), make(progress: nil)] {
            let header = menu.items[0]
            XCTAssertFalse(header.isEnabled)
            XCTAssertNil(header.action)
            let view = try XCTUnwrap(header.view)
            XCTAssertEqual(view.frame.width, MenuBarGlanceMenu.minimumWidth)
            XCTAssertGreaterThan(view.frame.height, 0)
            XCTAssertTrue(view.autoresizingMask.contains(.width))
        }
    }

    func testHeaderViewShowsTheGlanceHeaderInEveryState() throws {
        let cases: [(NoteProgress?, String, Double?)] = [
            (NoteProgress(completed: 4, total: 7), "4 of 7 done", 4.0 / 7.0),
            (NoteProgress(completed: 0, total: 0), "0 of 0 done", 0),
            (nil, "—", nil),
        ]
        for (progress, count, fraction) in cases {
            let glance = MenuBarGlance(dayKey: day, progress: progress, groups: [],
                                       laterRemainingCount: nil, canAddTask: true)
            let menu = MenuBarGlanceMenu.make(glance, actions: actions)
            let view = try XCTUnwrap(menu.items[0].view as? NSHostingView<MenuBarGlanceHeaderView>)

            XCTAssertEqual(view.rootView.header, glance.header)
            XCTAssertEqual(view.rootView.header.dateLabel, "Wed 7 Oct")
            XCTAssertEqual(view.rootView.header.countLabel, count)
            XCTAssertEqual(view.rootView.header.fraction, fraction, "nil draws no bar")
        }
    }

    func testRowsAreEnabledAndOnlyTruncatedRowsHaveATooltip() {
        let long = String(repeating: "word ", count: 20).trimmingCharacters(in: .whitespaces)
        let menu = make(notes: [note("Short", nil), note(long, nil)])

        XCTAssertTrue(menu.items[2].isEnabled)
        XCTAssertNil(menu.items[2].toolTip)
        XCTAssertTrue(menu.items[3].isEnabled)
        XCTAssertTrue(menu.items[3].title.hasSuffix("…"))
        XCTAssertEqual(menu.items[3].toolTip, long)
    }

    func testCategoriesShareOneRightTabStop() throws {
        let work = try TaskCategory(name: "Work", creationOrder: 0)
        let menu = make(notes: [note("Short", work), note("A much longer task title", nil)], categories: [work])

        let stops = try [2, 3].map { index -> [NSTextTab] in
            let title = try XCTUnwrap(menu.items[index].attributedTitle)
            let style = try XCTUnwrap(title.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            return style.tabStops
        }
        XCTAssertEqual(stops[0], stops[1])
        XCTAssertEqual(stops[0].map(\.alignment), [.right])
    }

    func testAddTaskFollowsTheModelAndNoItemHasAKeyEquivalent() {
        let progress = NoteProgress(completed: 0, total: 0)
        for (canAdd, progress) in [(true, progress), (false, progress), (true, nil)] as [(Bool, NoteProgress?)] {
            let menu = make(progress: progress, canAddTask: canAdd)
            let add = menu.items.first { $0.title == "Add Task…" }
            XCTAssertEqual(add?.isEnabled, canAdd && progress != nil)
            XCTAssertFalse(menu.autoenablesItems)
            XCTAssertTrue(menu.items.allSatisfy { $0.keyEquivalent.isEmpty })
            XCTAssertTrue(menu.items.filter { !$0.isSeparatorItem && $0.title != "Add Task…" && $0.action != nil }
                .allSatisfy(\.isEnabled))
        }
    }

    // MARK: Actions

    func testEachItemRunsItsClosureAndBuildingRunsNone() {
        let unavailable = make(progress: nil, laterCount: 2)
        XCTAssertEqual(calls, [], "Building the menu has no side effect")

        for title in ["Retry", "Later · 2 remaining", "Open Today", "Settings…", "Quit MenuPocket"] {
            perform(title, in: unavailable)
        }
        XCTAssertEqual(calls, ["retry", "openLater", "openToday", "showSettings", "quit"])

        calls = []
        let tasks = make(notes: (1...6).map { note("Task \($0)", nil) })
        perform("Task 1", in: tasks)
        perform("1 more in Today", in: tasks)
        perform("Add Task…", in: tasks)
        XCTAssertEqual(calls, ["openToday", "openToday", "addTask"])
    }

    // MARK: Helpers

    private func make(progress: NoteProgress?, notes: [Note] = [], laterCount: Int? = nil,
                      canAddTask: Bool = true) -> NSMenu {
        let glance = MenuBarGlance(dayKey: day, progress: progress,
                                   groups: TaskGroup.groups(categories: [], notes: notes),
                                   laterRemainingCount: laterCount, canAddTask: canAddTask)
        return MenuBarGlanceMenu.make(glance, actions: actions)
    }

    private func make(notes: [Note], categories: [TaskCategory] = [], laterCount: Int? = nil) -> NSMenu {
        let glance = MenuBarGlance(dayKey: day, progress: NoteProgress(notes: notes, for: day),
                                   groups: TaskGroup.groups(categories: categories, notes: notes),
                                   laterRemainingCount: laterCount, canAddTask: true)
        return MenuBarGlanceMenu.make(glance, actions: actions)
    }

    private var actions: MenuBarGlanceActions {
        MenuBarGlanceActions(openToday: { [weak self] in self?.calls.append("openToday") },
                             addTask: { [weak self] in self?.calls.append("addTask") },
                             openLater: { [weak self] in self?.calls.append("openLater") },
                             showSettings: { [weak self] in self?.calls.append("showSettings") },
                             quit: { [weak self] in self?.calls.append("quit") },
                             retry: { [weak self] in self?.calls.append("retry") })
    }

    /// "header" for the custom view, "-" for separators, else the visible title.
    private func layout(_ menu: NSMenu) -> [String] {
        menu.items.map { item in
            if item.isSeparatorItem { return "-" }
            if item.view != nil { return "header" }
            return item.attributedTitle?.string ?? item.title
        }
    }

    private func perform(_ title: String, in menu: NSMenu) {
        guard let index = layout(menu).firstIndex(where: { $0 == title || $0.hasPrefix(title + "\t") }) else {
            return XCTFail("No item \(title)")
        }
        menu.performActionForItem(at: index)
    }

    private func note(_ text: String, _ category: TaskCategory?, completed: Bool = false) -> Note {
        let instant = Date(timeIntervalSince1970: 1_790_000_000)
        return Note(id: UUID(), text: text, dayKey: day, createdAt: instant,
                    completedAt: completed ? instant : nil, categoryID: category?.id)
    }
}
