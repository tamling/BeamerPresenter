import SwiftUI

/// Horizontal, clickable strip of slide thumbnails with a drag handle above it
/// to zoom. The current slide is highlighted; clicking (single or double, per
/// Settings) jumps to that slide. Auto-scrolls to keep the current slide
/// visible.
///
/// Zooming is designed to feel as fluid as resizing a window: while the handle
/// is dragged the height lives in view state only (persisted once, on release),
/// the existing bitmaps are just *scaled* — no PDF rendering, no blur, no
/// implicit animation per frame — and only the visible thumbnails are laid out.
/// The crisp re-render at the final size runs once, when the drag ends.
struct ThumbnailStrip: View {
    @EnvironmentObject var state: PresentationState
    @AppStorage(Prefs.thumbStripHeight) private var stripHeight: Double = 70
    @AppStorage(Prefs.doubleClickSlides) private var doubleClick = false

    @State private var dragStartHeight: Double?
    @State private var liveHeight: Double?            // the height mid-drag (not yet persisted)
    @State private var frozenRenderHeight: CGFloat?   // bitmaps stay at this size mid-drag

    private let heightRange = 50.0...260.0
    private var thumbHeight: CGFloat { CGFloat(liveHeight ?? stripHeight) }

    /// Rendering happens at 64 pt buckets; display scales to the live height.
    private var bucket: CGFloat { max(64, (thumbHeight / 64).rounded(.up) * 64) }
    private var renderHeight: CGFloat { frozenRenderHeight ?? bucket }

    var body: some View {
        VStack(spacing: 0) {
            // Drag up/down to zoom the thumbnails (the strip sits below, so
            // dragging up enlarges them).
            ResizeHandle(axis: .vertical) { translation in
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    if dragStartHeight == nil {
                        dragStartHeight = stripHeight
                        frozenRenderHeight = bucket   // freeze the bitmaps for the drag
                    }
                    let start = dragStartHeight ?? stripHeight
                    liveHeight = min(max(start - Double(translation),
                                         heightRange.lowerBound), heightRange.upperBound)
                }
            } onEnded: {
                if let liveHeight { stripHeight = liveHeight }   // persist once
                liveHeight = nil
                dragStartHeight = nil
                frozenRenderHeight = nil          // one crisp re-render at the final size
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
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
                // The initial index isn't a *change* (e.g. a resumed deck opens
                // at its old slide), so scroll there once on appearance too.
                .onAppear { proxy.scrollTo(state.index, anchor: .center) }
                .onChange(of: state.index) { newValue in
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
            .frame(height: thumbHeight + 28)
            .background(Theme.raised)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
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
                    .strokeBorder(isCurrent ? Theme.accentRing : Theme.hairlineStrong,
                                  lineWidth: isCurrent ? 2.5 : 1)
            )
            .shadow(color: isCurrent ? Theme.accent.opacity(0.4) : .clear, radius: 6)
            Text("\(i + 1)")
                .font(.mono(10)).tracking(0.5)
                .foregroundStyle(isCurrent ? Theme.accentInk : Theme.textMuted)
        }
    }
}
