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
                .accessibilityLabel("Dữ liệu demo")
        }
    }

    @ViewBuilder
    private var moduleContent: some View {
        if model.enabledModulesInOrder.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Chưa bật nội dung nào.")
                    .fontWeight(.medium)
                Text("Mở Cài đặt để chọn nội dung hiển thị.")
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
            Button("Cài đặt…", action: onOpenSettings)
                .accessibilityLabel("Mở Cài đặt MenuPocket")

            Spacer()

            Button("Làm mới") {
                model.refreshEnabledModules()
            }
            .disabled(model.enabledModulesInOrder.isEmpty)
            .accessibilityLabel("Làm mới dữ liệu demo")

            Button("Thoát", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            .accessibilityLabel("Thoát MenuPocket")
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
                loadingText("Đang tải dữ liệu demo…")
            case let .ready(snapshot):
                snapshotContent(snapshot)
            case let .refreshing(snapshot):
                snapshotContent(snapshot)
                loadingText("Đang cập nhật dữ liệu demo…")
            case .empty:
                Text("Chưa có dữ liệu demo")
                    .foregroundStyle(.secondary)
            case .initialFailure:
                Text("Không tải được dữ liệu demo.")
                    .foregroundStyle(.secondary)
                retryButton
            case let .stale(snapshot):
                snapshotContent(snapshot)
                Label(
                    "Không cập nhật được; đang hiển thị dữ liệu trước đó.",
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
        Text("Cập nhật lúc \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
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
        Button("Thử lại", action: onRetry)
            .accessibilityLabel("Thử lại \(module.displayName)")
    }
}
