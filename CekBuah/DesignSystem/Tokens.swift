import SwiftUI

/// Spacing scale: 4, 8, 12, 16, 24.
enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

enum Radius {
    static let card: CGFloat = 12
}

enum TouchTarget {
    static let minimum: CGFloat = 44
}

extension Color {
    /// Colour that switches between light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Status colours are only used for icons and borders. Text always uses system label colours,
/// and every status always shows an icon plus text (never colour alone).
extension RipenessState {
    var symbolName: String {
        switch self {
        case .unripe: "leaf"
        case .ripe: "checkmark.circle.fill"
        case .overripe: "exclamationmark.circle"
        case .rotten: "xmark.octagon.fill"
        case .unsure: "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .unripe: Color(light: 0x0F766E, dark: 0x5EEAD4)
        case .ripe: Color(light: 0x15803D, dark: 0x4ADE80)
        case .overripe: Color(light: 0x9A3412, dark: 0xFB923C)
        case .rotten: Color(light: 0xB91C1C, dark: 0xF87171)
        case .unsure: Color(light: 0x4B5563, dark: 0x9CA3AF)
        }
    }
}

/// Card surface used across screens.
struct CardBackground: ViewModifier {
    var border: Color = Color(uiColor: .separator)

    func body(content: Content) -> some View {
        content
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(border, lineWidth: 1))
    }
}

extension View {
    func card(border: Color = Color(uiColor: .separator)) -> some View {
        modifier(CardBackground(border: border))
    }
}

/// Full-width button with a 44 pt minimum height.
struct PrimaryButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.xs)
            .foregroundStyle(prominent ? Color.white : Color.accentColor)
            .background(
                RoundedRectangle(cornerRadius: Radius.card)
                    .fill(prominent ? Color.accentColor : Color.accentColor.opacity(0.12))
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}
