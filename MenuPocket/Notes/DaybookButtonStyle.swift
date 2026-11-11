import SwiftUI

/// The Daybook task window's colors, shared by its panes and button styles.
enum DaybookPalette {
    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.145, green: 0.137, blue: 0.122)
            : Color(red: 0.980, green: 0.969, blue: 0.941)
    }

    static func rail(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.188, green: 0.173, blue: 0.145)
            : Color(red: 0.941, green: 0.922, blue: 0.878)
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.894, green: 0.667, blue: 0.514)
            : Color(red: 0.608, green: 0.310, blue: 0.196)
    }

    static func rule(_ scheme: ColorScheme) -> Color {
        Color.primary.opacity(scheme == .dark ? 0.14 : 0.12)
    }

    static func danger(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.941, green: 0.549, blue: 0.502)
            : Color(red: 0.702, green: 0.212, blue: 0.169)
    }
}

/// Daybook buttons are capsules. Quiet actions are outlined secondary text
/// that firms up on hover. The one prominent action per view sits on a soft
/// accent tint and fills with the accent on hover. A destructive role uses the
/// danger color in place of the accent.
struct DaybookButtonStyle: ButtonStyle {
    enum Prominence { case quiet, prominent }

    var prominence: Prominence = .quiet

    func makeBody(configuration: Configuration) -> some View {
        DaybookButton(configuration: configuration, prominence: prominence)
    }
}

extension ButtonStyle where Self == DaybookButtonStyle {
    static var daybook: DaybookButtonStyle { DaybookButtonStyle() }
    static var daybookProminent: DaybookButtonStyle { DaybookButtonStyle(prominence: .prominent) }
}

private struct DaybookButton: View {
    let configuration: ButtonStyle.Configuration
    let prominence: DaybookButtonStyle.Prominence
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var isDestructive: Bool { configuration.role == .destructive }
    private var isProminent: Bool { prominence == .prominent }
    private var isActive: Bool { (isHovered || configuration.isPressed) && isEnabled }
    /// Accent for ordinary actions, danger for destructive ones.
    private var hue: Color {
        isDestructive ? DaybookPalette.danger(colorScheme) : DaybookPalette.accent(colorScheme)
    }

    var body: some View {
        configuration.label
            .font(.system(size: 12.5, weight: isProminent ? .medium : .regular))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(minHeight: 26)
            .background { Capsule().fill(fill) }
            .overlay {
                if !isProminent {
                    Capsule().strokeBorder(border, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .animation(.easeOut(duration: 0.12), value: isActive)
            .onHover { isHovered = $0 }
    }

    private var foreground: Color {
        if isProminent { return isActive ? DaybookPalette.canvas(colorScheme) : hue }
        if isDestructive { return hue }
        return isActive ? .primary : .secondary
    }

    private var fill: Color {
        if isProminent { return isActive ? hue : hue.opacity(colorScheme == .dark ? 0.16 : 0.12) }
        return isActive && isDestructive ? hue.opacity(colorScheme == .dark ? 0.14 : 0.10) : .clear
    }

    private var border: Color {
        guard isActive else { return DaybookPalette.rule(colorScheme) }
        return isDestructive ? hue.opacity(0.6) : Color.secondary
    }
}
