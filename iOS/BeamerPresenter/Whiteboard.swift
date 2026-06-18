import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// A free-form scratch slide shown instead of the deck: a white board with
/// freehand ink and movable items (text, a small table, or a QR code). Boards
/// live outside the PDF, so they can be added live during a talk. All geometry
/// is in *unit* coordinates so it scales identically on the iPad, the audience
/// screen, and any export.
struct Whiteboard: Identifiable {
    let id = UUID()
    var name: String
    var slideIndex: Int = 0           // the slide showing when this board was created
    var strokes: [InkStroke] = []
    var items: [BoardItem] = []
}

struct BoardItem: Identifiable {
    enum Kind: String { case text, table, qr }

    let id = UUID()
    var kind: Kind
    var center: CGPoint          // unit position of the item's centre
    var width: CGFloat           // unit width (fraction of board width)
    var text: String             // plain text, QR payload, or "a | b\nc | d" table
    var fontScale: CGFloat = 0.045

    static func makeDefault(_ kind: Kind) -> BoardItem {
        switch kind {
        case .text:  return BoardItem(kind: .text, center: CGPoint(x: 0.5, y: 0.35), width: 0.4, text: "Text")
        case .table: return BoardItem(kind: .table, center: CGPoint(x: 0.5, y: 0.4), width: 0.5, text: "a | b\nc | d")
        case .qr:    return BoardItem(kind: .qr, center: CGPoint(x: 0.5, y: 0.4), width: 0.22, text: "https://")
        }
    }
}

/// Generates a crisp QR code image from a string.
enum QRCode {
    private static let context = CIContext()

    static func image(from string: String) -> UIImage? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(trimmed.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?
            .transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Rendering (presenter, audience, export all share this)

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

/// A board's background, committed ink, live stroke, and items.
struct BoardCanvas: View {
    let board: Whiteboard
    var liveStroke: [CGPoint] = []
    var liveColor: Color = .red
    var liveWidth: CGFloat = 0.004
    var liveWidths: [CGFloat] = []
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
                        drawStroke(ctx, points: stroke.points, widths: stroke.pointWidths,
                                   baseWidth: stroke.width, color: stroke.color, in: sz)
                    }
                    drawStroke(ctx, points: liveStroke, widths: liveWidths,
                               baseWidth: liveWidth, color: liveColor, in: sz)
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
                    Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
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

/// A clean grid table: shaded header row, alternating tints, hairline separators.
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

/// An editable mirror of `TableItemView`: same look, but each cell is a TextField
/// so the presenter can tap a cell and type. Edits are serialised back to the
/// `"a | b"` form and reported via `onChange`.
struct TableEditor: View {
    let width: CGFloat
    let fontSize: CGFloat
    let onChange: (String) -> Void

    @State private var rows: [[String]]

    init(text: String, width: CGFloat, fontSize: CGFloat, onChange: @escaping (String) -> Void) {
        self.width = width
        self.fontSize = fontSize
        self.onChange = onChange
        _rows = State(initialValue: TableEditor.parse(text))
    }

    // The editor is presenter-only, so it always uses the Night palette.
    private let style = BoardStyle.dark

    var body: some View {
        let cols = max(1, rows.map(\.count).max() ?? 1)
        let radius = fontSize * 0.45
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<cols, id: \.self) { c in
                        TextField("", text: cellBinding(r, c))
                            .textFieldStyle(.plain)
                            .font(.system(size: fontSize, weight: r == 0 ? .semibold : .regular))
                            .foregroundColor(style.text)
                            .tint(Theme.accent)
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

    private func cellBinding(_ r: Int, _ c: Int) -> Binding<String> {
        Binding(
            get: { rows.indices.contains(r) && rows[r].indices.contains(c) ? rows[r][c] : "" },
            set: { newValue in
                guard rows.indices.contains(r), rows[r].indices.contains(c) else { return }
                rows[r][c] = newValue
                onChange(TableEditor.serialize(rows))
            })
    }

    static func parse(_ text: String) -> [[String]] {
        let parsed = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) } }
        let cols = max(1, parsed.map(\.count).max() ?? 1)
        return parsed.map { $0 + Array(repeating: "", count: max(0, cols - $0.count)) }
    }

    static func serialize(_ rows: [[String]]) -> String {
        rows.map { $0.joined(separator: " | ") }.joined(separator: "\n")
    }
}
