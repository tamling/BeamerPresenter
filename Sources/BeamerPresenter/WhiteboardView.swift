import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

// MARK: - Pure rendering (presenter, audience, and export all share this)

/// Renders a board's white background, committed ink, and items at a given size.
/// No environment or interaction — so it can also be handed to `ImageRenderer`
/// for export. Apply `.aspectRatio` on the caller's side.
struct BoardCanvas: View {
    let board: Whiteboard
    var liveStroke: [CGPoint] = []
    var liveColor: Color = .red

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.white
                Canvas { ctx, sz in
                    for stroke in board.strokes {
                        ctx.stroke(boardPath(stroke.points, in: sz),
                                   with: .color(stroke.color),
                                   style: boardLineStyle(stroke.width * sz.width))
                    }
                    if liveStroke.count > 1 {
                        ctx.stroke(boardPath(liveStroke, in: sz),
                                   with: .color(liveColor),
                                   style: boardLineStyle(0.004 * sz.width))
                    }
                }
                ForEach(board.items) { item in
                    BoardItemView(item: item, boardSize: size)
                        .position(x: item.center.x * size.width,
                                  y: item.center.y * size.height)
                }
            }
        }
    }
}

/// One item (text / table / QR) rendered at board scale.
struct BoardItemView: View {
    let item: BoardItem
    let boardSize: CGSize

    private var pixelWidth: CGFloat { max(8, item.width * boardSize.width) }
    private var fontSize: CGFloat { max(6, item.fontScale * boardSize.width) }

    var body: some View {
        switch item.kind {
        case .text:
            Text(item.text.isEmpty ? " " : item.text)
                .font(.system(size: fontSize))
                .foregroundStyle(.black)
                .multilineTextAlignment(.leading)
                .frame(width: pixelWidth, alignment: .topLeading)
        case .qr:
            Group {
                if let image = QRCode.image(from: item.text) {
                    Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 4).stroke(.gray)
                        .overlay(Image(systemName: "qrcode").foregroundStyle(.gray))
                }
            }
            .frame(width: pixelWidth, height: pixelWidth)
        case .table:
            TableItemView(text: item.text, width: pixelWidth, fontSize: fontSize)
        }
    }
}

/// A simple grid table. Rows are separated by newlines, columns by `|`.
struct TableItemView: View {
    let text: String
    let width: CGFloat
    let fontSize: CGFloat

    private var rows: [[String]] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    var body: some View {
        let cols = max(1, rows.map(\.count).max() ?? 1)
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                GridRow {
                    ForEach(0..<cols, id: \.self) { c in
                        Text(c < rows[r].count ? rows[r][c] : "")
                            .font(.system(size: fontSize))
                            .foregroundStyle(.black)
                            .padding(.horizontal, fontSize * 0.4)
                            .padding(.vertical, fontSize * 0.25)
                            .frame(maxWidth: .infinity, minHeight: fontSize + 6)
                            .border(Color.black.opacity(0.6), width: 1)
                    }
                }
            }
        }
        .frame(width: width)
    }
}

// MARK: - Interactive presenter board

/// The whiteboard as shown on the presenter screen: shared rendering plus a layer
/// for drawing ink and moving/selecting items.
struct WhiteboardPane: View {
    @EnvironmentObject var state: PresentationState

    var body: some View {
        ZStack {
            if let board = state.activeBoard {
                BoardCanvas(board: board,
                            liveStroke: state.boardStroke,
                            liveColor: state.penColor)
                BoardInteractionLayer()
            } else {
                Color.white
            }
        }
        .aspectRatio(state.slideAspect, contentMode: .fit)
        .border(.gray.opacity(0.5))
        .overlay(alignment: .bottom) {
            if state.isBoardActive, state.selectedItemID != nil {
                BoardItemInspector().padding(8)
            }
        }
    }
}

/// Captures pen drags (when the pen tool is active) and otherwise shows a move
/// handle on each item for selecting and repositioning it.
private struct BoardInteractionLayer: View {
    @EnvironmentObject var state: PresentationState

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                if state.tool == .pen {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let p = unitPoint(value.location, in: size)
                                    if state.boardStroke.isEmpty {
                                        state.boardBeginStroke(at: p)
                                    } else {
                                        state.boardExtendStroke(to: p)
                                    }
                                }
                                .onEnded { _ in state.boardEndStroke() }
                        )
                } else if let board = state.activeBoard {
                    ForEach(board.items) { item in
                        moveHandle(for: item, in: size)
                    }
                }
            }
        }
    }

    private func moveHandle(for item: BoardItem, in size: CGSize) -> some View {
        let selected = state.selectedItemID == item.id
        return Circle()
            .fill(Color.accentColor.opacity(selected ? 0.95 : 0.55))
            .overlay(
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            )
            .frame(width: 26, height: 26)
            .position(x: item.center.x * size.width, y: item.center.y * size.height)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        state.selectedItemID = item.id
                        state.moveItem(item.id, to: unitPoint(value.location, in: size))
                    }
            )
            .help("Drag to move · tap to select")
    }
}

// MARK: - Item inspector

/// Compact editor for the selected item: its text/payload, size, and delete.
private struct BoardItemInspector: View {
    @EnvironmentObject var state: PresentationState

