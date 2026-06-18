import SwiftUI

// MARK: - Night Console design tokens
// Drop-in from the "Night Console" spec (v1, 2026). A single fixed dark theme:
// one near-black surface ladder, a cool text ladder, hairlines, and one electric
// lime signal. Use these tokens directly rather than semantic system colours.

extension Color {
    init(hex: UInt) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8)  & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255)
    }
}

enum Theme {
    // Surfaces (base → inset ladder)
    static let base      = Color(hex: 0x15171C)   // window bg, primary surface
    static let raised    = Color(hex: 0x1B1E24)   // title bar, toolbar
    static let surface   = Color(hex: 0x1E2228)   // cards, list rows
    static let key       = Color(hex: 0x23272E)   // tactile keys, thumbnails
    static let inset     = Color(hex: 0x0F1115)   // wells: counter, scratch field
    static let stage     = Color(hex: 0x0C0D10)   // slide mat behind the deck
    static let blackout  = Color(hex: 0x08090B)   // audience black-out

    // Text & lines
    static let textPrimary   = Color(hex: 0xE9ECF0)
    static let textSecondary = Color(hex: 0x8B939E)
    static let textMuted     = Color(hex: 0x6F7682)
    static let textFaint     = Color(hex: 0x5B636E)
    static let hairline      = Color.white.opacity(0.06)   // 0.08 = strong
    static let hairlineStrong = Color.white.opacity(0.08)

    // Accent + status
    static let accent     = Color(hex: 0xC7F24E)   // LIVE, active tool, primary btn, timer
    static let accentDim  = Color(hex: 0xC7F24E).opacity(0.14)
    static let onAccent   = Color(hex: 0x15171C)
    static let statusOk   = Color(hex: 0x5BD08A)   // LaTeX ready
    static let statusWarn = Color(hex: 0xE0B341)   // dependency missing
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
