import AppKit
import SwiftUI

@main
struct MenuPocketApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuPocketPanel(model: appDelegate.model) {
                appDelegate.showSettings()
            }
        } label: {
            if let text = appDelegate.model.menuBarDisplayText {
                Label(text, systemImage: "square.grid.2x2")
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel("MenuPocket, \(text)")
            } else {
                Label("MenuPocket", systemImage: "square.grid.2x2")
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("MenuPocket")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
