import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    static let initialContentSize = NSSize(width: 560, height: 440)
    static let minimumWindowSize = NSSize(width: 500, height: 380)

    init(model: AppModel, initialTab: SettingsTab = .content) {
        let hostingController = NSHostingController(
            rootView: SettingsView(model: model, initialTab: initialTab)
        )
        // The window owns its resize limits. Letting NSHostingController derive a
        // minimum from the current SwiftUI tab can silently replace the product's
        // 500 × 380 pt minimum after the window is shown.
        hostingController.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Cài đặt MenuPocket"
        window.contentViewController = hostingController
        window.setContentSize(Self.initialContentSize)
        Self.applyMinimumWindowSize(to: window)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func showSettings() {
        guard let window else { return }

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Showing an NSHostingController-backed window lets SwiftUI refresh the
        // window's minimum size. Reassert the product limit after that refresh.
        Self.applyMinimumWindowSize(to: window)
    }

    private static func applyMinimumWindowSize(to window: NSWindow) {
        let minimumFrame = NSRect(origin: .zero, size: minimumWindowSize)
        window.contentMinSize = window.contentRect(forFrameRect: minimumFrame).size
    }
}
