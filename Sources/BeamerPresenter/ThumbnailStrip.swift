import SwiftUI

/// Horizontal, clickable strip of slide thumbnails. The current slide is
/// highlighted; clicking (single or double, per Settings) jumps to that slide.
/// Auto-scrolls to keep the current slide visible. The height follows the
/// draggable handle above the strip (persisted), so the thumbnails can be
/// zoomed.
struct ThumbnailStrip: View {
    @EnvironmentObject var state: PresentationState
    @AppStorage(Prefs.thumbStripHeight) private var stripHeight: Double = 70
    @AppStorage(Prefs.doubleClickSlides) private var doubleClick = false

    private var thumbHeight: CGFloat { CGFloat(stripHeight) }

    /// Thumbnails are rendered at the next 64 pt bucket and *displayed* scaled
    /// to the live height — so a zoom drag never re-renders PDF pages per
    /// pixel (that made the drag visibly stutter) and stays fluid.
    private var renderHeight: CGFloat { max(64, (thumbHeight / 64).rounded(.up) * 64) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<state.pageCount, id: \.self) { i in
                        thumb(i)
                            .contentShape(Rectangle())
                            .onTapGesture(count: doubleClick ? 2 : 1) { state.go(to: i) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("Slide \(i + 1)")
                            .accessibilityAction { state.go(to: i) }
                            .id(i)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            // The initial index isn't a *change* (e.g. a resumed deck opens at
            // its old slide), so scroll there once on appearance too.
            .onAppear { proxy.scrollTo(state.index, anchor: .center) }
            .onChange(of: state.index) { newValue in
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
        .frame(height: thumbHeight + 28)
        .background(Theme.raised)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    @ViewBuilder
    private func thumb(_ i: Int) -> some View {
        let isCurrent = i == state.index
        VStack(spacing: 3) {
            Group {
                if let image = state.thumbnail(at: i, height: renderHeight) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Theme.key
                }
            }
            .frame(height: thumbHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isCurrent ? Theme.accent : Theme.hairlineStrong,
                                  lineWidth: isCurrent ? 2.5 : 1)
            )
            .shadow(color: isCurrent ? Theme.accent.opacity(0.4) : .clear, radius: 6)
            Text("\(i + 1)")
                .font(.mono(10)).tracking(0.5)
                .foregroundStyle(isCurrent ? Theme.accent : Theme.textMuted)
        }
    }
}
