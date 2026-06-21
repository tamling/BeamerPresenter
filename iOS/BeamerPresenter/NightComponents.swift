import SwiftUI

// MARK: - Signature components (Night Console spec §04)

/// A tactile key: the default for every toolbar control. Default = key surface +
/// hairline; active = lime border + lime glow with the caption turning lime. A
/// 14–16px glyph stacked over a mono uppercase caption.
struct KeyButton<Glyph: View>: View {
    let caption: String
    var active = false
    var width: CGFloat = 44
    var height: CGFloat = 38
    let action: () -> Void
    @ViewBuilder var glyph: () -> Glyph

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                glyph()
                    .frame(width: width, height: height)
                    .background(Theme.key, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .stroke(active ? Theme.accent : Theme.hairline, lineWidth: 1))
                    .shadow(color: active ? Theme.accent.opacity(0.5) : .clear, radius: 6)
                Text(caption).font(.mono(9)).textCase(.uppercase).tracking(0.6)
                    .foregroundStyle(active ? Theme.accent : Theme.textMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Convenience: an SF-symbol glyph key.
extension KeyButton where Glyph == Image {
    init(_ caption: String, systemImage: String, active: Bool = false,
         width: CGFloat = 44, height: CGFloat = 38, action: @escaping () -> Void) {
        self.caption = caption
        self.active = active
        self.width = width
        self.height = height
        self.action = action
        self.glyph = { Image(systemName: systemImage) }
    }
}

/// The single solid-lime primary action (one per screen). Dark label, soft glow.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(16, "SemiBold"))
            .foregroundStyle(Theme.onAccent)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: Theme.accent.opacity(0.45), radius: 14, y: 2)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// A hairline-bordered "ghost" key — secondary actions.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(15, "Medium"))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The glowing "LIVE" pill — lime-14% fill, lime border, a dot that blinks.
struct LivePill: View {
    @State private var on = true
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.accent).frame(width: 7, height: 7)
                .opacity(on ? 1 : 0.25)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: on)
            Text("LIVE").font(.mono(10, bold: true)).tracking(1.2)
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Theme.accentDim, in: Capsule())
        .overlay(Capsule().stroke(Theme.accent.opacity(0.6), lineWidth: 1))
        .onAppear { on.toggle() }
    }
}

/// The app's brand mark — the glowing "two screens" glyph from the app icon: a
/// clean solid audience screen overlapping a presenter-screen frame, with a
/// small cursor dot. Fills its frame; give it a key-tile background at the call
/// site. `dot` should match that background so the cursor reads as a punch-out.
struct BrandMark: View {
    var color: Color = Theme.accent
    var dot: Color = Theme.base

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let bw = w * 0.42, bh = h * 0.30          // back (presenter) screen
            let bcx = w * 0.59, bcy = h * 0.40
            let fw = w * 0.45, fh = h * 0.34          // front (audience) screen
            let fcx = w * 0.43, fcy = h * 0.585

            ZStack {
                RoundedRectangle(cornerRadius: w * 0.05, style: .continuous)
                    .stroke(color, lineWidth: w * 0.072)
                    .frame(width: bw, height: bh)
                    .position(x: bcx, y: bcy)
                RoundedRectangle(cornerRadius: w * 0.06, style: .continuous)
                    .fill(color)
                    .frame(width: fw, height: fh)
                    .position(x: fcx, y: fcy)
                Circle().fill(dot)
                    .frame(width: w * 0.06, height: w * 0.06)
                    .position(x: fcx + fw * 0.22, y: fcy + fh * 0.16)
            }
            .shadow(color: color.opacity(0.5), radius: w * 0.045)
        }
    }
}

extension View {
    /// A standard Night card surface with hairline border.
    func nightCard(_ radius: CGFloat = 12) -> some View {
        self.background(Theme.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Theme.hairline, lineWidth: 1))
    }
}
