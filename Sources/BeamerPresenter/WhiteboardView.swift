import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

// MARK: - Pure rendering (presenter, audience, and export all share this)

/// The palette a board renders in. Presenter and the audience screen use `.dark`
/// (the Night look); the PDF/board export uses `.light` so printed pages stay
/// ink-on-white and readable on paper.
struct BoardStyle {
    var background: Color
    var showGrid: Bool
    var gridDot: Color
    var text: Color
    var tableBorder: Color
    var tableHeader: Color
    var tableSurface: Color
    var tableStripe: Color

    func rowColor(_ r: Int) -> Color {
        if r == 0 { return tableHeader }
        return r.isMultiple(of: 2) ? tableSurface : tableStripe
    }

    /// Night look — presenter + audience.
    static let dark = BoardStyle(
        background: Theme.stage,
        showGrid: true,
        gridDot: Theme.textFaint.opacity(0.4),
        text: Theme.textPrimary,
        tableBorder: Theme.hairlineStrong,
        tableHeader: Theme.key,
        tableSurface: Theme.surface,
        tableStripe: Color(hex: 0x21252C)
    )

    /// Printable look — PDF / board export. Ink-on-white, no grid.
    static let light = BoardStyle(
        background: .white,
        showGrid: false,
        gridDot: .clear,
        text: .black,
        tableBorder: Color(white: 0.80),
        tableHeader: Color(white: 0.93),
        tableSurface: .white,
        tableStripe: Color(white: 0.975)
    )
}

/// Renders a board's background, committed ink, and items at a given size.
/// No environment or interaction — so it can also be handed to `ImageRenderer`
/// for export. Apply `.aspectRatio` on the caller's side.
struct BoardCanvas: View {
    let board: Whiteboard
    var liveStroke: [CGPoint] = []
    var liveColor: Color = .red
    var style: BoardStyle = .dark

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                style.background
                if style.showGrid {
                    Canvas { ctx, sz in
                        let step = max(16, sz.width * 0.028)
                        var y = step
                        while y < sz.height {
                            var x = step
                            while x < sz.width {
                                ctx.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)),
                                         with: .color(style.gridDot))
                                x += step
                            }
                            y += step
                        }
                    }
                }
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
                    BoardItemView(item: item, boardSize: size, style: style)
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
    var style: BoardStyle = .dark

    private var pixelWidth: CGFloat { max(8, item.width * boardSize.width) }
    private var fontSize: CGFloat { max(6, item.fontScale * boardSize.width) }

    var body: some View {
        switch item.kind {
        case .text:
            Text(item.text.isEmpty ? " " : item.text)
                .font(.system(size: fontSize))
                .foregroundStyle(style.text)
                .multilineTextAlignment(.leading)
                .frame(width: pixelWidth, alignment: .topLeading)
        case .qr:
            Group {
                if let image = QRCode.image(from: item.text) {
                    // QR always sits on a white chip with a quiet zone so it scans
                    // on the dark board (and is seamless on the light export).
                    Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
                        .padding(pixelWidth * 0.06)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6).stroke(style.tableBorder)
                        .overlay(Image(systemName: "qrcode").foregroundStyle(style.text.opacity(0.5)))
                }
            }
            .frame(width: pixelWidth, height: pixelWidth)
        case .table:
            TableItemView(text: item.text, width: pixelWidth, fontSize: fontSize, style: style)
        }
    }
}

/// A clean grid table: shaded header row, alternating row tints, hairline
/// separators, and rounded clipped corners. Rows are separated by newlines,
/// columns by `|`.
struct TableItemView: View {
    let text: String
    let width: CGFloat
    let fontSize: CGFloat
    var style: BoardStyle = .dark

    private var rows: [[String]] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    var body: some View {
        let cols = max(1, rows.map(\.count).max() ?? 1)
        let radius = fontSize * 0.45
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<cols, id: \.self) { c in
                        Text(c < rows[r].count ? rows[r][c] : "")
                            .font(.system(size: fontSize, weight: r == 0 ? .semibold : .regular))
                            .foregroundStyle(style.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, fontSize * 0.5)
                            .padding(.vertical, fontSize * 0.32)
                            .overlay(alignment: .trailing) {
                                if c < cols - 1 { Rectangle().fill(style.tableBorder).frame(width: 0.75) }
                            }
                    }
                }
                .background(style.rowColor(r))
                .overlay(alignment: .bottom) {
                    if r < rows.count - 1 { Rectangle().fill(style.tableBorder).frame(height: 0.75) }
                }
            }
        }
        .frame(width: width)
        .background(style.tableSurface)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(style.tableBorder, lineWidth: 1))
    }
}

