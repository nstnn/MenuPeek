import SwiftUI

struct SettingsView: View {
    let model: AppModel
    let appVersion: String
    let onQuit: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsMoreKeyboardControls = false

    init(model: AppModel, bundle: Bundle = .main, onQuit: @escaping () -> Void) {
        self.model = model
        appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        self.onQuit = onQuit
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let warning = model.preferenceWarning {
                        Label(warning.message, systemImage: "exclamationmark.triangle")
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("preferencesWarning")
                    }

                    if let saveError = model.preferenceSaveError {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("preferencesSaveError")
                    }

                    settingsSection("Startup") {
                        Toggle("Open at Login", isOn: Binding(
                            get: { model.isLoginItemEnabled },
                            set: { model.setLoginItemEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .disabled(!model.canChangeLoginItemRegistration)
                        .accessibilityIdentifier("openAtLoginToggle")

                        Text(model.loginItemStatus.message)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("openAtLoginStatus")

                        if let failure = model.loginItemOperationFailure {
                            Label(failure.message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("openAtLoginError")
                        }

                        if model.loginItemStatus == .requiresApproval {
                            Button("Open Login Items Settings…") {
                                model.openSystemSettingsLoginItems()
                            }
                            .accessibilityIdentifier("openLoginItemsSettings")
                        }
                    }

                    settingsSection("Appearance") {
                        SystemMonospaceSegmentedPicker(label: "Theme", selection: Binding(
                            get: { model.preferences.theme },
                            set: { model.setTheme($0) }
                        ), options: AppTheme.allCases.map { ($0, $0.title) })
                        .disabled(!model.isPreferenceEditingAllowed)
                        .accessibilityIdentifier("themePicker")
                    }

                    settingsSection("Quick Add") {
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
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Press Control-Option-N in any app to add a task for today.")
                            .accessibilityIdentifier("quickAddShortcut")

                        if let failure = model.quickAddRegistrationFailure {
                            Label("\(failure.message) \(failure.retryGuidance)", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("quickAddError")
                        }
                    }

                    settingsSection("Keyboard Shortcuts") {
                        shortcutGroup("From any app", shortcuts: [
                            .init("Quick Add", ["⌃", "⌥", "N"], "Control-Option-N", note: quickAddShortcutStatus)
                        ])
                        shortcutGroup("In MenuPocket", shortcuts: SettingsShortcut.appCommands)

                        Text("Adding tasks and switching lists are unavailable while editing, confirming deletion, or managing categories.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()
                        DisclosureGroup(isExpanded: $showsMoreKeyboardControls) {
                            VStack(alignment: .leading, spacing: 18) {
                                shortcutGroup("Task editor", shortcuts: SettingsShortcut.taskEditor)
                                shortcutGroup("Quick Add panel", shortcuts: SettingsShortcut.quickAddPanel)
                                Text("Command-N, Command-1, Command-2, Command-comma, and Command-Q do nothing in the Quick Add panel.")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                shortcutGroup("Keyboard navigation", shortcuts: SettingsShortcut.navigation)
                                shortcutGroup("History", shortcuts: SettingsShortcut.history)
                                shortcutGroup("Category manager", shortcuts: SettingsShortcut.categories)
                                shortcutGroup("Text editing", shortcuts: SettingsShortcut.textEditing)
                                shortcutGroup("Window zoom", shortcuts: SettingsShortcut.zoom)
                                shortcutGroup("Other app commands", shortcuts: SettingsShortcut.otherCommands)
                            }
                            .padding(.top, 12)
                        } label: {
                            Text("More keyboard controls")
                                .foregroundStyle(.primary)
                        }
                        .accessibilityIdentifier("keyboardControlsDisclosure")

                        Text("⌘ Command · ⌥ Option · ⌃ Control · ⇧ Shift")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Key symbols: Command, Option, Control, and Shift.")
                    }
                    .accessibilityIdentifier("keyboardShortcutsSection")

                    settingsSection("App") {
                        LabeledContent("Name", value: "MenuPocket")
                            .accessibilityRepresentation {
                                Text("App name: MenuPocket")
                            }
                        LabeledContent("Version", value: appVersion)
                            .accessibilityRepresentation {
                                Text("Version: \(appVersion)")
                            }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("settingsContent")

            HStack {
                Spacer()
                Button("Quit MenuPocket", action: onQuit)
                    .accessibilityIdentifier("quitMenuPocket")
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        // Settings contains no editable fields, so all its controls share this treatment.
        .keyboardFocusAppearance()
        .font(.system(size: 13, design: .monospaced))
        .fontDesign(.monospaced)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { DaybookPalette.canvas(colorScheme) }
    }

    private var quickAddShortcutStatus: String {
        if !model.preferences.quickAddEnabled {
            return "Enable Quick Add above to use this shortcut."
        }
        if model.quickAddRegistrationFailure != nil {
            return "Unavailable. See Quick Add above for details."
        }
        if model.isQuickAddRegistered {
            return "Quick Add is enabled."
        }
        return "Quick Add registration is pending."
    }

    private func shortcutGroup(_ title: String, shortcuts: [SettingsShortcut]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(shortcuts.indices, id: \.self) { index in
                    if index != shortcuts.startIndex { Divider() }
                    shortcutRow(shortcuts[index])
                }
            }
        }
    }

    private func shortcutRow(_ shortcut: SettingsShortcut) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(shortcut.title)
                if let note = shortcut.note {
                    Text(note)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(shortcut.keys.indices, id: \.self) { index in
                    let key = shortcut.keys[index]
                    if key == "or" {
                        Text(key).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    } else {
                        Text(key)
                            .font(.system(size: key.count > 1 ? 12 : 13, design: .monospaced))
                            .padding(.horizontal, 6)
                            .frame(minWidth: 25, minHeight: 24)
                            .background {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.primary.opacity(colorScheme == .light ? 0.035 : 0.06))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 5)
                                            .strokeBorder(Color.primary.opacity(0.12))
                                    }
                            }
                    }
                }
            }
            .fixedSize()
        }
        .padding(.vertical, 7)
        .frame(minHeight: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut.title)
        .accessibilityValue(shortcut.spokenKeys)
        .accessibilityHint(shortcut.note ?? "")
    }

    private func settingsSection<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0))
                }
        }
    }
}

