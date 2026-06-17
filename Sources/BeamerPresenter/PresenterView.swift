import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
///
/// The split between the current slide and the side column, and between the next
/// slide and the notes, are both draggable; the chosen sizes persist across
/// launches.
struct PresenterView: View {
    @EnvironmentObject var state: PresentationState
    let onOpen: () -> Void

    /// Width of the right-hand column (next slide + notes), in points.
    @AppStorage("presenterSidebarWidth") private var sidebarWidth: Double = 360
    /// Share of the side column's height given to the notes pane (0…1).
    @AppStorage("presenterNotesFraction") private var notesFraction: Double = 0.5

    @State private var sidebarDragStart: Double?
    @State private var notesDragStart: Double?

    private let sidebarRange = 260.0...820.0
    private let notesRange = 0.15...0.85

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                ControlBar(onOpen: onOpen)

                if state.isBoardActive {
                    BoardBar(onSave: saveActiveBoard)
                }

                HStack(spacing: 0) {
                    currentPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Drag left/right to resize the side column (it sits to the
                    // right of this handle, so dragging right shrinks it).
                    ResizeHandle(axis: .horizontal) { translation in
                        let start = sidebarDragStart ?? sidebarWidth
                        sidebarDragStart = start
                        sidebarWidth = (start - Double(translation)).clamped(to: sidebarRange)
                    } onEnded: {
                        sidebarDragStart = nil
                    }

                    sideColumn
                        .frame(width: sidebarWidth)
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

    /// Next slide on top, notes below, with a draggable divider between them.
    private var sideColumn: some View {
        GeometryReader { geo in
            let handle: CGFloat = 10
            let total = geo.size.height
            let notesH = max(0, (total - handle) * notesFraction)
            let nextH = max(0, total - handle - notesH)

            VStack(spacing: 0) {
                slidePane(title: "Next", index: state.index + 1, interactive: false)
                    .opacity(state.index + 1 < state.pageCount ? 1 : 0.25)
                    .frame(height: nextH)

                // Drag up/down to resize the notes pane (it sits below, so
                // dragging down shrinks it).
                ResizeHandle(axis: .vertical) { translation in
                    let start = notesDragStart ?? notesFraction
                    notesDragStart = start
                    let span = max(total - handle, 1)
                    notesFraction = (start - Double(translation) / Double(span)).clamped(to: notesRange)
                } onEnded: {
                    notesDragStart = nil
                }

                notesPane
                    .frame(height: notesH)
            }
        }
    }

    /// The large left pane: the current slide, or the whiteboard when active.
    private var currentPane: some View {
        VStack(spacing: 4) {
            Text(state.isBoardActive ? "Whiteboard" : "Current")
                .font(.caption).foregroundStyle(.secondary)
            if state.isBoardActive {
                WhiteboardPane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SlideView(pageIndex: state.index, interactive: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .border(.gray.opacity(0.5))
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

    /// Exports the active whiteboard to a PDF chosen by the user.
    @MainActor
    private func saveActiveBoard() {
        guard let board = state.activeBoard else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(board.name).pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !BoardExporter.writePDF(board: board, aspect: state.slideAspect, to: url) {
            let alert = NSAlert()
            alert.messageText = "Could not save the whiteboard"
            alert.informativeText = url.lastPathComponent
            alert.runModal()
        }
    }

    private var notesPane: some View {
        VStack(spacing: 4) {
            Text("Notes").font(.caption).foregroundStyle(.secondary)
            notesContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .border(.gray.opacity(0.5))
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var notesContent: some View {
        if state.notesDoc != nil {
            PDFPageView(document: state.notesDoc, pageIndex: state.index)
        } else if let text = state.textNotes[state.index], !text.isEmpty {
            ScrollView {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else if state.hasNotes {
            placeholder(icon: "note.text",
                        title: "No note for this slide",
                        detail: "Notes loaded from the .tex source.")
        } else {
            placeholder(icon: "note.text",
                        title: "No notes for this presentation",
                        detail: "Show notes on a second screen with:\n\\setbeameroption{show notes on second screen=right}\n\nor keep a <name>.tex with \\note{…} next to the PDF.")
        }
    }

    private func placeholder(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
            Text(title).font(.headline)
            Text(detail)
                .font(.system(.caption, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A thin, draggable divider. Reports the cumulative drag translation (in points)
/// along its axis so the parent can resize the adjacent pane, and shows the
/// matching resize cursor on hover.
struct ResizeHandle: View {
    enum Axis { case horizontal, vertical }   // horizontal = a vertical bar dragged left/right

    let axis: Axis
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    @State private var hovering = false

    private var isHorizontal: Bool { axis == .horizontal }

    var body: some View {
        ZStack {
            Color.clear
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(hovering ? 0.55 : 0.3))
                .frame(width: isHorizontal ? 4 : 40,
                       height: isHorizontal ? 40 : 4)
        }
        .frame(width: isHorizontal ? 10 : nil,
               height: isHorizontal ? nil : 10)
        .frame(maxWidth: isHorizontal ? nil : .infinity,
               maxHeight: isHorizontal ? .infinity : nil)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside {
                (isHorizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { onChanged(isHorizontal ? $0.translation.width : $0.translation.height) }
                .onEnded { _ in onEnded() }
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
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
            Button { state.toggleBoard() } label: { Image(systemName: "square.and.pencil") }
                .foregroundStyle(state.isBoardActive ? Color.accentColor : .primary)
                .help("Whiteboard (W)")

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
