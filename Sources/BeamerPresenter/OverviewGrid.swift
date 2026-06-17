import SwiftUI

/// Full-window grid of every slide (magicPresenter-style overview). Click a
/// slide to jump to it and dismiss the overview.
struct OverviewGrid: View {
    @EnvironmentObject var state: PresentationState
    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Overview — \(state.pageCount) slides").font(.headline)
                Spacer()
                Button {
                    state.showOverview = false
                } label: {
                    Label("Close", systemImage: "xmark")
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(0..<state.pageCount, id: \.self) { i in
                        Button {
                            state.go(to: i)
                            state.showOverview = false
                        } label: {
                            cell(i)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func cell(_ i: Int) -> some View {
        let isCurrent = i == state.index
        VStack(spacing: 4) {
            Group {
                if let image = state.thumbnail(at: i, height: 160) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Color.black
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isCurrent ? Color.accentColor : Color.gray.opacity(0.4),
                                  lineWidth: isCurrent ? 3 : 1)
            )
            Text("\(i + 1)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
