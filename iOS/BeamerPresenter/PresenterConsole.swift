import SwiftUI

/// The macOS-style presenter console used on a wide (landscape / regular-width)
/// iPad: the current slide on the left, and a resizable right column with the
/// **next** slide on top, the **speaker notes** below it, and your **own notes**
/// at the bottom. All three dividers are draggable and the sizes persist.
struct PresenterConsole: View {
    @EnvironmentObject var model: PresentationModel
    let loadTex: () -> Void

    @AppStorage("consoleSidebarWidth") private var sidebarWidth: Double = 380
    @AppStorage("consoleNotesFraction") private var notesFraction: Double = 0.5
    @AppStorage("consoleScratchHeight") private var scratchHeight: Double = 150

    @State private var sidebarStart: Double?
    @State private var notesStart: Double?
    @State private var scratchStart: Double?

    private let sidebarRange = 280.0...760.0
    private let notesRange = 0.15...0.85
    private let scratchRange = 90.0...520.0

    var body: some View {
        HStack(spacing: 0) {
            pane("Current") {
                SlideView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Drag to resize the side column (it's to the right, so dragging right shrinks it).
            ResizeHandle(axis: .horizontal) { t in
                let start = sidebarStart ?? sidebarWidth
                sidebarStart = start
                sidebarWidth = (start - Double(t)).clamped(to: sidebarRange)
            } onEnded: { sidebarStart = nil }

            sideColumn.frame(width: sidebarWidth)
        }
        .padding(8)
    }

    private var sideColumn: some View {
        GeometryReader { geo in
            let handle: CGFloat = 12
            let total = geo.size.height
            let scratchH = min(CGFloat(scratchHeight), max(90, total * 0.6))
            let avail = max(0, total - 2 * handle - scratchH)
            let notesH = avail * notesFraction
            let nextH = avail - notesH

            VStack(spacing: 0) {
                pane("Next") {
                    StaticSlideView(index: model.index + 1)
                        .opacity(model.index + 1 < model.pageCount ? 1 : 0.25)
                }
                .frame(height: nextH)

                ResizeHandle(axis: .vertical) { t in
                    let start = notesStart ?? notesFraction
                    notesStart = start
                    notesFraction = (start - Double(t) / Double(max(avail, 1))).clamped(to: notesRange)
                } onEnded: { notesStart = nil }

                NotesPanel(loadTex: loadTex)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(height: notesH)

                ResizeHandle(axis: .vertical) { t in
                    let start = scratchStart ?? scratchHeight
                    scratchStart = start
                    scratchHeight = (start - Double(t)).clamped(to: scratchRange)
                } onEnded: { scratchStart = nil }

                ScratchPane().frame(height: scratchH)
            }
        }
    }

    private func pane<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.4)))
        }
    }
}

/// A read-only slide at a fixed index (used for the "Next" preview).
struct StaticSlideView: View {
    @EnvironmentObject var model: PresentationModel
    let index: Int

    var body: some View {
        ZStack {
            Color.black
            if index >= 0, index < model.pageCount {
                PDFPageView(document: model.document, pageIndex: index, displayBox: model.slideBox)
            }
        }
    }
}

/// Your own free-form notes: a text editor with quick-insert (time / deck name /
/// slide number) and a save-to-file button; autosaved per deck.
struct ScratchPane: View {
    @EnvironmentObject var model: PresentationModel
    @State private var shareURL: URL?
    @State private var showShare = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("My notes").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Time") {
                        model.appendScratch(Date().formatted(date: .omitted, time: .shortened))
                    }
                    Button("Deck name") { model.appendScratch(model.title) }
                    Button("Slide number") { model.appendScratch("Slide \(model.index + 1)/\(model.pageCount)") }
                } label: { Image(systemName: "bolt") }
                Button { saveToFile() } label: { Image(systemName: "square.and.arrow.down") }
                    .disabled(model.scratch.isEmpty)
            }
            TextEditor(text: $model.scratch)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.4)))
                .onChange(of: model.scratch) { _ in model.saveScratch() }
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL { ShareSheet(items: [url]) }
        }
    }

    private func saveToFile() {
        let name = (model.title.isEmpty ? "notes" : model.title) + " notes.txt"
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? model.scratch.write(to: dest, atomically: true, encoding: .utf8)
        shareURL = dest
        showShare = true
    }
}

/// A thin, draggable divider that reports cumulative translation along its axis.
struct ResizeHandle: View {
    enum Axis { case horizontal, vertical }   // horizontal = a vertical bar dragged left/right
    let axis: Axis
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    private var isHorizontal: Bool { axis == .horizontal }

    var body: some View {
        ZStack {
            Color.clear
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.45))
                .frame(width: isHorizontal ? 4 : 44, height: isHorizontal ? 44 : 4)
        }
        .frame(width: isHorizontal ? 12 : nil, height: isHorizontal ? nil : 12)
        .frame(maxWidth: isHorizontal ? nil : .infinity,
               maxHeight: isHorizontal ? .infinity : nil)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { onChanged(isHorizontal ? $0.translation.width : $0.translation.height) }
                .onEnded { _ in onEnded() }
        )
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
