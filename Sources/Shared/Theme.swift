import SwiftUI

// MARK: - Night Console design tokens
// From the "Night Console" spec (v1, 2026): one surface ladder, a text ladder,
// hairlines, and one electric lime signal. Two appearances share the tokens —
// Night (dark, default) and Paper (light). Use these tokens directly rather than
// semantic system colours.

extension Color {
    init(hex: UInt) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8)  & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255)
    }
}

/// The two console looks: the original dark "Night Console" and the light
/// "Paper" (silver-grey surfaces, same lime signal, red-orange note markup).
enum Appearance: String, CaseIterable {
    case night, paper

    var title: String { self == .night ? "Night (dark)" : "Paper (light)" }

    /// The user's choice (Settings → Appearance); Night by default.
    static var current: Appearance {
        Appearance(rawValue: UserDefaults.standard.string(forKey: Prefs.appearance) ?? "") ?? .night
    }
}

enum Theme {
    private static var paper: Bool { Appearance.current == .paper }
    private static func pick(_ night: Color, _ paper: Color) -> Color { self.paper ? paper : night }

    // Surfaces (base → inset ladder)
    static var base: Color     { pick(Color(hex: 0x15171C), Color(hex: 0xDEDEDE)) }   // window bg, primary surface
    static var raised: Color   { pick(Color(hex: 0x1B1E24), Color(hex: 0xEFEFEF)) }   // title bar, toolbar
    static var surface: Color  { pick(Color(hex: 0x1E2228), Color(hex: 0xF4F4F4)) }   // cards, list rows
    static var key: Color      { pick(Color(hex: 0x23272E), Color(hex: 0xF7F7F7)) }   // tactile keys, thumbnails
    static var inset: Color    { pick(Color(hex: 0x0F1115), Color(hex: 0xE6E6E6)) }   // wells: counter, scratch field
    static var stage: Color    { pick(Color(hex: 0x0C0D10), Color(hex: 0xCFCFCF)) }   // slide mat behind the deck
    static let blackout        = Color(hex: 0x08090B)                                 // audience black-out (always black)

    // Text & lines
    // The ladder is spaced so every rung clears WCAG AA (4.5:1) on the surfaces
    // it is drawn on: muted carries 9–10 pt captions and faint 12–13 pt prose,
    // far below the large-text exemption.
    static var textPrimary: Color   { pick(Color(hex: 0xE9ECF0), Color(hex: 0x2A2A2A)) }
    static var textSecondary: Color { pick(Color(hex: 0xA4ADBA), Color(hex: 0x4A4A4A)) }
    static var textMuted: Color     { pick(Color(hex: 0x929AA5), Color(hex: 0x565656)) }
    static var textFaint: Color     { pick(Color(hex: 0x828993), Color(hex: 0x626262)) }
    static var hairline: Color       { pick(Color.white.opacity(0.06), Color.black.opacity(0.12)) }
    static var hairlineStrong: Color { pick(Color.white.opacity(0.08), Color.black.opacity(0.18)) }

