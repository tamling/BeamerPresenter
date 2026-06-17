import SwiftUI

/// Root of the presenter window: shows the welcome screen until a presentation
/// is loaded, then the full presenter console.
struct RootPresenterView: View {
    @EnvironmentObject var state: PresentationState
    let onOpen: () -> Void
    let onOpenURL: (URL) -> Void

    var body: some View {
        if state.isLoaded {
            PresenterView(onOpen: onOpen)
        } else {
            WelcomeView(onOpen: onOpen, onOpenURL: onOpenURL)
        }
    }
}

/// Your private screen: control bar, current slide, next slide, notes, a
/// thumbnail strip for navigation, and an optional overview overlay.
struct PresenterView: View {
    @EnvironmentObject var state: PresentationState
    let onOpen: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                ControlBar(onOpen: onOpen)

                HStack(spacing: 8) {
                    slidePane(title: "Current", index: state.index, interactive: true)
                    VStack(spacing: 8) {
                        slidePane(title: "Next", index: state.index + 1, interactive: false)
                            .opacity(state.index + 1 < state.pageCount ? 1 : 0.25)
                        notesPane
                    }
                    .frame(width: 360)
                }
                .frame(maxHeight: .infinity)

                ThumbnailStrip()
            }
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))

            if state.showOverview {
                OverviewGrid().transition(.opacity)
            }
        }
    }

    private func slidePane(title: String, index: Int, interactive: Bool) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            SlideView(pageIndex: index, interactive: interactive)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .border(.gray.opacity(0.5))
        }
    }

    @ViewBuilder
    private var notesPane: some View {
        if state.hasNotes {
            VStack(spacing: 4) {
                Text("Notes").font(.caption).foregroundStyle(.secondary)
                PDFPageView(document: state.notesDoc, pageIndex: state.index)
                    .border(.gray.opacity(0.5))
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "note.text")
                Text("No notes in this PDF").font(.headline)
                Text("Compile with:\n\\setbeameroption{show notes on second screen=right}")
                    .font(.system(.caption, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Top toolbar with open/close, navigation, overview, blackout, and clocks.
private struct ControlBar: View {
    @EnvironmentObject var state: PresentationState
    let onOpen: () -> Void

    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let penColors: [(String, Color)] = [("Red", .red), ("Green", .green),
                                                ("Blue", .blue), ("Yellow", .yellow)]

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) { Image(systemName: "folder") }
                .help("Open another presentation")
            Button { state.unload() } label: { Image(systemName: "house") }
                .help("Back to start")

            Divider().frame(height: 18)

            Button { state.previous() } label: { Image(systemName: "chevron.left") }
                .disabled(state.index == 0)
            Text("Slide \(state.index + 1) / \(state.pageCount)")
                .font(.headline.monospacedDigit())
                .frame(minWidth: 120)
            Button { state.next() } label: { Image(systemName: "chevron.right") }
                .disabled(state.index + 1 >= state.pageCount)

            Divider().frame(height: 18)

            Button { state.showOverview.toggle() } label: { Image(systemName: "square.grid.2x2") }
                .help("Overview (G)")
            Button { state.blackout.toggle() } label: {
                Image(systemName: state.blackout ? "eye.slash.fill" : "eye.slash")
            }
            .help("Black out audience screen (B)")

            Divider().frame(height: 18)

            Button { state.toggleTool(.pen) } label: { Image(systemName: "pencil.tip") }
                .foregroundStyle(state.tool == .pen ? Color.accentColor : .primary)
                .help("Pen (P)")
            Button { state.toggleTool(.laser) } label: { Image(systemName: "dot.circle.and.cursorarrow") }
                .foregroundStyle(state.tool == .laser ? Color.accentColor : .primary)
                .help("Laser pointer (L)")
            ForEach(penColors, id: \.0) { name, color in
                Button { state.penColor = color } label: {
                    Circle().fill(color)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.primary.opacity(state.penColor == color ? 0.9 : 0.2),
                                                       lineWidth: state.penColor == color ? 2 : 1))
                }
                .help("Pen colour: \(name)")
            }
            Button { state.undoStroke() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!state.hasInkOnCurrentSlide)
                .help("Undo stroke (Z)")
            Button { state.clearStrokes() } label: { Image(systemName: "trash") }
                .disabled(!state.hasInkOnCurrentSlide)
                .help("Clear ink (C)")

            Spacer()

            Label(elapsed, systemImage: "stopwatch")
                .font(.headline.monospacedDigit())
            Button { state.resetTimer() } label: { Image(systemName: "arrow.counterclockwise") }
                .help("Reset timer (R)")
            Text(now, style: .time)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .underPageBackgroundColor))
        .onReceive(tick) { now = $0 }
    }

    private var elapsed: String {
        let secs = max(0, Int(now.timeIntervalSince(state.startDate)))
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }
}
