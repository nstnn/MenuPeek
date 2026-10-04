import AppKit
import Observation
import SwiftUI

/// Shares input modality across windows without changing the first responder.
/// Text fields keep their normal editing focus; only control decoration uses this state.
@MainActor
@Observable
final class KeyboardFocusVisibility {
    static let shared = KeyboardFocusVisibility()
    private(set) var isVisible = false
    @ObservationIgnored private var eventMonitor: Any?

    private init() {
        // One app-local monitor, retained for the application's lifetime. It
        // observes input without consuming events or requiring a global permission.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseUp, .rightMouseUp, .otherMouseUp, .keyDown
        ]) { [weak self] event in
            self?.observe(event)
            return event
        }
    }

    private func observe(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown,
             .leftMouseUp, .rightMouseUp, .otherMouseUp:
            isVisible = false
        case .keyDown where event.keyCode == 48 &&
            event.modifierFlags.intersection([.command, .control, .option]).isEmpty:
            // Tab and Shift-Tab enter keyboard navigation. Other typing and
            // shortcuts leave the mode alone, including focus restoration.
            isVisible = true
        default:
            break
        }
    }
}

private struct KeyboardFocusAppearance: ViewModifier {
    @State private var visibility = KeyboardFocusVisibility.shared

    func body(content: Content) -> some View {
        content.focusEffectDisabled(!visibility.isVisible)
    }
}

extension View {
    /// Apply to non-text controls, never to a container that includes text fields.
    func keyboardFocusAppearance() -> some View {
        modifier(KeyboardFocusAppearance())
    }
}
