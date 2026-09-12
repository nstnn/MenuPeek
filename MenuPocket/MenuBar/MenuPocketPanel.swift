import AppKit
import SwiftUI

struct MenuPocketPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MenuPocket")
                .font(.headline)

            Divider()

            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 240)
    }
}