    // Accent + status
    /// The brand red. One value, written down in four files no compiler
    /// compares — Tools/check_colors.py is what keeps them equal.
    ///
    /// A fill colour only: LIVE, the active tool, the primary button, the ring
    /// on the current thumbnail, and the console window's border. As text on
    /// the Night ground it reaches 3.67:1 and fails AA, which is what
    /// `accentInk` exists for.
    static let accent     = Color(hex: 0xE30613)
    static var accentDim: Color { accent.opacity(paper ? 0.35 : 0.16) }
    /// White, not black — and this is worth spelling out, because the obvious
    /// shortcut gets it backwards. By the real WCAG formula (sRGB gamma
    /// expansion, then 0.2126/0.7152/0.0722) white reaches 4.88:1 on this red
    /// and black 4.30:1, so white is both the better label and the only one
    /// that clears AA at all. A luminance formula that skips the gamma step
    /// reports black at 5.23 against white's 4.02 and would have picked the
    /// failing colour. Tools/check_colors.py asserts the right answer.
    static let onAccent   = Color(hex: 0xFFFFFF)
    /// The brand as text, glyph or thin line. The red itself cannot do this
    /// job, so this is a light rose of the same family: 9.26:1 on the Night
    /// ground, where the red manages 3.67:1.
    ///
    /// It also has to stay clear of `PenInk.red`, which says "you are over
    /// time" a few millimetres away in the same bar — measured, they are 42.8
    /// apart in CIE Lab. The brand red itself is only 22.4 from that colour,
    /// which is tolerable solely because the two never share a role: the brand
    /// is never drawn as status text, and the overrun red is never a fill.
    /// On Paper this darkens to read on silver (7.10:1 on #F4F4F4).
    static var accentInk: Color  { pick(Color(hex: 0xFFA0A8), Color(hex: 0xA8040D)) }
    static var accentRing: Color { pick(accent, Color(hex: 0xA8040D)) }
    static var statusOk: Color   { pick(Color(hex: 0x5BD08A), Color(hex: 0x2F9E5B)) }   // LaTeX ready
    static var statusWarn: Color { pick(Color(hex: 0xE0B341), Color(hex: 0xC98A12)) }   // dependency missing
    /// "The timer is running" — a state, not the brand.
    ///
    /// This used to be `accent`, which was fine only for as long as the accent
    /// was an orange. The elapsed chip sits immediately left of the "Left"
    /// chip, and that one turns `PenInk.red` once the lecture runs over. Two
    /// adjacent chips, one meaning "running" and one meaning "you are over" —
    /// they have to stay apart in hue whatever the brand does, so "running"
    /// gets its own token and keeps the colour it has always had.
    /// Flat, not appearance-dependent — exactly as `accent` was when the chip
    /// still borrowed it, so this commit moves the token without moving a pixel.
    static let statusRunning = Color(hex: 0xEE7C30)
    /// Label drawn on a `statusRunning` fill. The orange is light, so the
    /// near-black wins by a wide margin: measured with the real WCAG formula
    /// (sRGB gamma — Tools/check_colors.py) it reaches 6.46:1 on #EE7C30,
    /// where white reaches only 2.78:1 and would fail AA.
    static let onStatusRunning = Color(hex: 0x15171C)

    // Speaker-notes markup (Markdown-style highlighting)
    static var noteMarkup: Color { pick(Color(hex: 0xEE7A52), Color(hex: 0xB8452A)) }   // # ** * - > and headings
    static var noteLink: Color   { pick(Color(hex: 0x74B1DE), Color(hex: 0x2F6A9E)) }
    static var noteCode: Color   { pick(Color(hex: 0xE9C46A), Color(hex: 0x8E3420)) }
    static var noteCodeBg: Color { pick(Color.white.opacity(0.06), Color(hex: 0xEADBD5)) }
}

/// Rebuilds a window's SwiftUI tree when the appearance changes (the tokens
/// above are read at render time) and matches system controls to it.
struct Themed<Content: View>: View {
    @AppStorage(Prefs.appearance) private var appearance = Appearance.night.rawValue
    let content: Content

    var body: some View {
        content
            .id(appearance)
            .preferredColorScheme(appearance == Appearance.paper.rawValue ? .light : .dark)
    }
}

extension View {
    func themed() -> some View { Themed(content: self) }
}

/// Annotation pen colours (the only other saturated hues in the app).
enum PenInk {
    static let red    = Color(hex: 0xFF5A4D)   // red / laser
    static let green  = Color(hex: 0x5BD08A)
    static let blue   = Color(hex: 0x5BA8FF)
    static let yellow = Color(hex: 0xE8C84E)
}

// MARK: - Typography
// Three families: Space Grotesk (display), IBM Plex Sans (UI/body), JetBrains
// Mono (timers, labels). `.custom` falls back to the system font when the .ttf
// isn't bundled, so the app still works before the fonts are added (see README).

extension Font {
    static func display(_ size: CGFloat) -> Font { .custom("SpaceGrotesk-Bold", size: size) }
    static func ui(_ size: CGFloat, _ weight: String = "Regular") -> Font {
        .custom("IBMPlexSans-" + weight, size: size)
    }
    static func mono(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "JetBrainsMono-Bold" : "JetBrainsMono-Regular", size: size)
    }
}

extension View {
    /// A mono uppercase micro-label (`.14–.18em` tracking).
    func microLabel() -> some View {
        self.font(.mono(10)).textCase(.uppercase).tracking(1.6)
            .foregroundStyle(Theme.textMuted)
    }
}
