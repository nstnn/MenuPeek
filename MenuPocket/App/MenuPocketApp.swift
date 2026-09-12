import SwiftUI

@main
struct MenuPocketApp: App {
    var body: some Scene {
        MenuBarExtra {
            MenuPocketPanel()
        } label: {
            Label("MenuPocket", systemImage: "square.grid.2x2")
                .labelStyle(.iconOnly)
                .accessibilityLabel("MenuPocket")
        }
        .menuBarExtraStyle(.window)
    }
}
