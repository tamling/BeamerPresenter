import SwiftUI
import PDFKit

/// Renders a single, non-interactive page of a `PDFDocument`, scaled to fit.
/// Several of these can share one document and display different pages (e.g.
/// current vs. next slide).
struct PDFPageView: NSViewRepresentable {
    let document: PDFDocument?
    let pageIndex: Int

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displaysPageBreaks = false
        view.backgroundColor = .black
        view.enclosingScrollView?.hasVerticalScroller = false
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }
        guard let document,
              pageIndex >= 0, pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else { return }
        if view.currentPage != page {
            view.go(to: page)
        }
        view.autoScales = true
    }
}
