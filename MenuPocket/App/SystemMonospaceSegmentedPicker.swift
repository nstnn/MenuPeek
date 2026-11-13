import AppKit
import SwiftUI

/// SwiftUI's segmented Picker does not forward its font to NSSegmentedControl.
/// Keep the native control, selection and accessibility while setting its font.
struct SystemMonospaceSegmentedPicker<Selection: Equatable>: NSViewRepresentable {
    let label: String
    @Binding var selection: Selection
    let options: [(value: Selection, title: String)]
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: options.map(\.title), trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.select(_:)))
        control.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        control.segmentDistribution = .fill
        control.setAccessibilityLabel(label)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.picker = self
        control.isEnabled = isEnabled
        control.selectedSegment = options.firstIndex { $0.value == selection } ?? -1
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width,
               height: nsView.intrinsicContentSize.height)
    }

    @MainActor
    final class Coordinator: NSObject {
        var picker: SystemMonospaceSegmentedPicker

        init(_ picker: SystemMonospaceSegmentedPicker) { self.picker = picker }

        @objc func select(_ sender: NSSegmentedControl) {
            guard picker.isEnabled, picker.options.indices.contains(sender.selectedSegment) else { return }
            picker.selection = picker.options[sender.selectedSegment].value
        }
    }
}
