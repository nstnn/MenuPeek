import AppKit
import XCTest
@testable import MenuPocket

@MainActor
final class QuickAddPanelTests: XCTestCase {
    private func makeController(
        submit: @escaping (String) -> QuickAddSubmitResult = { _ in .added }
    ) -> QuickAddPanelController {
        let controller = QuickAddPanelController(submit: submit)
        // Capture only the main-actor controller, never the test case: Swift 6.0
        // (CI's Xcode 16.4) rejects sending a non-Sendable XCTestCase to the main actor.
        addTeardownBlock { @MainActor in
            controller.dismiss()
            controller.panel.close()
        }
        return controller
    }

    private func key(_ characters: String, _ modifiers: NSEvent.ModifierFlags = .command,
                     keyCode: UInt16 = 0) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                         timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: keyCode)!
    }

    func testPanelIsNonActivatingKeyableAndStaysOutOfWindowCycling() {
        let panel = makeController().panel
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.styleMask.contains(.titled))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.isExcludedFromWindowsMenu)
        XCTAssertFalse(panel.isReleasedWhenClosed)
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
        XCTAssertFalse(panel.isVisible)
    }

    func testShowFocusesTheFieldAndToggleReusesOnePanel() {
        let controller = makeController()
        let panel = controller.panel
        controller.toggle()
        XCTAssertTrue(panel.isVisible)
        let editor = panel.firstResponder as? NSTextView
        XCTAssertTrue(editor?.isFieldEditor == true)
        XCTAssertNotNil(editor?.delegate as? NSTextField)
        controller.toggle()
        XCTAssertFalse(panel.isVisible)
        controller.toggle()
        XCTAssertTrue(controller.panel === panel)
        XCTAssertTrue(panel.isVisible)
    }

    func testAddedSubmissionSavesTextAndClosesWithNothingRetained() {
        var submitted: [String] = []
        let controller = makeController { submitted.append($0); return .added }
        controller.show()
        controller.model.text = "  Buy milk "
        controller.submit()
        XCTAssertEqual(submitted, ["  Buy milk "])
        XCTAssertFalse(controller.isShown)
        XCTAssertEqual(controller.model.text, "")
        XCTAssertNil(controller.model.errorMessage)
    }

    func testFailedSubmissionKeepsPanelOpenWithTextAndInlineError() {
        var result = QuickAddSubmitResult.writeFailed
        let controller = makeController { _ in result }
        controller.show()
        controller.model.text = "Call the bank"
        controller.submit()
        XCTAssertTrue(controller.isShown)
        XCTAssertEqual(controller.model.text, "Call the bank")
        XCTAssertEqual(controller.model.errorMessage, QuickAddSubmitResult.writeFailed.message)
        result = .unavailable
        controller.submit()
        XCTAssertTrue(controller.isShown)
        XCTAssertEqual(controller.model.errorMessage, QuickAddSubmitResult.unavailable.message)
        result = .added
        controller.submit()
        XCTAssertFalse(controller.isShown)
        controller.show()
        XCTAssertNil(controller.model.errorMessage)
    }

    func testEmptyInputDoesNotSubmitAndKeepsPanelOpen() {
        var calls = 0
        let controller = makeController { _ in calls += 1; return .empty }
        controller.show()
        controller.model.text = " \n\t "
        controller.submit()
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(controller.isShown)
        controller.model.text = "x"
        controller.submit()
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(controller.isShown)
        XCTAssertNil(controller.model.errorMessage)
    }

    func testEscapeCommandWAndResignKeyDiscardTextErrorAndUndoHistory() throws {
        let controller = makeController { _ in .writeFailed }
        let panel = controller.panel
        let dismissals: [() -> Void] = [
            { panel.sendEvent(self.key("\u{1b}", [], keyCode: 53)) },
            { XCTAssertTrue(panel.performKeyEquivalent(with: self.key("\u{1b}", [], keyCode: 53))) },
            { XCTAssertTrue(panel.performKeyEquivalent(with: self.key("w"))) },
            { controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel)) },
        ]
        for dismiss in dismissals {
            controller.show()
            controller.model.text = "Unsent"
            controller.submit()
            let undoManager = try XCTUnwrap(panel.undoManager)
            // Any registered action proves history exists. The handler is @Sendable in the
            // macOS 15 SDK (CI's Xcode 16.4), so it must not touch the main-actor model.
            undoManager.registerUndo(withTarget: controller.model) { _ in }
            XCTAssertTrue(undoManager.canUndo)
            dismiss()
            XCTAssertFalse(panel.isVisible)
            XCTAssertEqual(controller.model.text, "")
            XCTAssertNil(controller.model.errorMessage)
            XCTAssertFalse(undoManager.canUndo)
            controller.show()
            XCTAssertEqual(controller.model.text, "")
            XCTAssertFalse(undoManager.canUndo)
            controller.dismiss()
        }
    }

    func testQuitNewTaskAndSettingsShortcutsDoNothingWhileShown() {
        var calls = 0
        let controller = makeController { _ in calls += 1; return .added }
        let panel = controller.panel
        controller.show()
        controller.model.text = "Keep me"
        for shortcut in ["q", "n", ","] {
            XCTAssertTrue(panel.performKeyEquivalent(with: key(shortcut)), shortcut)
        }
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(controller.model.text, "Keep me")
        XCTAssertEqual(calls, 0)
        // Other command combinations are not claimed by the panel.
        XCTAssertFalse(panel.performKeyEquivalent(with: key("q", [.command, .option])))
    }

    func testSubmitIsIgnoredWhileHidden() {
        var calls = 0
        let controller = makeController { _ in calls += 1; return .added }
        controller.model.text = "Stale"
        controller.submit()
        XCTAssertEqual(calls, 0)
    }
}