    var body: some View {
        if let item = state.selectedItem {
            HStack(spacing: 8) {
                Image(systemName: icon(item.kind))
                    .foregroundStyle(.secondary)

                if item.kind == .table {
                    TextEditor(text: textBinding(item.id))
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 48)
                        .help("Rows on separate lines, columns separated by |")
                } else {
                    TextField(item.kind == .qr ? "URL or text to encode" : "Text",
                              text: textBinding(item.id))
                        .textFieldStyle(.roundedBorder)
                }

                Stepper("", onIncrement: { state.scaleItem(item.id, by: 1.1) },
                            onDecrement: { state.scaleItem(item.id, by: 1 / 1.1) })
                    .labelsHidden()
                    .help("Resize")

                Button { state.deleteSelectedItem() } label: {
                    Image(systemName: "trash")
                }
                .help("Delete item")

                Button { state.selectedItemID = nil } label: {
                    Image(systemName: "checkmark")
                }
                .help("Done")
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: 520)
        }
    }

    private func textBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { state.activeBoard?.items.first { $0.id == id }?.text ?? "" },
            set: { state.updateItemText(id, $0) }
        )
    }

    private func icon(_ kind: BoardItem.Kind) -> String {
        switch kind {
        case .text:  return "textformat"
        case .table: return "tablecells"
        case .qr:    return "qrcode"
        }
    }
}

// MARK: - Board toolbar

/// Second toolbar row shown while a board is active: board management plus the
/// quick-insert buttons (text / table / QR) and export.
struct BoardBar: View {
    @EnvironmentObject var state: PresentationState
    let onSave: @MainActor () -> Void
    let onInsert: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button { state.addBoard() } label: { Image(systemName: "plus.rectangle") }
                .help("New whiteboard")

            Button { state.previousBoard() } label: { Image(systemName: "chevron.left") }
                .disabled((state.activeBoardIndex ?? 0) == 0)
            Text("Board \((state.activeBoardIndex ?? 0) + 1) / \(state.boards.count)")
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 96)
            Button { state.nextBoard() } label: { Image(systemName: "chevron.right") }
                .disabled((state.activeBoardIndex ?? 0) + 1 >= state.boards.count)

            Button { state.deleteActiveBoard() } label: { Image(systemName: "trash") }
                .help("Delete this whiteboard")

            Divider().frame(height: 18)

            Button { state.addItem(.text) } label: { Label("Text", systemImage: "textformat") }
                .help("Add a text box")
            Button { state.addItem(.table) } label: { Label("Table", systemImage: "tablecells") }
                .help("Add a table")
            Button { state.addItem(.qr) } label: { Label("QR", systemImage: "qrcode") }
                .help("Add a QR code")

            Divider().frame(height: 18)

            Button { onSave() } label: { Label("Save…", systemImage: "square.and.arrow.down") }
                .help("Save this whiteboard as its own PDF")
            Button { onInsert() } label: { Label("Insert into PDF", systemImage: "rectangle.stack.badge.plus") }
                .disabled(state.sourceURL == nil)
                .help("Insert after the current slide into a copy of the deck")

            Spacer()

            Button { state.hideBoard() } label: { Label("Done", systemImage: "xmark.circle") }
                .help("Back to the slides (W)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

// MARK: - Export

/// Renders a board to PDF using SwiftUI's `ImageRenderer`. The board content is
/// vector (shapes/text), so it stays crisp at any page size.
@MainActor
enum BoardExporter {
    /// One board page as standalone PDF data at the given point size.
    static func renderPDFData(board: Whiteboard, size: CGSize) -> Data? {
        let content = BoardCanvas(board: board)
            .frame(width: size.width, height: size.height)
            .background(Color.white)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)

        let data = NSMutableData()
        var success = false
        renderer.render { sz, renderInContext in
            var box = CGRect(origin: .zero, size: sz)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            renderInContext(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            success = true
        }
        return success ? data as Data : nil
    }

    /// Writes the board to its own single-page PDF file.
    @discardableResult
    static func writePDF(board: Whiteboard, aspect: CGFloat, to url: URL) -> Bool {
        let height: CGFloat = 1080
        guard let data = renderPDFData(board: board, size: CGSize(width: max(1, height * aspect), height: height))
        else { return false }
        return (try? data.write(to: url)) != nil
    }

    /// Loads the original deck, inserts the board as a new page right after
    /// `afterIndex`, and writes the result to `dest` — leaving the original file
    /// untouched (it works on an in-memory copy). The inserted page matches the
    /// deck's page height at the slide's aspect ratio.
    @discardableResult
    static func insertIntoCopy(of sourceURL: URL, board: Whiteboard,
                               afterIndex: Int, aspect: CGFloat, to dest: URL) -> Bool {
        guard let doc = PDFDocument(url: sourceURL), doc.pageCount > 0 else { return false }
        let refIndex = min(max(afterIndex, 0), doc.pageCount - 1)
        let pageHeight = doc.page(at: refIndex)?.bounds(for: .mediaBox).height ?? 540
        let size = CGSize(width: max(1, pageHeight * aspect), height: pageHeight)

        guard let data = renderPDFData(board: board, size: size),
              let boardDoc = PDFDocument(data: data),
              let boardPage = boardDoc.page(at: 0)?.copy() as? PDFPage else { return false }

        doc.insert(boardPage, at: min(afterIndex + 1, doc.pageCount))
        return doc.write(to: dest)
    }
}

// MARK: - Shared helpers

private func boardPath(_ points: [CGPoint], in size: CGSize) -> Path {
    var p = Path()
    guard let first = points.first else { return p }
    p.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
    for pt in points.dropFirst() {
        p.addLine(to: CGPoint(x: pt.x * size.width, y: pt.y * size.height))
    }
    return p
}

private func boardLineStyle(_ width: CGFloat) -> StrokeStyle {
    StrokeStyle(lineWidth: max(1, width), lineCap: .round, lineJoin: .round)
}

private func unitPoint(_ p: CGPoint, in size: CGSize) -> CGPoint {
    CGPoint(x: min(max(0, p.x / size.width), 1),
            y: min(max(0, p.y / size.height), 1))
}
