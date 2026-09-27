import SwiftUI

struct SettingsView: View {
    let model: AppModel
    let appVersion: String
    let onQuit: () -> Void

    init(model: AppModel, bundle: Bundle = .main, onQuit: @escaping () -> Void) {
        self.model = model
        appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        self.onQuit = onQuit
    }

    var body: some View {
        Form {
            if let warning = model.preferenceWarning {
                Label(warning.message, systemImage: "exclamationmark.triangle")
                    .accessibilityIdentifier("preferencesWarning")
            }

            if let saveError = model.preferenceSaveError {
                Label(saveError, systemImage: "exclamationmark.triangle")
            }

            Section("Startup") {
                Toggle("Open at Login", isOn: Binding(
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
                    Button("Open Login Items Settings…") {
                        model.openSystemSettingsLoginItems()
                    }
                    .accessibilityIdentifier("openLoginItemsSettings")
                }
            }

            Section("App") {
                LabeledContent("Name", value: "MenuPocket")
                    .accessibilityRepresentation {
                        Text("App name: MenuPocket")
                    }
                LabeledContent("Version", value: appVersion)
                    .accessibilityRepresentation {
                        Text("Version: \(appVersion)")
                    }

                Button("Quit MenuPocket", action: onQuit)
                    .accessibilityIdentifier("quitMenuPocket")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    return SettingsView(model: model, onQuit: {})
}

#Preview("Open at Login — Off") {
    makeLoginItemPreview(status: .disabled)
}

#Preview("Open at Login — On") {
    makeLoginItemPreview(status: .enabled)
}

#Preview("Open at Login — Approval Required") {
    makeLoginItemPreview(status: .requiresApproval)
}

#Preview("Open at Login — Unavailable") {
    makeLoginItemPreview(status: .unavailable)
}

#Preview("Open at Login — Error") {
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
