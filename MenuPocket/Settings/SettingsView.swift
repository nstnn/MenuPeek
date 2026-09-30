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

            Section("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { model.preferences.theme },
                    set: { model.setTheme($0) }
                )) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(!model.isPreferenceEditingAllowed)
                .accessibilityIdentifier("themePicker")
            }

            Section("Quick Add") {
                // A label wider than "Open at Login" widens the label column and
                // clips the other sections at the 500 × 380 pt minimum.
                Toggle("Shortcut", isOn: Binding(
                    get: { model.preferences.quickAddEnabled },
                    set: { model.setQuickAddEnabled($0) }
                ))
                .toggleStyle(.switch)
                .disabled(!model.isPreferenceEditingAllowed)
                .accessibilityLabel("Quick Add shortcut")
                .accessibilityIdentifier("quickAddToggle")

                // The shortcut is fixed; the text never claims it is free of conflicts.
                Text("Press ⌃⌥N in any app to add a task for today.")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Press Control-Option-N in any app to add a task for today.")
                    .accessibilityIdentifier("quickAddShortcut")

                if let failure = model.quickAddRegistrationFailure {
                    Label("\(failure.message) \(failure.retryGuidance)", systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("quickAddError")
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

private extension AppTheme {
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

private extension HotKeyRegistrationError {
    /// Registration is retried only at launch or when the setting is turned off and on.
    var retryGuidance: String {
        switch self {
        case .alreadyInUse:
            "Quit the app using it, then turn this off and on to try again."
        case .systemError:
            "Turn this off and on to try again."
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

@MainActor
private func makeQuickAddPreview(registrationError: HotKeyRegistrationError? = nil) -> SettingsView {
    let model = AppModel(
        store: PreviewPreferencesStore(),
        providers: [],
        loginItemService: PreviewLoginItemService(status: .disabled, operationResult: nil),
        hotKeyService: PreviewHotKeyService(registrationError: registrationError)
    )
    model.startQuickAdd {}
    model.setQuickAddEnabled(true)
    return SettingsView(model: model, onQuit: {})
}

#Preview("Quick Add — On") {
    makeQuickAddPreview()
}

#Preview("Quick Add — Shortcut in Use") {
    makeQuickAddPreview(registrationError: .alreadyInUse)
}

// Never touches Carbon, so previews cannot claim a real global hotkey.
private final class PreviewHotKeyService: HotKeyService {
    private let registrationError: HotKeyRegistrationError?

    init(registrationError: HotKeyRegistrationError?) {
        self.registrationError = registrationError
    }

    func register(
        _ combination: HotKeyCombination,
        onPress: @escaping @MainActor () -> Void
    ) throws(HotKeyRegistrationError) {
        if let registrationError { throw registrationError }
    }

    func unregister() {}
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
