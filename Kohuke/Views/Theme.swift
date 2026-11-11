import SwiftUI
import Observation

/// One of the website's four styles: brick and Baltic by day, forest and plum
/// by night. The values are the tokens of the `[data-style]` blocks in
/// `assets/styles.css` in the website repo, to the value.
///
/// One thing is laid out differently from the site. There a card is `--paper`
/// and the ground under it `--wash`; here the page is the ground and a card
/// sits on it. By day that is the site's paper under a white card, as it has
/// always been; by night it is the site's wash under its paper, so a card is
/// still the lighter of the two.
enum Style: String, CaseIterable, Identifiable {
    case red, green, blue, plum

    var id: String { rawValue }
    var dark: Bool { self == .green || self == .plum }

    /// The website's key for the style's name, and its English.
    var nameKey: (String, String) {
        switch self {
        case .red: return ("styleRed", "Red")
        case .green: return ("styleGreen", "Green (dark)")
        case .blue: return ("styleBlue", "Blue")
        case .plum: return ("stylePlum", "Plum (dark)")
        }
    }

    var palette: Palette {
        switch self {
        case .red:
            return Palette(ink: 0x27141A, muted: 0x7D5754, paper: 0xFFF0EA, wash: 0xF7DDD4, hairline: 0xF0CEC3,
                           accent: 0xA81E28, here: 0x0B62C4, card: 0xFFFFFF, onAccent: 0xFFFFFF)
        case .green:
            return Palette(ink: 0xE7F1EA, muted: 0xA2B7A9, paper: 0x101A15, wash: 0x25332C, hairline: 0x354740,
                           accent: 0x6FD39A, here: 0xE0873A, card: 0x1D2A23, onAccent: 0x101A15)
        case .blue:
            return Palette(ink: 0x0F1D31, muted: 0x4D6079, paper: 0xEDF3FB, wash: 0xD6E3F2, hairline: 0xC6D6EA,
                           accent: 0x1B4A8C, here: 0xC0267E, card: 0xFFFFFF, onAccent: 0xFFFFFF)
        case .plum:
            return Palette(ink: 0xF1E9F6, muted: 0xB9A8C6, paper: 0x16111C, wash: 0x2E2638, hairline: 0x43384F,
                           accent: 0xC9A6F2, here: 0xE0873A, card: 0x271F30, onAccent: 0x16111C)
        }
    }
}

struct Palette {
    let ink, muted, paper, wash, hairline, accent, here, card, onAccent: Color

    init(ink: UInt32, muted: UInt32, paper: UInt32, wash: UInt32, hairline: UInt32,
         accent: UInt32, here: UInt32, card: UInt32, onAccent: UInt32) {
        self.ink = Color(hex: ink)
        self.muted = Color(hex: muted)
        self.paper = Color(hex: paper)
        self.wash = Color(hex: wash)
        self.hairline = Color(hex: hairline)
        self.accent = Color(hex: accent)
        self.here = Color(hex: here)
        self.card = Color(hex: card)
        self.onAccent = Color(hex: onAccent)
    }
}

/// Which style the app is drawn in. The website keeps this choice in the
/// browser rather than on the account, so the app keeps it on the phone. Blue
/// until somebody chooses, which is the style the flashcards were first drawn in.
///
/// It is observable and every colour below is read through it, so a screen
/// that draws with `Theme.ink` is redrawn the moment another style is chosen,
/// with nothing passed down to it.
@Observable
final class StyleStore: @unchecked Sendable {
    static let shared = StyleStore()
    private static let key = "style"

    private(set) var style: Style

    private init() {
        style = UserDefaults.standard.string(forKey: Self.key).flatMap(Style.init(rawValue:)) ?? .blue
    }

    func choose(_ next: Style) {
        guard next != style else { return }
        style = next
        UserDefaults.standard.set(next.rawValue, forKey: Self.key)
    }
}

/// The colours of the style in use.
enum Theme {
    private static var palette: Palette { StyleStore.shared.style.palette }

    static var ink: Color { palette.ink }
    static var muted: Color { palette.muted }
    static var paper: Color { palette.paper }
    static var wash: Color { palette.wash }
    static var hairline: Color { palette.hairline }
    static var accent: Color { palette.accent }
    static var here: Color { palette.here }
    static var card: Color { palette.card }
    /// What is written on the accent: white by day, the ground by night,
    /// where the accent is the light thing on the screen.
    static var onAccent: Color { palette.onAccent }
    static var dark: Bool { StyleStore.shared.style.dark }

    static let radius: CGFloat = 14
}

/// The filled button, in the accent. The system's own writes white on the
/// tint whatever the tint is, which on the two dark styles is white on a pale
/// green or lavender.
struct ProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var size

    func makeBody(configuration: Configuration) -> some View {
        let large = size == .large
        configuration.label
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, large ? 20 : 12)
            .padding(.vertical, large ? 14 : 7)
            .background(Theme.accent.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45),
                        in: RoundedRectangle(cornerRadius: large ? 12 : 8))
    }
}

extension ButtonStyle where Self == ProminentButtonStyle {
    static var prominent: ProminentButtonStyle { ProminentButtonStyle() }
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

/// A rounded white card on the paper, with the hairline the site draws.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.hairline))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }

    /// The page's paper behind a scroll view or a list.
    func paperBackground() -> some View {
        self.scrollContentBackground(.hidden).background(Theme.paper.ignoresSafeArea())
    }
}

/// A heading over a group, in the site's small capitals.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1)
            .foregroundStyle(Theme.muted)
    }
}

/// A full-width message for a screen with nothing to show yet.
struct EmptyNote: View {
    let title: String
    let text: String
    var systemImage: String = "tray"

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(text)
        }
        .foregroundStyle(Theme.muted)
    }
}

/// The two colours an answer is said in: Knew it in green, Still learning in
/// red, whatever the style, and lighter on the two night styles.
extension Theme {
    static var knew: Color { dark ? Color(hex: 0x6FD39A) : Color(hex: 0x1E7A46) }
    static var again: Color { dark ? Color(hex: 0xF08A7E) : Color(hex: 0xB3261E) }
}
