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
    static var textPrimary: Color   { pick(Color(hex: 0xE9ECF0), Color(hex: 0x2A2A2A)) }
    static var textSecondary: Color { pick(Color(hex: 0x8B939E), Color(hex: 0x4A4A4A)) }
    static var textMuted: Color     { pick(Color(hex: 0x6F7682), Color(hex: 0x626262)) }
    static var textFaint: Color     { pick(Color(hex: 0x5B636E), Color(hex: 0x8A8A8A)) }
    static var hairline: Color       { pick(Color.white.opacity(0.06), Color.black.opacity(0.12)) }
    static var hairlineStrong: Color { pick(Color.white.opacity(0.08), Color.black.opacity(0.18)) }

    // Accent + status
    /// Lime fill: LIVE, active tool, primary button, timer.
    static let accent     = Color(hex: 0xC7F24E)
    static var accentDim: Color { accent.opacity(paper ? 0.35 : 0.14) }
    static let onAccent   = Color(hex: 0x15171C)
    /// Lime used as text, glyph or thin line. On Paper, lime text is unreadable,
    /// so it turns a dark olive; rings get a mid lime.
    static var accentInk: Color  { pick(accent, Color(hex: 0x4E6A0C)) }
    static var accentRing: Color { pick(accent, Color(hex: 0x7FA51A)) }
    static var statusOk: Color   { pick(Color(hex: 0x5BD08A), Color(hex: 0x2F9E5B)) }   // LaTeX ready
    static var statusWarn: Color { pick(Color(hex: 0xE0B341), Color(hex: 0xC98A12)) }   // dependency missing

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
