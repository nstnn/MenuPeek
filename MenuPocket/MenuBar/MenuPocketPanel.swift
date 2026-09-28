import AppKit
import SwiftUI

struct MenuPocketPanel: View {
    static let width: CGFloat = 360
    static let maximumHeight: CGFloat = 480
    static let outerPadding: CGFloat = 16
    static let blockSpacing: CGFloat = 12

    let model: AppModel
    let onOpenSettings: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            panelLayout {
                moduleContent
            }
            // Do not compress the compact candidate just to make it appear to
            // fit; overflow should select the scrolling candidate below.
            .fixedSize(horizontal: false, vertical: true)

            panelLayout {
                ScrollView {
                    moduleContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("panelModuleScrollView")
            }
        }
        .padding(Self.outerPadding)
        .frame(width: Self.width)
        .frame(maxHeight: Self.maximumHeight)
        // ViewThatFits otherwise reports the full proposed height even when its
        // compact child is shorter. Preserve the 480 pt ceiling while adopting
        // the selected child's natural height.
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.panelDidOpen() }
    }

    private func panelLayout<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Self.blockSpacing) {
            header
            content()
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack {
            Text("MenuPocket")
                .font(.headline)

            Spacer()

            Text("DEMO")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Demo data")
        }
    }

    @ViewBuilder
    private var moduleContent: some View {
        if model.enabledModulesInOrder.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("No content enabled.")
                    .fontWeight(.medium)
                Text("Open Settings to choose what to display.")
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: Self.blockSpacing) {
                ForEach(model.enabledModulesInOrder) { module in
                    ModulePanelRow(
                        module: module,
                        state: model.runtimeStates[module.id] ?? ModuleRuntimeState()
                    ) {
                        model.retryModule(module.id)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…", action: onOpenSettings)
                .accessibilityLabel("Open MenuPocket Settings")

            Spacer()

            Button("Refresh") {
                model.refreshEnabledModules()
            }
            .disabled(model.enabledModulesInOrder.isEmpty)
            .accessibilityLabel("Refresh demo data")

            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            .accessibilityLabel("Quit MenuPocket")
        }
    }
}

enum ModulePanelPhase: Equatable {
    case loading
    case ready(ModuleSnapshot)
    case refreshing(ModuleSnapshot)
    case empty
    case initialFailure
    case stale(ModuleSnapshot)

    init(state: ModuleRuntimeState) {
        if let snapshot = state.snapshot {
            if state.isLoading {
                self = .refreshing(snapshot)
            } else if state.lastError != nil {
                self = .stale(snapshot)
            } else {
                self = .ready(snapshot)
            }
        } else if state.isLoading || !state.hasCompletedAttempt {
            self = .loading
        } else if state.lastError != nil {
            self = .initialFailure
        } else {
            self = .empty
        }
    }
}

private struct ModulePanelRow: View {
    let module: ModuleDescriptor
    let phase: ModulePanelPhase
    let onRetry: () -> Void

    init(
        module: ModuleDescriptor,
        state: ModuleRuntimeState,
        onRetry: @escaping () -> Void
    ) {
        self.module = module
        phase = ModulePanelPhase(state: state)
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(module.displayName, systemImage: module.systemImageName)
                .fontWeight(.medium)

            switch phase {
            case .loading:
                loadingText("Loading demo data…")
            case let .ready(snapshot):
                snapshotContent(snapshot)
            case let .refreshing(snapshot):
                snapshotContent(snapshot)
                loadingText("Refreshing demo data…")
            case .empty:
                Text("No demo data")
                    .foregroundStyle(.secondary)
            case .initialFailure:
                Text("Could not load demo data.")
                    .foregroundStyle(.secondary)
                retryButton
            case let .stale(snapshot):
                snapshotContent(snapshot)
                Label(
                    "Could not refresh; showing previous data.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.secondary)
                retryButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func snapshotContent(_ snapshot: ModuleSnapshot) -> some View {
        Text(snapshot.primaryValue)
            .font(.title3)
            .fontWeight(.semibold)
        Text(snapshot.description)
            .foregroundStyle(.secondary)
        Text("Updated at \(snapshot.updatedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "en"))))")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func loadingText(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    private var retryButton: some View {
        Button("Retry", action: onRetry)
            .accessibilityLabel("Retry \(module.displayName)")
    }
}
