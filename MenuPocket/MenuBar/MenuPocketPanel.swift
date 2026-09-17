import AppKit
import SwiftUI

struct MenuPocketPanel: View {
    let model: AppModel
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MenuPocket")
                .font(.headline)

            if model.enabledModulesInOrder.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chưa bật nội dung nào.")
                        .fontWeight(.medium)
                    Text("Mở Cài đặt để chọn nội dung hiển thị.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(model.enabledModulesInOrder) { module in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(module.displayName, systemImage: module.systemImageName)
                            .fontWeight(.medium)
                        Text("Dữ liệu demo sẽ xuất hiện ở đây.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

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
        .frame(width: 360)
    }
}
