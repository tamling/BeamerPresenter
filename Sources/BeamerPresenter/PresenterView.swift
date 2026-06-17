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
            PresenterView()
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

    /// Width of the right-hand column (next slide + notes), in points.
    @AppStorage("presenterSidebarWidth") private var sidebarWidth: Double = 360
    /// Share of the side column's height given to the notes pane (0…1).
    @AppStorage("presenterNotesFraction") private var notesFraction: Double = 0.5
    /// Height of the scratch-notes pane, in points.
    @AppStorage("presenterScratchHeight") private var scratchHeight: Double = 132

    @State private var sidebarDragStart: Double?
    @State private var notesDragStart: Double?
    @State private var scratchDragStart: Double?

    private let sidebarRange = 260.0...820.0
    private let notesRange = 0.15...0.85
    private let scratchRange = 80.0...460.0

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                ControlBar()

                if state.isBoardActive {
                    BoardBar(onSave: saveActiveBoard, onInsert: insertBoardIntoPDF)
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
            let scratchH = min(CGFloat(scratchHeight), max(80, total * 0.6))
            let avail = max(0, total - 2 * handle - scratchH)
            let notesH = avail * notesFraction
            let nextH = avail - notesH

            VStack(spacing: 0) {
                slidePane(title: "Next", index: state.index + 1, interactive: false)
                    .opacity(state.index + 1 < state.pageCount ? 1 : 0.25)
                    .frame(height: nextH)

                // Drag up/down to resize the notes pane (it sits below, so
                // dragging down shrinks it).
                ResizeHandle(axis: .vertical) { translation in
                    let start = notesDragStart ?? notesFraction
                    notesDragStart = start
                    let span = max(avail, 1)
                    notesFraction = (start - Double(translation) / Double(span)).clamped(to: notesRange)
                } onEnded: {
                    notesDragStart = nil
                }

                notesPane
                    .frame(height: notesH)

                // Drag up/down to resize the scratch pane (below it).
                ResizeHandle(axis: .vertical) { translation in
                    let start = scratchDragStart ?? scratchHeight
                    scratchDragStart = start
                    scratchHeight = (start - Double(translation)).clamped(to: scratchRange)
                } onEnded: {
                    scratchDragStart = nil
                }

                scratchPane
                    .frame(height: scratchH)
            }
        }
    }

    /// A small free-form notes editor, autosaved as `<pdf>.notes.txt` and
    /// explicitly saveable to a file of your choice via the button.
    private var scratchPane: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Scratch notes").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Time") { appendScratch(Date().formatted(date: .omitted, time: .shortened)) }
                    Button("Deck name") { appendScratch(state.title) }
                    Button("Slide number") { appendScratch("Slide \(state.index + 1)/\(state.pageCount)") }
                } label: {
                    Image(systemName: "bolt")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Insert the time, deck name, or slide number")
                Button { saveScratchToFile() } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .help("Save notes as a .txt file…")
            }
            TextEditor(text: $state.scratch)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.3)))
                .onChange(of: state.scratch) { _ in state.saveScratch() }
        }
    }

    /// Appends a quick value (time / deck name / slide number) to the notes.
    private func appendScratch(_ value: String) {
        state.scratch += (state.scratch.isEmpty ? "" : "\n") + value
        state.saveScratch()
    }

    /// Saves the scratch notes to a user-chosen `.txt` file.
    @MainActor
    private func saveScratchToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(state.title.isEmpty ? "notes" : state.title) notes.txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try state.scratch.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not save the notes"
            alert.informativeText = url.lastPathComponent
            alert.runModal()
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

    /// Inserts the active whiteboard after the current slide into a copy of the
    /// deck PDF, saved to a user-chosen file (the original is left untouched).
    @MainActor
    private func insertBoardIntoPDF() {
        guard let board = state.activeBoard, let source = state.sourceURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(state.title) + \(board.name).pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        if !BoardExporter.insertIntoCopy(of: source, board: board, afterIndex: state.index,
                                         aspect: state.slideAspect, to: dest) {
            let alert = NSAlert()
            alert.messageText = "Could not insert the whiteboard into the PDF"
            alert.informativeText = dest.lastPathComponent
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

/// In-app bar with all the live controls — exit, navigation, overview/blackout/
/// whiteboard, pen/laser, the pen-colour swatches, ink undo/clear, and the
/// clocks — each shown as a symbol with a caption beneath it. The same commands
/// also live in the macOS menu bar (and on the keyboard).
private struct ControlBar: View {
    @EnvironmentObject var state: PresentationState

    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            tool("Exit", "rectangle.portrait.and.arrow.right") { state.unload() }

            Spacer(minLength: 8)

            // Navigation, then the audience and drawing groups, spread apart.
            tool("Prev", "chevron.left", disabled: state.index == 0) { state.previous() }
            captioned("Slide") {
                Text("\(state.index + 1) / \(state.pageCount)")
                    .font(.headline.monospacedDigit())
            }
            tool("Next", "chevron.right", disabled: state.index + 1 >= state.pageCount) { state.next() }

            Spacer(minLength: 22)

            tool("Overview", "square.grid.2x2", active: state.showOverview) { state.showOverview.toggle() }
            tool("Blackout", state.blackout ? "eye.slash.fill" : "eye.slash", active: state.blackout) { state.blackout.toggle() }
            tool("Board", "square.and.pencil", active: state.isBoardActive) { state.toggleBoard() }

            Spacer(minLength: 22)

            tool("Pen", "pencil.tip", active: state.tool == .pen) { state.toggleTool(.pen) }
            tool("Laser", "dot.circle.and.cursorarrow", active: state.tool == .laser) { state.toggleTool(.laser) }

            ForEach(PenPalette.colors, id: \.name) { name, color in
                captioned(name) {
                    Button {
                        state.penColor = color
                        if state.tool == .none { state.tool = .pen }   // keep the laser if it's active
                    } label: {
                        Circle().fill(color)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(
                                .primary.opacity(state.penColor == color ? 0.9 : 0.2),
                                lineWidth: state.penColor == color ? 2.5 : 1))
                    }
                    .buttonStyle(.borderless)
                }
            }

            tool("Undo", "arrow.uturn.backward", disabled: !state.hasInkOnCurrentSlide) { state.undoStroke() }
            tool("Clear", "trash", disabled: !state.hasInkOnCurrentSlide) { state.clearStrokes() }

            Spacer(minLength: 8)

            // Right cluster: the timer (start/stop, reset) and clocks.
            tool(state.timerRunning ? "Pause" : "Start",
                 state.timerRunning ? "pause" : "play",
                 active: !state.timerRunning) { state.toggleTimer() }
            tool("Reset", "arrow.counterclockwise") { state.resetTimer() }
            captioned("Elapsed") {
                Label(elapsed, systemImage: "stopwatch")
                    .font(.headline.monospacedDigit())
            }
            captioned("Time") {
                Text(now, style: .time)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(nsColor: .underPageBackgroundColor))
        .onReceive(tick) { now = $0 }
    }

    /// A captioned icon button; tinted when `active`, greyed when `disabled`.
    private func tool(_ caption: String, _ systemImage: String,
                      active: Bool = false, disabled: Bool = false,
                      action: @escaping () -> Void) -> some View {
        captioned(caption) {
            Button(action: action) {
                Image(systemName: systemImage).font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(active ? Color.accentColor : .primary)
            .disabled(disabled)
        }
    }

    /// A control stacked above a small caption. The content sits in a fixed-height
    /// band so every symbol lines up on the same horizontal line, captions below.
    private func captioned<Content: View>(_ caption: String,
                                          @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 3) {
            content()
                .frame(height: 24)
            Text(caption)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private var elapsed: String {
        _ = now   // re-render every tick
        let secs = max(0, Int(state.elapsedSeconds))
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }
}
