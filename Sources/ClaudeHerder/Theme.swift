import SwiftUI

/// Palette and type borrowed from Anthropic's docs: ivory paper, near-black ink, clay accent.
enum Theme {
    static let background = Color(hex: 0xFAF9F5)
    static let surface = Color.white
    static let border = Color(hex: 0xE8E6DC)
    static let borderStrong = Color(hex: 0xC9C6BA)
    /// Veil over a hovered card: fades its text so the buttons stand out.
    static let dim = Color.white.opacity(0.85)
    static let pillGrey = Color(hex: 0xE3E0D5)
    static let ink = Color(hex: 0x141413)
    static let secondary = Color(hex: 0x5E5D59)
    static let tertiary = Color(hex: 0x87867F)
    static let clay = Color(hex: 0xD97757)

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The Claude "spark": thin rounded rays around a center.
struct Spark: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(Theme.clay)
                    .frame(width: size * 0.12, height: size * (i.isMultiple(of: 2) ? 0.5 : 0.38))
                    .offset(y: -size * 0.22)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Pill button: solid black like the docs' "Open Claude Code", or grey for secondary actions.
struct PillButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(prominent ? .white : Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                (prominent ? Theme.ink : Theme.pillGrey).opacity(configuration.isPressed ? 0.75 : 1),
                in: Capsule())
    }
}

/// Outlined control matching the docs' search box and "Copy page" button.
struct OutlinedControl: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }
}

extension View {
    func outlinedControl() -> some View {
        modifier(OutlinedControl())
    }
}