/// The laser dot drawn over a board (presenter + audience). It shares the board's
/// aspect-fit frame, so the unit point lines up on both screens. Never exported.
struct BoardLaserDot: View {
    let point: CGPoint
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let sz = geo.size
            Canvas { ctx, _ in
                let r = 0.018 * sz.width
                let c = CGPoint(x: point.x * sz.width, y: point.y * sz.height)
                let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: r * 0.5, dy: r * 0.5)), with: .color(color))
                ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.35)))
            }
            .allowsHitTesting(false)
        }
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
                            liveColor: state.penColor,
                            style: state.boardStyle)
                BoardInteractionLayer()
                if let laser = state.laserPoint {
                    BoardLaserDot(point: laser, color: state.penColor)
                }
            } else {
                state.boardStyle.background
            }
        }
        .aspectRatio(state.slideAspect, contentMode: .fit)
        .border(Theme.hairlineStrong)
        .overlay(alignment: .bottom) {
            if state.isBoardActive, state.selectedItemID != nil {
                BoardItemInspector().padding(8)
            }
        }
    }
}

/// Captures pen drags (when the pen tool is active), laser drags (laser tool),
/// and otherwise shows a move handle on each item for selecting/repositioning it.
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
                } else if state.tool == .laser {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { state.setLaser(unitPoint($0.location, in: size)) }
                                .onEnded { _ in state.setLaser(nil) }
                        )
                } else if let board = state.activeBoard {
                    ForEach(board.items) { item in
                        moveHandle(for: item, in: size)
                        deleteHandle(for: item, in: size)
                    }
                    if let selected = board.items.first(where: { $0.id == state.selectedItemID }) {
                        resizeHandle(for: selected, in: size)
                    }
                }
            }
        }
    }

    /// Bottom-right handle on the selected item; drag horizontally to resize
    /// (the font scales with the width).
    private func resizeHandle(for item: BoardItem, in size: CGSize) -> some View {
        let halfWidth = item.width * size.width / 2
        return RoundedRectangle(cornerRadius: 4)
            .fill(Color.accentColor.opacity(0.95))
            .overlay(
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            )
            .frame(width: 22, height: 22)
            .position(x: item.center.x * size.width + halfWidth + 14,
                      y: item.center.y * size.height)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = abs(value.location.x - item.center.x * size.width)
                        state.setItemWidth(item.id, (dx * 2) / max(size.width, 1))
                    }
            )
            .help("Drag to resize")
    }

    /// Small red "✕" at each item's top-right corner for one-click deletion.
    private func deleteHandle(for item: BoardItem, in size: CGSize) -> some View {
        let halfWidth = item.width * size.width / 2
        return Button { state.deleteItem(item.id) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.red))
        }
        .buttonStyle(.plain)
        .position(x: item.center.x * size.width + halfWidth + 14,
                  y: item.center.y * size.height - 26)
        .help("Delete this item")
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
/// quick-insert buttons (text / table / QR) and export. Styled as a compact,
/// rounded, translucent Safari-like toolbar with segmented groups.
struct BoardBar: View {
    @EnvironmentObject var state: PresentationState
    let onSave: @MainActor () -> Void
    let onInsert: @MainActor () -> Void

    @State private var showingTablePicker = false

