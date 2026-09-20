import AppKit
import SwiftUI

struct MenuPocketPanel: View {
    let model: AppModel
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            if model.enabledModulesInOrder.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chưa bật nội dung nào.")
                        .fontWeight(.medium)
                    Text("Mở Cài đặt để chọn nội dung hiển thị.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(model.enabledModulesInOrder) { module in
                    ModulePanelRow(
                        module: module,
                        state: model.runtimeStates[module.id] ?? ModuleRuntimeState()
                    ) {
                        model.retryModule(module.id)
                    }
                }
            }

            Divider()

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
        .padding(16)
        .frame(width: 360)
        .onAppear { model.panelDidOpen() }
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
