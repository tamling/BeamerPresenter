import SwiftUI
import PDFKit
import Combine

/// Active drawing tool on the slide.
enum Tool { case none, pen, laser }

/// One freehand annotation, stored in *unit* coordinates (0...1 of the slide
/// rect) and a *relative* width so it scales identically on the small presenter
/// pane and the full audience screen.
struct Stroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var color: Color
    var width: CGFloat   // fraction of slide width
}

/// Single source of truth shared by both windows. A keypress or click mutates
/// state here and the presenter + audience views update in lockstep.
final class PresentationState: ObservableObject {
    @Published private(set) var slideDoc: PDFDocument?   // left half (or full page)
    @Published private(set) var notesDoc: PDFDocument?   // right half, nil for plain PDFs
    @Published private(set) var pageCount: Int = 0
    @Published private(set) var hasNotes: Bool = false
    @Published private(set) var isLoaded: Bool = false
    @Published private(set) var title: String = ""
    @Published private(set) var slideAspect: CGFloat = 16.0 / 9.0

    @Published var index: Int = 0
    @Published var blackout: Bool = false
    @Published var showOverview: Bool = false
    @Published private(set) var startDate = Date()

    // Annotation / laser
    @Published var tool: Tool = .none
    @Published var penColor: Color = .red
    @Published var strokes: [Int: [Stroke]] = [:]
    @Published var currentStroke: [CGPoint] = []
    @Published var laserPoint: CGPoint?

    private var thumbCache: [Int: NSImage] = [:]

    // MARK: - Loading

    @discardableResult
    func load(url: URL) -> Bool {
        guard let probe = PDFDocument(url: url), probe.pageCount > 0 else { return false }
        let split = PDFModel.isNotesLayout(probe)

        slideDoc = PDFModel.croppedDocument(url: url, half: split ? .left : .full)
        notesDoc = split ? PDFModel.croppedDocument(url: url, half: .right) : nil
        guard let doc = slideDoc, let first = doc.page(at: 0) else { return false }

        let box = first.bounds(for: .cropBox)
        slideAspect = box.width / max(box.height, 1)
        hasNotes = split
        pageCount = doc.pageCount
        title = url.deletingPathExtension().lastPathComponent
        thumbCache.removeAll()
        strokes.removeAll()
        currentStroke = []
        laserPoint = nil
        tool = .none
        index = 0
        blackout = false
        showOverview = false
        startDate = Date()
        isLoaded = true
        return true
    }

    func unload() {
        slideDoc = nil
        notesDoc = nil
        pageCount = 0
        hasNotes = false
        title = ""
        thumbCache.removeAll()
        strokes.removeAll()
        currentStroke = []
        laserPoint = nil
        tool = .none
        index = 0
        blackout = false
        showOverview = false
        isLoaded = false
    }

    // MARK: - Navigation

    func next()      { go(to: index + 1) }
    func previous()  { go(to: index - 1) }
    func goToFirst() { go(to: 0) }
    func goToLast()  { go(to: pageCount - 1) }

    func go(to i: Int) {
        guard pageCount > 0 else { return }
        let clamped = min(max(0, i), pageCount - 1)
        if clamped != index {
            currentStroke = []
            laserPoint = nil
        }
        index = clamped
    }

    func resetTimer() { startDate = Date() }

    // MARK: - Tools / annotations

    func toggleTool(_ t: Tool) {
        tool = (tool == t) ? .none : t
        if tool != .laser { laserPoint = nil }
        if tool != .pen { currentStroke = [] }
    }

    func beginStroke(at p: CGPoint) { currentStroke = [p] }
    func extendStroke(to p: CGPoint) { currentStroke.append(p) }

    func endStroke(width: CGFloat = 0.004) {
        defer { currentStroke = [] }
        guard currentStroke.count > 1 else { return }
        strokes[index, default: []].append(Stroke(points: currentStroke, color: penColor, width: width))
    }

    func setLaser(_ p: CGPoint?) { laserPoint = p }

    func undoStroke() {
        guard var s = strokes[index], !s.isEmpty else { return }
        s.removeLast()
        strokes[index] = s.isEmpty ? nil : s
    }

    func clearStrokes() {
        strokes[index] = nil
        currentStroke = []
    }

    var hasInkOnCurrentSlide: Bool {
        !(strokes[index]?.isEmpty ?? true)
    }

    // MARK: - Thumbnails

    /// Lazily renders and caches a thumbnail of the slide half for the strip and
    /// the overview grid.
    func thumbnail(at i: Int, height: CGFloat = 110) -> NSImage? {
        guard let doc = slideDoc, i >= 0, i < doc.pageCount, let page = doc.page(at: i) else { return nil }
        if let cached = thumbCache[i] { return cached }
        let box = page.bounds(for: .cropBox)
        let aspect = box.width / max(box.height, 1)
        let size = NSSize(width: height * aspect, height: height)
        let image = page.thumbnail(of: size, for: .cropBox)
        thumbCache[i] = image
        return image
    }
}
