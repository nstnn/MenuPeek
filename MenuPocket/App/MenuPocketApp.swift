import AppKit
import SwiftUI

@main
struct MenuPocketApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuPocketPanel {
                appDelegate.showSettings()
            }
        } label: {
            Label("MenuPocket", systemImage: "square.grid.2x2")
                .labelStyle(.iconOnly)
                .accessibilityLabel("MenuPocket")
        }
        .menuBarExtraStyle(.window)
    }
}
