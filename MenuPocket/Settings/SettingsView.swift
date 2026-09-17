import SwiftUI

enum SettingsTab: Hashable {
    case content
    case general
    case demo
}

struct SettingsView: View {
    static let demoExplanation =
        "Ứng dụng đang dùng dữ liệu demo. Bạn có thể chọn nội dung thật ở phiên bản sau."

    let model: AppModel
    let appVersion: String
    @State private var selectedTab: SettingsTab

    init(model: AppModel, initialTab: SettingsTab = .content, bundle: Bundle = .main) {
        self.model = model
        appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 12) {
            if let warning = model.preferenceWarning {
                Label(warning.message, systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("preferencesWarning")
            }

            if let saveError = model.preferenceSaveError {
                Label(saveError, systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            TabView(selection: $selectedTab) {
                ContentSettingsView(model: model)
                    .tabItem {
                        Label("Nội dung", systemImage: "square.grid.2x2")
                    }
                    .tag(SettingsTab.content)

                GeneralSettingsView(version: appVersion)
                    .tabItem {
                        Label("Chung", systemImage: "gearshape")
                    }
                    .tag(SettingsTab.general)

                SettingsPlaceholder(
                    systemImage: "testtube.2",
                    title: "Demo",
                    message: "Các kịch bản dữ liệu demo sẽ xuất hiện ở đây."
                )
                .tabItem {
                    Label("Demo", systemImage: "testtube.2")
                }
                .tag(SettingsTab.demo)
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
                    HStack {
                        Toggle(isOn: Binding(
                            get: { model.preferences.enabledModuleIDs.contains(module.id) },
                            set: { model.setModuleEnabled(module.id, enabled: $0) }
                        )) {
                            Label(module.displayName, systemImage: module.systemImageName)
                        }
                        .toggleStyle(.switch)

                        Button("Lên") { model.moveModuleUp(module.id) }
                            .disabled(model.modulesInOrder.first?.id == module.id)
                            .accessibilityLabel("Lên \(module.displayName)")

                        Button("Xuống") { model.moveModuleDown(module.id) }
                            .disabled(model.modulesInOrder.last?.id == module.id)
                            .accessibilityLabel("Xuống \(module.displayName)")
                    }
                }
            }
            .disabled(!model.isPreferenceEditingAllowed)

            Section("Thanh menu") {
                Picker("Mục ghim", selection: Binding<ModuleDescriptor.ID?>(
                    get: { model.preferences.pinnedModuleID },
                    set: { model.setPinnedModule($0) }
                )) {
                    Text("Không ghim").tag(nil as ModuleDescriptor.ID?)
                    ForEach(model.enabledPinnableModulesInOrder) { module in
                        Text(module.displayName).tag(module.id as ModuleDescriptor.ID?)
                    }
                }

                Picker("Chế độ hiển thị", selection: Binding(
                    get: { model.preferences.menuBarDisplayMode },
                    set: { model.setMenuBarDisplayMode($0) }
                )) {
                    Text("Chỉ biểu tượng").tag(MenuBarDisplayMode.iconOnly)
                    Text("Biểu tượng và thông tin").tag(MenuBarDisplayMode.iconAndInformation)
                }
            }
            .disabled(!model.isPreferenceEditingAllowed)
        }
    }
}

private struct GeneralSettingsView: View {
    let version: String

    var body: some View {
        Form {
            Section("Ứng dụng") {
                LabeledContent("Tên", value: "MenuPocket")
                LabeledContent("Phiên bản", value: version)
            }

            Section("Dữ liệu demo") {
                Text(SettingsView.demoExplanation)
                Text("Dữ liệu minh họa được xử lý cục bộ trên máy này; ứng dụng không kết nối dịch vụ bên ngoài.")
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