/// Read-only reference for the existing handlers in AppDelegate, TaskWindowView,
/// QuickAddPanelController, the History views, and TaskCategoryManagerView.
/// Keep the descriptions in sync when those handlers change; this catalog installs no shortcuts.
private struct SettingsShortcut {
    let title: String
    let keys: [String]
    let spokenKeys: String
    let note: String?

    init(_ title: String, _ keys: [String], _ spokenKeys: String, note: String? = nil) {
        self.title = title
        self.keys = keys
        self.spokenKeys = spokenKeys
        self.note = note
    }

    static let appCommands: [Self] = [
        .init("Add task", ["⌘", "N"], "Command-N", note: "In the selected list; Today when browsing History."),
        .init("Show Today", ["⌘", "1"], "Command-1"),
        .init("Show Later", ["⌘", "2"], "Command-2"),
        .init("Open Settings", ["⌘", ","], "Command-comma"),
        .init("Close active window", ["⌘", "W"], "Command-W"),
        .init("Quit MenuPocket", ["⌘", "Q"], "Command-Q")
    ]
    static let taskEditor: [Self] = [
        .init("Save task", ["Return"], "Return", note: "While typing a task, or with Save focused."),
        .init("Cancel task entry or edit", ["Esc"], "Escape"),
        .init("Choose category", ["↑", "↓"], "Up or Down arrow", note: "With the category picker focused.")
    ]
    static let quickAddPanel: [Self] = [
        .init("Save to Today / General", ["Return"], "Return"),
        .init("Close and discard text", ["Esc", "or", "⌘", "W"], "Escape or Command-W")
    ]
    static let navigation: [Self] = [
        .init("Move focus", ["Tab"], "Tab", note: "Keyboard navigation follows your macOS keyboard settings."),
        .init("Move focus backward", ["⇧", "Tab"], "Shift-Tab"),
        .init("Activate focused task control", ["Space", "or", "Return"], "Space or Return")
    ]
    static let history: [Self] = [
        .init("Move between calendar days", ["←", "↑", "↓", "→"], "Arrow keys", note: "With a calendar day focused."),
        .init("Open focused day", ["Space", "or", "Return"], "Space or Return"),
        .init("Change task filter", ["←", "→"], "Left or Right arrow", note: "With the All / Unfinished / Completed filter focused.")
    ]
    static let categories: [Self] = [
        .init("Create or rename category", ["Return"], "Return", note: "While typing in its name field."),
        .init("Cancel current action", ["Esc"], "Escape")
    ]
    static let textEditing: [Self] = [
        .init("Cut", ["⌘", "X"], "Command-X"),
        .init("Copy", ["⌘", "C"], "Command-C"),
        .init("Paste", ["⌘", "V"], "Command-V"),
        .init("Select all", ["⌘", "A"], "Command-A"),
        .init("Undo typing", ["⌘", "Z"], "Command-Z", note: "Undo and redo apply to text in the focused field."),
        .init("Redo typing", ["⇧", "⌘", "Z"], "Shift-Command-Z")
    ]
    static let zoom: [Self] = [
        .init("Zoom in", ["⌘", "+"], "Command-plus", note: "Command-equals works too. Also in the View menu."),
        .init("Zoom out", ["⌘", "−"], "Command-minus"),
        .init("Actual size", ["⌘", "0"], "Command-zero")
    ]
    static let otherCommands: [Self] = [
        .init("Hide MenuPocket", ["⌘", "H"], "Command-H"),
        .init("Hide other apps", ["⌥", "⌘", "H"], "Option-Command-H"),
        .init("Minimize active window", ["⌘", "M"], "Command-M")
    ]
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
