import SwiftUI

/// Horizontal, tappable strip of slide thumbnails; the current one is highlighted
/// and kept in view.
struct ThumbnailStrip: View {
    @EnvironmentObject var model: PresentationModel
    private let height: CGFloat = 64

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<model.pageCount, id: \.self) { i in
                        Button { model.go(to: i) } label: { thumb(i) }
                            .buttonStyle(.plain)
                            .id(i)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .onChange(of: model.index) { newValue in
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func thumb(_ i: Int) -> some View {
        let isCurrent = i == model.index
        VStack(spacing: 2) {
            Group {
                if let image = model.thumbnail(i, height: height) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Color.black
                }
            }
            .frame(height: height)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isCurrent ? Color.accentColor : Color.gray.opacity(0.4),
                              lineWidth: isCurrent ? 3 : 1))
            Text("\(i + 1)")
                .font(.caption2)
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
        }
    }
}
