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
    @Published private(set) var textNotes: [Int: String] = [:]   // notes parsed from a sibling .tex
    @Published private(set) var pageCount: Int = 0
    @Published private(set) var isLoaded: Bool = false

    /// True when this deck has any notes at all — either a PDF notes column or
    /// `\note{}` text read from the `.tex` source.
    var hasNotes: Bool { notesDoc != nil || !textNotes.isEmpty }
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

    // Whiteboards (blank scratch slides). `activeBoardIndex == nil` means the
    // deck is showing; a non-nil index overlays that board on both screens.
    @Published var boards: [Whiteboard] = []
    @Published var activeBoardIndex: Int?
    @Published var selectedItemID: UUID?
    @Published var boardStroke: [CGPoint] = []   // in-progress ink on the board

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
        pageCount = doc.pageCount
        // A split deck already carries its notes in the right half; for a plain
        // PDF, fall back to `\note{}` text from a sibling `.tex` if one exists.
        textNotes = split ? [:] : TexNotes.load(forPDF: url, pageCount: doc.pageCount)
        title = url.deletingPathExtension().lastPathComponent
        thumbCache.removeAll()
        strokes.removeAll()
        currentStroke = []
        laserPoint = nil
        tool = .none
        boards.removeAll()
        activeBoardIndex = nil
        selectedItemID = nil
        boardStroke = []
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
        textNotes = [:]
        pageCount = 0
        title = ""
        thumbCache.removeAll()
        strokes.removeAll()
        currentStroke = []
        laserPoint = nil
        tool = .none
        boards.removeAll()
        activeBoardIndex = nil
        selectedItemID = nil
        boardStroke = []
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
        if activeBoardIndex != nil { hideBoard() }   // navigating slides leaves the board
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

    /// Undo / clear / "has ink" route to the active board when one is showing,
    /// so the control bar and keyboard shortcuts work in both contexts.
    func undoStroke() {
        if activeBoardIndex != nil { boardUndo(); return }
        guard var s = strokes[index], !s.isEmpty else { return }
        s.removeLast()
        strokes[index] = s.isEmpty ? nil : s
    }

    func clearStrokes() {
        if activeBoardIndex != nil { boardClearInk(); return }
        strokes[index] = nil
        currentStroke = []
    }

    var hasInkOnCurrentSlide: Bool {
        if let board = activeBoard { return !board.strokes.isEmpty }
        return !(strokes[index]?.isEmpty ?? true)
    }

    // MARK: - Whiteboards

    var activeBoard: Whiteboard? {
        guard let i = activeBoardIndex, boards.indices.contains(i) else { return nil }
        return boards[i]
    }

    var isBoardActive: Bool { activeBoardIndex != nil }

    var selectedItem: BoardItem? {
        guard let id = selectedItemID else { return nil }
        return activeBoard?.items.first { $0.id == id }
    }

    func toggleBoard() { isBoardActive ? hideBoard() : showBoards() }

    /// Shows a board, creating the first one on demand.
    func showBoards() {
        if boards.isEmpty {
            addBoard()
        } else {
            activeBoardIndex = min(activeBoardIndex ?? boards.count - 1, boards.count - 1)
        }
    }

    func hideBoard() {
        activeBoardIndex = nil
        selectedItemID = nil
        boardStroke = []
    }

    func addBoard() {
        boards.append(Whiteboard(name: "Whiteboard \(boards.count + 1)"))
        activeBoardIndex = boards.count - 1
        selectedItemID = nil
        boardStroke = []
    }

    func nextBoard() {
        guard let i = activeBoardIndex, i + 1 < boards.count else { return }
        activeBoardIndex = i + 1
        selectedItemID = nil
    }

    func previousBoard() {
        guard let i = activeBoardIndex, i > 0 else { return }
        activeBoardIndex = i - 1
        selectedItemID = nil
    }

    func deleteActiveBoard() {
        guard let i = activeBoardIndex else { return }
        boards.remove(at: i)
        activeBoardIndex = boards.isEmpty ? nil : min(i, boards.count - 1)
        selectedItemID = nil
        boardStroke = []
    }

    private func mutateActiveBoard(_ change: (inout Whiteboard) -> Void) {
        guard let i = activeBoardIndex, boards.indices.contains(i) else { return }
        change(&boards[i])
    }

    // Items
    func addItem(_ kind: BoardItem.Kind) {
        let item = BoardItem.makeDefault(kind)
        mutateActiveBoard { $0.items.append(item) }
        selectedItemID = item.id
    }

    func updateItemText(_ id: UUID, _ text: String) {
        mutateActiveBoard { board in
            if let k = board.items.firstIndex(where: { $0.id == id }) { board.items[k].text = text }
        }
    }

    func moveItem(_ id: UUID, to center: CGPoint) {
        mutateActiveBoard { board in
            if let k = board.items.firstIndex(where: { $0.id == id }) {
                board.items[k].center = CGPoint(x: clamp01(center.x), y: clamp01(center.y))
            }
        }
    }

    func scaleItem(_ id: UUID, by factor: CGFloat) {
        mutateActiveBoard { board in
            if let k = board.items.firstIndex(where: { $0.id == id }) {
                board.items[k].width = min(max(0.05, board.items[k].width * factor), 1)
                board.items[k].fontScale = min(max(0.02, board.items[k].fontScale * factor), 0.2)
            }
        }
    }

    func deleteSelectedItem() {
        guard let id = selectedItemID else { return }
        mutateActiveBoard { $0.items.removeAll { $0.id == id } }
        selectedItemID = nil
    }

    // Board ink
    func boardBeginStroke(at p: CGPoint) { boardStroke = [p] }
    func boardExtendStroke(to p: CGPoint) { boardStroke.append(p) }

    func boardEndStroke(width: CGFloat = 0.004) {
        defer { boardStroke = [] }
        guard boardStroke.count > 1 else { return }
        let stroke = Stroke(points: boardStroke, color: penColor, width: width)
        mutateActiveBoard { $0.strokes.append(stroke) }
    }

    func boardUndo() {
        mutateActiveBoard { if !$0.strokes.isEmpty { $0.strokes.removeLast() } }
    }

    func boardClearInk() {
        mutateActiveBoard { $0.strokes.removeAll() }
        boardStroke = []
    }

    private func clamp01(_ v: CGFloat) -> CGFloat { min(max(0, v), 1) }

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
