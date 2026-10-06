import AppKit
import Observation
import SwiftUI

/// The result of one capture-panel submission, mirroring the add outcomes of
/// `DailyNotesState` so the panel does not depend on saved-data state.
enum QuickAddSubmitResult: Equatable {
    case added
    case empty
    case unavailable
    case writeFailed

    var message: String? {
        switch self {
        case .added, .empty: nil
        case .unavailable: "Today's tasks are unavailable. Open MenuPocket to retry."
        case .writeFailed: "Could not save task. Try again."
        }
    }
}

@MainActor
@Observable
final class QuickAddPanelModel {
    var text = ""
    fileprivate(set) var errorMessage: String?
}

/// A borderless panel that takes keyboard focus without activating MenuPocket.
final class QuickAddPanel: NSPanel {
    /// Called for Escape and ⌘W.
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func sendEvent(_ event: NSEvent) {
        if isEscape(event) {
            onCancel?()
            return
        }
        super.sendEvent(event)
    }

    /// Claims Escape before the SwiftUI host or field editor can, so dismissal
    /// does not depend on `cancelOperation` reaching the panel. An input method
    /// that is composing keeps Escape.
    private func isEscape(_ event: NSEvent) -> Bool {
        event.type == .keyDown && event.keyCode == 53 &&
            event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock).isEmpty &&
            (firstResponder as? NSTextView)?.hasMarkedText() != true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isEscape(event) {
            onCancel?()
            return true
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard modifiers == .command || modifiers == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let action: Selector?
        switch (key, modifiers.contains(.shift)) {
        case ("w", false):
            onCancel?()
            return true
        // Quitting, adding in the Today window, switching its list, or opening
        // Settings from a capture panel would be surprising, so these do nothing.
        case ("q", false), ("n", false), ("1", false), ("2", false), (",", false):
            return true
        // The frontmost app may own the menu bar, so send standard edit
        // commands to the field directly instead of relying on the main menu.
        case ("x", false): action = #selector(NSText.cut(_:))
        case ("c", false): action = #selector(NSText.copy(_:))
        case ("v", false): action = #selector(NSText.paste(_:))
        case ("a", false): action = #selector(NSText.selectAll(_:))
        case ("z", false): action = Selector(("undo:"))
        case ("z", true): action = Selector(("redo:"))
        default: action = nil
        }
        if let action, NSApplication.shared.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Owns the one reusable Quick Add panel. Saving is supplied by the caller, so
/// the panel never reads or changes the Today window's state.
@MainActor
final class QuickAddPanelController: NSObject, NSWindowDelegate {
    static let contentWidth: CGFloat = 480

    let panel: QuickAddPanel
    let model = QuickAddPanelModel()
    private let submitText: (String) -> QuickAddSubmitResult
    private let undoManager = UndoManager()
    private weak var previousKeyWindow: NSWindow?

    init(submit: @escaping (String) -> QuickAddSubmitResult) {
        submitText = submit
        panel = QuickAddPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        super.init()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.title = "Quick Add"
        let hostingController = NSHostingController(
            rootView: QuickAddPanelView(model: model) { [weak self] in self?.submit() }
        )
        hostingController.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hostingController
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.dismiss() }
    }

    var isShown: Bool { panel.isVisible }

    func toggle() {
        if isShown { dismiss() } else { show() }
    }

    func show() {
        guard !isShown else { return }
        let app = NSApplication.shared
        previousKeyWindow = app.isActive && app.keyWindow !== panel ? app.keyWindow : nil
        reset()
        panel.layoutIfNeeded()
        position()
        panel.makeKeyAndOrderFront(nil)
        focusField()
    }

    func dismiss() {
        guard isShown else { return }
        panel.makeFirstResponder(nil)
        panel.orderOut(nil)
        reset()
        if let window = previousKeyWindow, window.isVisible, NSApplication.shared.isActive {
            window.makeKeyAndOrderFront(nil)
        }
        previousKeyWindow = nil
    }

    func submit() {
        guard isShown else { return }
        guard !model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let result = submitText(model.text)
        if result == .added {
            dismiss()
        } else {
            model.errorMessage = result.message
        }
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Clicking another window or app discards the capture.
        dismiss()
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { undoManager }

    // MARK: Private

    private func reset() {
        model.text = ""
        model.errorMessage = nil
        undoManager.removeAllActions()
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: (visible.midX - size.width / 2).rounded(),
                                     y: (visible.midY - size.height / 2).rounded()))
    }

    private func focusField() {
        guard let field = Self.firstTextField(in: panel.contentView) else { return }
        panel.makeFirstResponder(field)
    }

    private static func firstTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let field = firstTextField(in: subview) { return field }
        }
        return nil
    }
}

struct QuickAddPanelView: View {
    @Bindable var model: QuickAddPanelModel
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Add a task for today", text: $model.text)
                .textFieldStyle(.plain)
                .font(.title2)
                .accessibilityLabel("Quick Add task")
                .accessibilityIdentifier("quickAddField")
                .onSubmit(onSubmit)
            if let message = model.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("quickAddError")
            }
        }
        .padding(16)
        .frame(width: QuickAddPanelController.contentWidth, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
