import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            SettingsPlaceholder(
                systemImage: "square.grid.2x2",
                title: "Nội dung",
                message: "Các tùy chọn nội dung sẽ xuất hiện ở đây."
            )
            .tabItem {
                Label("Nội dung", systemImage: "square.grid.2x2")
            }

            SettingsPlaceholder(
                systemImage: "gearshape",
                title: "Chung",
                message: "Các tùy chọn chung sẽ xuất hiện ở đây."
            )
            .tabItem {
                Label("Chung", systemImage: "gearshape")
            }

            SettingsPlaceholder(
                systemImage: "testtube.2",
                title: "Demo",
                message: "Các kịch bản dữ liệu demo sẽ xuất hiện ở đây."
            )
            .tabItem {
                Label("Demo", systemImage: "testtube.2")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SettingsPlaceholder: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
