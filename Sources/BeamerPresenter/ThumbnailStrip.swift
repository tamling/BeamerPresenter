import SwiftUI

/// Horizontal, clickable strip of slide thumbnails with a drag handle above it
/// to zoom. The current slide is highlighted; clicking (single or double, per
/// Settings) jumps to that slide. Auto-scrolls to keep the current slide
/// visible.
///
/// Zooming is designed to feel fluid: while the handle is being dragged the
/// existing bitmaps are only *scaled* (with a slight blur as a visual cue) —
/// no PDF rendering happens mid-drag. The crisp re-render at the final size
/// runs once, when the drag ends.
struct ThumbnailStrip: View {
    @EnvironmentObject var state: PresentationState
    @AppStorage(Prefs.thumbStripHeight) private var stripHeight: Double = 70
    @AppStorage(Prefs.doubleClickSlides) private var doubleClick = false

    @State private var dragStartHeight: Double?
    @State private var frozenRenderHeight: CGFloat?   // bitmaps stay at this size mid-drag

    private let heightRange = 50.0...260.0
    private var thumbHeight: CGFloat { CGFloat(stripHeight) }

    /// Rendering happens at 64 pt buckets; display scales to the live height.
    private var bucket: CGFloat { max(64, (thumbHeight / 64).rounded(.up) * 64) }
    private var renderHeight: CGFloat { frozenRenderHeight ?? bucket }
    private var isZooming: Bool { frozenRenderHeight != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Drag up/down to zoom the thumbnails (the strip sits below, so
            // dragging up enlarges them).
            ResizeHandle(axis: .vertical) { translation in
                if dragStartHeight == nil {
                    dragStartHeight = stripHeight
                    frozenRenderHeight = bucket   // freeze the bitmaps for the drag
                }
                let start = dragStartHeight ?? stripHeight
                stripHeight = min(max(start - Double(translation),
                                      heightRange.lowerBound), heightRange.upperBound)
            } onEnded: {
                dragStartHeight = nil
                frozenRenderHeight = nil          // one crisp re-render at the final size
            }

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
            .blur(radius: isZooming ? 1.2 : 0)   // soft cue while scaling mid-drag
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
