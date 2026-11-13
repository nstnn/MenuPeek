import AppKit
import SwiftUI

/// What a Daybook popover returns when it closes: a task row action, or a
/// composer category (nil is General).
enum TaskActionSelection {
    case edit
    case delete
    case moveToToday
    case move(TaskMoveRequest)
    case category(UUID?)
}

/// One line of the actions popover.
enum TaskActionRow: Identifiable {
    struct Item {
        /// Also the accessibility identifier, so it must be unique in one popover.
        let id: String
        let title: String
        let accessibilityLabel: String
        let symbol: String?
        var isEnabled = true
        var isDestructive = false
        /// A Move To destination the task already belongs to.
        var isCurrent = false
        let selection: TaskActionSelection?
    }

    case item(Item)
    case header(String)
    case separator(String)

    var id: String {
        switch self {
        case let .item(item): item.id
        case let .header(title): "header-\(title)"
        case let .separator(key): "separator-\(key)"
        }
    }

    var actionable: Item? {
        if case let .item(item) = self, item.isEnabled, item.selection != nil { return item }
        return nil
    }
}

/// Highlight and choice for one open popover. Pointer hover and arrow keys
/// share one highlight, as in a native menu.
@MainActor
final class TaskActionsModel: ObservableObject {
    let rows: [TaskActionRow]
    @Published var highlighted: String?
    var onChoose: (TaskActionSelection?) -> Void = { _ in }

    init(rows: [TaskActionRow]) {
        self.rows = rows
    }

    private var actionableIDs: [String] { rows.compactMap { $0.actionable?.id } }

    /// Which item a keyboard-opened popover highlights first.
    enum InitialHighlight {
        case none
        case first
        case item(String)
    }

    func highlight(_ start: InitialHighlight) {
        switch start {
        case .none: highlighted = nil
        case .first: highlighted = actionableIDs.first
        case let .item(id): highlighted = actionableIDs.contains(id) ? id : actionableIDs.first
        }
    }

    func step(_ offset: Int) {
        let ids = actionableIDs
        guard !ids.isEmpty else { return }
        guard let current = highlighted, let index = ids.firstIndex(of: current) else {
            highlighted = offset > 0 ? ids.first : ids.last
            return
        }
        highlighted = ids[(index + offset + ids.count) % ids.count]
    }

    func chooseHighlighted() {
        guard let id = highlighted,
              let item = rows.lazy.compactMap(\.actionable).first(where: { $0.id == id }) else { return }
        onChoose(item.selection)
    }

    func choose(_ item: TaskActionRow.Item) {
        guard item.isEnabled, let selection = item.selection else { return }
        onChoose(selection)
    }
}

/// The Daybook-styled replacement for native menus: a paper card with soft
/// accent highlights. Row actions add an inline Move To list and Delete in the
/// danger color; the composer uses it to choose a category.
struct TaskActionsPopoverView: View {
    @ObservedObject var model: TaskActionsModel
    var accessibilityLabel = "Task actions"
    var accessibilityIdentifier = "taskActionsPopover"
    /// Prefix for item identifiers, followed by the item ID.
    var itemIdentifierPrefix = "taskAction-"
    /// Accessibility value of the checked item.
    var currentValue = "Current group"
    @Environment(\.colorScheme) private var colorScheme

