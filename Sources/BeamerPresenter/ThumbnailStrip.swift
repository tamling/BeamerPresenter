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
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    @ViewBuilder
    private func thumb(_ i: Int) -> some View {
        let isCurrent = i == state.index
        VStack(spacing: 2) {
            Group {
                if let image = state.thumbnail(at: i, height: thumbHeight) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Color.black
                }
            }
            .frame(height: thumbHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isCurrent ? Color.accentColor : Color.gray.opacity(0.4),
                                  lineWidth: isCurrent ? 3 : 1)
            )
            Text("\(i + 1)")
                .font(.caption2)
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
        }
    }
}
