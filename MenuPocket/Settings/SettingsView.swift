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

                GeneralSettingsView(model: model, version: appVersion)
                    .tabItem {
                        Label("Chung", systemImage: "gearshape")
                    }
                    .tag(SettingsTab.general)

                DemoSettingsView(model: model)
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
    let model: AppModel
    let version: String

    var body: some View {
        Form {
            Section("Khởi động") {
                Toggle("Mở khi đăng nhập", isOn: Binding(
                    get: { model.isLoginItemEnabled },
                    set: { model.setLoginItemEnabled($0) }
                ))
                .toggleStyle(.switch)
                .disabled(!model.canChangeLoginItemRegistration)
                .accessibilityIdentifier("openAtLoginToggle")

                Text(model.loginItemStatus.message)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("openAtLoginStatus")

                if let failure = model.loginItemOperationFailure {
                    Label(failure.message, systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("openAtLoginError")
                }

                if model.loginItemStatus == .requiresApproval {
                    Button("Mở Mục đăng nhập…") {
                        model.openSystemSettingsLoginItems()
                    }
                    .accessibilityIdentifier("openLoginItemsSettings")
                }
            }

            Section("Ứng dụng") {
                LabeledContent("Tên", value: "MenuPocket")
                    .accessibilityRepresentation {
                        Text("Tên ứng dụng: MenuPocket")
                    }
                LabeledContent("Phiên bản", value: version)
                    .accessibilityRepresentation {
                        Text("Phiên bản: \(version)")
                    }
            }

            Section("Dữ liệu demo") {
                Text(SettingsView.demoExplanation)
                Text("Dữ liệu minh họa được xử lý cục bộ trên máy này; ứng dụng không kết nối dịch vụ bên ngoài.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DemoSettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Kịch bản mô phỏng") {
                Text("Chọn cách từng mô-đun phản hồi để xem trước các trạng thái của ứng dụng.")
                    .foregroundStyle(.secondary)

                ForEach(model.modulesInOrder) { module in
                    Picker(module.displayName, selection: Binding(
                        get: { model.demoScenarios[module.id] ?? .normal },
                        set: { model.setDemoScenario($0, for: module.id) }
                    )) {
                        ForEach(DemoScenario.allCases, id: \.self) { scenario in
                            Text(scenario.displayName).tag(scenario)
                        }
                    }
                    .accessibilityLabel("Kịch bản cho \(module.displayName)")
                }
            }

            Section {
                Button("Tải lại dữ liệu demo") {
                    model.refreshEnabledModules()
                }
                .disabled(model.enabledModulesInOrder.isEmpty)
            } footer: {
                Text("Kịch bản chỉ được giữ trong phiên hiện tại và sẽ trở về Bình thường khi mở lại ứng dụng.")
            }
        }
    }
}

#if DEBUG
@MainActor
private func makeLoginItemPreview(
    status: LoginItemStatus,
    operationResult: LoginItemOperationResult? = nil
) -> SettingsView {
    let service = PreviewLoginItemService(status: status, operationResult: operationResult)
    let model = AppModel(
        store: PreviewPreferencesStore(),
        providers: [],
        loginItemService: service
    )
    if operationResult != nil {
        model.setLoginItemEnabled(true)
    }
    return SettingsView(model: model, initialTab: .general)
}

#Preview("Mở khi đăng nhập — Tắt") {
    makeLoginItemPreview(status: .disabled)
}

#Preview("Mở khi đăng nhập — Bật") {
    makeLoginItemPreview(status: .enabled)
}

#Preview("Mở khi đăng nhập — Cần phê duyệt") {
    makeLoginItemPreview(status: .requiresApproval)
}

#Preview("Mở khi đăng nhập — Không khả dụng") {
    makeLoginItemPreview(status: .unavailable)
}

#Preview("Mở khi đăng nhập — Lỗi") {
    makeLoginItemPreview(
        status: .disabled,
        operationResult: .init(status: .disabled, failure: .registrationFailed)
    )
}

private final class PreviewLoginItemService: LoginItemService {
    private(set) var status: LoginItemStatus
    private let operationResult: LoginItemOperationResult?

    init(status: LoginItemStatus, operationResult: LoginItemOperationResult?) {
        self.status = status
        self.operationResult = operationResult
    }

    func readStatus() -> LoginItemStatus { status }

    func register() -> LoginItemOperationResult {
        let result = operationResult ?? .init(status: status, failure: nil)
        status = result.status
        return result
    }

    func unregister() -> LoginItemOperationResult {
        .init(status: status, failure: nil)
    }

    func openSystemSettingsLoginItems() {}
}

private final class PreviewPreferencesStore: PreferencesStoring {
    func load() throws -> PreferencesLoadOutcome { .loaded(.defaultValue) }

    func save(_ preferences: AppPreferences) throws -> PreferencesSaveOutcome { .saved }
}
#endif
