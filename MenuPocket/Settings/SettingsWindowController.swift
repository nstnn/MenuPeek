import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    static let initialContentSize = NSSize(width: 560, height: 440)
    static let minimumWindowSize = NSSize(width: 500, height: 380)

    init() {
        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Cài đặt MenuPocket"
        window.contentViewController = hostingController
        window.setContentSize(Self.initialContentSize)
        window.minSize = Self.minimumWindowSize
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
    }
}
