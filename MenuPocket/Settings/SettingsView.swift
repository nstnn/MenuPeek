import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            ContentSettingsView(model: model)
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

private struct ContentSettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Nội dung hiển thị") {
                ForEach(model.modulesInOrder) { module in
                    Toggle(isOn: Binding(
                        get: { model.preferences.enabledModuleIDs.contains(module.id) },
                        set: { model.setModuleEnabled(module.id, enabled: $0) }
                    )) {
                        Label(module.displayName, systemImage: module.systemImageName)
                    }
                    .toggleStyle(.switch)
                    .disabled(!model.isPreferenceEditingAllowed)
                }
            }

            if let warning = model.preferenceWarning {
                Text(warning.message)
                    .foregroundStyle(.secondary)
            }

            if let saveError = model.preferenceSaveError {
                Text(saveError)
                    .foregroundStyle(.secondary)
            }
        }
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