    static let width: CGFloat = 224

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(model.rows) { row in
                switch row {
                case let .item(item): itemView(item)
                case let .header(title):
                    Text(title)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 5)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                case .separator:
                    DaybookPalette.rule(colorScheme)
                        .frame(height: 1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(5)
        .frame(width: Self.width, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(DaybookPalette.canvas(colorScheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func itemView(_ item: TaskActionRow.Item) -> some View {
        let isHighlighted = model.highlighted == item.id && item.isEnabled
        let hue = item.isDestructive ? DaybookPalette.danger(colorScheme) : DaybookPalette.accent(colorScheme)
        let foreground: Color = item.isDestructive || isHighlighted ? hue : .primary
        return Button { model.choose(item) } label: {
            HStack(spacing: 8) {
                Group {
                    if item.isCurrent {
                        Image(systemName: "checkmark").foregroundStyle(DaybookPalette.accent(colorScheme))
                    } else if let symbol = item.symbol {
                        Image(systemName: symbol)
                            .foregroundStyle(item.isDestructive || isHighlighted ? hue : Color.secondary)
                    } else {
                        // Keeps titles aligned with the icon column.
                        Color.clear.frame(height: 1)
                    }
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(width: 16)
                Text(item.title)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(foreground)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHighlighted ? hue.opacity(colorScheme == .dark ? 0.18 : 0.12) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled || item.isCurrent ? 1 : 0.4)
        .onHover { inside in
            if inside, item.isEnabled {
                model.highlighted = item.id
            } else if !inside, model.highlighted == item.id {
                model.highlighted = nil
            }
        }
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityValue(item.isCurrent ? currentValue : "")
        .accessibilityAddTraits(item.isCurrent ? .isSelected : [])
        .accessibilityIdentifier(itemIdentifierPrefix + item.id)
    }
}

/// A borderless key panel that owns the popover's keyboard: arrows move the
/// highlight, Return/Space choose, and Escape closes without a choice.
private final class TaskActionsPanel: NSPanel {
    var onKey: (NSEvent) -> Bool = { _ in false }
    var onResignKey: () -> Void = {}

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey(event) { return }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey()
    }

    override func cancelOperation(_ sender: Any?) {
        onResignKey()
    }
}

/// Presents one actions popover under a trigger view and reports the choice
/// after the panel has closed and the task window is key again.
@MainActor
final class TaskActionsPresenter {
    private var panel: TaskActionsPanel?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var completion: ((TaskActionSelection?) -> Void)?
    private weak var trigger: NSView?

    var isOpen: Bool { panel != nil }

    /// Which trigger edge the popover lines up with.
    enum Alignment { case leading, trailing }

    struct Labels {
        var popover = "Task actions"
        var identifier = "taskActionsPopover"
        var itemPrefix = "taskAction-"
        var currentValue = "Current group"
    }

    func present(rows: [TaskActionRow], from view: NSView,
                 highlight: TaskActionsModel.InitialHighlight, alignment: Alignment = .trailing,
                 labels: Labels = Labels(),
                 completion: @escaping (TaskActionSelection?) -> Void) {
        guard panel == nil, let parent = view.window else { return }
        let model = TaskActionsModel(rows: rows)
        model.highlight(highlight)
        model.onChoose = { [weak self] selection in self?.close(with: selection) }

        let host = NSHostingView(rootView: TaskActionsPopoverView(
            model: model, accessibilityLabel: labels.popover, accessibilityIdentifier: labels.identifier,
            itemIdentifierPrefix: labels.itemPrefix, currentValue: labels.currentValue))
        host.appearance = parent.effectiveAppearance
        let size = host.fittingSize

        let panel = TaskActionsPanel(contentRect: NSRect(origin: .zero, size: size),
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.appearance = parent.effectiveAppearance
        panel.contentView = host
        panel.setAccessibilityLabel(labels.popover)
        panel.setFrameOrigin(Self.origin(for: size, below: view, in: parent, alignment: alignment))
        panel.onKey = { [weak self, weak model] event in
            guard let self, let model else { return false }
            return self.handle(event, model: model)
        }
        panel.onResignKey = { [weak self] in self?.close(with: nil) }

        self.panel = panel
        self.trigger = view
        self.completion = completion
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()

        // A click or scroll outside closes the popover. A click on the trigger
        // only closes it, rather than closing and reopening.
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        ) { [weak self] event in
            guard let self, let panel = self.panel, event.window !== panel else { return event }
            let onTrigger = event.type != .scrollWheel && self.isOnTrigger(event)
            self.close(with: nil)
            return onTrigger ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(with: nil) }
        }
    }

    func close(with selection: TaskActionSelection?) {
        guard let panel else { return }
        self.panel = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        let parent = panel.parent
        parent?.removeChildWindow(panel)
        panel.onResignKey = {}
        panel.orderOut(nil)
        parent?.makeKey()
        let completion = self.completion
        self.completion = nil
        completion?(selection)
    }

    private func handle(_ event: NSEvent, model: TaskActionsModel) -> Bool {
        switch event.keyCode {
        case 126: model.step(-1) // up
        case 125: model.step(1) // down
        case 36, 76, 49: model.chooseHighlighted() // return, enter, space
        case 53: close(with: nil) // escape
        case 48: close(with: nil) // tab leaves the popover, as it does a menu
        default: return false
        }
        return true
    }

    private func isOnTrigger(_ event: NSEvent) -> Bool {
        guard let trigger, let window = trigger.window, event.window === window else { return false }
        let point = trigger.convert(event.locationInWindow, from: nil)
        return trigger.bounds.insetBy(dx: -2, dy: -2).contains(point)
    }

    /// Below the trigger with the chosen edges aligned; above it when the
    /// screen has no room below, and always inside the visible frame.
    private static func origin(for size: NSSize, below view: NSView, in window: NSWindow,
                               alignment: Alignment) -> NSPoint {
        let anchor = window.convertToScreen(view.convert(view.bounds, to: nil))
        let gap: CGFloat = 4
        let x = alignment == .trailing ? anchor.maxX - size.width : anchor.minX
        var origin = NSPoint(x: x, y: anchor.minY - gap - size.height)
        if let screen = (window.screen ?? NSScreen.main)?.visibleFrame {
            if origin.y < screen.minY { origin.y = anchor.maxY + gap }
            origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
            origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        }
        return origin
    }
}
