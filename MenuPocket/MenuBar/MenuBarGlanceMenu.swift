import AppKit
import SwiftUI

/// What each glance item does. The caller supplies every closure, so the menu
/// itself never reaches the shared state, storage, or a window.
struct MenuBarGlanceActions {
    /// Open Today, a task row, and the overflow row.
    var openToday: @MainActor () -> Void
    /// Add Task…, which always targets Today.
    var addTask: @MainActor () -> Void
    /// The `Later · N remaining` line.
    var openLater: @MainActor () -> Void
    var showSettings: @MainActor () -> Void
    var quit: @MainActor () -> Void
    /// Offered only while Today is unavailable.
    var retry: @MainActor () -> Void
}

/// Builds the read-only glance `NSMenu` from a `MenuBarGlance` value.
@MainActor
enum MenuBarGlanceMenu {
    /// The header's narrowest width; it widens with the menu.
    static let minimumWidth: CGFloat = 260
    /// Space between a row's title and its right-aligned category.
    private static let categoryGap: CGFloat = 24

    static func make(_ glance: MenuBarGlance, actions: MenuBarGlanceActions) -> NSMenu {
        let menu = NSMenu(title: "MenuPocket")
        // Enabled flags come from the model, not from responder validation.
        menu.autoenablesItems = false
        menu.addItem(headerItem(glance.header))
        menu.addItem(.separator())

        switch glance.body {
        case .unavailable:
            menu.addItem(disabledItem("Tasks are unavailable."))
            menu.addItem(ActionItem(title: "Retry", handler: actions.retry))
        case .empty:
            menu.addItem(disabledItem("No tasks yet"))
        case .allDone:
            menu.addItem(disabledItem("All done"))
        case let .tasks(rows, overflowCount):
            let tabStop = categoryTabStop(for: rows)
            for row in rows {
                let item = ActionItem(title: row.title, handler: actions.openToday)
                if let category = row.categoryName, let tabStop {
                    item.attributedTitle = rowTitle(row.title, category: category, tabStop: tabStop)
                }
                item.toolTip = row.toolTip
                menu.addItem(item)
            }
            if let overflowCount {
                menu.addItem(ActionItem(title: "\(overflowCount) more in Today", handler: actions.openToday))
            }
        }

        if let laterCount = glance.laterRemainingCount {
            menu.addItem(.separator())
            menu.addItem(ActionItem(title: "Later · \(laterCount) remaining", handler: actions.openLater))
        }

        menu.addItem(.separator())
        menu.addItem(ActionItem(title: "Open Today", handler: actions.openToday))
        menu.addItem(ActionItem(title: "Add Task…", isEnabled: glance.canAddTask, handler: actions.addTask))
        menu.addItem(ActionItem(title: "Settings…", handler: actions.showSettings))
        menu.addItem(ActionItem(title: "Quit MenuPocket", handler: actions.quit))
        return menu
    }

    /// A custom-view item with no action, so it cannot be highlighted or chosen.
    private static func headerItem(_ header: MenuBarGlance.Header) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        let view = NSHostingView(rootView: MenuBarGlanceHeaderView(header: header))
        view.frame.size = NSSize(width: minimumWidth, height: view.fittingSize.height)
        // Track the menu's width, which the widest row can set.
        view.autoresizingMask = [.width]
        item.view = view
        return item
    }

    private static func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// One right tab stop shared by every row, so categories line up.
    private static func categoryTabStop(for rows: [MenuBarGlance.Row]) -> CGFloat? {
        let categories = rows.compactMap(\.categoryName)
        guard !categories.isEmpty else { return nil }
        let titles = rows.map { width(of: $0.title) }.max() ?? 0
        let names = categories.map { width(of: $0, font: categoryFont) }.max() ?? 0
        return titles + categoryGap + names
    }

    private static func rowTitle(_ title: String, category: String, tabStop: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: tabStop)]
        let text = NSMutableAttributedString(string: title, attributes: [
            .font: menuFont, .paragraphStyle: paragraph,
        ])
        text.append(NSAttributedString(string: "\t\(category)", attributes: [
            .font: categoryFont, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph,
        ]))
        return text
    }

    private static var menuFont: NSFont { .menuFont(ofSize: 0) }
    private static var categoryFont: NSFont { .menuFont(ofSize: NSFont.smallSystemFontSize) }

    private static func width(of string: String, font: NSFont = menuFont) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }
}

/// A menu item that runs a closure. It is its own target; `NSMenuItem.target`
/// is weak and the menu owns the item, so nothing outlives the menu.
@MainActor
final class MenuBarGlanceActionItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, isEnabled: Bool = true, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(runHandler), keyEquivalent: "")
        target = self
        self.isEnabled = isEnabled
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func runHandler() { handler() }
}

private typealias ActionItem = MenuBarGlanceActionItem

/// The glance header: the date and `N of M done` on one line, with the Today
/// window's capsule bar below. VoiceOver reads it as one element.
struct MenuBarGlanceHeaderView: View {
    let header: MenuBarGlance.Header

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(header.dateLabel)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 12)
                Text(header.countLabel)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            if let fraction = header.fraction {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(Color.accentColor)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 6)
        // VoiceOver reads the label then the value: "Wednesday 7 October, 4 of 7 tasks done".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(header.spokenDate)
        .accessibilityValue(header.accessibilityValue)
    }
}
