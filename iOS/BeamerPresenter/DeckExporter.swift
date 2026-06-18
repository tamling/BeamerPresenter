import SwiftUI
import PDFKit

/// Renders a new PDF of the whole deck with the freehand ink burned onto each
/// slide and the whiteboards inserted after the slide on which they were made.
/// Drawn with Core Graphics (vector) so slides and boards stay crisp. Ported
/// from the macOS `BoardExporter` (`NSColor`→`UIColor`).
@MainActor
enum DeckExporter {
    struct Summary { var inkSlides: Int; var boards: Int }

    /// One board page as standalone single-page PDF data, via SwiftUI's
    /// `ImageRenderer` (board content is vector, so it stays crisp).
    static func renderBoardPDF(_ board: Whiteboard, size: CGSize) -> Data? {
        let content = BoardCanvas(board: board)
            .frame(width: size.width, height: size.height)
            .background(Theme.stage)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)

        let data = NSMutableData()
        var ok = false
        renderer.render { sz, draw in
            var box = CGRect(origin: .zero, size: sz)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            ok = true
        }
        return ok ? data as Data : nil
    }

    /// Exports the current presentation to `dest`. Returns a summary or nil on
    /// failure. Uses the in-memory document (so split decks export their slide
    /// half via `slideBox`).
    @discardableResult
    static func export(model: PresentationModel, to dest: URL) -> Summary? {
        guard let doc = model.document, let first = doc.page(at: 0) else { return nil }
        let slideBox = model.slideBox
        let pageSize = first.bounds(for: slideBox).size
        guard pageSize.width > 0, pageSize.height > 0 else { return nil }

        // Pre-render board pages, grouped by the slide they follow.
        var boardPages: [Int: [PDFPage]] = [:]
        var boardCount = 0
        for board in model.boards {
            let at = min(max(0, board.slideIndex), doc.pageCount - 1)
            guard let data = renderBoardPDF(board, size: pageSize),
                  let bdoc = PDFDocument(data: data), let bpage = bdoc.page(at: 0) else { continue }
            boardPages[at, default: []].append(bpage)
            boardCount += 1
        }

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: dest as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        var inkSlides = 0
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: slideBox)

            ctx.beginPDFPage(nil)
            ctx.saveGState()
            ctx.translateBy(x: -box.minX, y: -box.minY)
            page.draw(with: slideBox, to: ctx)
            ctx.restoreGState()

            if let pageStrokes = model.strokes[i], !pageStrokes.isEmpty {
                inkSlides += 1
                drawStrokes(pageStrokes, in: box, ctx: ctx)
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
        return Summary(inkSlides: inkSlides, boards: boardCount)
    }

    private static func drawStrokes(_ strokes: [InkStroke], in box: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in strokes {
            ctx.setStrokeColor(UIColor(stroke.color).cgColor)
            // PDF origin is bottom-left, so flip y from the unit (top-left) coords.
            func point(_ pt: CGPoint) -> CGPoint {
                CGPoint(x: pt.x * box.width, y: (1 - pt.y) * box.height)
            }
            if stroke.pointWidths.count == stroke.points.count, stroke.points.count > 1 {
                // Per-point pressure: stroke each segment at its mean width.
                for i in 1..<stroke.points.count {
                    ctx.setLineWidth(max(0.5, (stroke.pointWidths[i - 1] + stroke.pointWidths[i]) / 2 * box.width))
                    ctx.move(to: point(stroke.points[i - 1]))
                    ctx.addLine(to: point(stroke.points[i]))
                    ctx.strokePath()
                }
            } else {
                ctx.setLineWidth(max(0.5, stroke.width * box.width))
                for (k, pt) in stroke.points.enumerated() {
                    if k == 0 { ctx.move(to: point(pt)) } else { ctx.addLine(to: point(pt)) }
                }
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }
}
