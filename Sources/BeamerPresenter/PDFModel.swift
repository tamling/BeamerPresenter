import PDFKit
import CoreGraphics

/// Which portion of a (possibly double-width) Beamer page to show.
enum Half {
    case left   // the slide
    case right  // the notes column
    case full   // a plain PDF with no notes layout
}

enum PDFModel {
    /// A Beamer page compiled with
    /// `\setbeameroption{show notes on second screen=right}` is ~2x wider than a
    /// normal slide: slide on the left half, notes on the right half. We load a
    /// fresh `PDFDocument` per half and set each page's `cropBox` so PDFKit only
    /// renders that half. Each `PDFDocument` owns its own `PDFPage` objects, so
    /// the three crops never fight over a shared cropBox.
    static func croppedDocument(url: URL, half: Half) -> PDFDocument? {
        guard let doc = PDFDocument(url: url) else { return nil }
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            let crop: CGRect
            switch half {
            case .left:
                crop = CGRect(x: box.minX, y: box.minY, width: box.width / 2, height: box.height)
            case .right:
                crop = CGRect(x: box.midX, y: box.minY, width: box.width / 2, height: box.height)
            case .full:
                crop = box
            }
            page.setBounds(crop, for: .cropBox)
        }
        return doc
    }

    /// Heuristic: a notes-on-second-screen page is far wider than any normal
    /// slide aspect ratio (16:9 ≈ 1.78, 4:3 ≈ 1.33). Double-width pushes it
    /// past ~2.4, so that's a safe split threshold.
    static func isNotesLayout(_ document: PDFDocument) -> Bool {
        guard let first = document.page(at: 0) else { return false }
        let box = first.bounds(for: .mediaBox)
        return box.width / max(box.height, 1) > 2.4
    }
}
