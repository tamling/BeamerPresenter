import SwiftUI

/// A full-screen grid of every slide as a thumbnail; tap one to jump to it and
/// dismiss. The current slide is highlighted.
struct OverviewGrid: View {
    @EnvironmentObject var model: PresentationModel
    @Binding var isPresented: Bool

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)]
    private let thumbHeight: CGFloat = 130

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(0..<model.pageCount, id: \.self) { i in
                            Button {
                                model.go(to: i)
                                isPresented = false
                            } label: { cell(i) }
                            .buttonStyle(.plain)
                            .id(i)
                        }
                    }
                    .padding(20)
                }
                .onAppear { proxy.scrollTo(model.index, anchor: .center) }
            }
            .background(Theme.base.ignoresSafeArea())
            .navigationTitle("All slides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func cell(_ i: Int) -> some View {
        let isCurrent = i == model.index
        VStack(spacing: 6) {
            Group {
                if let image = model.thumbnail(i, height: thumbHeight) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Color.black
                }
            }
            .frame(height: thumbHeight)
            .frame(maxWidth: .infinity)
            .background(Theme.key)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isCurrent ? Theme.accent : Theme.hairlineStrong,
                              lineWidth: isCurrent ? 2.5 : 1))
            .shadow(color: isCurrent ? Theme.accent.opacity(0.4) : .clear, radius: 8)
            Text("\(i + 1)")
                .font(.mono(11))
                .foregroundStyle(isCurrent ? Theme.accent : Theme.textMuted)
        }
    }
}
