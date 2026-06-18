import SwiftUI

/// Horizontal, clickable strip of slide thumbnails. The current slide is
/// highlighted; clicking jumps to that slide. Auto-scrolls to keep the current
/// slide visible.
struct ThumbnailStrip: View {
    @EnvironmentObject var state: PresentationState
    private let thumbHeight: CGFloat = 70

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<state.pageCount, id: \.self) { i in
                        Button { state.go(to: i) } label: {
                            thumb(i)
                        }
                        .buttonStyle(.plain)
                        .id(i)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
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
                if let image = state.thumbnail(at: i, height: thumbHeight) {
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
