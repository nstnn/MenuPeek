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
            let presentation = appDelegate.model.menuBarPresentation
            if let text = presentation.displayText {
                Label(text, systemImage: "square.grid.2x2")
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel(presentation.accessibilityLabel)
            } else {
                Label("MenuPocket", systemImage: "square.grid.2x2")
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(presentation.accessibilityLabel)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
