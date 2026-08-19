import SwiftUI

/// Full-window grid of every slide. Click a
/// slide to jump to it and dismiss the overview.
struct OverviewGrid: View {
    @EnvironmentObject var state: PresentationState
    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("All slides").font(.display(22)).foregroundStyle(Theme.textPrimary)
                Text("\(state.pageCount)").microLabel()
                Spacer()
                Button { state.showOverview = false } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 26)
                        .background(Theme.key, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
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
                .padding(20)
            }
        }
        .background(Theme.base)
    }

    @ViewBuilder
    private func cell(_ i: Int) -> some View {
        let isCurrent = i == state.index
        VStack(spacing: 6) {
            Group {
                if let image = state.thumbnail(at: i, height: 160) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Theme.key
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isCurrent ? Theme.accent : Theme.hairlineStrong,
                                  lineWidth: isCurrent ? 2.5 : 1)
            )
            .shadow(color: isCurrent ? Theme.accent.opacity(0.4) : .clear, radius: 8)
            Text("\(i + 1)").font(.mono(11)).foregroundStyle(isCurrent ? Theme.accent : Theme.textMuted)
        }
    }
}
