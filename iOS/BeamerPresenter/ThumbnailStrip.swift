import SwiftUI

/// Horizontal, tappable strip of slide thumbnails; the current one is highlighted
/// and kept in view.
struct ThumbnailStrip: View {
    @EnvironmentObject var model: PresentationModel
    private let height: CGFloat = 64

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(0..<model.pageCount, id: \.self) { i in
                        Button { model.go(to: i) } label: { thumb(i) }
                            .buttonStyle(.plain)
                            .id(i)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            // The initial index isn't a *change* (a resumed deck opens at its old
            // slide), so scroll there once on appearance too.
            .onAppear { proxy.scrollTo(model.index, anchor: .center) }
            .onChange(of: model.index) { newValue in
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
        .background(Theme.raised)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    @ViewBuilder
    private func thumb(_ i: Int) -> some View {
        let isCurrent = i == model.index
        VStack(spacing: 3) {
            Group {
                if let image = model.thumbnail(i, height: height) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Theme.key
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isCurrent ? Theme.accentRing : Theme.hairlineStrong,
                              lineWidth: isCurrent ? 2.5 : 1))
            .shadow(color: isCurrent ? Theme.accent.opacity(0.4) : .clear, radius: 6)
            Text("\(i + 1)")
                .font(.mono(10)).tracking(0.5)
                .foregroundStyle(isCurrent ? Theme.accentInk : Theme.textMuted)
        }
    }
}
