import AppKit
import SwiftUI

struct MenuPocketPanel: View {
    let model: AppModel
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MenuPocket")
                .font(.headline)

            Divider()

            HStack {
                Button("Cài đặt…", action: onOpenSettings)

                Spacer()

                Button("Thoát", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 240)
    }
}