    private var boardIndex: Int { state.activeBoardIndex ?? 0 }

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            group {
                barButton("plus.rectangle", "New") { state.addBoard() }
                barButton("chevron.left", disabled: boardIndex == 0) { state.previousBoard() }
                Text("\(boardIndex + 1) / \(state.boards.count)")
                    .font(.mono(13, bold: true)).foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 42)
                barButton("chevron.right", disabled: boardIndex + 1 >= state.boards.count) { state.nextBoard() }
                barButton("trash", disabled: state.boards.isEmpty) { state.deleteActiveBoard() }
            }

            group {
                barButton("textformat", "Text") { state.addItem(.text) }
                Button { showingTablePicker = true } label: { barLabel("tablecells", "Table") }
                    .buttonStyle(.plain)
                    .help("Choose rows × columns, then insert")
                    .popover(isPresented: $showingTablePicker, arrowEdge: .bottom) {
                        TableSizePicker { rows, cols in
                            state.addTable(rows: rows, columns: cols)
                            showingTablePicker = false
                        }
                    }
                barButton("qrcode", "QR") { state.addItem(.qr) }
                Menu {
                    Button("Time") { state.addTextItem(Date().formatted(date: .omitted, time: .shortened)) }
                    Button("Deck name") { state.addTextItem(state.title) }
                    Button("Slide number") { state.addTextItem("Slide \(state.index + 1) / \(state.pageCount)") }
                } label: {
                    barLabel("bolt", "Quick")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Insert the time, deck name, or slide number")
            }

            group {
                barButton(state.boardLight ? "sun.max" : "moon.stars",
                          state.boardLight ? "White" : "Black") { state.boardLight.toggle() }
            }

            group {
                barButton("square.and.arrow.down", "Save",
                          disabled: state.activeBoardIsEmpty) { onSave() }
                barButton("rectangle.stack.badge.plus", "Insert",
                          disabled: state.activeBoardIsEmpty || state.sourceURL == nil) { onInsert() }
            }

            group {
                barButton("xmark.circle", "Done") { state.hideBoard() }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .padding(.horizontal, 8)
    }

    /// A segmented cluster with an inset rounded background.
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2) { content() }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }

    private func barButton(_ icon: String, _ title: String? = nil,
                           disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { barLabel(icon, title) }
            .buttonStyle(.plain)
            .disabled(disabled)
            .opacity(disabled ? 0.4 : 1)
    }

    private func barLabel(_ icon: String, _ title: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            if let title { Text(title).font(.ui(12, "Medium")) }
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Apple Notes-style grid picker: hover to size the table, click to insert.
struct TableSizePicker: View {
    let onPick: (_ rows: Int, _ columns: Int) -> Void

    private let maxRows = 8
    private let maxCols = 8
    private let cell: CGFloat = 16
    @State private var rows = 0
    @State private var cols = 0

    var body: some View {
        VStack(spacing: 8) {
            Text(rows > 0 ? "\(rows) × \(cols)" : "Insert Table")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            VStack(spacing: 3) {
                ForEach(1...maxRows, id: \.self) { r in
                    HStack(spacing: 3) {
                        ForEach(1...maxCols, id: \.self) { c in
                            RoundedRectangle(cornerRadius: 3)
                                .fill((r <= rows && c <= cols) ? Color.accentColor
                                                               : Color.secondary.opacity(0.18))
                                .frame(width: cell, height: cell)
                                .onHover { inside in if inside { rows = r; cols = c } }
                                .onTapGesture { onPick(r, c) }
                        }
                    }
                }
            }
        }
        .padding(12)
    }
}

// MARK: - Export

/// Renders a board to PDF using SwiftUI's `ImageRenderer`. The board content is
/// vector (shapes/text), so it stays crisp at any page size.
@MainActor
enum BoardExporter {
    /// One board page as standalone PDF data at the given point size.
    static func renderPDFData(board: Whiteboard, size: CGSize) -> Data? {
        let content = BoardCanvas(board: board, style: .light)
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

    /// Result of a full-presentation export.
    struct ExportSummary {
        var inkSlides: Int
        var boardsAfterSlides: [Int]   // 1-based slide numbers each board was placed after
    }

    /// Renders a new PDF of the whole deck with the freehand ink burned onto each
    /// slide and the whiteboards inserted after the slide on which they were made.
    /// Drawn with Core Graphics (vector) so slides and boards stay crisp.
    @MainActor
    static func exportPresentation(sourceURL: URL, split: Bool, aspect: CGFloat,
                                   strokes: [Int: [Stroke]], boards: [Whiteboard],
                                   to dest: URL) -> ExportSummary? {
        guard let slides = PDFModel.croppedDocument(url: sourceURL, half: split ? .left : .full),
              let first = slides.page(at: 0) else { return nil }

        let pageSize = first.bounds(for: .cropBox).size

        // Pre-render board pages, grouped by the slide they follow.
        var boardPages: [Int: [PDFPage]] = [:]
        var insertedAfter: [Int] = []
        for board in boards {
            guard let data = renderPDFData(board: board, size: pageSize),
                  let bdoc = PDFDocument(data: data), let bpage = bdoc.page(at: 0) else { continue }
            boardPages[board.slideIndex, default: []].append(bpage)
            insertedAfter.append(board.slideIndex + 1)
        }

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: dest as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        var inkSlides = 0
        for i in 0..<slides.pageCount {
            guard let page = slides.page(at: i) else { continue }
            let box = page.bounds(for: .cropBox)

            ctx.beginPDFPage(nil)
            ctx.saveGState()
            ctx.translateBy(x: -box.minX, y: -box.minY)
            page.draw(with: .cropBox, to: ctx)
            ctx.restoreGState()

            if let pageStrokes = strokes[i], !pageStrokes.isEmpty {
                inkSlides += 1
                ctx.saveGState()
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                for stroke in pageStrokes {
                    ctx.setStrokeColor(NSColor(stroke.color).cgColor)
                    ctx.setLineWidth(max(0.5, stroke.width * box.width))
                    for (k, pt) in stroke.points.enumerated() {
                        let p = CGPoint(x: pt.x * box.width, y: (1 - pt.y) * box.height)
                        if k == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
                    }
                    ctx.strokePath()
                }
                ctx.restoreGState()
            }
            ctx.endPDFPage()

            for bpage in boardPages[i] ?? [] {
                let bb = bpage.bounds(for: .mediaBox)
                ctx.beginPDFPage(nil)
                ctx.saveGState()
                ctx.translateBy(x: -bb.minX, y: -bb.minY)
                bpage.draw(with: .mediaBox, to: ctx)
                ctx.restoreGState()
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        return ExportSummary(inkSlides: inkSlides, boardsAfterSlides: insertedAfter.sorted())
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
