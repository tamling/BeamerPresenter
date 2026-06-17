import SwiftUI
import PDFKit

/// Renders a single, non-interactive page of a `PDFDocument`, scaled to fit.
/// Gestures are handled by the SwiftUI layer on top, so interaction is disabled.
struct PDFPageView: UIViewRepresentable {
    let document: PDFDocument?
    let pageIndex: Int
    var displayBox: PDFDisplayBox = .cropBox

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displaysPageBreaks = false
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
        if view.displayBox != displayBox { view.displayBox = displayBox }
        guard let document,
              pageIndex >= 0, pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else { return }
        if view.currentPage != page { view.go(to: page) }
        view.autoScales = true
    }
}
